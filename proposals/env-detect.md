# 环境判定独立模块提案：native-env

> 状态：P1 骨架已落地——`modules/native-env` 单包 env + `examples/envprobe`，
> mac 本机已验裸机读数；P2 打分制与品牌细分歧未动工。判据全集见
> [experience/environment-detection.md](../experience/environment-detection.md)。

## 背景与动机

- 已收集齐全三类运行环境判据：虚拟机、容器、无 GPU 加速，出处全部落地在
  experience/environment-detection.md
- 现有实现散在三处，判定口径不一
  - gui/win/stub.c 的 l1_on_virtual_gpu：CPUID hypervisor 位 + 适配器名关键词，只覆盖 Windows，只服务 GPU 档一处决策
  - gui/sys 的 sysinfo：机器信息探测，虚拟机固件表实测经验沉淀在此
  - modules/gui-gpu 的 probe：wgpu 装载探测，判「库在不在」不判「环境允不允许」
- 诉求：整合成一个独立能力，外界可能用得到——即对外单件检索面

## 有没有必要独立成库——结论：有

- 按 module-split.md 的既有判据逐条过
  - 消费方式属「纯读写型」：无窗口、无事件循环、任何进程可调、CLI 可用——与当年 gui-sys 同位
  - 依赖隔离靠模块不靠包：非 GUI 应用要用检测，不该为它 import 整个 native-gui，模块闭包会拖进全部控件工具包
  - 对外动机成立：环境检测是独立检索词——vm detect、container detect、gpu detect；justjavac 单件套件先例证明这类系统小件有独立下载量
- 与 2026-11-02 拆分回退定案的关系
  - 回退前提是「不打算对外」——维护成本大于架构收益；本次动机是对外，前提翻转
  - 回退教训照单接受：一份版本、一条钉版、发版协调都是真实成本
  - 但本模块是零 prebuild、零第三方二进制、零 FFI 重依赖的最轻形态，成本远小于当年四模块方案
- 独立成立的前提：对外发布 mooncakes。若最终只自用，则维持 gui 内部包更划算，提案整体作废

## 定位与边界

- 定位：运行环境判定——回答三个问题：在不在虚拟机、在不在容器、有没有 GPU 加速可用
- 输出：结论 + 置信分 + 信号明细——哪条信号命中、分数多少，可打印可入库
- 不做
  - 对抗性反检测：不与隐藏手段对抗，测不出就按真机跑，对档位判断无损
  - 沙箱对抗场景：pafish、al-khaser 面向恶意软件分析，非本库用途
  - 行为层启发：鼠标移动、用户交互类信号不收——那是反沙箱用途

## 模块形态

- 名字：推荐 NoahLiu/native-env，与 native-gui 家族一致；备选 env-detect、sysenv
- 位置：modules/native-env/，注册进 moon.work
- 依赖：零——只用 core；不依赖 native-gui、gui-gpu、任何子模块
- 包：单包 env/ 起步，对齐 gui-gpu 的 gpu 单包形态；检测项膨胀后再议分包
- FFI 面：三平台小桩，无 prebuild
  - Windows：__cpuid、EnumDisplayDevicesW、注册表读，一处 stub.c
  - macOS：sysctlbyname 一处 stub
  - Linux：纯文件读取，零桩

## API 定稿

- 设计原则
  - 零错误类型：环境判定不存在「失败要调用方处理」——读不到就当信号缺失，全平台降级返回 Unknown；错误细节进信号明细不抛出去
  - 进程级缓存：虚拟机、容器、会话类型在进程生命周期内不变，便捷判定内部只查一次；GPU 热插拔暂不追，记为边界
  - 包名即前缀：@env 包对外函数不再加 si_ / pr_ 类前缀
- 单项快捷判定——应用平时用这层

```
pub fn is_vm() -> Bool
pub fn vm_brand() -> String?          // "kvm" / "qemu" / "vmware" / "hyperv" / "vbox" / "parallels" / "xen" / "apple-vz" / "bhyve" / "wsl"
pub fn is_container() -> Bool
pub fn container_kind() -> String?    // "docker" / "podman" / "wsl" / "lxc" / "systemd-nspawn" / "openvz"
pub fn gpu_tier() -> GpuTier
pub fn gpu_detail() -> String         // 适配器名或不可用原因
pub fn session_kind() -> SessionKind
pub fn desktop_kind() -> DesktopKind
```

- 一次全采——诊断与展示用，envprobe 示例吃这一层

```
pub fn detect() -> EnvReport

pub(all) struct EnvReport {
  platform : String                 // "windows" / "linux" / "macos"
  vm : VmVerdict
  container : ContainerVerdict
  gpu : GpuVerdict
  session : SessionKind
  desktop : DesktopKind
  signals : Array[Signal]           // 每条命中信号：名字 + 置信分 + 一句细节
}

pub(all) struct Signal {
  name : String                     // "cpuid_hypervisor_bit" / "adapter_name" / "dockerenv" / ...
  score : Int                       // 信号自带置信分，累加决定结论
  detail : String                   // "ECX bit 31 = 1" / "QXL (Red Hat)" / ...
}
```

- 结论类型——全平台统一成员，平台差异吸收在判定内不在类型上

```
pub(all) enum GpuTier {
  Hardware                          // 真显卡，GPU 档可开
  Virtual                           // 虚拟显卡：有 3D 但驱动崩溃面大，默认禁用档
  Software                          // 软渲染：llvmpipe / WARP
  None                              // 无任何 GPU 通路
}

pub(all) enum SessionKind {
  X11                               // Linux X11 会话
  Wayland                           // Linux Wayland 会话——X 工具读数不可信的信号
  Tty                               // Linux 无图形会话：SSH、控制台
  Native                            // Windows / macOS：原生窗口系统，无此区分
  Unknown
}

pub(all) enum DesktopKind {
  Gnome; Kde; Xfce; Mate; Cinnamon; Budgie; Lxqt; Unity; Deepin
  Windows; Macos
  Unknown
}

pub(all) enum VmVerdict {
  BareMetal
  Vm(String)                        // 品牌串，同 vm_brand
  Unknown                           // 信号不足，不下结论
}

pub(all) enum ContainerVerdict {
  No
  Yes(String)                       // 容器类型串，同 container_kind
}

pub(all) struct GpuVerdict {
  tier : GpuTier
  detail : String
}
```

- 判定顺序固定：容器 → 虚拟机 → 会话 → 桌面 → GPU——容器限核会误触 VM 核数启发式，顺序不能反
- gpu_tier 是本库的核心增值：GUI 应用要的不是「有没有显卡」而是「敢不敢走 GPU 档」——虚拟显卡归 Virtual、软渲染归 Software、远程会话无硬加速归 Software 或 None，各自降级策略不同
- P2 追加项，P1 不做
  - vm_score() -> Int——置信分总量与阈值判定，P1 用「任一硬信号命中」的简单口径
  - detect_with(options)——信号开关，跳过指定信号名；P1 全信号固定开启

## 判据分期

- P1 骨架——判据全部有出处、可直接落
  - Windows VM：CPUID hypervisor 位、签名串、适配器名关键词——自 l1_on_virtual_gpu 迁移并加宽——注册表 SystemManufacturer / SystemProductName、WMI 兜底
  - Linux 容器：systemd 同款顺序——container 环境变量 → /.dockerenv 与 /run/.containerenv → PID namespace inode 0xEFFFFFFC 兜底，全部免 root
  - Linux GPU：/dev/dri/renderD 存在性 + GL 渲染器串认 llvmpipe / softpipe / swrast
  - macOS VM 与 GPU：sysctl hw.model、kern.hv_vmm_present、MTLCreateSystemDefaultDevice
  - Windows GPU：DXGI_ADAPTER_FLAG_SOFTWARE 旗标判定——比现有关键词更硬的信号
  - 会话与桌面：XDG 环境变量判 X11 / Wayland / Tty，XDG_CURRENT_DESKTOP 判桌面环境——判据与 gui/sys 的 session_type、desktop_detect 同源，实现独立，理由见「与现有代码的关系」
- P2 打分与品牌——判据扩容与置信判定
  - 打分机制
    - 信号采集与打分分离：采集层只产出 Signal 数组，打分层是纯函数——MoonBit 单元测试直接构造信号组合断言结论，不依赖真机
    - 分值按可靠性四档定死，参考 VMAware 的分值体系
      - 决定性，150 分：CPUID 签名串命中、/.dockerenv 类文件标记
      - 强，100 分：hypervisor 位、DMI 厂商串命中、适配器名命中、/dev/dri 缺失
      - 中，40 到 70 分：注册表键、VM 进程、MAC 前缀、品牌串关键词
      - 弱，10 到 35 分：核数过少、内存过小、无温度传感器
    - 阈值与三态
      - 总分不低于 100 判 VM
      - 35 到 99 归 Unknown——信号不足不下结论，不硬猜
      - 35 以下判 BareMetal
    - is_vm 语义升级：P1 是「任一硬信号命中」的简单口径，P2 改为总分过阈值；vm_score 返回 0-100 归一化分
    - 特判优先于打分，三条铁律
      - Hyper-V 宿主：检测到 Hyper-V 自装特征时，hypervisor 位与厂商串信号不计分——Windows 装了 Hyper-V 会把宿主硬件值改成 VM 值，裸机误报的头号来源
      - 云裸金属：云厂商信号命中且无任何 hypervisor 信号时，结论降 Unknown 不判 VM
      - 容器先判：判定为容器时跳过核数、内存类弱信号——限核容器必然触发
  - 品牌识别
    - VM 品牌清单：kvm、qemu、qemu-kvm、vmware、hyperv、vbox、parallels、xen、bhyve、apple-vz、bochs、uml
    - 容器品牌清单：docker、podman、wsl、lxc、systemd-nspawn、openvz
    - 品牌由信号标注归属：每条信号声明命中的品牌，最高分品牌即 vm_brand 结论；多品牌同分时取信号分和最高者，冲突明细留在 signals 里可查
  - 判据扩容清单——按平台，判据出处全在 experience/environment-detection.md
    - Windows：VBox 服务键与驱动文件、VMware Tools 键、vboxservice 与 vmtoolsd 进程、CPUID 品牌串认 QEMU Virtual CPU 与 Bochs 硬编码串、Hyper-V 虚拟处理器叶 0x40000004、云厂商注册表识别
    - Linux：DMI 厂商串表全表收录——systemd 同款：KVM、OpenStack、KubeVirt、Amazon EC2、QEMU、VMware、innotek、VirtualBox、Xen、Bochs、Parallels、BHYVE、Hyper-V、Apple Virtualization、Google Compute Engine；MAC 前缀表八家；/proc/cpuinfo 的 hypervisor 标志行；UML 品牌串
    - macOS：ioreg 的 board-id 与 manufacturer 串、IODeviceTree 的 Virtual Machine 串、csrutil 状态异常、USB 厂商串
    - 低优先缓做：AES-NI 能力位一致性、NtQueryLicenseValue、沙箱类品牌——对抗向信号对本库档位判断收益低
  - API 扩展
    - vm_score() -> Int：0-100 归一化置信分
    - detect_with(options) : skip 信号名数组，按名关信号——诊断某信号是否误导结论时用
    - EnvReport 结构不变：总分对 signals 求和即得，不加冗余字段
  - 验收
    - 打分纯函数单元测试：阈值边界、特判三条、多品牌冲突、信号开关——全部离线可测
    - 真机矩阵同 P1，重点回归 Hyper-V 宿主机不误报
- P3 持续扩项
  - 按 experience/environment-detection.md 清单逐条补，acpi 串、Hyper-V 虚拟处理器叶、能力位一致性等
  - 云厂商识别：aws、gce、azure，低优先

## 与现有代码的关系

- gui/win 的 l1_on_virtual_gpu：第一期并行不动，native-env 稳定后 gui 改调库并删除就地实现——先并行后替换
- gui/sys 的 sysinfo：API 不迁——那是「机器是什么」，本库是「环境是什么性质」；但 si_machine 的 SMBIOS / 注册表底层读取与 VM 判据是同一信号源，native-env 的信号采集层自建同款读取，将来 gui/sys 可内部改调 native-env 消重
- 收编语义要认清：native-env 零依赖，不能 import gui/sys——session_type、desktop_detect 是「判据复用、实现独立」——环境变量判定就几行，搬进来自己实现；方向永远是 native-env 不依赖 gui、gui 消费 native-env，反向 import 禁止
- modules/gui-gpu：装载探测前可先问 gpu_tier；依赖方向 gui-gpu → native-env，单向无环
- 示例：examples/envprobe——CLI 打印环境报告，一行一个信号，独立模块注册 moon.work

## 验收与门禁

- moon check 零错误零警告；moon test env 全绿
- 真机矩阵交用户执行：真机三平台 + KVM Windows——company win10 现成——加 Linux 容器本地，逐信号比对打印报告
- 每期一提交一推送，P2 后首发 0.1.0 到 mooncakes

## 待拍板项

- 名字：native-env / env-detect / sysenv
- 是否对外发布：独立的成立前提
- P1 范围确认：以上四臂是否齐做，还是先 Windows VM + Linux 容器两臂
