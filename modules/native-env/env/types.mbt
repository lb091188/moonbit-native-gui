// 公开类型：全平台统一成员，平台差异吸收在判定内不在类型上（提案 API 定稿）。

///|
/// GPU 档位——GUI 应用要的不是「有没有显卡」而是「敢不敢走 GPU 档」。
#derive(Eq, Debug)
pub(all) enum GpuTier {
  /// 真显卡，GPU 档可开
  Hardware
  /// 虚拟显卡：有 3D 加速但驱动崩溃面大，默认禁用档
  Virtual
  /// 软渲染：llvmpipe、WARP 这类纯 CPU 光栅
  Software
  /// 无任何 GPU 通路
  GpuNone
}

///|
/// 图形会话类型。
#derive(Eq, Debug)
pub(all) enum SessionKind {
  /// Linux X11 会话
  X11
  /// Linux Wayland 会话——X 工具读数不可信的信号
  Wayland
  /// Linux 无图形会话：SSH、控制台
  Tty
  /// Windows / macOS：原生窗口系统，无此区分
  Native
  /// 信号不足
  UnknownSession
}

///|
/// 桌面环境。
#derive(Eq, Debug)
pub(all) enum DesktopKind {
  Gnome
  Kde
  Xfce
  Mate
  Cinnamon
  Budgie
  Lxqt
  Unity
  Deepin
  Windows
  Macos
  UnknownDesktop
}

///|
/// 虚拟机结论： BareMetal 判裸机，Vm 带品牌串，Unknown 信号不足不下结论。
#derive(Eq, Debug)
pub(all) enum VmVerdict {
  BareMetal
  Vm(String)
  Unknown
}

///|
/// 容器结论。
#derive(Eq, Debug)
pub(all) enum ContainerVerdict {
  No
  Yes(String)
}

///|
/// GPU 判定：档位加一句可打印原因。
#derive(Eq, Debug)
pub(all) struct GpuVerdict {
  tier : GpuTier
  detail : String
}

///|
/// 单条命中信号：名字 + 置信分 + 一句细节。
#derive(Eq, Debug)
pub(all) struct Signal {
  name : String
  score : Int32
  detail : String
}

///|
/// 一次全采的环境报告：诊断与展示用，envprobe 示例吃这一层。
#derive(Debug)
pub(all) struct EnvReport {
  platform : String
  vm : VmVerdict
  container : ContainerVerdict
  gpu : GpuVerdict
  session : SessionKind
  desktop : DesktopKind
  /// 每条命中信号：名字 + 置信分 + 一句细节
  signals : Array[Signal]
}
