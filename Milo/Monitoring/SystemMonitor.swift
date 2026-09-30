import AppKit
import Combine

@MainActor
final class SystemMonitor: ObservableObject {
    @Published private(set) var snapshot: SystemSnapshot?
    @Published private(set) var cpuHistory: [Double?] = []
    @Published private(set) var memoryHistory: [Double?] = []
    @Published private(set) var swapHistory = SwapHistory()
    @Published private(set) var applications: ApplicationSnapshot?
    @Published private(set) var disk: DiskSnapshot?
    @Published var isPinned = false

    private let sampler = SystemSampler()
    private let resourceSampler = ResourceSampler()
    private var resourceTask: Task<Void, Never>?
    private var lastResourceSample: TimeInterval = -.infinity
    private var timer: Timer?
    private var sleepObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?

    func start() {
        sample()
        startTimer()
        let center = NSWorkspace.shared.notificationCenter
        sleepObserver = center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.timer?.invalidate()
                self?.resourceTask?.cancel()
            }
        }
        wakeObserver = center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.sampler.reset()
                self.cpuHistory.removeAll()
                self.memoryHistory.removeAll()
                self.swapHistory = SwapHistory()
                self.resourceTask?.cancel()
                self.resourceTask = nil
                self.lastResourceSample = -.infinity
                self.applications = nil
                self.disk = nil
                self.sample()
                self.startTimer()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        resourceTask?.cancel()
        resourceTask = nil
        let center = NSWorkspace.shared.notificationCenter
        if let sleepObserver { center.removeObserver(sleepObserver) }
        if let wakeObserver { center.removeObserver(wakeObserver) }
        sleepObserver = nil
        wakeObserver = nil
    }

    private func startTimer() {
        timer?.invalidate()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }
        timer.tolerance = 0.15
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func sample() {
        let snapshot = sampler.sample()
        self.snapshot = snapshot
        cpuHistory.append(snapshot.cpu?.total)
        memoryHistory.append(snapshot.memory?.percentage)
        swapHistory.append(snapshot.swapRate)
        if cpuHistory.count > 60 { cpuHistory.removeFirst(cpuHistory.count - 60) }
        if memoryHistory.count > 60 { memoryHistory.removeFirst(memoryHistory.count - 60) }
        sampleResources()
    }

    private func sampleResources() {
        let now = ProcessInfo.processInfo.systemUptime
        guard resourceTask == nil, now - lastResourceSample >= 3 else { return }
        let reset = !lastResourceSample.isFinite
        lastResourceSample = now
        let running = NSWorkspace.shared.runningApplications.compactMap { app -> RunningApplicationDescriptor? in
            guard app.activationPolicy != .prohibited, let url = app.bundleURL else { return nil }
            return RunningApplicationDescriptor(pid: app.processIdentifier,
                                                name: app.localizedName ?? url.deletingPathExtension().lastPathComponent,
                                                bundlePath: url.path)
        }
        let resourceSampler = resourceSampler
        resourceTask = Task { [weak self] in
            let result = await resourceSampler.sample(applications: running, reset: reset)
            guard !Task.isCancelled, let self else { return }
            self.applications = result.0
            self.disk = result.1
            self.resourceTask = nil
        }
    }
}

private actor ResourceSampler {
    private let applications = ApplicationSampler()
    private let disk = DiskSampler()

    func sample(applications running: [RunningApplicationDescriptor], reset: Bool) -> (ApplicationSnapshot, DiskSnapshot) {
        if reset {
            applications.reset()
            disk.reset()
        }
        return (applications.sample(applications: running), disk.sample())
    }
}
