import Darwin
import Foundation
import Testing

struct ApplicationMetricsTests {
    private func reading(_ pid: Int32 = 10, start: UInt64 = 1,
                         cpu: UInt64 = 100, timestamp: UInt64 = 100,
                         memory: UInt64 = 100) -> ApplicationProcessSample {
        ApplicationProcessSample(pid: pid, startedAt: start, userTicks: cpu,
                                 systemTicks: 0, timestamp: timestamp, memoryBytes: memory)
    }

    @Test func cpuUsesMachTicksAndWholeMachineNormalization() throws {
        let old = reading(cpu: 100, timestamp: 100)
        let new = reading(cpu: 300, timestamp: 200)
        #expect(try #require(new.cpuPercentage(since: old, processorCount: 4)) == 50)
        #expect(reading(cpu: 100, timestamp: 200).cpuPercentage(since: old, processorCount: 4) == 0)
        #expect(reading(start: 2, cpu: 300, timestamp: 200).cpuPercentage(since: old, processorCount: 4) == nil)
        #expect(reading(cpu: 99, timestamp: 200).cpuPercentage(since: old, processorCount: 4) == nil)
        #expect(old.cpuPercentage(since: old, processorCount: 4) == nil)
    }

    @Test func groupsNestedHelpersAndChildrenWithoutMixingSeparateApps() {
        let grouping = ApplicationGrouping(applications: [
            RunningApplicationDescriptor(pid: 10, name: "Browser", bundlePath: "/Applications/Browser.app"),
            RunningApplicationDescriptor(pid: 20, name: "Editor", bundlePath: "/Applications/Editor.app")
        ], paths: [11: "/Applications/Browser.app/Contents/Frameworks/Helper.app/Contents/MacOS/Helper",
                   21: "/Applications/Editor.app/Contents/MacOS/Editor",
                   30: "/usr/libexec/shared-helper"],
           parents: [11: 1, 12: 11, 21: 10, 30: 1, 31: 32, 32: 31])
        #expect(grouping.applicationPath(for: 11) == "/Applications/Browser.app")
        #expect(grouping.applicationPath(for: 12) == "/Applications/Browser.app")
        #expect(grouping.applicationPath(for: 21) == "/Applications/Editor.app")
        #expect(grouping.applicationPath(for: 30) == nil)
        #expect(grouping.applicationPath(for: 31) == nil)
    }

    @Test func missingAndNewProcessesRemainExplicitWhileHelpersAreSummed() throws {
        let grouping = ApplicationGrouping(applications: [
            RunningApplicationDescriptor(pid: 10, name: "Browser", bundlePath: "/Applications/Browser.app")
        ], paths: [:], parents: [11: 10, 12: 10, 13: 10])
        let samples: [Int32: ApplicationProcessSample] = [10: reading(cpu: 300, timestamp: 200, memory: 200),
                       11: reading(11, cpu: 200, timestamp: 200, memory: 300),
                       12: reading(12, cpu: 20, timestamp: 200, memory: 50)]
        let previous: [Int32: ApplicationProcessSample] = [10: reading(), 11: reading(11)]
        let snapshot = ApplicationSampler.snapshot(pids: [10, 11, 12, 13, 30], samples: samples,
                                                    previous: previous, grouping: grouping, processorCount: 4)
        let app = try #require(snapshot.cpuTop.first)
        #expect(app.cpuPercentage == 75)
        #expect(app.memoryBytes == 550)
        #expect(app.processCount == 3)
        #expect(app.isPartial)
        #expect(snapshot.unavailableProcessCount == 2)
        #expect(snapshot.unattributedProcessCount == 1)
        let initial = ApplicationSampler.snapshot(pids: [10], samples: [10: reading()], previous: [:],
                                                  grouping: grouping, processorCount: 4)
        #expect(initial.cpuTop.isEmpty)
        #expect(initial.memoryTop.count == 1)
        #expect(initial.isWarmingUp)
        let unavailable = ApplicationSampler.snapshot(pids: [10], samples: [:], previous: previous,
                                                      grouping: grouping, processorCount: 4)
        #expect(unavailable.memoryTop.isEmpty)
    }

    @Test func topFiveUseIndependentRankings() {
        let descriptors = (10...16).map {
            RunningApplicationDescriptor(pid: Int32($0), name: "App \($0)", bundlePath: "/App\($0).app")
        }
        let grouping = ApplicationGrouping(applications: descriptors, paths: [:], parents: [:])
        let samples = Dictionary(uniqueKeysWithValues: (10...16).map {
            (Int32($0), reading(Int32($0), cpu: UInt64($0), timestamp: 200, memory: UInt64(100 - $0)))
        })
        let previous = Dictionary(uniqueKeysWithValues: (10...16).map { (Int32($0), reading(Int32($0), cpu: 0)) })
        let snapshot = ApplicationSampler.snapshot(pids: Array(samples.keys), samples: samples,
                                                    previous: previous, grouping: grouping, processorCount: 4)
        #expect(snapshot.cpuTop.count == 5)
        #expect(snapshot.memoryTop.count == 5)
        #expect(snapshot.cpuTop.first?.name == "App 16")
        #expect(snapshot.memoryTop.first?.name == "App 10")
    }

    @Test func liveSelfSampleUsesSameClockAsMachAbsoluteTime() throws {
        let pid = getpid()
        let before = try #require(ApplicationSampler.readProcess(pid))
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        let duration = UInt64(50_000_000) * UInt64(timebase.denom) / UInt64(timebase.numer)
        while mach_absolute_time() - before.timestamp < duration { _ = getpid() }
        let after = try #require(ApplicationSampler.readProcess(pid))
        let oneCore = try #require(after.cpuPercentage(since: before, processorCount: 1))
        // On Apple silicon, confusing ticks with nanoseconds gives a ~42x error.
        #expect(oneCore > 5)
        #expect(oneCore <= 100)
        #expect(after.memoryBytes > 0)
    }
}
