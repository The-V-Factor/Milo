import Darwin
import Foundation

final class SystemSampler {
    private var previousTicks: CPUTicks?
    private let host = mach_host_self()

    deinit {
        mach_port_deallocate(mach_task_self_, host)
    }

    func reset() { previousTicks = nil }

    func sample() -> SystemSnapshot {
        var errors: [String] = []
        let ticks = readCPUTicks()
        let usage = ticks.flatMap { current in previousTicks.flatMap { current.usage(since: $0) } }
        previousTicks = ticks
        if ticks == nil { errors.append("CPU 采样失败") }

        var averages = [Double](repeating: 0, count: 3)
        let load: LoadAverage?
        if getloadavg(&averages, 3) == 3 {
            load = LoadAverage(one: averages[0], five: averages[1], fifteen: averages[2])
        } else {
            load = nil
            errors.append("平均负载读取失败")
        }

        let memory = readMemory()
        if memory == nil { errors.append("内存采样失败") }
        var swap = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        let swapUsed: UInt64?
        if sysctlbyname("vm.swapusage", &swap, &size, nil, 0) == 0 {
            swapUsed = swap.xsu_used
        } else {
            swapUsed = nil
            errors.append("交换空间读取失败")
        }
        return SystemSnapshot(cpu: usage, load: load, memory: memory, swapUsed: swapUsed, errors: errors)
    }

    private func readCPUTicks() -> CPUTicks? {
        var info = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(host, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return CPUTicks(user: info.cpu_ticks.0, system: info.cpu_ticks.1,
                        idle: info.cpu_ticks.2, nice: info.cpu_ticks.3)
    }

    private func readMemory() -> MemoryUsage? {
        var info = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return MemoryUsage(
            total: ProcessInfo.processInfo.physicalMemory, pageSize: UInt64(getpagesize()),
            internalPages: UInt64(info.internal_page_count), purgeablePages: UInt64(info.purgeable_count),
            wiredPages: UInt64(info.wire_count), compressedPages: UInt64(info.compressor_page_count),
            freePages: UInt64(info.free_count), speculativePages: UInt64(info.speculative_count),
            externalPages: UInt64(info.external_page_count)
        )
    }
}
