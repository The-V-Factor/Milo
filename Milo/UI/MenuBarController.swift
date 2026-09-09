import AppKit
import Combine
import SwiftUI

@MainActor
final class MenuBarController: NSObject, NSPopoverDelegate {
    private let monitor = SystemMonitor()
    private let item = NSStatusBar.system.statusItem(withLength: 190)
    private let popover = NSPopover()
    private var subscription: AnyCancellable?
    private var hoverTask: DispatchWorkItem?
    private var trackingArea: NSTrackingArea?
    private var pointerTimer: Timer?
    private var outsideSince: Date?
    private var globalClickMonitor: Any?
    private var localEventMonitor: Any?

    override init() {
        super.init()
        popover.behavior = .applicationDefined
        popover.animates = false
        popover.delegate = self
        let hostingController = NSHostingController(rootView: DashboardView(monitor: monitor))
        hostingController.view.wantsLayer = true
        hostingController.view.layer?.backgroundColor = NSColor.clear.cgColor
        popover.contentViewController = hostingController

        if let button = item.button {
            button.image = NSImage(systemSymbolName: "cpu", accessibilityDescription: "Milo")
            button.imagePosition = .imageLeading
            button.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
            button.target = self
            button.action = #selector(togglePopover)
            let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
            button.addTrackingArea(area)
            trackingArea = area
        }

        subscription = monitor.$snapshot.sink { [weak self] snapshot in
            let cpu = MetricFormat.percent(snapshot?.cpu?.total)
            let memory = MetricFormat.percent(snapshot?.memory?.percentage)
            self?.item.button?.title = " CPU \(cpu) · MEM \(memory)"
            self?.item.button?.setAccessibilityLabel("Milo，CPU \(cpu)，内存 \(memory)，点击查看详情")
        }
        monitor.start()
    }

    @objc func mouseEntered(with event: NSEvent) {
        hoverTask?.cancel()
        let task = DispatchWorkItem { [weak self] in self?.showPopover() }
        hoverTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: task)
    }

    @objc func mouseExited(with event: NSEvent) {
        hoverTask?.cancel()
    }

    @objc private func togglePopover() {
        hoverTask?.cancel()
        if popover.isShown && monitor.isPinned {
            popover.close()
        } else {
            monitor.isPinned = true
            showPopover()
            NSApp.activate(ignoringOtherApps: true)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func showPopover() {
        guard !popover.isShown, let button = item.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        if let window = popover.contentViewController?.view.window {
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
        }
        button.highlight(true)
        outsideSince = nil
        let timer = Timer(timeInterval: 0.15, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkPointer() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pointerTimer = timer
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.popover.close() }
        }
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            let consumeEvent = MainActor.assumeIsolated {
                guard let self else { return false }
                if event.type == .keyDown {
                    if event.keyCode == 53 {
                        self.popover.close()
                        return true
                    }
                } else if event.window !== self.popover.contentViewController?.view.window,
                          event.window !== self.item.button?.window {
                    self.popover.close()
                }
                return false
            }
            return consumeEvent ? nil : event
        }
    }

    private func checkPointer() {
        guard !monitor.isPinned else { return }
        let point = NSEvent.mouseLocation
        let panelContainsPointer = popover.contentViewController?.view.window?.frame.contains(point) ?? false
        var buttonContainsPointer = false
        if let button = item.button, let window = button.window {
            buttonContainsPointer = window.convertToScreen(button.convert(button.bounds, to: nil)).contains(point)
        }
        if panelContainsPointer || buttonContainsPointer {
            outsideSince = nil
        } else if let outsideSince {
            if Date().timeIntervalSince(outsideSince) > 0.3 { popover.close() }
        } else {
            outsideSince = Date()
        }
    }

    func popoverDidClose(_ notification: Notification) {
        monitor.isPinned = false
        item.button?.highlight(false)
        pointerTimer?.invalidate()
        pointerTimer = nil
        if let globalClickMonitor { NSEvent.removeMonitor(globalClickMonitor) }
        if let localEventMonitor { NSEvent.removeMonitor(localEventMonitor) }
        globalClickMonitor = nil
        localEventMonitor = nil
    }

    func stop() {
        hoverTask?.cancel()
        popover.close()
        monitor.stop()
        if let trackingArea { item.button?.removeTrackingArea(trackingArea) }
        NSStatusBar.system.removeStatusItem(item)
    }
}
