import Foundation

struct CPUTicks {
    let user: UInt32
    let system: UInt32
    let idle: UInt32
    let nice: UInt32

    func usage(since previous: CPUTicks) -> CPUUsage? {
        // Mach counters are unsigned 32-bit values and can wrap on long uptimes.
        let userDelta = Double(user &- previous.user) + Double(nice &- previous.nice)
        let systemDelta = Double(system &- previous.system)
        let idleDelta = Double(idle &- previous.idle)
        let total = userDelta + systemDelta + idleDelta
        guard total > 0 else { return nil }
        return CPUUsage(user: userDelta / total * 100, system: systemDelta / total * 100)
    }
}

struct CPUUsage {
    let user: Double
    let system: Double
    var total: Double { user + system }
    var idle: Double { max(0, 100 - total) }
}

struct LoadAverage {
    let one: Double
    let five: Double
    let fifteen: Double
}

struct MemoryUsage {
    let total: UInt64
    let app: UInt64
    let wired: UInt64
    let compressed: UInt64
    let free: UInt64
    let cached: UInt64

    init(total: UInt64, pageSize: UInt64, internalPages: UInt64, purgeablePages: UInt64,
         wiredPages: UInt64, compressedPages: UInt64, freePages: UInt64,
         speculativePages: UInt64, externalPages: UInt64) {
        self.total = total
        app = (internalPages - min(internalPages, purgeablePages)) * pageSize
        wired = wiredPages * pageSize
        compressed = compressedPages * pageSize
        // Speculative pages appear in both free_count and external_page_count.
        // Exclude them from free; externalPages already counts them in cache.
        free = (freePages - min(freePages, speculativePages)) * pageSize
        cached = (externalPages + purgeablePages) * pageSize
    }

    var used: UInt64 { app + wired + compressed }
    var percentage: Double { total == 0 ? 0 : min(100, Double(used) / Double(total) * 100) }
}

struct SystemSnapshot {
    let cpu: CPUUsage?
    let load: LoadAverage?
    let memory: MemoryUsage?
    let swapUsed: UInt64?
    let errors: [String]
}

enum MetricFormat {
    static func percent(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.0f%%", value)
    }

    static func bytes(_ value: UInt64?) -> String {
        guard let value else { return "—" }
        let gib = Double(value) / 1_073_741_824
        if gib >= 1 { return String(format: "%.2f GiB", gib) }
        return String(format: "%.0f MiB", Double(value) / 1_048_576)
    }
}
