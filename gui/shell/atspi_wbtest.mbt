// AT-SPI 桥的无头回归：只钉纯函数面（行解析 / 角色·状态·接口映射 / 路径
//  scheme / 文本切片 / 入站派发），不碰真总线——总线在场与否由启动路径的
// 背间隔重试自理（无 at-spi 的 CI 上 atspi_start 失败即标记不可用，不崩）。

///|
fn atspi_test_node(
  id : Int,
  parent : Int,
  role : String,
  name : String,
  state : String,
  value : String,
  text : String,
  enabled : Bool,
) -> AtspiNode {
  { id, parent, enabled, role, name, state, value, text, x: 10.0, y: 20.0, w: 80.0, h: 30.0 }
}

///|
test "atspi：行 TSV 往返解析（字段序与发布侧一致）" {
  let row = atspi_test_node(7, 3, "button", "确定", "", "", "确定", true)
  let tsv = "7\t3\t1\tbutton\t确定\t\t\t确定\t10\t20\t80\t30"
  match atspi_row_parse(tsv) {
    Some(r) => {
      assert_eq(r.id, row.id)
      assert_eq(r.parent, row.parent)
      assert_eq(r.role, "button")
      assert_eq(r.name, "确定")
      assert_eq(r.text, "确定")
      assert_eq(r.enabled, true)
      assert_eq(r.x, 10.0)
      assert_eq(r.h, 30.0)
    }
    None => fail("解析失败")
  }
  // 字段不够 / 数字坏了都要 None（不许半价行）
  assert_true(atspi_row_parse("1\t2\t3") is None)
  assert_true(atspi_row_parse("x\t2\t1\tb\t\t\t\t\t10\t20\t80\t30") is None)
}

///|
test "atspi：角色/角色名映射（枚举值按 AtspiRole 实物）" {
  assert_eq(atspi_role_of("button"), 43) // push_button
  assert_eq(atspi_role_of("checkbox"), 7) // check_box
  assert_eq(atspi_role_of("radio"), 44) // radio_button
  assert_eq(atspi_role_of("switch"), 7) // check_box（与 UIA/AX 同口径）
  assert_eq(atspi_role_of("slider"), 51)
  assert_eq(atspi_role_of("stepper"), 52)
  assert_eq(atspi_role_of("text_input"), 61)
  assert_eq(atspi_role_of("select"), 11) // combo_box
  assert_eq(atspi_role_of("progress"), 42)
  assert_eq(atspi_role_of("heading"), 83)
  assert_eq(atspi_role_of("link"), 88)
  assert_eq(atspi_role_of("window"), 23) // frame
  assert_eq(atspi_role_of("闻所未闻的角色"), 39) // panel 兜底
  assert_eq(atspi_role_name_of("button"), "push button")
  assert_eq(atspi_role_name_of("switch"), "check box")
}

///|
test "atspi：状态位集合（焦点/勾选/只读/多行/可编辑）" {
  let btn = atspi_test_node(1, 0, "button", "确定", "", "", "", true)
  let st = atspi_states_of(btn, 0)
  assert_true(st.contains(25)) // showing
  assert_true(st.contains(30)) // visible
  assert_true(st.contains(8)) // enabled
  assert_true(!st.contains(12)) // 无焦点
  // 焦点命中
  assert_true(atspi_states_of(btn, 1).contains(12))
  // 勾选态
  let cb = atspi_test_node(2, 0, "checkbox", "记住我", "checked", "", "", true)
  assert_true(atspi_states_of(cb, 0).contains(4)) // checked
  // 只读文本件：read_only 有、editable 无
  let ro = atspi_test_node(3, 0, "text_input", "", "read_only", "abc", "", true)
  let st3 = atspi_states_of(ro, 0)
  assert_true(st3.contains(43)) // read_only
  assert_true(!st3.contains(7)) // editable
  // 多行文本件：multi_line + editable
  let ta = atspi_test_node(4, 0, "text_area", "", "", "line1\nline2", "", true)
  let st4 = atspi_states_of(ta, 0)
  assert_true(st4.contains(17)) // multi_line
  assert_true(st4.contains(7)) // editable
  // 禁用件：enabled/sensitive 都不给
  let dis = atspi_test_node(5, 0, "button", "取消", "", "", "", false)
  let st5 = atspi_states_of(dis, 0)
  assert_true(!st5.contains(8))
  assert_true(!st5.contains(24))
}

///|
test "atspi：接口挂载（Accessible/Component 全体 + 按角色三族）" {
  let btn = atspi_test_node(1, 0, "button", "确定", "", "", "", true)
  let ifs = atspi_ifaces_of(btn)
  assert_true(ifs.contains("org.a11y.atspi.Accessible"))
  assert_true(ifs.contains("org.a11y.atspi.Component"))
  assert_true(ifs.contains("org.a11y.atspi.Action"))
  assert_true(!ifs.contains("org.a11y.atspi.Text"))
  let ed = atspi_test_node(2, 0, "text_input", "", "", "abc", "", true)
  assert_true(atspi_ifaces_of(ed).contains("org.a11y.atspi.Text"))
  assert_true(!atspi_ifaces_of(ed).contains("org.a11y.atspi.Action"))
  let sl = atspi_test_node(3, 0, "slider", "", "", "50%", "", true)
  assert_true(atspi_ifaces_of(sl).contains("org.a11y.atspi.Value"))
  let panel = atspi_test_node(4, 0, "group", "", "", "", "", true)
  let pifs = atspi_ifaces_of(panel)
  assert_true(!pifs.contains("org.a11y.atspi.Text"))
  assert_true(!pifs.contains("org.a11y.atspi.Value"))
  assert_true(!pifs.contains("org.a11y.atspi.Action"))
}

///|
test "atspi：路径 scheme（应用根/窗口根/控件按 id 稳态）" {
  assert_eq(atspi_widget_path(42), "/org/a11y/atspi/accessible/win/42")
  let rows : Array[AtspiNode] = [
    atspi_test_node(9, 0, "window", "窗", "", "", "", true),
    atspi_test_node(10, 9, "button", "确定", "", "", "", true),
    atspi_test_node(11, 9, "text_input", "", "", "abc", "", true),
  ]
  // 窗口根行 = parent==0
  assert_eq(atspi_window_row(rows).unwrap().id, 9)
  // 按路径找行
  assert_eq(atspi_row_at(rows, "/org/a11y/atspi/accessible/win/10").unwrap().id, 10)
  assert_true(atspi_row_at(rows, "/org/a11y/atspi/accessible/win/999") is None)
  assert_true(atspi_row_at(rows, "/org/a11y/atspi/accessible/root") is None) // 合成节点
  // 子行按快照序
  let kids = atspi_children_of(rows, 9)
  assert_eq(kids.length(), 2)
  assert_eq(kids[0].id, 10)
  assert_eq(kids[1].id, 11)
}

///|
test "atspi：文本切片按字符（AT-SPI 偏移单位，中文不吃字节）" {
  // "你好ab"：4 字符 / 6 字节——按字符切片才不劈开汉字
  assert_eq(atspi_slice_chars("你好ab", 0, 2), "你好")
  assert_eq(atspi_slice_chars("你好ab", 2, 4), "ab")
  assert_eq(atspi_slice_chars("你好ab", 1, 3), "好a")
  assert_eq(atspi_slice_chars("你好ab", 3, 99), "b") // 越界钳制
  assert_eq(atspi_slice_chars("你好ab", 4, 2), "") // end<start 给空
  assert_eq(atspi_chars("你好ab").length(), 4)
}

///|
test "atspi：百分比解析（\"50%\"→50）" {
  assert_eq(atspi_pct("50%"), 50.0)
  assert_eq(atspi_pct("100%"), 100.0)
  assert_eq(atspi_pct("0"), 0.0)
  assert_eq(atspi_pct(""), 0.0)
  assert_eq(atspi_pct("abc"), 0.0)
}

///|
test "atspi：入站派发（假 CallReq 驱动，不碰真总线）" {
  // 造一棵三行树：窗口根 + 按钮 + 输入框
  let tsv = "1\t0\t1\twindow\t演示窗\t\t\t\t0\t0\t400\t300\n" +
    "2\t1\t1\tbutton\t确定\t\t\t确定\t10\t10\t80\t30\n" +
    "5\t1\t1\ttext_input\t昵称\t\t你好世界\t\t220\t10\t160\t30\n"
  @win.a11y_publish(@utf8.encode(tsv), 3)
  @win.a11y_set_focus(2)
  // 记录应答的假 CallReq（bus=2 = a11y 总线）
  let got : Array[(String, Array[@dbus.GDBusValue])] = []
  let req = fn(
    path : String,
    iface : String,
    action : String,
    args : Array[@dbus.GDBusValue],
  ) -> @dbus.CallReq {
    {
      bus: 2,
      sender: ":1.9",
      path,
      iface,
      action,
      args,
      reply: fn(vals : Array[@dbus.GDBusValue]) -> Unit {
        got.push((action, vals))
      },
      reply_error: fn(name : String, _msg : String) -> Unit {
        got.push(("ERR:" + name, []))
      },
    }
  }
  // Accessible.GetRole（按钮 = push_button 43）
  assert_true(
    atspi_handle(req("/org/a11y/atspi/accessible/win/2", "org.a11y.atspi.Accessible", "GetRole", [])),
  )
  assert_eq(got.length(), 1)
  assert_eq(got[0].0, "GetRole")
  match got[0].1 {
    [@dbus.GVUInt32(43)] => ()
    _ => fail("GetRole 应答不是 u=43（push_button）")
  }
  // GetChildren（窗口根的孩子 = 按钮一个，(so) 形态）
  assert_true(
    atspi_handle(
      req(
        "/org/a11y/atspi/accessible/win",
        "org.a11y.atspi.Accessible",
        "GetChildren",
        [],
      ),
    ),
  )
  match got[1].1 {
    [@dbus.GVArray("(so)", kids)] => assert_eq(kids.length(), 2) // 按钮 + 输入框
    _ => fail("GetChildren 应答形态不对")
  }
  // Properties.Get Name
  assert_true(
    atspi_handle(
      req(
        "/org/a11y/atspi/accessible/win/2",
        "org.freedesktop.DBus.Properties",
        "Get",
        [@dbus.GVString("org.a11y.atspi.Accessible"), @dbus.GVString("Name")],
      ),
    ),
  )
  match got[2].1 {
    [@dbus.GVVariant(@dbus.GVString(n))] => assert_eq(n, "确定")
    _ => fail("Properties.Get Name 应答形态不对")
  }
  // Text.GetText 打输入框：字符口径切前两个字符（"你好"）
  assert_true(
    atspi_handle(
      req(
        "/org/a11y/atspi/accessible/win/5",
        "org.a11y.atspi.Text",
        "GetText",
        [@dbus.GVInt32(0), @dbus.GVInt32(2)],
      ),
    ),
  )
  match got[3].1 {
    [@dbus.GVString(t)] => assert_eq(t, "你好")
    _ => fail("Text.GetText 应答形态不对")
  }
  // 非文本件不挂 Text：直接拒（与 GetInterfaces 广告一致），不是崩
  assert_false(
    atspi_handle(
      req(
        "/org/a11y/atspi/accessible/win/2",
        "org.a11y.atspi.Text",
        "GetText",
        [@dbus.GVInt32(0), @dbus.GVInt32(1)],
      ),
    ),
  )
  // 非 a11y 路径直接不接（返回 false）
  assert_false(
    atspi_handle(req("/some/other/path", "org.a11y.atspi.Accessible", "GetRole", [])),
  )
}

///|
test "atspi：连接活性判据（自愈重连换名即该重Embed）" {
  // 名一致且活着：不用动
  assert_true(!atspi_needs_reembed(":1.7", ":1.7", true))
  // 自愈重建后唯一名变了（registry 挂旧名）：必须重Embed
  assert_true(atspi_needs_reembed(":1.7", ":1.9", true))
  // 连接没了（自愈尚未重建）：重Embed
  assert_true(atspi_needs_reembed(":1.7", ":1.7", false))
  assert_true(atspi_needs_reembed(":1.7", "", false))
  // 未连接时空名也算不符（Conn::name 空串口径）
  assert_true(atspi_needs_reembed(":1.7", "", true))
}

///|
test "atspi：真总线集成（无 a11y 总线的环境跳过）" {
  match atspi_start() {
    Err(e) => {
      println("atspi: skip（本机无 a11y 总线: \{e}）")
    }
    Ok(_) => {
      // 发一帧三行快照（窗口 + 按钮 + 勾选）并泵一拍
      let tsv = "1\t0\t1\twindow\t演示窗\t\t\t\t0\t0\t400\t300\n" +
        "2\t1\t1\tbutton\t确定\t\t\t确定\t10\t10\t80\t30\n" +
        "3\t1\t1\tcheckbox\t记住我\tchecked\t\t\t10\t50\t80\t30\n"
      @win.a11y_publish(@utf8.encode(tsv), 3)
      atspi_tick()
      let mine = @dbus.dbus_a11y_unique_name()
      assert_true(mine != "", msg="a11y 总线应给出本端唯一名")
      // ① registry 根的孩子里应有我们（Embed 注册生效）
      match
        @dbus.gdbus_call_a11y(
          "org.a11y.atspi.Registry",
          ATSPI_ROOT_PATH,
          "org.a11y.atspi.Accessible",
          "GetChildren",
          [],
        ) {
        Ok(@dbus.GVArray("(so)", kids)) => {
          let mut found = false
          for k in kids {
            match k {
              @dbus.GVStruct([@dbus.GVString(n), @dbus.GVPath(p)]) =>
                if n == mine && p == ATSPI_ROOT_PATH {
                  found = true
                }
              _ => ()
            }
          }
          assert_true(found, msg="registry 根下应看到本应用")
        }
        _ => fail("registry GetChildren 应答形态不对")
      }
      // ② 自调用问自己的根要孩子（走 handler 应答整条链）
      match
        @dbus.gdbus_call_a11y(
          mine,
          ATSPI_ROOT_PATH,
          "org.a11y.atspi.Accessible",
          "GetChildren",
          [],
        ) {
        Ok(@dbus.GVArray("(so)", kids)) => assert_eq(kids.length(), 1)
        _ => fail("应用根 GetChildren 应答形态不对")
      }
      // ③ 自调用问窗口根的孩子（= 快照里两个控件）
      match
        @dbus.gdbus_call_a11y(
          mine,
          ATSPI_WIN_PATH,
          "org.a11y.atspi.Accessible",
          "GetChildren",
          [],
        ) {
        Ok(@dbus.GVArray("(so)", kids)) => assert_eq(kids.length(), 2)
        _ => fail("窗口根 GetChildren 应答形态不对")
      }
      println("atspi: 真总线集成通过")
    }
  }
}
