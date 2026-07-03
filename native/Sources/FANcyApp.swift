import SwiftUI
import AppKit

@main
struct FANcyApp: App {
    @StateObject private var state = AppState()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(state)
                .preferredColorScheme(state.colorScheme)
                .frame(minWidth: 680, minHeight: 700)
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 740, height: 880)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }

        // Menu bar extra — shows CPU temp in menu bar
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

        Button(L10n.automatic) { state.restoreAuto() }
            .disabled(state.mode == .auto)
        Button(L10n.activateFanCurve) { state.activateCurve() }
            .disabled(state.mode == .curve)

        Divider()

        Button(L10n.openFANcy) {
            NSApp.activate(ignoringOtherApps: true)
            for w in NSApp.windows where !w.title.isEmpty && w.title != "Item-0" {
                w.makeKeyAndOrderFront(nil)
                return
            }
            NSApp.activate(ignoringOtherApps: true)
        }
        .keyboardShortcut("o")

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
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
}
