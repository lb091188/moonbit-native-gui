// 会话与桌面判定臂：判据与 gui/sys 的 session_type、desktop_detect 同源，
// 实现独立——native-env 零依赖，不能 import gui（提案「与现有代码的关系」）。

///|
/// 解析 Linux 会话类型：XDG_SESSION_TYPE 优先，回落 WAYLAND_DISPLAY 非空
/// 即 Wayland，再回落 SSH_CONNECTION 非空即 Tty；全缺给 Unknown。
/// 出处 gui/sys/session.mbt 同源判据。
fn session_parse_linux(
  session_type : String?,
  wayland_display : String?,
  ssh_connection : String?,
) -> SessionKind {
  match session_type {
    Some(v) =>
      match v.to_lower() {
        "x11" => return X11
        "wayland" => return Wayland
        "tty" => return Tty
        _ => ()
      }
    None => ()
  }
  match wayland_display {
    Some(v) => if v.trim().to_owned() != "" { return Wayland }
    None => ()
  }
  match ssh_connection {
    Some(v) => if v.trim().to_owned() != "" { return Tty }
    None => ()
  }
  UnknownSession
}

///|
/// 单个 XDG_CURRENT_DESKTOP 值到桌面枚举的映射，大小写不敏感。
/// 出处 gui/sys/desktop.mbt 同源映射表。
fn desktop_parse_one(value : String) -> DesktopKind {
  match value.to_lower() {
    "gnome" => Gnome
    "kde" | "plasma" => Kde
    "xfce" => Xfce
    "mate" => Mate
    "x-cinnamon" => Cinnamon
    "budgie" => Budgie
    "lxqt" => Lxqt
    "unity" => Unity
    "deepin" => Deepin
    _ => UnknownDesktop
  }
}

///|
/// 解析 XDG_CURRENT_DESKTOP 原文：冒号分隔多值（如 "ubuntu:GNOME"），按段
/// 试取首个可识别值。出处 gui/sys/desktop.mbt 同源解析。
fn desktop_parse_linux(value : String?) -> DesktopKind {
  match value {
    Some(v) => {
      for seg in v.split(":") {
        let kind = desktop_parse_one(seg.trim().to_owned())
        if !(kind is UnknownDesktop) {
          return kind
        }
      }
      UnknownDesktop
    }
    None => UnknownDesktop
  }
}
