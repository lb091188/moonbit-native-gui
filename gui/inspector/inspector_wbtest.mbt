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
