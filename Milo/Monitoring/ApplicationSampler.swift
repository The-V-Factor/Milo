import Darwin
import Foundation

struct RunningApplicationDescriptor: Sendable {
    let pid: Int32
    let name: String
    let bundlePath: String
}

struct ApplicationUsage: Identifiable, Sendable {
    let id: String
    let name: String
    let bundlePath: String
    let processCount: Int
    let cpuPercentage: Double?
    let memoryBytes: UInt64
    let isPartial: Bool
}

struct ApplicationSnapshot: Sendable {
    let cpuTop: [ApplicationUsage]
    let memoryTop: [ApplicationUsage]
    let sampledApplicationCount: Int
    let unavailableProcessCount: Int
    let unattributedProcessCount: Int
    let isWarmingUp: Bool
    var samplingError: String? = nil
}

struct ApplicationProcessSample {
    let pid: Int32
    let startedAt: UInt64
    let userTicks: UInt64
    let systemTicks: UInt64
    let timestamp: UInt64
    let memoryBytes: UInt64

    func cpuPercentage(since previous: Self, processorCount: Int) -> Double? {
        guard pid == previous.pid, startedAt == previous.startedAt,
              timestamp > previous.timestamp, processorCount > 0,
              userTicks >= previous.userTicks, systemTicks >= previous.systemTicks else { return nil }
        // proc_pid_rusage CPU times and mach_absolute_time use the same Mach tick units.
        let cpu = Double(userTicks - previous.userTicks) + Double(systemTicks - previous.systemTicks)
        return min(100, cpu / Double(timestamp - previous.timestamp) / Double(processorCount) * 100)
    }
}

struct ApplicationGrouping {
    let applications: [String: RunningApplicationDescriptor]
    private let direct: [Int32: String]
    private let parents: [Int32: Int32]

    init(applications descriptors: [RunningApplicationDescriptor],
         paths: [Int32: String], parents: [Int32: Int32]) {
        var applications: [String: RunningApplicationDescriptor] = [:]
        var direct: [Int32: String] = [:]
        // Prefer the outer app's name over the names of its nested helper apps.
        for app in descriptors.sorted(by: { $0.bundlePath.count < $1.bundlePath.count }) {
            guard let path = Self.bundlePath(containing: app.bundlePath) else { continue }
            if applications[path] == nil { applications[path] = app }
            direct[app.pid] = path
        }
        for (pid, path) in paths {
            if let bundle = Self.bundlePath(containing: path), applications[bundle] != nil {
                direct[pid] = bundle
            }
        }
        self.applications = applications
        self.direct = direct
        self.parents = parents
    }

    func applicationPath(for pid: Int32) -> String? {
        var current = pid
        var visited = Set<Int32>()
        while current > 1, visited.insert(current).inserted {
            if let app = direct[current] { return app }
            guard let parent = parents[current] else { break }
            current = parent
        }
        return nil
    }

    static func bundlePath(containing path: String) -> String? {
        let components = URL(fileURLWithPath: path).standardizedFileURL.pathComponents
        guard let last = components.firstIndex(where: { $0.hasSuffix(".app") }) else { return nil }
        return NSString.path(withComponents: Array(components[...last]))
    }
}

final class ApplicationSampler {
    private var previous: [Int32: ApplicationProcessSample] = [:]
    private var previousUptime: TimeInterval?

    func reset() {
        previous.removeAll()
        previousUptime = nil
    }

    func sample(applications: [RunningApplicationDescriptor]) -> ApplicationSnapshot {
        let uptime = ProcessInfo.processInfo.systemUptime
        if let previousUptime, uptime - previousUptime > 10 { reset() }
        guard let pids = currentUserPIDs() else {
            reset()
            return ApplicationSnapshot(cpuTop: [], memoryTop: [], sampledApplicationCount: 0,
                                       unavailableProcessCount: 0, unattributedProcessCount: 0,
                                       isWarmingUp: false, samplingError: "应用列表读取失败")
        }

        var samples: [Int32: ApplicationProcessSample] = [:]
        var paths: [Int32: String] = [:]
        var parents: [Int32: Int32] = [:]
        for pid in pids {
            var bsd = proc_bsdinfo()
            let size = MemoryLayout<proc_bsdinfo>.size
            if proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsd, Int32(size)) == size {
                parents[pid] = Int32(bsd.pbi_ppid)
            }
            var path = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
            if proc_pidpath(pid, &path, UInt32(path.count)) > 0 {
                paths[pid] = String(decoding: path.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            }
            samples[pid] = Self.readProcess(pid)
        }
        let grouping = ApplicationGrouping(applications: applications, paths: paths, parents: parents)
        let snapshot = Self.snapshot(pids: pids, samples: samples, previous: previous,
                                     grouping: grouping,
                                     processorCount: ProcessInfo.processInfo.activeProcessorCount)
        previous = samples
        previousUptime = uptime
        return snapshot
    }

    static func snapshot(pids: [Int32], samples: [Int32: ApplicationProcessSample],
                         previous: [Int32: ApplicationProcessSample], grouping: ApplicationGrouping,
                         processorCount: Int) -> ApplicationSnapshot {
        var grouped: [String: [Int32]] = [:]
        var unattributed = 0
        for pid in pids {
            if let path = grouping.applicationPath(for: pid) {
                grouped[path, default: []].append(pid)
            } else {
                unattributed += 1
            }
        }
        let usages = grouped.compactMap { path, pids -> ApplicationUsage? in
            guard let app = grouping.applications[path] else { return nil }
            let readings = pids.compactMap { samples[$0] }
            // Missing samples must not turn into a zero-byte application.
            guard !readings.isEmpty else { return nil }
            let percentages = readings.compactMap { reading in
                previous[reading.pid].flatMap {
                    reading.cpuPercentage(since: $0, processorCount: processorCount)
                }
            }
            return ApplicationUsage(id: path, name: app.name, bundlePath: path,
                                    processCount: readings.count,
                                    cpuPercentage: percentages.isEmpty ? nil : min(100, percentages.reduce(0, +)),
                                    memoryBytes: readings.reduce(0) { $0 + $1.memoryBytes },
                                    isPartial: readings.count != pids.count || percentages.count != readings.count)
        }
        let cpuTop = usages.filter { $0.cpuPercentage != nil }.sorted {
            if $0.cpuPercentage == $1.cpuPercentage { return $0.id < $1.id }
            return $0.cpuPercentage! > $1.cpuPercentage!
        }
        let memoryTop = usages.sorted {
            if $0.memoryBytes == $1.memoryBytes { return $0.id < $1.id }
            return $0.memoryBytes > $1.memoryBytes
        }
        return ApplicationSnapshot(cpuTop: Array(cpuTop.prefix(5)), memoryTop: Array(memoryTop.prefix(5)),
                                   sampledApplicationCount: usages.count,
                                   unavailableProcessCount: pids.count - samples.count,
                                   unattributedProcessCount: unattributed,
                                   isWarmingUp: previous.isEmpty && !samples.isEmpty)
    }

    static func readProcess(_ pid: Int32) -> ApplicationProcessSample? {
        var usage = rusage_info_v2()
        let result = withUnsafeMutablePointer(to: &usage) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V2, $0)
            }
        }
        guard result == 0, usage.ri_proc_exit_abstime == 0 else { return nil }
        return ApplicationProcessSample(pid: pid, startedAt: usage.ri_proc_start_abstime,
                                        userTicks: usage.ri_user_time, systemTicks: usage.ri_system_time,
                                        timestamp: mach_absolute_time(), memoryBytes: usage.ri_phys_footprint)
    }

    private func currentUserPIDs() -> [Int32]? {
        let required = proc_listpids(UInt32(PROC_UID_ONLY), getuid(), nil, 0)
        guard required > 0 else { return nil }
        // Processes can start between the size query and the list query.
        var capacity = Int(required) / MemoryLayout<Int32>.size + 64
        for _ in 0..<3 {
            var pids = [Int32](repeating: 0, count: capacity)
            let size = pids.count * MemoryLayout<Int32>.size
            let bytes = proc_listpids(UInt32(PROC_UID_ONLY), getuid(), &pids, Int32(size))
            guard bytes > 0 else { return nil }
            if bytes < size {
                return Array(pids.prefix(Int(bytes) / MemoryLayout<Int32>.size)).filter { $0 > 0 }
            }
            capacity *= 2
        }
        return nil
    }
}
