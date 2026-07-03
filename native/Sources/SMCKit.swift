import Foundation

/// Swift wrapper around the C SMC bridge.
/// Reads work without root (direct IOKit).
/// Writes go through the privileged helper (Unix socket) if installed,
/// otherwise fall back to direct IOKit (requires root).
enum SMCKit {
    private static var isOpen = false

    static func open() -> Bool {
        guard !isOpen else { return true }
        if smc_bridge_open() == 0 {
            isOpen = true
            return true
        }
        return false
    }

    static func close() {
        smc_bridge_close()
        isOpen = false
    }

    // MARK: - Read (no root needed)

    static func readFloat(_ key: String) -> Float? {
        guard isOpen, key.count == 4 else { return nil }
        let v = smc_bridge_read_float(key)
        return v > -0.5 ? v : nil
    }

    static func readUInt8(_ key: String) -> Int? {
        guard isOpen, key.count == 4 else { return nil }
        let v = smc_bridge_read_ui8(key)
        return v >= 0 ? Int(v) : nil
    }

    // MARK: - Write (uses helper if available, else direct)

    private static func helperCommand(_ cmd: String) -> Bool {
        if let resp = HelperInstaller.sendCommand(cmd) {
            return resp.starts(with: "ok")
        }
        return false
    }

    /// Whether the privileged helper is reachable.
    static var helperAvailable: Bool {
        HelperInstaller.sendCommand("auto") != nil  // lightweight ping
    }

    @discardableResult
    static func writeFloat(_ key: String, _ value: Float) -> Bool {
        guard isOpen, key.count == 4 else { return false }
        // Try direct first (works if running as root)
        if smc_bridge_write_float(key, value) == 0 { return true }
        return false
    }

    @discardableResult
    static func writeUInt8(_ key: String, _ value: UInt8) -> Bool {
        guard isOpen, key.count == 4 else { return false }
        if smc_bridge_write_ui8(key, value) == 0 { return true }
        return false
    }

    // MARK: - Fan data

    static var fanCount: Int { readUInt8("FNum") ?? 0 }

    static func fanActual(_ fan: Int) -> Float { readFloat("F\(fan)Ac") ?? 0 }
    static func fanMin(_ fan: Int) -> Float    { readFloat("F\(fan)Mn") ?? 2317 }
    static func fanMax(_ fan: Int) -> Float    { readFloat("F\(fan)Mx") ?? 7826 }
    static func fanTarget(_ fan: Int) -> Float { readFloat("F\(fan)Tg") ?? 0 }
    static func fanIsManual(_ fan: Int) -> Bool { (readUInt8("F\(fan)md") ?? 0) != 0 }

    static func setFanManual(_ fan: Int, rpm: Float) -> Bool {
        // Try helper first
        if HelperInstaller.isInstalled {
            return helperCommand("set \(fan) \(Int(rpm))")
        }
        // Fallback: direct (needs root)
        let mn = fanMin(fan), mx = fanMax(fan)
        let clamped = max(mn, min(mx, rpm))
        guard writeUInt8("F\(fan)md", 1) else { return false }
        return writeFloat("F\(fan)Tg", clamped)
    }

    static func setFanAuto(_ fan: Int) -> Bool {
        if HelperInstaller.isInstalled {
            return helperCommand("auto")
        }
        return writeUInt8("F\(fan)md", 0)
    }

    static func restoreAllAuto() {
        if HelperInstaller.isInstalled {
            _ = helperCommand("auto")
            return
        }
        let n = fanCount
        for i in 0..<n {
            _ = writeUInt8("F\(i)md", 0)
        }
    }

    // MARK: - Temperatures

    static var cpuTemp: Float {
        for k in ["Tp00", "Tp09", "Tp0T", "TC0P"] {
            if let t = readFloat(k), t > 0, t < 150 { return t }
        }
        return -1
    }

    static var gpuTemp: Float {
        for k in ["Tg08", "Tg0C", "Tg0O", "TG0P"] {
            if let t = readFloat(k), t > 0, t < 150 { return t }
        }
        return -1
    }
}
