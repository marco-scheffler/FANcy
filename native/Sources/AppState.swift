import Foundation
import Combine
import SwiftUI
import UserNotifications

/// Fan mode
enum FanMode: String, CaseIterable { case auto, manual, curve }

/// Live data for a single fan.
struct FanInfo: Identifiable {
    let id: Int
    var actual: Double = 0
    var min: Double = 2317
    var max: Double = 7826
    var target: Double = 0
    var isManual: Bool = false
}

/// A single sample for history charts.
struct TempSample: Identifiable {
    let id = UUID()
    let date: Date
    let cpu: Double
    let gpu: Double
    let memPct: Double  // RAM usage %
}

/// Central app state.
final class AppState: ObservableObject {
    /// Shared instance — the menu bar and the on-demand window use the same state.
    static let shared = AppState()

    @Published var cpuTemp: Double = -1
    @Published var gpuTemp: Double = -1
    @Published var fans: [FanInfo] = []
    @Published var mode: FanMode = .auto
    @Published var curve: FanCurve = FanCurve.load()
    @Published var curveStatus: String = ""
    @Published var activeProfile: CurveProfile = .balanced
    @Published var tempHistory: [TempSample] = []
    @Published var memory: MemoryUsage = MemoryUsage.read()
    @AppStorage("appearance") var appearance: Int = 0

    var globalMin: Double { fans.map(\.min).max() ?? 2317 }
    var globalMax: Double { fans.map(\.max).min() ?? 7826 }
    var averageRPM: Double {
        guard !fans.isEmpty else { return 0 }
        return fans.map(\.actual).reduce(0, +) / Double(fans.count)
    }

    private var timer: Timer?
    private var lastSetRPM: Double = 0
    private var lastTempWarning: Date = .distantPast
    private var lastFanWarning: Date = .distantPast
    private let historyMaxAge: TimeInterval = 600 // 10 minutes

    init() {
        guard SMCKit.open() else {
            print("Failed to open SMC")
            return
        }
        requestNotificationPermission()
        readAll()
        startPolling()
    }

    deinit {
        timer?.invalidate()
        SMCKit.restoreAllAuto()
        SMCKit.close()
    }

    // MARK: - Notifications

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func sendNotification(title: String, body: String, id: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private func checkTemperatureAlerts() {
        // High temp warning (>90°C, max once per 2 minutes)
        if cpuTemp > 90, Date().timeIntervalSince(lastTempWarning) > 120 {
            sendNotification(
                title: L10n.tempWarningTitle,
                body: L10n.tempWarningBody(cpuTemp),
                id: "temp_warning"
            )
            lastTempWarning = Date()
        }

        // Fan failure warning (0 RPM when system is hot, max once per 5 minutes)
        for fan in fans {
            if fan.actual < 1 && cpuTemp > 50,
               Date().timeIntervalSince(lastFanWarning) > 300 {
                sendNotification(
                    title: L10n.fanFailureTitle,
                    body: L10n.fanFailureBody(fan.id + 1),
                    id: "fan_failure_\(fan.id)"
                )
                lastFanWarning = Date()
            }
        }
    }

    // MARK: - Polling

    func startPolling() {
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    private func tick() {
        readAll()
        applyCurveIfNeeded()
        recordHistory()
        checkTemperatureAlerts()
    }

    func readAll() {
        cpuTemp = Double(SMCKit.cpuTemp)
        gpuTemp = Double(SMCKit.gpuTemp)

        let n = SMCKit.fanCount
        if fans.count != n {
            fans = (0..<n).map { i in
                FanInfo(id: i,
                        actual: Double(SMCKit.fanActual(i)),
                        min: Double(SMCKit.fanMin(i)),
                        max: Double(SMCKit.fanMax(i)),
                        target: Double(SMCKit.fanTarget(i)),
                        isManual: SMCKit.fanIsManual(i))
            }
        } else {
            for i in 0..<n {
                fans[i].actual = Double(SMCKit.fanActual(i))
                fans[i].target = Double(SMCKit.fanTarget(i))
                fans[i].isManual = SMCKit.fanIsManual(i)
            }
        }
    }

    // MARK: - Temperature History

    private func recordHistory() {
        guard cpuTemp > 0 else { return }
        memory = MemoryUsage.read()
        let sample = TempSample(date: Date(), cpu: cpuTemp, gpu: gpuTemp,
                                memPct: memory.usedPercent)
        tempHistory.append(sample)
        let cutoff = Date().addingTimeInterval(-historyMaxAge)
        tempHistory.removeAll { $0.date < cutoff }
    }

    // MARK: - Actions

    func setAllFans(rpm: Double) {
        mode = .manual
        for i in 0..<fans.count {
            _ = SMCKit.setFanManual(i, rpm: Float(rpm))
        }
        readAll()
    }

    func setFan(_ index: Int, rpm: Double) {
        mode = .manual
        _ = SMCKit.setFanManual(index, rpm: Float(rpm))
        readAll()
    }

    func restoreAuto() {
        mode = .auto
        curveStatus = ""
        lastSetRPM = 0
        SMCKit.restoreAllAuto()
        readAll()
    }

    func activateCurve() {
        mode = .curve
        curveStatus = L10n.followingCurve
        lastSetRPM = 0
    }

    func selectProfile(_ profile: CurveProfile) {
        activeProfile = profile
        if let preset = profile.curve {
            curve = preset
            curve.save()
        }
        activateCurve()
    }

    // MARK: - Curve with hysteresis

    private func applyCurveIfNeeded() {
        guard mode == .curve, cpuTemp > 0 else { return }
        let pct = curve.interpolate(temp: cpuTemp)
        let targetRPM = FanCurve.pctToRPM(pct, min: globalMin, max: globalMax)

        if FanCurve.needsUpdate(targetRPM: targetRPM, lastRPM: lastSetRPM) {
            for fan in fans {
                let rpm = FanCurve.pctToRPM(pct, min: fan.min, max: fan.max)
                _ = SMCKit.setFanManual(fan.id, rpm: Float(rpm))
            }
            lastSetRPM = targetRPM
        }

        curveStatus = String(format: "%.0f°C → %.0f%%", cpuTemp, pct)
    }

    // MARK: - Appearance

    var colorScheme: ColorScheme? {
        switch appearance {
        case 1: return .light
        case 2: return .dark
        default: return nil
        }
    }
}
