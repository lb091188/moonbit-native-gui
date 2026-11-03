// 桌面会话类型：Linux 上「跑在 X11 还是 Wayland」的唯一判据。
//
// 为什么单独立一件：Wayland 会话里 X 工具照旧能起进程、照旧退出码 0
// （`pr_run` 把 `DISPLAY`/`XAUTHORITY` 传给子进程，XWayland 在底下接着）——
// xrandr 报一块 XWAYLAND 虚拟屏、redshift 的 gamma 改了没效果、wmctrl 只看得到
// X 兼容层的窗口。**返回成功但无效**是系统能力族最大的坑，调用方拿假读数做
// 布局或护眼决策比报错更糟。所以这几个能力在探测处按会话类型显式降级，
// 不给假数（口径见 `docs/zh/system-capabilities.md`「Wayland 会话」）。
//
// 环境变量读的是当前进程环境（与 envx 同口径）；会话类型在进程生命周期内不变，
// 高频调用可自存一次结果。

///|
/// 桌面会话类型。Windows / macOS 上没有这套区分，按平台判过之后不会走到这里。
pub(all) enum SessionType {
  /// X11 会话（X 工具链的读数是真的）
  X11
  /// Wayland 会话（X 工具只剩 XWayland 兼容层，读数不可信）
  Wayland
  /// 认不出（变量都没设，或值不在已知集合里）
  Unknown
}

///|
pub impl Show for SessionType with fn output(self, logger) {
  match self {
    X11 => logger.write_string("SessionType::X11")
    Wayland => logger.write_string("SessionType::Wayland")
    Unknown => logger.write_string("SessionType::Unknown")
  }
}

///|
pub extend SessionType with Show::{to_string, output}

///|
/// 会话类型解析（纯函数）：`XDG_SESSION_TYPE` 优先（loginctl / DE 都会写），
/// 值认 `wayland` / `x11`（大小写不敏感，其余值如 `tty` 归 Unknown）；该变量
/// 没写时回落 `WAYLAND_DISPLAY`——非空即 Wayland 会话（GNOME 与 wlroots 都会设，
/// 值是 `wayland-0` 这类运行时器名）。
pub fn session_type_of(
  xdg_session_type : String,
  wayland_display : String,
) -> SessionType {
  let v = xdg_session_type.to_lower().trim()
  if v == "wayland" {
    Wayland
  } else if v == "x11" {
    X11
  } else if v == "" {
    // 没写 XDG_SESSION_TYPE 的会话（部分 wlroots 启动器）看运行时器名变量
    if wayland_display.trim().length() > 0 {
      Wayland
    } else {
      Unknown
    }
  } else {
    // tty / display-manager / 自造值：既不当 X11 也不当 Wayland
    Unknown
  }
}

///|
/// 本机当前会话类型。
pub fn session_type() -> SessionType {
  session_type_of(
    envx_get("XDG_SESSION_TYPE").unwrap_or(""),
    envx_get("WAYLAND_DISPLAY").unwrap_or(""),
  )
}

///|
/// 是否跑在 Wayland 会话里（X 工具族按此降级）。
pub fn in_wayland_session() -> Bool {
  session_type() is Wayland
}
