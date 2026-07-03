import Foundation
import Darwin

/// System memory usage via Mach host_statistics64.
struct MemoryUsage {
    let total: UInt64       // bytes
    let used: UInt64        // bytes (active + wired + compressed)
    let free: UInt64        // bytes (free + inactive + purgeable)
    let active: UInt64
    let wired: UInt64
    let compressed: UInt64
    let appMemory: UInt64   // internal - purgeable (≈ actual app usage)

    var usedGB: Double { Double(used) / 1_073_741_824 }
    var totalGB: Double { Double(total) / 1_073_741_824 }
    var freeGB: Double { Double(free) / 1_073_741_824 }
    var usedPercent: Double {
        guard total > 0 else { return 0 }
        return Double(used) / Double(total) * 100
    }

    /// Pressure level: 0 = green, 1 = yellow, 2 = red
    var pressure: Int {
        let pct = usedPercent
        if pct < 70 { return 0 }
        if pct < 85 { return 1 }
        return 2
    }

    static func read() -> MemoryUsage {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)

        let result = withUnsafeMutablePointer(to: &stats) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, intPtr, &count)
            }
        }

        guard result == KERN_SUCCESS else {
            return MemoryUsage(total: 0, used: 0, free: 0, active: 0,
                               wired: 0, compressed: 0, appMemory: 0)
        }

        let pageSize = UInt64(vm_kernel_page_size)

        // Total physical RAM
        var totalMem: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        sysctlbyname("hw.memsize", &totalMem, &size, nil, 0)

        let active = UInt64(stats.active_count) * pageSize
        let wired = UInt64(stats.wire_count) * pageSize
        let compressed = UInt64(stats.compressor_page_count) * pageSize
        let free = UInt64(stats.free_count) * pageSize
        let inactive = UInt64(stats.inactive_count) * pageSize
        let purgeable = UInt64(stats.purgeable_count) * pageSize
        let internal_pages = UInt64(stats.internal_page_count) * pageSize

        let used = active + wired + compressed
        let appMemory = internal_pages > purgeable ? internal_pages - purgeable : internal_pages

        return MemoryUsage(
            total: totalMem,
            used: used,
            free: free + inactive + purgeable,
            active: active,
            wired: wired,
            compressed: compressed,
            appMemory: appMemory
        )
    }
}
