import Foundation
import Testing

struct SystemMetricsTests {
    @Test func cpuUsesDeltasAndIncludesNiceTime() throws {
        let previous = CPUTicks(user: 100, system: 100, idle: 100, nice: 10)
        let current = CPUTicks(user: 120, system: 110, idle: 165, nice: 15)
        let usage = try #require(current.usage(since: previous))
        #expect(usage.user == 25)
        #expect(usage.system == 10)
        #expect(usage.total == 35)
        #expect(usage.idle == 65)
    }

    @Test func unchangedCountersAreUnavailable() {
        let ticks = CPUTicks(user: 1, system: 2, idle: 3, nice: 0)
        #expect(ticks.usage(since: ticks) == nil)
    }

    @Test func cpuHandlesCounterWrap() throws {
        let previous = CPUTicks(user: UInt32.max - 4, system: 0, idle: 0, nice: 0)
        let current = CPUTicks(user: 5, system: 0, idle: 10, nice: 0)
        #expect(try #require(current.usage(since: previous)).total == 50)
    }

    @Test(arguments: [UInt64(4096), UInt64(16384)])
    func memoryAccountsForPagesWithoutCountingSpeculativeTwice(pageSize: UInt64) {
        let memory = MemoryUsage(total: 1000 * pageSize, pageSize: pageSize,
                                 internalPages: 400, purgeablePages: 50, wiredPages: 100,
                                 compressedPages: 100, freePages: 150, speculativePages: 20,
                                 externalPages: 270)
        #expect(memory.app == 350 * pageSize)
        #expect(memory.used == 550 * pageSize)
        #expect(memory.free == 130 * pageSize)
        #expect(memory.cached == 320 * pageSize)
        #expect(memory.used + memory.free + memory.cached == memory.total)
        #expect(abs(memory.percentage - 55) < 0.0001)
    }

    @Test func transientPageCountsDoNotUnderflow() {
        let memory = MemoryUsage(total: 0, pageSize: 4096, internalPages: 1, purgeablePages: 2,
                                 wiredPages: 0, compressedPages: 0, freePages: 1,
                                 speculativePages: 2, externalPages: 0)
        #expect(memory.app == 0)
        #expect(memory.free == 0)
        #expect(memory.percentage == 0)
    }

    @Test func unavailableAndBinaryUnitsAreExplicit() {
        #expect(MetricFormat.percent(nil) == "—")
        #expect(MetricFormat.bytes(nil) == "—")
        #expect(MetricFormat.bytes(1_073_741_824) == "1.00 GiB")
        #expect(MetricFormat.bytes(1_048_576) == "1 MiB")
    }

    @Test func liveSamplingAndReset() async throws {
        let sampler = SystemSampler()
        let first = sampler.sample()
        #expect(first.cpu == nil)
        #expect(first.errors.isEmpty)
        #expect(try #require(first.memory).total == ProcessInfo.processInfo.physicalMemory)
        #expect(try #require(first.load).one >= 0)
        #expect(first.swapUsed != nil)
        try await Task.sleep(for: .seconds(1))
        let second = sampler.sample()
        #expect(second.errors.isEmpty)
        let cpu = try #require(second.cpu)
        #expect((0...100).contains(cpu.total))
        sampler.reset()
        #expect(sampler.sample().cpu == nil)
        print("Live sample: CPU \(MetricFormat.percent(cpu.total)), memory \(MetricFormat.bytes(second.memory?.used)) / \(MetricFormat.bytes(second.memory?.total)), load \(second.load?.one ?? -1)")
    }
}
