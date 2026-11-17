// inspector 服务核纯函数用例：socket 路径、命令分发、TSV 组装、截断。
// 不起真监听（那要进程间连，归真机 mng inspect 验）。

///|
test "inspect_socket_path：目录链、文件名与 slug 净化" {
  let p = inspect_socket_path("libyue.hello")
  // 目录：测试机有 XDG_RUNTIME_DIR 或 TMPDIR，都是绝对路径
  assert_true(p.contains("/moonbit-inspect-"))
  assert_true(p.contains(".sock"))
  assert_true(!p.contains("libyue.hello")) // 点号已净化
  // 净化：非 [A-Za-z0-9_-] 全部换下划线
  let q = inspect_socket_path("a b/c.d")
  assert_true(q.contains("moonbit-inspect-a_b_c_d."))
  // 超长截断 + 哈希尾
  let long = inspect_socket_path("x-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
  assert_true(long.length() < 140)
}

///|
test "inspect_handle：tree 列头与数据行、未知命令" {
  let t = inspect_handle("tree")
  assert_true(t.has_prefix("#kind\trole\tname\tid\tparent\tx\ty\tw\th\tstate\tvalue\ttext\tenabled\n"))
  assert_true(inspect_handle("nope").has_prefix("error: 未知命令"))
  assert_true(inspect_handle("").has_prefix("error: 空请求"))
  assert_true(inspect_handle("style").has_prefix("error: style 需要 <id>"))
  assert_true(inspect_handle("style abc").has_prefix("error: style 需要 <id>"))
}

///|
test "insp_truncate：上限内原样、超限切完整行加 truncated" {
  let short = "a\nb\n"
  assert_eq(insp_truncate(short, 100), short)
  let big = "行一\n行二\n行三\n"
  // 上限恰好卡在行中间：截到最近完整行并尾标 truncated
  let t = insp_truncate(big, 10)
  assert_true(t.has_suffix("truncated\n"))
  assert_true(@utf8.encode(t).length() <= 10 + "truncated\n".length())
}

///|
test "parse_insp_int：正负与拒非数字" {
  assert_eq(parse_insp_int("42"), Some(42))
  assert_eq(parse_insp_int("  7 "), Some(7))
  assert_eq(parse_insp_int("-3"), Some(-3))
  assert_true(parse_insp_int("") is None)
  assert_true(parse_insp_int("12x") is None)
  assert_true(parse_insp_int("+") is None)
}

///|
test "inspect_handle：style <id> 不在快照给 error；空树 tree 只有列头" {
  // 测试进程没跑过帧同步，快照为空：tree 只剩列头、style 给 not found
  assert_eq(inspect_handle("tree"), "#kind\trole\tname\tid\tparent\tx\ty\tw\th\tstate\tvalue\ttext\tenabled\n")
  assert_true(inspect_handle("style 5").has_prefix("error: id 5 不在当前树快照"))
}

///|
test "insp_strip_trailing_slash：mac TMPDIR 尾斜杠归一，根目录保留" {
  assert_eq(insp_strip_trailing_slash("/var/folders/x/T/"), "/var/folders/x/T")
  assert_eq(insp_strip_trailing_slash("/var/folders/x/T"), "/var/folders/x/T")
  assert_eq(insp_strip_trailing_slash("/"), "/")
  assert_eq(insp_strip_trailing_slash("/tmp"), "/tmp")
}

///|
test "inspect_handle：shot 解析 --full 与路径两档（无帧都给 error）" {
  // 测试进程没跑过帧同步：视口档与整页档都落 error（解析本身不炸）
  assert_true(inspect_handle("shot").has_prefix("error:"))
  assert_true(inspect_handle("shot --full").has_prefix("error:"))
  assert_true(inspect_handle("shot /tmp/x.png").has_prefix("error:"))
  assert_true(inspect_handle("shot --full /tmp/x.png").has_prefix("error:"))
}

///|
test "insp_file_slug：文件名净化与空回退" {
  assert_eq(insp_file_slug("你好 MoonBit"), "___MoonBit")
  assert_eq(insp_file_slug(""), "app")
}

///|
test "insp_style_all：只列已设字段，分组前缀看名知组" {
  let st : @style.Style = {
    ..@style.empty_style(),
    font_size: Some(14.0),
    border_radius: Some(6.0),
    flex_direction: Some(@yoga.Column),
    opacity: Some(0.5),
  }
  let fields = insp_style_all(st)
  let names = fields.map(fn(kv) { kv.0 })
  assert_true(names.contains("text.font_size"))
  assert_true(names.contains("border.radius"))
  assert_true(names.contains("flex.flex_direction"))
  assert_true(names.contains("pos.opacity"))
  // 未设字段省略
  assert_true(!names.contains("text.color"))
  assert_true(!names.contains("edge.padding_top"))
  // 值形态：数值直出
  let mut font = ""
  for kv in fields {
    if kv.0 == "text.font_size" {
      font = kv.1
    }
  }
  assert_eq(font, "14")
}

///|
test "inspect_handle：highlight 参数校验与无帧档" {
  assert_true(
    inspect_handle("highlight").has_prefix("error: highlight 需要 <id>"),
  )
  assert_true(
    inspect_handle("highlight abc").has_prefix("error: highlight 需要 <id>"),
  )
  // 空快照：目标 id 不在树里
  assert_true(inspect_handle("highlight 5").has_prefix("error: id 5 不在当前树快照"))
  // 0 = 取消，不需要帧
  assert_true(inspect_handle("highlight 0").has_prefix("ok highlight off"))
}

///|
test "insp_tree_walk：组件视图收模板件藏内部件，子件挂回最近已收祖先" {
  // 根（无标记，组件子树之外 → 收）
  let root = @widget.Widget::new()
  // 模板组件：comp 非空 → 收；其内部件（无标记）藏；内部件下的模板文本收且挂回组件
  let stepper = @widget.Widget::new()
  stepper.comp = "ui-stepper"
  stepper.kind = "ui-stepper"
  let inner_row = @widget.Widget::new()
  let minus_w = @widget.Widget::new()
  @widget.mount_children(inner_row, [@widget.node_of(minus_w)])
  let label = @widget.Widget::new()
  label.comp = "ui-text"
  label.kind = "ui-text"
  @widget.mount_children(
    stepper,
    [@widget.node_of(inner_row), @widget.node_of(label)],
  )
  @widget.mount_children(root, [@widget.node_of(stepper)])
  let out : Array[@widget.A11yNode] = []
  insp_tree_walk(root, 0, false, false, out)
  // 组件视图：root、stepper、label 三行；inner_row/minus 藏
  assert_eq(out.length(), 3)
  assert_eq(out[0].id, root.id)
  assert_eq(out[0].parent, 0)
  assert_eq(out[1].id, stepper.id)
  assert_eq(out[1].parent, root.id)
  // label 的父挂回 stepper（inner_row 被藏，不占 parent 链）
  assert_eq(out[2].id, label.id)
  assert_eq(out[2].parent, stepper.id)
  // 全量档：五件全在，父子链保持真实
  let all : Array[@widget.A11yNode] = []
  insp_tree_walk(root, 0, false, true, all)
  assert_eq(all.length(), 5)
  let mut minus_parent = 0
  for n in all {
    if n.id == minus_w.id {
      minus_parent = n.parent
    }
  }
  assert_eq(minus_parent, inner_row.id)
}
