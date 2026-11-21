# native-env

运行环境判定库：回答三个问题——在不在虚拟机、在不在容器、有没有 GPU 加速可用。零依赖独立模块，任何 MoonBit 原生应用可直接消费，非 GUI 应用不必拖进界面工具包。

判据全集与出处：[experience/environment-detection.md](../../experience/environment-detection.md)；方案与 API 定稿：[proposals/env-detect.md](../../proposals/env-detect.md)。

## 快速上手

```moonbit
// 便捷判定——应用平时用这层，进程级缓存只查一次
let in_vm = @env.is_vm()
let brand = @env.vm_brand()        // Some("kvm") / Some("vmware") / None
let kind = @env.container_kind()   // Some("docker") / Some("wsl") / None

// GPU 档——要的不是「有没有显卡」而是「敢不敢走 GPU 档」
match @env.gpu_tier() {
  Hardware => // GPU 档可开
  Virtual => // 虚拟显卡：有 3D 但驱动崩溃面大，默认禁用
  Software => // 软渲染：llvmpipe / WARP
  GpuNone => // 无任何 GPU 通路
}

// 一次全采——诊断与展示用
let report = @env.detect()
for s in report.signals {
  println("\{s.name}（\{s.score} 分）\{s.detail}")
}
```

真机看读数：`cd examples/envprobe && moon run main`，CLI 打印完整报告。

## 判定顺序

固定为容器 → 虚拟机 → 会话 → 桌面 → GPU，顺序不能反：容器限核会误触 VM 的资源类启发式。

## 平台覆盖

| 臂 | Windows | macOS | Linux |
|---|---|---|---|
| 虚拟机 | CPUID hypervisor 位 + 厂商签名串 + Hyper-V 宿主特判 + SMBIOS 厂商串 + 适配器名关键词 | hw.model + kern.hv_vmm_present | /proc/cpuinfo 标志 + DMI 厂商串 + /sys/hypervisor + MAC 前缀 |
| 容器 | 未做——Docker Desktop 进程不在容器内 | 未做 | systemd 同款顺序：OpenVZ → WSL → container 环境变量 → 标记文件 → cgroup → PID namespace inode |
| GPU 档 | DXGI 软件旗标 → 适配器关键词 → 远程会话 | Metal 默认设备 | 渲染节点 + DRM 驱动/vendor + /dev/dxg（WSL2） |
| 会话与桌面 | Native / Windows | Native / Macos | XDG_SESSION_TYPE / XDG_CURRENT_DESKTOP |

## 边界

- 零错误类型：读不到就当信号缺失，全平台降级返回 Unknown，不抛错
- 进程级缓存：环境判定结果进程内不变；GPU 热插拔暂不追
- 不做对抗性反检测：测不出就按真机跑，对档位判断无损
- P1 口径：VM 判「任一硬信号命中」；置信分打分制与品牌细分歧 P2，见提案
