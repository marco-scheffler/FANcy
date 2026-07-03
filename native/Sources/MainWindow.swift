import SwiftUI
import AppKit

/// Hosts the main FANcy window on demand. The app is otherwise menu-bar-only
/// (LSUIElement), so there is no window or Dock icon at launch — the window is
/// created the first time the user picks "Open" and just hidden when closed.
final class MainWindowController {
    static let shared = MainWindowController()
    private var window: NSWindow?
    private init() {}

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: MainWindowRoot())
            let win = NSWindow(contentViewController: hosting)
            win.title = "FANcy"
            win.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            win.setContentSize(NSSize(width: 740, height: 880))
            win.contentMinSize = NSSize(width: 680, height: 700)
            win.isReleasedWhenClosed = false  // keep it for reuse when closed
            win.center()
            window = win
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

/// Root of the on-demand window — keeps the shared state and appearance in sync.
struct MainWindowRoot: View {
    @ObservedObject private var state = AppState.shared

    var body: some View {
        ContentView()
            .environmentObject(state)
            .preferredColorScheme(state.colorScheme)
            .frame(minWidth: 680, minHeight: 700)
    }
}
