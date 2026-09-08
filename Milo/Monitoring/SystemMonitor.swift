import AppKit
import Combine

@MainActor
final class SystemMonitor: ObservableObject {
    @Published private(set) var snapshot: SystemSnapshot?
    @Published private(set) var cpuHistory: [Double?] = []
    @Published private(set) var memoryHistory: [Double?] = []
    @Published var isPinned = false

    private let sampler = SystemSampler()
    private var timer: Timer?
    private var sleepObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?

    func start() {
        sample()
        startTimer()
        let center = NSWorkspace.shared.notificationCenter
        sleepObserver = center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.timer?.invalidate() }
        }
        wakeObserver = center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.sampler.reset()
                self.cpuHistory.removeAll()
                self.memoryHistory.removeAll()
                self.sample()
                self.startTimer()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
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
        if cpuHistory.count > 60 { cpuHistory.removeFirst(cpuHistory.count - 60) }
        if memoryHistory.count > 60 { memoryHistory.removeFirst(memoryHistory.count - 60) }
    }
}
