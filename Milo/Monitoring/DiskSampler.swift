import Foundation
import IOKit

struct DiskCapacity: Sendable {
    let total: UInt64
    let available: UInt64

    init?(total: Int, available: Int) {
        guard total > 0, available >= 0, available <= total else { return nil }
        self.total = UInt64(total)
        self.available = UInt64(available)
    }

    // APFS volumes share container space. This is total minus currently available
    // capacity, not the size of files belonging exclusively to the Data volume.
    var used: UInt64 { total - available }
    var percentage: Double { Double(used) / Double(total) * 100 }
}

struct DiskIORate: Sendable {
    let read: Double
    let write: Double
}

struct DiskDeviceCounters: Sendable {
    let read: UInt64
    let write: UInt64
}

struct DiskCounters: Sendable {
    let devices: [UInt64: DiskDeviceCounters]
    let timestamp: TimeInterval

    func rate(since previous: DiskCounters) -> DiskIORate? {
        let elapsed = timestamp - previous.timestamp
        guard elapsed > 0, elapsed <= 10, !devices.isEmpty,
              devices.keys.sorted() == previous.devices.keys.sorted() else { return nil }
        var read = 0.0
        var write = 0.0
        for (id, current) in devices {
            guard let old = previous.devices[id],
                  current.read >= old.read, current.write >= old.write else { return nil }
            read += Double(current.read - old.read)
            write += Double(current.write - old.write)
        }
        return DiskIORate(read: read / elapsed, write: write / elapsed)
    }
}

struct DiskSnapshot: Sendable {
    let capacity: DiskCapacity?
    let ioRate: DiskIORate?
    let deviceCount: Int
}

final class DiskSampler {
    private let origin = ContinuousClock.now
    private var previousCounters: DiskCounters?
    private var capacity: DiskCapacity?
    private var capacityTimestamp: TimeInterval?

    func reset() {
        previousCounters = nil
        capacityTimestamp = nil
    }

    func sample() -> DiskSnapshot {
        let timestamp = continuousTime()
        if capacityTimestamp.map({ timestamp - $0 >= 30 }) ?? true {
            capacity = readCapacity()
            capacityTimestamp = timestamp
        }
        let counters = readCounters()
        let rate = counters.flatMap { current in
            previousCounters.flatMap { current.rate(since: $0) }
        }
        previousCounters = counters
        return DiskSnapshot(capacity: capacity, ioRate: rate, deviceCount: counters?.devices.count ?? 0)
    }

    private func continuousTime() -> TimeInterval {
        // ContinuousClock includes sleep, so a missed wake notification cannot
        // turn accumulated disk activity into a short-interval spike.
        let duration = origin.duration(to: .now).components
        return Double(duration.seconds) + Double(duration.attoseconds) / 1e18
    }

    private func readCapacity() -> DiskCapacity? {
        let volume = URL(fileURLWithPath: "/System/Volumes/Data", isDirectory: true)
        guard let values = try? volume.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey]),
              let total = values.volumeTotalCapacity, let available = values.volumeAvailableCapacity else { return nil }
        return DiskCapacity(total: total, available: available)
    }

    private func readCounters() -> DiskCounters? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOBlockStorageDriver"), &iterator)
                == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }

        var devices: [UInt64: DiskDeviceCounters] = [:]
        while case let driver = IOIteratorNext(iterator), driver != 0 {
            defer { IOObjectRelease(driver) }
            var provider: io_registry_entry_t = 0
            guard IORegistryEntryGetParentEntry(driver, kIOServicePlane, &provider) == KERN_SUCCESS else { return nil }
            defer { IOObjectRelease(provider) }
            guard IOObjectConformsTo(provider, "IOBlockStorageDevice") != 0,
                  let characteristics = property(provider, "Protocol Characteristics") as? [String: Any],
                  let interconnect = characteristics["Physical Interconnect"] as? String,
                  !interconnect.isEmpty, interconnect != "Virtual Interface" else { continue }

            var id: UInt64 = 0
            guard IORegistryEntryGetRegistryEntryID(provider, &id) == KERN_SUCCESS else { return nil }
            // Count each backing device once, never its APFS volumes or partitions.
            if devices[id] != nil { continue }
            guard let statistics = property(driver, "Statistics") as? [String: Any],
                  let read = statistics["Bytes (Read)"] as? NSNumber,
                  let write = statistics["Bytes (Write)"] as? NSNumber else { return nil }
            devices[id] = DiskDeviceCounters(read: read.uint64Value, write: write.uint64Value)
        }
        guard !devices.isEmpty else { return nil }
        return DiskCounters(devices: devices, timestamp: continuousTime())
    }

    private func property(_ entry: io_registry_entry_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }
}
