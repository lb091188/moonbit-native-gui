// 空闲检测的 GNOME 通道 + 集成门面（Wayland 原生路径 P1）。
//
// 平台读数分工：
//   Windows `GetLastInputInfo` / macOS HID 系统态 / Linux X11 的 XSS——
//     `@sys.idle_seconds`（C 桩，原样不动）；
//   GNOME（Wayland 原生会话与 GNOME X11 都算）—— Mutter 的 IdleMonitor：
//     `org.gnome.Mutter.IdleMonitor.GetIdletime`（对象
//     `/org/gnome/Mutter/IdleMonitor/Core`，返回 `x` 毫秒）。**精确读数**，
//     不靠「短间隔 watch + 记 last resumed」近似。
//
// 为什么 D-Bus 优先：X11 的 XSS 读数在 Wayland 会话下是虚高的（输入不进 X
// 服务端——`@sys` 侧已就此显式降级）；IdleMonitor 在 GNOME 的两种会话下
// 都准。KDE / wlroots 的 ext-idle-notify 是事件式协议（没有「当前空闲秒」
// 读数口），要 Wayland 协议客户端地基——归 P3 之后的批次，当前如实报不支持。
//
// 探测结果进程级缓存：服务不在总线上（非 GNOME 会话）时不必每次现问。

///|
/// Mutter IdleMonitor 的目标名 / 对象路径 / 接口（GNOME 侧钉死）。
pub const MUTTER_IDLE_DEST : String = "org.gnome.Mutter.IdleMonitor"

///|
pub const MUTTER_IDLE_PATH : String = "/org/gnome/Mutter/IdleMonitor/Core"

///|
pub const MUTTER_IDLE_IFACE : String = "org.gnome.Mutter.IdleMonitor"

///|
/// 探测状态：未探 / 在 / 不在。
priv enum MutterIdle {
  IdleUnknown
  IdlePresent
  IdleAbsent
}

let g_mutter : Ref[MutterIdle] = Ref(IdleUnknown)

///|
/// Mutter IdleMonitor 在不在会话总线上（进程级缓存：探过一次就不必再问；
/// 服务通常在会话启动前就已决定在不在）。
pub fn mutter_idle_present() -> Bool {
  match g_mutter.val {
    IdlePresent => true
    IdleAbsent => false
    IdleUnknown =>
      match
        @dbus.gdbus_call_session(
          MUTTER_IDLE_DEST,
          MUTTER_IDLE_PATH,
          "org.freedesktop.DBus.Peer",
          "Ping",
          [],
        ) {
        Ok(_) => {
          g_mutter.val = IdlePresent
          true
        }
        Err(_) => {
          g_mutter.val = IdleAbsent
          false
        }
      }
  }
}

///|
/// 经 IdleMonitor 读空闲毫秒（服务不在/这次失败给 None——调用方回落
/// `@sys` 的 C 平台读数）。
pub fn mutter_idle_ms() -> Int64? {
  if !mutter_idle_present() {
    return None
  }
  match
    @dbus.gdbus_call_session(
      MUTTER_IDLE_DEST,
      MUTTER_IDLE_PATH,
      MUTTER_IDLE_IFACE,
      "GetIdletime",
      [],
    ) {
    Ok(@dbus.GVInt64(ms)) => Some(ms)
    Ok(@dbus.GVU64(ms)) => Some(ms)
    _ => None
  }
}

///|
/// 空闲秒数（集成门面）：先 GNOME IdleMonitor（Wayland 原生与 GNOME X11
/// 都准），回落 `@sys` 的 C 平台读数（Windows / macOS / 有 X 服务端的
/// Linux）。两边都够不着给 `Unsupported`——**不把失败当 0 秒**。
pub fn idle_seconds() -> Result[Double, @sys.IdleError] {
  match mutter_idle_ms() {
    Some(ms) => Ok(@sys.idle_ms_to_seconds(ms))
    None => @sys.idle_seconds()
  }
}
