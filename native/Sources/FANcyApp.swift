import SwiftUI
import AppKit

@main
struct FANcyApp: App {
    // Menu-bar-only app: the sole scene is the MenuBarExtra. The main window is
    // opened on demand by MainWindowController (see MainWindow.swift).
    @ObservedObject private var state = AppState.shared
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(state)
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "fan")
                if state.cpuTemp > 0 {
                    Text(String(format: "%.0f°", state.cpuTemp))
                        .monospacedDigit()
                }
            }
        }
    }
}

// MARK: - Menu Bar View

struct MenuBarView: View {
    @EnvironmentObject var state: AppState

    private func cpuStr() -> String {
        state.cpuTemp > 0 ? String(format: "%.0f°C", state.cpuTemp) : "--"
    }
    private func gpuStr() -> String {
        state.gpuTemp > 0 ? String(format: "%.0f°C", state.gpuTemp) : "--"
    }

    var body: some View {
        // Use simple Text buttons — Label with HStack doesn't render in MenuBarExtra
        Text("CPU: \(cpuStr())    GPU: \(gpuStr())")
            .monospacedDigit()
        Text(String(format: "RAM: %.1f / %.0f GB (%.0f%%)",
                    state.memory.usedGB, state.memory.totalGB, state.memory.usedPercent))
            .monospacedDigit()

        Divider()

        ForEach(state.fans) { fan in
            Text("\(L10n.fan(fan.id + 1)): \(String(format: "%.0f RPM", fan.actual))")
                .monospacedDigit()
        }

        Divider()

        Text("\(L10n.fanMode): \(modeLabel)")

        if state.mode == .curve {
            Text(state.curveStatus)
                .font(.caption)
        }

        Divider()

        // Quick actions — work while the menu is open
        Button(L10n.automatic) { state.restoreAuto() }
            .keyboardShortcut("0", modifiers: .command)
            .disabled(state.mode == .auto)
        Button(L10n.silent) { state.selectProfile(.silent) }
            .keyboardShortcut("1", modifiers: .command)
            .disabled(state.mode == .curve && state.activeProfile == .silent)
        Button(L10n.performance) { state.selectProfile(.performance) }
            .keyboardShortcut("2", modifiers: .command)
            .disabled(state.mode == .curve && state.activeProfile == .performance)

        Button(L10n.activateFanCurve) { state.activateCurve() }
            .disabled(state.mode == .curve)

        Divider()

        Button(L10n.openFANcy) { MainWindowController.shared.show() }
            .keyboardShortcut("o")

        Button(L10n.checkForUpdates) { Updater.shared.checkForUpdates() }

        Button(L10n.quitFANcy) {
            SMCKit.restoreAllAuto()
            CrashGuard.removeGuardFile()
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    var modeLabel: String {
        switch state.mode {
        case .auto: return L10n.automatic
        case .manual: return L10n.manual
        case .curve: return L10n.fanCurveMode
        }
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillTerminate(_ notification: Notification) {
        SMCKit.restoreAllAuto()
        CrashGuard.removeGuardFile()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if CrashGuard.needsRestore() {
            print("Previous session didn't exit cleanly — restoring auto fan control")
            if SMCKit.open() {
                SMCKit.restoreAllAuto()
            }
        }
        CrashGuard.writeGuardFile()

        // Start Sparkle now, so its scheduled daily check runs from launch on —
        // not only after the user first opens the menu.
        _ = Updater.shared
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
}
