import Foundation

/// Crash guard: writes a sentinel file when fans are in manual/curve mode.
/// If the app crashes, the next launch detects the file and restores auto mode.
enum CrashGuard {
    private static var guardURL: URL {
        let tmp = FileManager.default.temporaryDirectory
        return tmp.appendingPathComponent("com.fancy.guard")
    }

    /// Write a guard file indicating the app is running.
    static func writeGuardFile() {
        let data = "running".data(using: .utf8) ?? Data()
        try? data.write(to: guardURL)
    }

    /// Remove the guard file on clean exit.
    static func removeGuardFile() {
        try? FileManager.default.removeItem(at: guardURL)
    }

    /// Check if a guard file exists from a previous crashed session.
    static func needsRestore() -> Bool {
        FileManager.default.fileExists(atPath: guardURL.path)
    }
}
