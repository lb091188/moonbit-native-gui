// Wayland 会话的夜温通道（Wayland 原生路径 P2 的夜灯半边）。
//
// 三档分工（方案 §五）：
//   GNOME：写 gsd-color 自己的配置键（org.gnome.settings-daemon.plugins.color
//     的 night-light-enabled / night-light-temperature）——驱动 DE 自带夜灯，
//     不是裸 gamma。本机 schema 在（键名实证），gsettings CLI 走 @sys.pr_run
//     （与壁纸的 gsettings 通道同一路数）；
//   KDE：Plasma 5.27 实证 `org.kde.kwin.ColorCorrect`（名 `org.kde.NightColor`，
//     对象 /ColorCorrect）**属性全 read-only**——currentTemperature/
//     targetTemperature/running/enabled 读得到，写入口 5.x 从来没有公开面；
//     Plasma 6 的 `org.kde.KWin.NightLight` 写入口径未核（S6 真机定），当前
//     探测存在性 + 读 running，写一律 Unsupported；
//   wlroots 裸 gamma（wlr-gamma-control）：要 Wayland 协议客户端地基，归
//     P3 之后，当前 Unsupported。
//
// K 值与 @sys 的 redshift 通道同口径（percent 0 → 2500K 最暖、100 → 6500K
// 中性；`@sys.nl_kelvin` 单源）。

///|
/// GNOME 夜灯配置 schema 与键（gsd-color 公开键名，本机 gsettings 实证）。
pub const NL_GNOME_SCHEMA : String = "org.gnome.settings-daemon.plugins.color"

///|
pub const NL_GNOME_KEY_ENABLED : String = "night-light-enabled"

///|
pub const NL_GNOME_KEY_TEMP : String = "night-light-temperature"

///|
/// KDE Plasma 5 的 ColorCorrect（KWin 5.27 实物：名 org.kde.NightColor，
/// 对象 /ColorCorrect，接口 org.kde.kwin.ColorCorrect）。
pub const NL_KDE5_DEST : String = "org.kde.NightColor"

///|
pub const NL_KDE5_PATH : String = "/ColorCorrect"

///|
pub const NL_KDE5_IFACE : String = "org.kde.kwin.ColorCorrect"

///|
/// KDE Plasma 6 的 NightLight（接口名/路径按方案文献；写入口径未核）。
pub const NL_KDE6_DEST : String = "org.kde.KWin.NightLight"

///|
pub const NL_KDE6_PATH : String = "/org/kde/KWin/NightLight"

///|
/// GNOME 档是否可用：schema 读得到（gsettings 在）即算。gsd-color 不在
/// 总线上时写键也落得下去（DE 起来才生效）——不拿「服务在不在」当门槛，
/// 只保证「写得进」。
pub fn nl_gnome_available() -> Bool {
  match
    @sys.pr_run(
      "gsettings",
      ["get", NL_GNOME_SCHEMA, NL_GNOME_KEY_TEMP],
      timeout_ms=3000,
    ) {
    Ok(_) => true
    Err(_) => false
  }
}

///|
/// GNOME 档设色温：enabled=true + temperature=K（K 口径同 @sys redshift）。
pub fn nl_gnome_set(percent : Int32) -> Result[Unit, @sys.NightlightError] {
  let k = @sys.nl_kelvin(percent)
  match nl_gnome_write_bool(true) {
    Err(m) => return Err(@sys.NightlightError::CommandFailed(m))
    Ok(_) => ()
  }
  match nl_gnome_write_uint(k) {
    Err(m) => Err(@sys.NightlightError::CommandFailed(m))
    Ok(_) => Ok(())
  }
}

///|
/// GNOME 档复位：enabled=false（温度键留着，DE 自己的调度不管它）。
pub fn nl_gnome_reset() -> Result[Unit, @sys.NightlightError] {
  match nl_gnome_write_bool(false) {
    Err(m) => Err(@sys.NightlightError::CommandFailed(m))
    Ok(_) => Ok(())
  }
}

///|
fn nl_gnome_write_bool(v : Bool) -> Result[Unit, String] {
  match
    @sys.pr_run(
      "gsettings",
      [
        "set",
        NL_GNOME_SCHEMA,
        NL_GNOME_KEY_ENABLED,
        if v {
          "true"
        } else {
          "false"
        },
      ],
      timeout_ms=3000,
    ) {
    Ok(_) => Ok(())
    Err(e) => Err("gsettings 写 \{NL_GNOME_KEY_ENABLED} 失败: \{e}")
  }
}

///|
fn nl_gnome_write_uint(v : Int32) -> Result[Unit, String] {
  match
    @sys.pr_run(
      "gsettings",
      ["set", NL_GNOME_SCHEMA, NL_GNOME_KEY_TEMP, "\{v}"],
      timeout_ms=3000,
    ) {
    Ok(_) => Ok(())
    Err(e) => Err("gsettings 写 \{NL_GNOME_KEY_TEMP} 失败: \{e}")
  }
}

///|
/// KDE 夜灯读数（Plasma 5 ColorCorrect）：当前色温 K + 是否在跑。接口不在
/// （Plasma 6 会话/非 KDE）给 None。
pub fn nl_kde_state() -> (Int32, Bool)? {
  match
    @dbus.gdbus_call_session(
      NL_KDE5_DEST,
      NL_KDE5_PATH,
      "org.freedesktop.DBus.Properties",
      "Get",
      [@dbus.GVString(NL_KDE5_IFACE), @dbus.GVString("currentTemperature")],
    ) {
    Ok(@dbus.GVVariant(@dbus.GVUInt32(k))) =>
      match
        @dbus.gdbus_call_session(
          NL_KDE5_DEST,
          NL_KDE5_PATH,
          "org.freedesktop.DBus.Properties",
          "Get",
          [@dbus.GVString(NL_KDE5_IFACE), @dbus.GVString("running")],
        ) {
        Ok(@dbus.GVVariant(@dbus.GVBool(running))) => Some((k, running))
        _ => Some((k, false))
      }
    _ => None
  }
}

///|
/// KDE 档写色温：**当前一律 Unsupported**——Plasma 5.27 的 ColorCorrect 属性
/// 全 read-only（实物 introspection 核过，5.x 没有公开写入口）；Plasma 6 的
/// NightLight 写入口径未核（S6 真机定）。不拿「读得到」装「写得进」。
pub fn nl_kde_set(_percent : Int32) -> Result[Unit, @sys.NightlightError] {
  Err(@sys.NightlightError::Unsupported)
}

///|
/// KDE 档复位：同 set（无公开写入口）。
pub fn nl_kde_reset() -> Result[Unit, @sys.NightlightError] {
  Err(@sys.NightlightError::Unsupported)
}

///|
/// Wayland 档设色温（集成门面）：GNOME 可写走 GNOME；KDE 会话如实报不
/// 支持（读得到写不进）；都不是给 Unsupported。X11 会话不走这里——
/// 调用方用 `@sys.nl_set_temperature`（redshift/xrandr 通道）。
pub fn wayland_nl_set(percent : Int32) -> Result[Unit, @sys.NightlightError] {
  if nl_gnome_available() {
    return nl_gnome_set(percent)
  }
  if nl_kde_state() is Some(_) {
    return nl_kde_set(percent)
  }
  Err(@sys.NightlightError::Unsupported)
}

///|
/// Wayland 档复位色温（同 set 的分派）。
pub fn wayland_nl_reset() -> Result[Unit, @sys.NightlightError] {
  if nl_gnome_available() {
    return nl_gnome_reset()
  }
  if nl_kde_state() is Some(_) {
    return nl_kde_reset()
  }
  Err(@sys.NightlightError::Unsupported)
}
