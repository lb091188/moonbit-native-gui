// Wayland 会话的显示器枚举通道（Wayland 原生路径 P2 的显示器半边）。
//
// 三档分工（方案 §五）：
//   KDE：`org.kde.KScreen` 的 `org.kde.kscreen.Backend.getConfig`——整棵
//     输出配置（顶层 a{sv}；outputs = av、每个 v 是 a{sv}；mode 的 size /
//     output 的 pos·size 都是 variant(a{sv})）。字段名与嵌套形态按本机
//     KScreen 实物抓取（id/name/refreshRate/size{width,height}；
//     connected/enabled/currentModeId/pos{x,y}/modes…）；
//   GNOME：mutter `org.gnome.Mutter.DisplayConfig.GetCurrentState`——私有/
//     不稳定 API，**字段序以接口 XML 为准且未核**（S7 真机定），当前只做
//     存在性探测，读一率 Unsupported——不拿猜的字段序产出假读数；
//   wlroots：wlr-output-management-unstable-v1 要 Wayland 协议客户端地基，
//     归 P3 之后，当前 Unsupported。
//
// 出口对齐 `@sys.mon_list` 的 `MonitorInfo`（同结构，应用侧无感切换）。
// KScreen 的 mode 没有 preferred 标志位（实物核过），故 `preferred` 恒
// false；`current` 由 output 的 currentModeId 对回。

///|
/// KScreen 后端接口（KDE 实物：dest org.kde.KScreen，path /backend）。
pub const KSCREEN_DEST : String = "org.kde.KScreen"

///|
pub const KSCREEN_PATH : String = "/backend"

///|
pub const KSCREEN_IFACE : String = "org.kde.kscreen.Backend"

///|
/// mutter DisplayConfig（GNOME；字段序未核，只探存在性）。
pub const MUTTER_DC_DEST : String = "org.gnome.Mutter.DisplayConfig"

///|
pub const MUTTER_DC_PATH : String = "/org/gnome/Mutter/DisplayConfig"

///|
/// KScreen 在不在（会话总线上有名）。
pub fn kscreen_available() -> Bool {
  match
    @dbus.gdbus_call_session(
      KSCREEN_DEST,
      KSCREEN_PATH,
      "org.freedesktop.DBus.Peer",
      "Ping",
      [],
    ) {
    Ok(_) => true
    Err(_) => false
  }
}

///|
/// mutter DisplayConfig 在不在（GNOME 会话）。
pub fn mutter_dc_available() -> Bool {
  match
    @dbus.gdbus_call_session(
      MUTTER_DC_DEST,
      MUTTER_DC_PATH,
      "org.freedesktop.DBus.Peer",
      "Ping",
      [],
    ) {
    Ok(_) => true
    Err(_) => false
  }
}

///|
/// variant(a{sv}) → 字典（KScreen 的 size/pos 都是这个形态）。
fn ksc_sub_dict(v : @dbus.GDBusValue) -> Map[String, @dbus.GDBusValue]? {
  match v {
    @dbus.GVVariant(@dbus.GVDict(m)) => Some(m)
    @dbus.GVDict(m) => Some(m)
    _ => None
  }
}

///|
/// variant(av) → 元素数组（outputs/modes 都是这个形态）。
fn ksc_sub_arr(v : @dbus.GDBusValue) -> Array[@dbus.GDBusValue]? {
  match v {
    @dbus.GVVariant(@dbus.GVArray(_, arr)) => Some(arr)
    @dbus.GVArray(_, arr) => Some(arr)
    _ => None
  }
}

///|
/// 取字典里的整数字段（int64/int32/uint32 都吃）。
fn ksc_int(m : Map[String, @dbus.GDBusValue], key : String) -> Int? {
  match m.get(key) {
    Some(@dbus.GVInt64(v)) => Some(v.to_int())
    Some(@dbus.GVInt32(v)) => Some(v)
    Some(@dbus.GVUInt32(v)) => Some(v)
    _ => None
  }
}

///|
/// 取字典里的字符串字段。
fn ksc_str(m : Map[String, @dbus.GDBusValue], key : String) -> String? {
  match m.get(key) {
    Some(@dbus.GVString(s)) => Some(s)
    _ => None
  }
}

///|
/// 取字典里的布尔字段。
fn ksc_bool(m : Map[String, @dbus.GDBusValue], key : String) -> Bool {
  match m.get(key) {
    Some(@dbus.GVBool(b)) => b
    _ => false
  }
}

///|
/// 一个 mode 的解码结果（id 用于对回 currentModeId）。
priv struct KscMode {
  id : String
  mode : @sys.MonitorMode
}

///|
/// 解一个 mode（a{sv}：id / refreshRate / size{a{sv} width,height}）。
fn ksc_mode(v : @dbus.GDBusValue) -> KscMode? {
  let m = match v {
    @dbus.GVVariant(@dbus.GVDict(m)) => m
    _ => return None
  }
  let id = match ksc_str(m, "id") {
    Some(s) => s
    None => return None
  }
  let (w, h) = match m.get("size") {
    Some(sv) =>
      match ksc_sub_dict(sv) {
        Some(sm) => (ksc_int(sm, "width").unwrap_or(0), ksc_int(sm, "height").unwrap_or(0))
        None => (0, 0)
      }
    None => (0, 0)
  }
  // refreshRate 双形态：本机 KScreen 给 int64 赫兹（25/50/60/75，实物核过），
  // 旧版/别家给 double 赫兹（59.9506）——都吃，统一换百分之一赫兹
  let rate = match m.get("refreshRate") {
    Some(@dbus.GVInt64(hz)) => (hz * 100).to_int()
    Some(@dbus.GVInt32(hz)) => hz * 100
    Some(@dbus.GVUInt32(hz)) => hz * 100
    Some(@dbus.GVDouble(hz)) => (hz * 100.0).to_int()
    Some(@dbus.GVVariant(@dbus.GVDouble(hz))) => (hz * 100.0).to_int()
    _ => 0
  }
  Some({ id, mode: { width: w, height: h, refresh_centi: rate, preferred: false, current: false } })
}

///|
/// 解一个 output（a{sv}）→ MonitorInfo。name 缺失的不是输出（跳过）。
fn ksc_output(v : @dbus.GDBusValue) -> @sys.MonitorInfo? {
  let m = match v {
    @dbus.GVVariant(@dbus.GVDict(m)) => m
    _ => return None
  }
  let name = match ksc_str(m, "name") {
    Some(n) => n
    None => return None
  }
  // modes：id + MonitorMode 平行收集（current 对回用）
  let ksc_modes : Array[KscMode] = []
  match m.get("modes") {
    Some(mv) =>
      match ksc_sub_arr(mv) {
        Some(arr) =>
          for e in arr {
            match ksc_mode(e) {
              Some(km) => ksc_modes.push(km)
              None => ()
            }
          }
        None => ()
      }
    None => ()
  }
  let cur_id = ksc_str(m, "currentModeId").unwrap_or("")
  let modes : Array[@sys.MonitorMode] = []
  let mut cw = 0
  let mut ch = 0
  let mut crate = 0
  for km in ksc_modes {
    let is_cur = cur_id != "" && km.id == cur_id
    if is_cur {
      cw = km.mode.width
      ch = km.mode.height
      crate = km.mode.refresh_centi
    }
    modes.push({
      width: km.mode.width,
      height: km.mode.height,
      refresh_centi: km.mode.refresh_centi,
      preferred: false,
      current: is_cur,
    })
  }
  let (px, py) = match m.get("pos") {
    Some(pv) =>
      match ksc_sub_dict(pv) {
        Some(pm) => (ksc_int(pm, "x").unwrap_or(0), ksc_int(pm, "y").unwrap_or(0))
        None => (0, 0)
      }
    None => (0, 0)
  }
  Some({
    name,
    connected: ksc_bool(m, "connected"),
    primary: ksc_bool(m, "primary"),
    width: cw,
    height: ch,
    refresh_centi: crate,
    pos_x: px,
    pos_y: py,
    // KScreen 不报物理尺寸（实物字段核过）——与 xrandr 臂报 0 同口径
    mm_width: 0,
    mm_height: 0,
    modes,
  })
}

///|
/// KScreen 输出枚举 → MonitorInfo（字段按实物解析）。KScreen 不在给 Err。
pub fn kscreen_mon_list() -> Result[Array[@sys.MonitorInfo], String] {
  if !kscreen_available() {
    return Err("KScreen 不在会话总线上")
  }
  match
    @dbus.gdbus_call_session(
      KSCREEN_DEST,
      KSCREEN_PATH,
      KSCREEN_IFACE,
      "getConfig",
      [],
    ) {
    Err(e) => Err("KScreen getConfig 失败: \{e.name} \{e.message}")
    Ok(cfg) => {
      let outs = match cfg {
        @dbus.GVDict(m) =>
          match m.get("outputs") {
            Some(ov) => ksc_sub_arr(ov)
            None => None
          }
        _ => None
      }
      match outs {
        None => Err("KScreen getConfig 形态不符（无 outputs）")
        Some(arr) => {
          let out : Array[@sys.MonitorInfo] = []
          for v in arr {
            match ksc_output(v) {
              Some(mi) => out.push(mi)
              None => ()
            }
          }
          Ok(out)
        }
      }
    }
  }
}

///|
/// Wayland 档显示器枚举（集成门面）：KDE 走 KScreen（本机实证）；GNOME 的
/// mutter DisplayConfig 字段序未核（S7 真机定）只探存在；都不是给 Err——
/// **不拿 XWayland 的 xrandr 假数据冒充**（那正是 P0 堵掉的形态）。
pub fn wayland_mon_list() -> Result[Array[@sys.MonitorInfo], String] {
  if kscreen_available() {
    return kscreen_mon_list()
  }
  if mutter_dc_available() {
    return Err("mutter DisplayConfig 在，但字段序未核（S7 真机定）——暂不产出读数")
  }
  Err("Wayland 会话无已知显示器通道（wlroots 协议客户端待 P3 之后）")
}
