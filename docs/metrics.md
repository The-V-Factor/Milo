# 指标说明

这份文档面向希望了解 Milo 数据来源与计算方式的读者。[返回首页](../README.md)。

- **CPU 使用率**：`host_statistics(HOST_CPU_LOAD_INFO)` 两次采样间的 tick 差值，用户态（含 nice）与系统态之和；所有核心归一到 0–100%。启动和唤醒后的首个样本显示 `—`，等待下一次采样。
- **Load Average**：`getloadavg` 的 1、5、15 分钟系统平均负载，不是百分比，也不是瞬时使用率。显示逻辑核心数供参考。
- **已用内存**：应用 + 有线 + 压缩。应用为 `(internal_page_count - purgeable_count) × pageSize`；压缩使用实际物理页数，不使用压缩前大小。
- **Free**：`(free_count - speculative_count) × pageSize`。
- **缓存**：`(external_page_count + purgeable_count) × pageSize`。speculative 同时包含在 free_count 和 external_page_count 中，从 Free 扣除后只在缓存计入一次。
- **Swap**：`sysctlbyname("vm.swapusage")` 的已用交换空间，与物理内存单独显示。
- **Swap 活动**：`HOST_VM_INFO64` 的 `swapins` / `swapouts` 累计页数差 × 本机页大小 ÷ 实际采样秒数，分别显示换入与换出速度（KiB/s / MiB/s）。曲线显示最近 60 秒合计速度，纵轴自动缩放，可悬停查看范围。它表示系统交换吞吐量，不是 SSD 的全部读写量，也不是已用 Swap 容量的变化率。
- **交换提示**：收集完整 60 秒后，按时间加权的换入 + 换出均值 ≥10 MiB/s 显示“交换活跃”，≥50 MiB/s 显示“交换繁忙”，否则显示“交换较少”。这些是待实测调整的试用阈值，不是 Apple 官方标准，也不代表内存压力或异常。采样失败、计数器回退或间隔超过 5 秒时重新累计，缺失速度显示 `—`。
- 内存来自 `host_statistics64(HOST_VM_INFO64)`，使用本机页大小，容量标注二进制单位 GiB / MiB。数据是系统计数器的近似快照，可能与活动监视器因刷新时机、统计口径不同而有小幅差异；内存使用率不代表内存压力。

### 应用排行与磁盘

- **应用 CPU**：读取可访问进程的累计 CPU 时间并计算区间差值，除以实际间隔及逻辑核心数，统一为整机 0–100% 口径。与活动监视器将单核心满载表示为 100% 的进程口径不同；首次采样、进程重启和唤醒后需等待基线。
- **应用内存**：合计进程 `ri_phys_footprint`，显示容量和相对于物理内存总量的百分比。footprint 包含压缩内存等记账项，不等于单纯的常驻内存，各应用总和也不等于概览中的“已用内存”。
- **应用归组**：按可执行文件所在的外层 `.app` 和可识别的父进程链合并。系统进程、权限不足的进程、归属不明的共享 XPC 服务可能无法计入；页面显示覆盖情况，部分可读项目带 `*`，不承诺与活动监视器完全一致。不使用管理员权限或读取进程的文件内容。
- **磁盘容量**：读取 `/System/Volumes/Data` 的总量和当前可用空间，已用为两者之差；不额外加入可清理空间。APFS 共享容器容量，不能将该“已用”解释为 Data 卷独占文件的大小。
- **磁盘读写**：读取 IOKit `IOBlockStorageDriver` 的累计读写字节，按物理设备去重后计算实际间隔内的差值。合计可读取的内置与外置物理磁盘，排除虚拟磁盘映像；这与启动数据卷的容量范围不同。首次采样、设备变化、计数回退和长间隔后显示 `—` 并重建基线，无活动时显示零。

参考：[Apple 进程统计实现](https://github.com/apple-oss-distributions/xnu/blob/main/osfmk/kern/bsd_kern.c)、[运行中的应用](https://developer.apple.com/documentation/appkit/nsworkspace/runningapplications)、[Apple 磁盘统计实现](https://github.com/apple-oss-distributions/IOStorageFamily/blob/main/IOBlockStorageDriver.cpp)。

采样约每秒一次，CPU / 内存保留最近 60 次采样，Swap 保留最近 60 秒趋势；睡眠时暂停，唤醒时重建 CPU / Swap、应用 CPU 和磁盘读写基线。数据仅在内存中保留，不启动 shell 子进程，不保存历史，不访问网络，不需要辅助功能或录屏权限。悬停检测仅在面板打开期间使用额外定时器。小屏幕上详情面板可滚动查看。

参考：[Apple VM 统计结构](https://developer.apple.com/documentation/kernel/vm_statistics64_data_t)、[XNU 页计数说明](https://github.com/apple-oss-distributions/xnu/blob/main/osfmk/mach/vm_statistics.h)、[NSPopover](https://developer.apple.com/documentation/appkit/nspopover)。
