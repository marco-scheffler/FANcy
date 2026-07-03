import Foundation
import AppKit

/// Manages installation and communication with the privileged helper tool.
/// The helper is a small binary that listens on a Unix domain socket for
/// fan control commands, running as root via a LaunchDaemon.
enum HelperInstaller {
    static let helperID = "com.fancy.helper"
    static let socketPath = "/tmp/fancy-fan.sock"

    private static var daemonPlist: URL {
        URL(fileURLWithPath: "/Library/LaunchDaemons/\(helperID).plist")
    }

    private static var helperBinary: URL {
        URL(fileURLWithPath: "/Library/PrivilegedHelperTools/\(helperID)")
    }

    /// Check if the helper is installed and running.
    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: helperBinary.path) &&
        FileManager.default.fileExists(atPath: daemonPlist.path)
    }

    /// Send a command to the helper via Unix socket. Returns response string.
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

    /// Install the helper tool (requires admin password via osascript).
    static func install(appBundlePath: String) -> Bool {
        // The helper binary is embedded in the app bundle
        let srcHelper = appBundlePath + "/Contents/MacOS/FANcyHelper"
        guard FileManager.default.fileExists(atPath: srcHelper) else {
            print("Helper binary not found at \(srcHelper)")
            return false
        }

        let plistContent = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(helperID)</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(helperBinary.path)</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
            <key>KeepAlive</key>
            <true/>
            <key>StandardErrorPath</key>
            <string>/tmp/fancy-helper.log</string>
        </dict>
        </plist>
        """

        // Write plist to temp, then use osascript to move it with admin privs
        let tmpPlist = "/tmp/\(helperID).plist"
        try? plistContent.write(toFile: tmpPlist, atomically: true, encoding: .utf8)

        let script = """
        do shell script "mkdir -p /Library/PrivilegedHelperTools && \
        cp '\(srcHelper)' '\(helperBinary.path)' && \
        chmod 755 '\(helperBinary.path)' && \
        chown root:wheel '\(helperBinary.path)' && \
        cp '\(tmpPlist)' '\(daemonPlist.path)' && \
        chown root:wheel '\(daemonPlist.path)' && \
        launchctl bootout system/\(helperID) 2>/dev/null; \
        launchctl bootstrap system '\(daemonPlist.path)'" \
        with administrator privileges
        """

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", script]

        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            return false
        }
    }

    /// Uninstall the helper.
    static func uninstall() -> Bool {
        let script = """
        do shell script "launchctl bootout system/\(helperID) 2>/dev/null; \
        rm -f '\(helperBinary.path)' '\(daemonPlist.path)'" \
        with administrator privileges
        """

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", script]

        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            return false
        }
    }
}
