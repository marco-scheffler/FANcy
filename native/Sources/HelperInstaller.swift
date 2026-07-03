import Foundation
import ServiceManagement

/// Manages the privileged helper via SMAppService (macOS 13+).
///
/// The helper is a LaunchDaemon bundled at
/// `Contents/Library/LaunchDaemons/com.fancy.helper.plist`, running as root and
/// listening on a Unix domain socket for fan-control commands from the app.
///
/// Registration is the modern login-items flow: `register()` enrols the daemon;
/// the user enables it once under System Settings → Login Items, after which the
/// status becomes `.enabled` and the helper runs.
enum HelperInstaller {
    static let plistName = "com.fancy.helper.plist"
    static let socketPath = "/tmp/fancy-fan.sock"

    private static var service: SMAppService {
        SMAppService.daemon(plistName: plistName)
    }

    /// Current registration status.
    static var status: SMAppService.Status { service.status }

    /// Helper is registered AND approved by the user (running).
    static var isInstalled: Bool { service.status == .enabled }

    /// Registered, but the user still has to enable it in Login Items.
    static var needsApproval: Bool { service.status == .requiresApproval }

    /// Register the daemon. Returns `nil` on success, or an error message.
    /// After a successful call the status is `.enabled` or `.requiresApproval`
    /// (the user must toggle it on in System Settings → Login Items).
    @discardableResult
    static func install() -> String? {
        do {
            try service.register()
            return nil
        } catch {
            NSLog("FANcy: helper register failed: \(error.localizedDescription)")
            return error.localizedDescription
        }
    }

    /// Unregister the daemon. Fire-and-forget; observe `status` for the result.
    static func uninstall() {
        Task {
            do {
                try await service.unregister()
            } catch {
                NSLog("FANcy: helper unregister failed: \(error.localizedDescription)")
            }
        }
    }

    /// Open System Settings → Login Items so the user can enable the helper.
    static func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    /// Send a command to the helper via Unix socket. Returns the response string.
    static func sendCommand(_ cmd: String) -> String? {
        let sock = socket(AF_UNIX, SOCK_STREAM, 0)
        guard sock >= 0 else { return nil }
        defer { close(sock) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = socketPath.utf8CString
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: 104) { dest in
                pathBytes.withUnsafeBufferPointer { src in
                    _ = memcpy(dest, src.baseAddress!, min(src.count, 104))
                }
            }
        }

        let addrLen = socklen_t(MemoryLayout<sockaddr_un>.size)
        let connectResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                connect(sock, sockPtr, addrLen)
            }
        }
        guard connectResult == 0 else { return nil }

        // Send command
        let cmdData = (cmd + "\n").data(using: .utf8)!
        _ = cmdData.withUnsafeBytes { send(sock, $0.baseAddress!, $0.count, 0) }

        // Read response
        var buffer = [UInt8](repeating: 0, count: 1024)
        let n = recv(sock, &buffer, buffer.count, 0)
        guard n > 0 else { return nil }
        return String(bytes: buffer[0..<n], encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
