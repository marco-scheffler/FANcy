import Foundation

/// Sparkle auto-update integration.
/// For non-App-Store distribution, Sparkle checks an appcast feed for updates.
///
/// Setup (post-build):
/// 1. Download Sparkle from https://github.com/sparkle-project/Sparkle/releases
/// 2. Copy Sparkle.framework into FANcy.app/Contents/Frameworks/
/// 3. Host an appcast.xml on your server with update info
/// 4. Set SUFeedURL in Info.plist
///
/// This file provides a lightweight wrapper that only activates if Sparkle
/// is present, so the app builds and runs fine without it.
enum SparkleUpdater {

    /// Check if Sparkle framework is available at runtime.
    static var isAvailable: Bool {
        let frameworkPath = Bundle.main.privateFrameworksPath ?? ""
        return FileManager.default.fileExists(atPath: frameworkPath + "/Sparkle.framework")
    }

    /// Trigger a manual update check via Sparkle.
    /// Falls back to opening the website if Sparkle is not embedded.
    static func checkForUpdates() {
        if isAvailable {
            // Load Sparkle dynamically to avoid hard link dependency
            if let bundle = Bundle(path: Bundle.main.privateFrameworksPath! + "/Sparkle.framework"),
               bundle.load(),
               let updaterClass = NSClassFromString("SPUStandardUpdaterController") as? NSObject.Type {
                let updater = updaterClass.init()
                updater.perform(NSSelectorFromString("checkForUpdates:"), with: nil)
                return
            }
        }
        // Fallback: open release page
        // Replace with your actual URL
        // NSWorkspace.shared.open(URL(string: "https://github.com/your/repo/releases")!)
    }
}
