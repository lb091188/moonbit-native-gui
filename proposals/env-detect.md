# 环境判定独立模块提案：native-env

> 状态：规划中，待拍板名字与是否对外发布。判据全集见
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

## API 草案

```
// 便捷判定
env::is_vm() -> Bool
env::vm_brand() -> String?         // kvm / qemu / vmware / hyperv / vbox / parallels / xen / apple-vz / ...
env::is_container() -> Bool
env::container_kind() -> String?   // docker / podman / wsl / lxc / systemd-nspawn / ...
env::gpu_tier() -> GpuTier         // Hardware / Virtual / Software / None
env::gpu_detail() -> String        // 适配器名或不可用原因

// 一次全采
env::detect() -> EnvReport         // verdict + signals：每条命中信号带名字与置信分
```

- 判定顺序固定：先容器，再虚拟机，再 GPU——容器限核会误触 VM 核数启发式，顺序不能反
- gpu_tier 是本库的核心增值：GUI 应用要的不是「有没有显卡」而是「敢不敢走 GPU 档」——虚拟显卡归 Virtual 档、软渲染归 Software 档，各自降级策略不同

## 判据分期

- P1 骨架——判据全部有出处、可直接落
  - Windows VM：CPUID hypervisor 位、签名串、适配器名关键词（自 l1_on_virtual_gpu 迁移并加宽）、注册表 SystemManufacturer / SystemProductName、WMI 兜底
  - Linux 容器：systemd 同款顺序——container 环境变量 → /.dockerenv 与 /run/.containerenv → PID namespace inode 0xEFFFFFFC 兜底，全部免 root
  - Linux GPU：/dev/dri/renderD 存在性 + GL 渲染器串认 llvmpipe / softpipe / swrast
  - macOS VM 与 GPU：sysctl hw.model、kern.hv_vmm_present、MTLCreateSystemDefaultDevice
  - Windows GPU：DXGI_ADAPTER_FLAG_SOFTWARE 旗标判定——比现有关键词更硬的信号
- P2 打分与品牌
  - SMBIOS / DMI 厂商串表、MAC 前缀表、CPUID 品牌串判据
  - 品牌识别：kvm / qemu / vmware / hyperv / vbox / parallels / xen / apple-vz / wsl
  - 置信分输出：每信号一分，累计过阈值出结论
- P3 持续扩项
  - 按 experience/environment-detection.md 清单逐条补，acpi 串、Hyper-V 虚拟处理器叶、能力位一致性等
  - 云厂商识别（aws / gce / azure）低优先

## 与现有代码的关系

- gui/win 的 l1_on_virtual_gpu：第一期并行不动，native-env 稳定后 gui 改调库并删除就地实现——先并行后替换
- gui/sys 的 sysinfo：不迁——那是「机器是什么」，本库是「环境是什么性质」；两处文档互链
- modules/gui-gpu：装载探测前可先问 gpu_tier；依赖方向 gui-gpu → native-env，单向无环
- 示例：examples/envprobe——CLI 打印环境报告，一行一个信号，独立模块注册 moon.work

## 验收与门禁

- moon check 零错误零警告；moon test env 全绿
- 真机矩阵交用户执行：真机三平台 + KVM Windows（company win10 现成）+ Linux 容器本地——逐信号比对打印报告
- 每期一提交一推送，P2 后首发 0.1.0 到 mooncakes

## 待拍板项

- 名字：native-env / env-detect / sysenv
- 是否对外发布：独立的成立前提
- P1 范围确认：以上四臂是否齐做，还是先 Windows VM + Linux 容器两臂
