import Foundation
import Darwin

/// What the whole machine is spending right now — not just the processes the list happens to show.
struct SystemUsage: Equatable {
    var cpuPercent: Double = 0    // 0-100, busy time across all cores
    var ramUsedMB: Double = 0
    var ramPercent: Double = 0
}

enum SystemStats {
    /// CPU ticks are cumulative since boot, so a percentage needs two samples.
    private nonisolated(unsafe) static var previousTicks: (busy: Double, total: Double)?

    static func sample() -> SystemUsage {
        if Demo.isEnabled { return Demo.system }
        let used = ramUsedMB()
        let total = Double(ProcessInfo.processInfo.physicalMemory) / 1024 / 1024
        return SystemUsage(cpuPercent: cpuPercent(),
                           ramUsedMB: used,
                           ramPercent: total > 0 ? used / total * 100 : 0)
    }

    // MARK: - CPU

    private static func cpuTicks() -> (busy: Double, total: Double)? {
        var info = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let user = Double(info.cpu_ticks.0)
        let system = Double(info.cpu_ticks.1)
        let idle = Double(info.cpu_ticks.2)
        let nice = Double(info.cpu_ticks.3)
        let busy = user + system + nice
        return (busy, busy + idle)
    }

    private static func cpuPercent() -> Double {
        guard let now = cpuTicks() else { return 0 }
        // First call has nothing to compare against: take a second sample rather than show 0%.
        guard let previous = previousTicks else {
            previousTicks = now
            usleep(200_000)
            guard let second = cpuTicks() else { return 0 }
            previousTicks = second
            let total = second.total - now.total
            return total > 0 ? (second.busy - now.busy) / total * 100 : 0
        }
        previousTicks = now
        let total = now.total - previous.total
        guard total > 0 else { return 0 }
        return min(100, max(0, (now.busy - previous.busy) / total * 100))
    }

    // MARK: - Memory

    /// "Memory used" the way Activity Monitor counts it: app memory + wired + compressed.
    private static func ramUsedMB() -> Double {
        var info = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        let pageSize = Double(vm_kernel_page_size)
        let used = Double(info.active_count) + Double(info.wire_count) + Double(info.compressor_page_count)
        return used * pageSize / 1024 / 1024
    }
}
