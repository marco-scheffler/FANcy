import AppKit
import Sparkle

/// FANcy's updater — a thin shell around Sparkle.
///
/// Sparkle fetches the appcast, verifies the EdDSA signature over the download
/// against `SUPublicEDKey`, and swaps the app bundle. FANcy only decides two
/// things on top:
///
/// - **Checking is automatic, installing never is.** A fan-control app runs a
///   root helper; nothing should replace it without the user's click.
/// - **The app comes forward before Sparkle shows anything.** FANcy is a
///   menu-bar app (`LSUIElement`), so without that the update window would sit
///   behind every other app — indistinguishable from an updater that does
///   nothing.
final class Updater: NSObject, SPUStandardUserDriverDelegate {
    static let shared = Updater()

    private var controller: SPUStandardUpdaterController!

    private override init() {
        super.init()
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: self
        )
        controller.updater.automaticallyDownloadsUpdates = false
    }

    /// The user asking from the menu.
    func checkForUpdates() {
        NSApp.activate(ignoringOtherApps: true)
        controller.checkForUpdates(nil)
    }

    // MARK: - SPUStandardUserDriverDelegate

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        NSApp.activate(ignoringOtherApps: true)
    }

    func standardUserDriverWillShowModalAlert() {
        NSApp.activate(ignoringOtherApps: true)
    }
}
