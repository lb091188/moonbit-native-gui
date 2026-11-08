// inspector 纯函数用例:父链深度、行文本、矩形读数、表格行折叠。

///|
/// 造快照节点的顺手写法(矩形/语义字段给死值,只测深度与文本折法)。
fn nd(id : Int, parent : Int, role : String, name : String) -> @widget.A11yNode {
  {
    id,
    parent,
    role,
    name,
    state: "",
    value: "",
    text: "",
    enabled: true,
    x: 10.0,
    y: 20.0,
    w: 120.0,
    h: 36.0,
  }
}

test "insp_depths:按父链算深度;父不在表里视作根" {
  // 1 ← 2 ← 3 链 + 孤儿(父=99)
  let nodes = [nd(1, 0, "window", ""), nd(2, 1, "panel", ""), nd(3, 2, "button", ""), nd(4, 99, "button", "孤儿")]
  let ds = insp_depths(nodes)
  assert_eq(ds[0], 0)
  assert_eq(ds[1], 1)
  assert_eq(ds[2], 2)
  // 孤儿的父不在快照里:按 0 算,不猜
  assert_eq(ds[3], 0)
}

test "insp_depths:环引用按表长截断,不死循环" {
  // 2 的父指回 1、1 的父指回 2(理论不可达,防御快照被改)
  let nodes = [nd(1, 2, "a", ""), nd(2, 1, "b", "")]
  let ds = insp_depths(nodes)
  assert_eq(ds.length(), 2)
  assert_true(ds[0] < 2)
}

test "insp_row_label:缩进 + 角色 + 「名」 + #id;名空不摆引号" {
  let n = nd(7, 0, "button", "确定")
  assert_eq(insp_row_label(n, 0), "button「确定」 #7")
  let m = nd(8, 0, "window", "")
  assert_eq(insp_row_label(m, 2), "    window #8")
}

test "insp_rect_text:x,y w×h 取整" {
  let n = nd(1, 0, "a", "")
  assert_eq(insp_rect_text(n), "10,20 120×36")
}

test "insp_table_rows:列序 控件/角色/id/矩形" {
  let nodes = [nd(1, 0, "window", ""), nd(2, 1, "button", "OK")]
  let rows = insp_table_rows(nodes)
  assert_eq(rows.length(), 2)
  let c = rows[1].cells
  assert_eq(c.length(), 4)
  assert_true(match c[0] { @ui.CellText(s) => s == "  button「OK」 #2"; _ => false })
  assert_true(match c[1] { @ui.CellText(s) => s == "button"; _ => false })
  assert_true(match c[2] { @ui.CellText(s) => s == "2"; _ => false })
  assert_true(match c[3] { @ui.CellText(s) => s == "10,20 120×36"; _ => false })
}

test "insp_detail_lines:九项读数,空语义字段标 (无)/(空)" {
  let mut n = nd(5, 1, "slider", "音量")
  n = { ..n, value: "50%", state: "" }
  let lines = insp_detail_lines(n)
  assert_eq(lines.length(), 8)
  assert_eq(lines[0], "id=5  parent=1")
  assert_eq(lines[1], "role=slider")
  assert_eq(lines[2], "name=音量")
  assert_eq(lines[3], "state=(无)")
  assert_eq(lines[4], "value=50%")
  assert_eq(lines[5], "text=(无)")
  assert_eq(lines[6], "enabled=true")
  assert_eq(lines[7], "rect=10,20 120×36")
  // 空名的 name 档
  let m = nd(6, 0, "window", "")
  assert_eq(insp_detail_lines(m)[2], "name=(空)")
}

test "insp_parse_double:整数/小数/负号;空与非数字给 None" {
  assert_true(match insp_parse_double("12") { Some(d) => d == 12.0; None => false })
  assert_true(match insp_parse_double("1.5") { Some(d) => d == 1.5; None => false })
  assert_true(match insp_parse_double("-0.75") { Some(d) => d == -0.75; None => false })
  assert_true(match insp_parse_double(".5") { Some(d) => d == 0.5; None => false })
  match insp_parse_double("") {
    Some(_) => abort("empty accepted")
    None => ()
  }
  match insp_parse_double("12px") {
    Some(_) => abort("unit accepted")
    None => ()
  }
  match insp_parse_double("-") {
    Some(_) => abort("bare minus accepted")
    None => ()
  }
}

test "insp_color_input:# → Hex、token → Named、空给 None" {
  assert_true(match insp_color_input("#ff8800") { Some(@style.Hex(s)) => s == "#ff8800"; _ => false })
  assert_true(match insp_color_input("primary") { Some(@style.Named(s)) => s == "primary"; _ => false })
  match insp_color_input("") {
    Some(_) => abort("empty accepted")
    None => ()
  }
}

test "insp_field_get/set:五字段读改 roundtrip;空输入保持原样" {
  let st = @style.style(background_color="primary", color="#ffffff", border_width=1.0, border_radius=6.0)
  // get:token 色按 resolve 出 hex(编辑器预填实际色值,便于照抄微调)、
  // Hex 直出、数值直出
  assert_true(insp_field_get(st, 0).has_prefix("#"))
  assert_eq(insp_field_get(st, 1), "#ffffff")
  assert_eq(insp_field_get(st, 3), "1")
  assert_eq(insp_field_get(st, 4), "6")
  // 未设的字段给空串
  assert_eq(insp_field_get(st, 2), "")
  // set:空输入原样返回(同一份样式值)
  let kept = insp_field_set(st, 0, "")
  assert_true(insp_field_get(kept, 0).has_prefix("#"))
  // set:颜色换 token、数值换小数
  let st2 = insp_field_set(st, 0, "danger")
  assert_true(match st2.background_color { Some(@style.Named(s)) => s == "danger"; _ => false })
  let st3 = insp_field_set(st, 4, "12.5")
  assert_true(match st3.border_radius { Some(d) => d == 12.5; _ => false })
  // set:解析失败保持原值(颜色字段喂非色、数值字段喂 12px)
  let st4 = insp_field_set(st, 3, "abc")
  assert_true(match st4.border_width { Some(d) => d == 1.0; _ => false })
}

test "insp_field_set + define_class:回灌注册表并查回(与 mngdev 同口)" {
  @style.reset_class_registry()
  @style.define_class("insp-demo", @style.style(background_color="primary"))
  let c0 = match @style.lookup_class("insp-demo") { Some(c) => c; None => abort("missing") }
  let nb = insp_field_set(c0.style, 0, "#336699")
  @style.define_class("insp-demo", nb)
  let c1 = match @style.lookup_class("insp-demo") { Some(c) => c; None => abort("missing after") }
  assert_true(match c1.style.background_color { Some(@style.Hex(s)) => s == "#336699"; _ => false })
  @style.reset_class_registry()
}
