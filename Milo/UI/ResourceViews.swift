import SwiftUI

struct ApplicationListsView: View {
    let snapshot: ApplicationSnapshot?
    private let mint = Color(red: 0.22, green: 0.76, blue: 0.62)
    private let blue = Color(red: 0.36, green: 0.61, blue: 0.96)

    var body: some View {
        VStack(spacing: 16) {
            ranking("CPU 前 5", apps: snapshot?.cpuTop ?? [], color: mint, isCPU: true)
            ranking("内存前 5", apps: snapshot?.memoryTop ?? [], color: blue, isCPU: false)
            VStack(alignment: .leading, spacing: 5) {
                Text(coverage)
                Text("合并当前用户的应用及辅助进程；系统进程及归属不明的共享服务不计入。带 * 的项目有进程不可读或尚未完成 CPU 采样。")
                Text("CPU 按整机 0–100% 计算；内存为进程 footprint 合计（含压缩），不等于概览中的已用内存。")
            }
            .font(.system(size: 10)).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var coverage: String {
        guard let snapshot else { return "正在读取应用信息…" }
        if let error = snapshot.samplingError { return error }
        return "已统计 \(snapshot.sampledApplicationCount) 个应用 · \(snapshot.unavailableProcessCount) 个进程不可读 · \(snapshot.unattributedProcessCount) 个未归属"
    }

    private func ranking(_ title: String, apps: [ApplicationUsage], color: Color, isCPU: Bool) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(title).font(.system(size: 12, weight: .semibold))
                Spacer()
                Text(isCPU ? "整机占比" : "占用 / 整机占比")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            if apps.isEmpty {
                Text(snapshot?.samplingError ?? (snapshot == nil || (isCPU && snapshot?.isWarmingUp == true)
                     ? "正在采样，稍等片刻…" : "暂无可读取的应用数据"))
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 50)
            } else {
                ForEach(Array(apps.enumerated()), id: \.element.id) { index, app in
                    HStack(spacing: 8) {
                        Text("\(index + 1)")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(color)
                            .frame(width: 14)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(app.name + (app.isPartial ? " *" : ""))
                                .font(.system(size: 12, weight: .medium))
                                .lineLimit(1).truncationMode(.middle)
                            Text("\(app.processCount) 个进程")
                                .font(.system(size: 9)).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 4)
                        if isCPU {
                            Text(app.cpuPercentage.map { String(format: "%.1f%%", $0) } ?? "—")
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundStyle(color)
                        } else {
                            VStack(alignment: .trailing, spacing: 3) {
                                Text(MetricFormat.bytes(app.memoryBytes))
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .foregroundStyle(color)
                                Text(String(format: "%.1f%%", Double(app.memoryBytes) / Double(ProcessInfo.processInfo.physicalMemory) * 100))
                                    .font(.system(size: 9)).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .help(app.name + "\n" + app.bundlePath)
                }
            }
        }
        .resourceCard()
    }
}

struct DiskDashboardView: View {
    let snapshot: DiskSnapshot?
    private let blue = Color(red: 0.36, green: 0.61, blue: 0.96)
    private let mint = Color(red: 0.22, green: 0.76, blue: 0.62)

    var body: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 14) {
                Label("启动数据卷", systemImage: "internaldrive")
                    .font(.system(size: 12, weight: .semibold))
                HStack(alignment: .firstTextBaseline) {
                    Text(MetricFormat.bytes(snapshot?.capacity?.used))
                        .font(.system(size: 25, weight: .semibold, design: .rounded))
                    Text("已用").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                }
                ProgressView(value: snapshot?.capacity?.percentage ?? 0, total: 100)
                    .tint(blue)
                    .opacity(snapshot?.capacity == nil ? 0.3 : 1)
                    .accessibilityLabel("启动数据卷已用比例")
                HStack {
                    capacityValue("可用", snapshot?.capacity?.available)
                    Spacer()
                    capacityValue("总量", snapshot?.capacity?.total)
                }
                Text(snapshot != nil && snapshot?.capacity == nil
                     ? "暂时无法读取启动数据卷容量。"
                     : "容量约每 30 秒更新；APFS 卷共享空间，可用容量不包含可清理空间。")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            .resourceCard()

            VStack(alignment: .leading, spacing: 16) {
                Label("物理磁盘总读写", systemImage: "arrow.left.arrow.right")
                    .font(.system(size: 12, weight: .semibold))
                HStack {
                    transferValue("读取", value: snapshot?.ioRate?.read, color: blue)
                    Spacer()
                    transferValue("写入", value: snapshot?.ioRate?.write, color: mint)
                }
                Text(ioDescription)
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            .resourceCard()
        }
    }

    private var ioDescription: String {
        guard let snapshot else { return "正在读取磁盘信息…" }
        guard snapshot.deviceCount > 0 else { return "暂时无法读取物理磁盘统计。" }
        return "合计 \(snapshot.deviceCount) 个可读取的物理磁盘（含外置盘），不含磁盘映像。启动、唤醒或设备变化后需等待下一次采样。"
    }

    private func capacityValue(_ title: String, _ bytes: UInt64?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 10)).foregroundStyle(.secondary)
            Text(MetricFormat.bytes(bytes)).font(.system(size: 14, weight: .medium, design: .rounded))
        }
    }

    private func transferValue(_ title: String, value: Double?, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(MetricFormat.rate(value))
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(color)
                .lineLimit(1).minimumScaleFactor(0.8)
        }
    }
}

private extension View {
    func resourceCard() -> some View {
        self.padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.thinMaterial.opacity(0.58), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .strokeBorder(.white.opacity(0.11), lineWidth: 0.6)
            }
    }
}
