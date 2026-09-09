import AppKit
import SwiftUI

struct DashboardView: View {
    @ObservedObject var monitor: SystemMonitor
    @AppStorage("panelOpacity") private var panelOpacity = 0.92
    @AppStorage("nightMode") private var nightMode = true
    private let mint = Color(red: 0.22, green: 0.76, blue: 0.62)
    private let blue = Color(red: 0.36, green: 0.61, blue: 0.96)

    var body: some View {
        VStack(spacing: 16) {
            header
            VStack(alignment: .leading, spacing: 12) {
                metricTitle("CPU", subtitle: "处理器", value: MetricFormat.percent(monitor.snapshot?.cpu?.total), color: mint)
                Sparkline(values: monitor.cpuHistory, color: mint)
                    .frame(height: 40)
                HStack {
                    detail("用户", MetricFormat.percent(monitor.snapshot?.cpu?.user))
                    Spacer()
                    detail("系统", MetricFormat.percent(monitor.snapshot?.cpu?.system))
                    Spacer()
                    detail("空闲", MetricFormat.percent(monitor.snapshot?.cpu?.idle))
                }
                Divider()
                HStack {
                    Text("平均负载").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(ProcessInfo.processInfo.activeProcessorCount) 个逻辑核心").font(.caption2).foregroundStyle(.tertiary)
                }
                HStack {
                    load("1 分钟", monitor.snapshot?.load?.one)
                    Spacer()
                    load("5 分钟", monitor.snapshot?.load?.five)
                    Spacer()
                    load("15 分钟", monitor.snapshot?.load?.fifteen)
                }
            }
            .padding(16)
            .background(.thinMaterial.opacity(0.58), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .strokeBorder(.white.opacity(0.11), lineWidth: 0.6)
            }

            VStack(alignment: .leading, spacing: 12) {
                metricTitle("MEMORY", subtitle: "内存", value: MetricFormat.percent(monitor.snapshot?.memory?.percentage), color: blue)
                Sparkline(values: monitor.memoryHistory, color: blue)
                    .frame(height: 32)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(MetricFormat.bytes(monitor.snapshot?.memory?.used)).font(.system(size: 20, weight: .semibold, design: .rounded))
                    Text("/ \(MetricFormat.bytes(monitor.snapshot?.memory?.total)) 已用").font(.caption).foregroundStyle(.secondary)
                }
                Divider()
                Grid(horizontalSpacing: 20, verticalSpacing: 8) {
                    memoryRow("应用", monitor.snapshot?.memory?.app, "有线", monitor.snapshot?.memory?.wired)
                    memoryRow("压缩", monitor.snapshot?.memory?.compressed, "缓存", monitor.snapshot?.memory?.cached)
                    memoryRow("空闲 Free", monitor.snapshot?.memory?.free, "交换 Swap", monitor.snapshot?.swapUsed)
                }
                Text("已用 = 应用 + 有线 + 压缩；缓存可被系统回收。")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            .padding(16)
            .background(.thinMaterial.opacity(0.58), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .strokeBorder(.white.opacity(0.11), lineWidth: 0.6)
            }

            if let errors = monitor.snapshot?.errors, !errors.isEmpty {
                Label(errors.joined(separator: " · "), systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            }
            footer
        }
        .padding(20)
        .frame(width: 360)
        .fixedSize(horizontal: false, vertical: true)
        .monospacedDigit()
        .background {
            GlassBackground(opacity: panelOpacity, nightMode: nightMode)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(.white.opacity(0.18 * panelOpacity), lineWidth: 0.8)
        }
        .shadow(color: .black.opacity(0.22), radius: 24, y: 10)
        .preferredColorScheme(nightMode ? .dark : .light)
    }

    private var header: some View {
        HStack(spacing: 10) {
            HStack(spacing: 4) {
                Capsule().fill(mint).frame(width: 5, height: 12)
                Capsule().fill(mint).frame(width: 5, height: 12)
            }
            .frame(width: 36, height: 30)
            .background(mint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 1) {
                Text("Milo").font(.system(size: 20, weight: .bold, design: .rounded))
                Text("你的 Mac，运行此刻").font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 4) {
                Circle().fill(monitor.snapshot?.errors.isEmpty == true ? mint : .orange).frame(width: 5, height: 5)
                Text("每秒更新").font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "circle.lefthalf.filled")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text("透明度")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Slider(value: $panelOpacity, in: 0...1.0, step: 0.01)
                    .controlSize(.small)
                    .tint(mint)
                    .accessibilityLabel("面板透明度")
                Text("\(Int(panelOpacity * 100))%")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, alignment: .trailing)
            }
            HStack {
                Label(monitor.isPinned ? "已固定 · 点击外部关闭" : "悬停预览 · 点击菜单栏固定",
                      systemImage: monitor.isPinned ? "pin.fill" : "cursorarrow")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer()
                Button {
                    nightMode.toggle()
                } label: {
                    Image(systemName: nightMode ? "sun.max.fill" : "moon.fill")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundStyle(nightMode ? .orange : .indigo)
                .help(nightMode ? "切换到日间样式" : "切换到夜间样式")
                .accessibilityLabel(nightMode ? "切换到日间样式" : "切换到夜间样式")
                Button { NSApp.terminate(nil) } label: {
                    Image(systemName: "power").font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("退出 Milo")
                .accessibilityLabel("退出 Milo")
            }
        }
    }

    private func metricTitle(_ title: String, subtitle: String, value: String, color: Color) -> some View {
        HStack(alignment: .firstTextBaseline) {
            HStack(spacing: 6) {
                Text(title).font(.system(size: 11, weight: .bold)).tracking(1.2)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(value).font(.system(size: 29, weight: .semibold, design: .rounded)).foregroundStyle(color)
        }
    }

    private func detail(_ title: String, _ value: String) -> some View {
        HStack(spacing: 5) {
            Text(title).foregroundStyle(.secondary)
            Text(value)
        }.font(.caption)
    }

    private func load(_ title: String, _ value: Double?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value.map { String(format: "%.2f", $0) } ?? "—").font(.system(size: 16, weight: .medium, design: .rounded))
            Text(title).font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }

    private func memoryRow(_ first: String, _ firstValue: UInt64?, _ second: String, _ secondValue: UInt64?) -> some View {
        GridRow {
            HStack { Text(first).foregroundStyle(.secondary); Spacer(); Text(MetricFormat.bytes(firstValue)) }
            HStack { Text(second).foregroundStyle(.secondary); Spacer(); Text(MetricFormat.bytes(secondValue)) }
        }.font(.system(size: 10))
    }
}

private struct GlassBackground: NSViewRepresentable {
    let opacity: Double
    let nightMode: Bool

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        view.appearance = NSAppearance(named: nightMode ? .darkAqua : .aqua)
        view.alphaValue = opacity
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.08
            view.appearance = NSAppearance(named: nightMode ? .darkAqua : .aqua)
            view.animator().alphaValue = opacity
        }
    }
}

private struct Sparkline: View {
    let values: [Double?]
    let color: Color

    var body: some View {
        Canvas { context, size in
            for fraction in [0.0, 0.5, 1.0] {
                var line = Path()
                let y = 1 + (size.height - 2) * fraction
                line.move(to: CGPoint(x: 0, y: y))
                line.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(line, with: .color(.secondary.opacity(0.12)), style: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
            }
            var path = Path()
            var hasPrevious = false
            for (index, value) in values.enumerated() {
                guard let value else { hasPrevious = false; continue }
                let x = size.width * Double(60 - values.count + index) / 59
                let y = 1 + (size.height - 2) * (1 - min(100, max(0, value)) / 100)
                if hasPrevious { path.addLine(to: CGPoint(x: x, y: y)) }
                else { path.move(to: CGPoint(x: x, y: y)) }
                hasPrevious = true
            }
            context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
        }
        .accessibilityLabel("最近 60 次采样趋势，纵轴 0 到 100 百分比")
        .help("最近 60 次采样 · 0–100% · 约每秒一次")
    }
}
