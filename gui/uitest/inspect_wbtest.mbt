// 无头检查直调用例：dump_tree 列序与 kind 采集、shot 落盘、kind 读数。

///|
/// 平台临时目录根（口径同 gui/sys/fsx_wbtest.mbt 的 fsx_tmp_root）：
/// Windows 读 %TEMP%/%TMP%（回退当前目录），其余读 $TMPDIR（回退 /tmp）。
/// shot 落盘路径不能用写死的 `/tmp`——Windows 原生进程下该目录不存在，
/// fsw_write_file 必失败，shot 断言恒红。
fn uitest_tmp_root() -> String {
  if @shell.platform_name() == "windows" {
    for name in ["TEMP", "TMP"] {
      match @env.get_env_var(name) {
        Some(v) if v.length() > 0 => return v
        _ => ()
      }
    }
    "."
  } else {
    match @env.get_env_var("TMPDIR") {
      Some(v) if v.length() > 0 => return v
      _ => ()
    }
    "/tmp"
  }
}

///|
/// 临时目录 + 文件名拼落盘路径：目录自带尾分隔符（mac 的 $TMPDIR）时不再补。
fn uitest_tmp_path(name : String) -> String {
  let dir = uitest_tmp_root()
  let sep = if dir.has_suffix("/") || dir.has_suffix("\\") { "" } else { "/" }
  "\{dir}\{sep}\{name}"
}

///|
test "Tester::dump_tree：列头 + kind/role/name 采集（与服务端 tree 同列序）" {
  let t = mount_all(
    [
      @widget.node_of_new(fn(w : @widget.Widget) -> @widget.Widget {
        w.kind = "Button"
        w.role = "button"
        w.label = "确定"
        w
      }),
    ],
    160.0,
    120.0,
  )
  t.frame()
  let out = t.dump_tree()
  // 首行列头与服务端 tree 命令一致
  assert_true(
    out.has_prefix(
      "#kind\trole\tname\tid\tparent\tx\ty\tw\th\tstate\tvalue\ttext\tenabled\n",
    ),
  )
  // 根行 Window + 按钮行带 kind 与正文
  assert_true(out.contains("Window"))
  assert_true(out.contains("Button\tbutton\t"))
}

///|
test "Tester::kind：读构造自带类型名" {
  let t = mount_all(
    [
      @widget.node_of_new(fn(w : @widget.Widget) -> @widget.Widget {
        w.kind = "Slider"
        w.role = "slider"
        w
      }),
    ],
    160.0,
    120.0,
  )
  t.frame()
  assert_true(t.dump_tree().contains("Slider\tslider\t"))
}

///|
test "Tester::shot：frame 后落盘 PNG；未 frame 给 false" {
  let t = mount_all([], 80.0, 60.0)
  assert_true(!t.shot(uitest_tmp_path("mng-uitest-shot-empty.png")))
  t.frame()
  assert_true(t.shot(uitest_tmp_path("mng-uitest-shot-test.png")))
}

///|
test "Tester::shot_full：无滚动容器给 false；有滚动容器按内容高出整页图" {
  // 无 ScrollView：没有整页可截
  let t0 = mount_all([], 120.0, 80.0)
  t0.frame()
  assert_true(!t0.shot_full(uitest_tmp_path("mng-uitest-full-none.png")))
  // 模拟 scroll_view 结构：视口(kind=ScrollView) 首子件是自然高内容容器
  let t1 = mount_all(
    [
      @widget.node_of_new(fn(v : @widget.Widget) -> @widget.Widget {
        v.kind = "ui-scroll-view"
        v.node.set_flex_direction(@yoga.Column)
        v.node.set_min_height(@yoga.fixed(0.0))
        v.node.set_min_width(@yoga.fixed(0.0))
        v.node.set_width(@yoga.fixed(120.0))
        let content = @widget.Widget::new()
        content.node.set_flex_direction(@yoga.Column)
        content.node.set_flex_shrink(0.0)
        content.node.set_height(@yoga.fixed(400.0))
        content.node.set_width(@yoga.percent(100.0))
        v.append_child(content)
        v
      }),
    ],
    120.0,
    80.0,
  )
  t1.frame()
  // 整页图高 = 内容高 400（视口只有 80），证明画的是视口外内容
  match @widget.paint_full_page(t1.root) {
    (Some(bm), clipped) => {
      assert_eq(bm.height, 400)
      assert_eq(bm.width, 120)
      assert_true(!clipped)
    }
    (None, _) => fail("整页重画应出图")
  }
  assert_true(t1.shot_full(uitest_tmp_path("mng-uitest-full-tall.png")))
}
