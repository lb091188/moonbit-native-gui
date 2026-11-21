// envprobe：打印运行环境报告，一行一个信号。真机矩阵按 TODO 条目逐环境
// 跑本命令比对读数。

///|
fn vm_text(vm : @env.VmVerdict) -> String {
  match vm {
    BareMetal => "裸机"
    Vm(brand) => "虚拟机（\{brand}）"
    Unknown => "信号不足，不下结论"
  }
}

///|
fn container_text(c : @env.ContainerVerdict) -> String {
  match c {
    No => "非容器"
    Yes(kind) => "容器（\{kind}）"
  }
}

///|
fn gpu_text(tier : @env.GpuTier, detail : String) -> String {
  let name = match tier {
    Hardware => "Hardware 真显卡，GPU 档可开"
    Virtual => "Virtual 虚拟显卡，默认禁用档"
    Software => "Software 软渲染"
    GpuNone => "None 无 GPU 通路"
  }
  "\{name}——\{detail}"
}

///|
fn session_text(s : @env.SessionKind) -> String {
  match s {
    X11 => "X11"
    Wayland => "Wayland"
    Tty => "TTY（无图形会话）"
    Native => "原生窗口系统"
    UnknownSession => "未知"
  }
}

///|
fn desktop_text(d : @env.DesktopKind) -> String {
  match d {
    Gnome => "GNOME"
    Kde => "KDE"
    Xfce => "Xfce"
    Mate => "MATE"
    Cinnamon => "Cinnamon"
    Budgie => "Budgie"
    Lxqt => "LXQt"
    Unity => "Unity"
    Deepin => "Deepin"
    Windows => "Windows"
    Macos => "macOS"
    UnknownDesktop => "未知"
  }
}

///|
fn main {
  let r = @env.detect()
  println("platform : \{r.platform}")
  println("vm       : \{vm_text(r.vm)}")
  println("container: \{container_text(r.container)}")
  println("gpu      : \{gpu_text(r.gpu.tier, r.gpu.detail)}")
  println("session  : \{session_text(r.session)}")
  println("desktop  : \{desktop_text(r.desktop)}")
  println("signals  : 命中 \{r.signals.length()} 条")
  for s in r.signals {
    println("  - \{s.name}（\{s.score} 分）\{s.detail}")
  }
}
