// W20c 托盘门面回归：纯函数部分（文件名 → 托盘 Id、桌面环境名、错误 Show）。
// 后端可用性与回调消息落点归 experiment/tray_probe（纯 C 探针直喂 wm_tray_*）。
// 真建托盘的几条默认 skip——门禁跑在开发机真桌面上，真注册会往系统通知区
// 插图标，测试一红进程带项退出、注销报文没发出去，Linux 面板就留幽灵图标；
// 设 NG_TRAY_WBTEST=1 手动跑互操作验证。

///|
/// 真总线托盘测试开关（shell 与 dbus 的 wbtest 同口径）。
fn real_tray_wbtest_enabled() -> Bool {
  match @sys.sys_getenv("NG_TRAY_WBTEST") {
    Some(v) => v != "" && v != "0"
    None => false
  }
}

///|
test "basename_no_ext：常见路径" {
  inspect(basename_no_ext("icon.png"), content="icon")
  inspect(basename_no_ext("/usr/share/pixmaps/app.png"), content="app")
  inspect(basename_no_ext("tray.ico"), content="tray")
  inspect(basename_no_ext("noext"), content="noext")
}

///|
test "basename_no_ext：Windows 反斜杠路径" {
  inspect(basename_no_ext("C:\\dir\\icon.ico"), content="icon")
  inspect(basename_no_ext("C:\\a.b\\c\\icon.png"), content="icon")
}

///|
test "basename_no_ext：目录名里的点不算扩展名" {
  // 末段是目录名时，其内的点不该被当扩展名分隔
  inspect(basename_no_ext("a.b/c"), content="c")
  inspect(basename_no_ext("/x.y/z/noext"), content="noext")
  // 反斜杠末段的点同理
  inspect(basename_no_ext("x.y\\win"), content="win")
}

///|
test "basename_no_ext：空串与尾点" {
  inspect(basename_no_ext(""), content="")
  inspect(basename_no_ext("foo."), content="foo")
  // 多重点只切最后一个
  inspect(basename_no_ext("a.tar.gz"), content="a.tar")
}

///|
test "desktop_environment 给非空串（认不出为 unknown）" {
  let name = desktop_environment()
  assert_true(name.length() > 0)
}

///|
test "TrayError 的 Show 三种变体" {
  assert_eq(TrayError::Unsupported.to_string(), "TrayError::Unsupported")
  assert_eq(TrayError::IconLoadFailed.to_string(), "TrayError::IconLoadFailed")
  assert_true(TrayError::Backend("槽表满").to_string().contains("槽表满"))
}

///|
test "Tray 生命周期（NG_TRAY_WBTEST=1 才真跑）" {
  // 真往系统通知区插一次图标再摘掉（建→摘在同一拍内完成）。默认 skip 见文件
  // 头；无托盘后端的环境（无显示服务 / Linux watcher 不在线）同样跳过而非
  // 造假——探测即口径。
  if !real_tray_wbtest_enabled() {
    println("skip: 默认不碰真托盘（设 NG_TRAY_WBTEST=1 跑）")
  } else if !Tray::is_supported() {
    println("skip: 本机没有可用的托盘后端")
  } else {
    match Tray::new("libyue-wbtest") {
      Err(e) => println("skip: 建托盘失败(\{e})")
      Ok(t) => {
        // Win32 后端应拿到槽号；SNI 后端没槽号，跳过槽号断言
        let slot = match t.backend() {
          Native(s) => s
          Sni(_) => 0
        }
        if slot >= 1 {
          assert_eq(t.backend_name(), "native")
          assert_eq(@win.tray_count(), 1)
          t.set_tooltip("libyue", "wbtest 提示")
          assert_eq(@win.tray_tooltip(slot), "wbtest 提示")
          // 队列空时派发给 false
          assert_false(dispatch_tray_event())
          // 挂菜单不崩，且弹出菜单句柄已回填（W20a 的翻译链走通）
          let menu = Menu::new()
          let _ = menu.add_item("甲")
          let _ = menu.add_separator()
          let _ = menu.add_item("乙")
          t.set_menu(menu)
          assert_true(t.state.menu_handle >= 1)
          t.remove()
          assert_eq(@win.tray_count(), 0)
        } else {
          assert_eq(t.backend_name(), "sni")
          // SNI 侧：设置标题/提示/菜单都不该崩（真面板行为留使用者复验）
          t.set_title("wbtest")
          t.set_tooltip("libyue", "wbtest 提示")
          let menu = Menu::new()
          let _ = menu.add_item("甲")
          t.set_menu(menu)
          t.remove()
        }
      }
    }
  }
}

///|
test "退出兜底：未收到退出信号时不报退出，批量注销可空跑" {
  assert_false(quit_requested())
  remove_all_trays()
  remove_all_trays() // 幂等：在册表已空
}

///|
test "退出兜底：批量注销真的摘掉 Win32 槽（否则退出后留僵尸图标）" {
  // 量的是 @win.tray_count()：只做 SNI 兜底时它注销后仍为 1——进程退出后
  // 通知区那个图标没有任何窗口接回调，右键既不弹菜单也不出 tooltip，要等
  // 鼠标扫过才被 Shell 顺手清掉。
  if !real_tray_wbtest_enabled() {
    println("skip: 默认不碰真托盘（设 NG_TRAY_WBTEST=1 跑）")
  } else if !Tray::is_supported() {
    println("skip: 本机没有可用的托盘后端")
  } else {
    match Tray::new("libyue-wbtest-batch") {
      Err(e) => println("skip: 建托盘失败(\{e})")
      Ok(t) =>
        match t.backend() {
          Native(_) => {
            assert_eq(@win.tray_count(), 1)
            remove_all_trays()
            assert_eq(@win.tray_count(), 0)
          }
          // SNI 侧由 sni 自己的表收尾，这里只验不崩
          Sni(_) => remove_all_trays()
        }
    }
  }
}

///|
test "自绘位图换图标：像素口径换算与非法输入保持原图标" {
  let solid = Bytes::makei(2 * 2 * 4, fn(_i) { b'\xff' })
  // 尺寸非正 / 字节不够 → 0（调用方据此保持原图标，不把空句柄塞给后端）
  assert_eq(argb_to_icon_handle(solid, 0, 4), 0)
  assert_eq(argb_to_icon_handle(solid, 4, 0), 0)
  assert_eq(argb_to_icon_handle(Bytes::makei(12, fn(_i) { b'\xff' }), 2, 4), 0)
  // 合法位图：native（Win/mac）建得出句柄，GTK 桩那侧给 0——两档都不该崩
  assert_true(argb_to_icon_handle(solid, 2, 2) >= 0)
  // 内置档同样走这条换算，句柄进程级缓存复用
  assert_eq(builtin_tray_handle(), builtin_tray_handle())
}

///|
test "Tray::set_icon_pixmap / set_icon_builtin（NG_TRAY_WBTEST=1 才真跑）" {
  if !real_tray_wbtest_enabled() {
    println("skip: 默认不碰真托盘（设 NG_TRAY_WBTEST=1 跑）")
  } else if !Tray::is_supported() {
    println("skip: 本机没有可用的托盘后端")
  } else {
    match Tray::new("libyue-wbtest-icon") {
      Err(e) => println("skip: 建托盘失败(\{e})")
      Ok(t) => {
        let (w, h, px) = (
          4,
          4,
          Bytes::makei(4 * 4 * 4, fn(i) { if i % 4 == 0 { b'\x80' } else { b'\x40' } }),
        )
        t.set_icon_pixmap(w, h, px)
        // 非法像素：静默保持上一次的图标，不崩也不清空
        t.set_icon_pixmap(0, 0, Bytes::makei(0, fn(_i) { b'\x00' }))
        t.set_icon_builtin()
        t.remove()
      }
    }
  }
}
