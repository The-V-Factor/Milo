import Testing

struct DiskMetricsTests {
    @Test func diskRateUsesPerDeviceDeltasAndActualElapsedTime() throws {
        let previous = DiskCounters(devices: [1: .init(read: 100, write: 200),
                                             2: .init(read: 500, write: 800)], timestamp: 10)
        let current = DiskCounters(devices: [1: .init(read: 400, write: 800),
                                            2: .init(read: 1_100, write: 2_000)], timestamp: 13)
        let rate = try #require(current.rate(since: previous))
        #expect(rate.read == 300)
        #expect(rate.write == 600)
    }

    @Test func idleDiskIsZeroButMissingDevicesAreUnavailable() throws {
        let devices: [UInt64: DiskDeviceCounters] = [1: .init(read: 100, write: 200)]
        let previous = DiskCounters(devices: devices, timestamp: 10)
        let rate = try #require(DiskCounters(devices: devices, timestamp: 13).rate(since: previous))
        #expect(rate.read == 0)
        #expect(rate.write == 0)
        #expect(DiskCounters(devices: [:], timestamp: 13).rate(since: previous) == nil)
    }

    @Test func hotplugAndCounterResetCannotBecomeRateSpikes() {
        let previous = DiskCounters(devices: [1: .init(read: 100, write: 200)], timestamp: 10)
        for devices: [UInt64: DiskDeviceCounters] in [
            [2: .init(read: 1_000_000, write: 2_000_000)],
            [1: .init(read: 100, write: 200), 2: .init(read: 1_000_000, write: 2_000_000)],
            [1: .init(read: 99, write: 200)],
            [1: .init(read: 100, write: 199)]
        ] {
            #expect(DiskCounters(devices: devices, timestamp: 13).rate(since: previous) == nil)
        }
    }

    @Test func diskRateRejectsInvalidIntervalsAndSleepGaps() {
        let devices: [UInt64: DiskDeviceCounters] = [1: .init(read: 100, write: 200)]
        let previous = DiskCounters(devices: devices, timestamp: 10)
        for timestamp in [9.0, 10.0, 21.0, Double.nan, Double.infinity] {
            #expect(DiskCounters(devices: devices, timestamp: timestamp).rate(since: previous) == nil)
        }
    }

    @Test func diskCapacityUsesAvailableBytesWithoutInventingPurgeableSpace() throws {
        let capacity = try #require(DiskCapacity(total: 1_000, available: 400))
        #expect(capacity.total == 1_000)
        #expect(capacity.available == 400)
        #expect(capacity.used == 600)
        #expect(capacity.percentage == 60)
        #expect(try #require(DiskCapacity(total: 1_000, available: 0)).percentage == 100)
        #expect(try #require(DiskCapacity(total: 1_000, available: 1_000)).percentage == 0)
        #expect(DiskCapacity(total: 0, available: 0) == nil)
        #expect(DiskCapacity(total: -1, available: 0) == nil)
        #expect(DiskCapacity(total: 1_000, available: -1) == nil)
        #expect(DiskCapacity(total: 1_000, available: 1_001) == nil)
    }
}
