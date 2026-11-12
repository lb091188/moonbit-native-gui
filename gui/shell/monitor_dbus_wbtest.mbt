// Wayland 显示器通道回归：合成一棵 KScreen 形态的值树喂解析器（无总线也可
// 验），真总线在场时跑一轮集成（不在则跳过）。

///|
/// 造一个 KScreen mode 条目（variant(a{sv})：id / size{width,height} /
/// refreshRate int64 赫兹——本机实物口径）。
fn ksc_t_mode(
  id : String,
  w : Int32,
  h : Int32,
  hz : Int64,
) -> @dbus.GDBusValue {
  let m : Map[String, @dbus.GDBusValue] = Map([])
  m.set("id", @dbus.GVString(id))
  let sz : Map[String, @dbus.GDBusValue] = Map([])
  sz.set("width", @dbus.GVInt64(w.to_int64()))
  sz.set("height", @dbus.GVInt64(h.to_int64()))
  m.set("size", @dbus.GVVariant(@dbus.GVDict(sz)))
  m.set("refreshRate", @dbus.GVInt64(hz))
  @dbus.GVVariant(@dbus.GVDict(m))
}

///|
/// 造一个 KScreen output 条目（variant(a{sv})）。
fn ksc_t_output(
  name : String,
  connected : Bool,
  current_id : String,
  modes : Array[@dbus.GDBusValue],
) -> @dbus.GDBusValue {
  let m : Map[String, @dbus.GDBusValue] = Map([])
  m.set("name", @dbus.GVString(name))
  m.set("connected", @dbus.GVBool(connected))
  m.set("enabled", @dbus.GVBool(connected))
  m.set("currentModeId", @dbus.GVString(current_id))
  m.set("modes", @dbus.GVVariant(@dbus.GVArray("v", modes)))
  let pos : Map[String, @dbus.GDBusValue] = Map([])
  pos.set("x", @dbus.GVInt64(1920L))
  pos.set("y", @dbus.GVInt64(0L))
  m.set("pos", @dbus.GVVariant(@dbus.GVDict(pos)))
  @dbus.GVVariant(@dbus.GVDict(m))
}

///|
test "kscreen：合成值树解析（嵌套 variant(a{sv}) / int64 赫兹 / currentModeId 对回）" {
  let out = ksc_t_output("HDMI-0", true, "449", [
    ksc_t_mode("448", 1920, 1080, 60),
    ksc_t_mode("449", 2560, 1440, 59),
  ])
  match ksc_output(out) {
    None => fail("output 解析失败")
    Some(mi) => {
      assert_eq(mi.name, "HDMI-0")
      assert_true(mi.connected)
      assert_eq(mi.modes.length(), 2)
      // currentModeId=449 → 2560x1440@5900（int64 赫兹 ×100）
      assert_eq(mi.width, 2560)
      assert_eq(mi.height, 1440)
      assert_eq(mi.refresh_centi, 5900)
      // pos 是 variant(a{sv})
      assert_eq(mi.pos_x, 1920)
      assert_eq(mi.pos_y, 0)
      // current 标记落在 449 上；KScreen 无 preferred 位，恒 false
      assert_eq(mi.modes[0].current, false)
      assert_true(mi.modes[1].current)
      assert_true(!mi.modes[0].preferred)
      // 物理尺寸 KScreen 不报——与 xrandr 臂报 0 同口径
      assert_eq(mi.mm_width, 0)
      assert_eq(mi.mm_height, 0)
    }
  }
  // 未连输出：currentModeId 空 → 0x0、模式仍在
  let off = ksc_t_output("DP-1", false, "", [ksc_t_mode("1", 1920, 1080, 60)])
  match ksc_output(off) {
    None => fail("未连 output 解析失败")
    Some(mi) => {
      assert_true(!mi.connected)
      assert_eq(mi.width, 0)
      assert_eq(mi.modes.length(), 1)
    }
  }
  // 没有 name 的不是输出（跳过）
  let bad = @dbus.GVVariant(@dbus.GVDict(Map([])))
  assert_true(ksc_output(bad) is None)
}

///|
test "kscreen：真总线集成（无 KScreen 的环境跳过）" {
  if !kscreen_available() {
    println("kscreen: skip（会话总线上无 KScreen）")
  } else {
    match kscreen_mon_list() {
      Err(e) => fail("KScreen 在但枚举失败: \{e}")
      Ok(list) => {
        println("kscreen: \{list.length()} 个输出")
        // 已连输出必须带分辨率与模式表（实物口径：currentModeId 对回）
        let mut seen_connected = false
        for m in list {
          if m.connected {
            seen_connected = true
            assert_true(
              m.width > 0 && m.height > 0,
              msg="已连输出无分辨率: \{m.name}",
            )
            assert_true(
              m.modes.length() > 0,
              msg="已连输出无模式表: \{m.name}",
            )
          }
        }
        assert_true(
          seen_connected,
          msg="KScreen 在但一个已连输出都没有",
        )
      }
    }
  }
}

///|
test "monitor 门面：Wayland 档不拿 XWayland 假数据冒充" {
  // 无 KScreen 且无 mutter 时必须 Err（不是回 xrandr 的 XWAYLAND 虚拟屏）
  if !kscreen_available() && !mutter_dc_available() {
    match wayland_mon_list() {
      Ok(_) =>
        fail("无 Wayland 显示器通道却返回了读数（假数据）")
      Err(_) => ()
    }
  }
}
