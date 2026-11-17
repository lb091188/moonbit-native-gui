// 检查器模式的纯函数用例：tree/style TSV 解析、深度、行标签、样式分组。

///|
test "insp_parse_tree：13 列解析与 # 列头跳过" {
  let tsv = "#kind\trole\tname\tid\tparent\tx\ty\tw\th\tstate\tvalue\ttext\tenabled\n" +
    "Window\t\t\t64\t0\t0\t0\t760\t680\t\t\t\t1\n" +
    "Button\tbutton\t重置\t20\t21\t123.28\t197\t49.79\t32\t\t\t重置\t1\n"
  let rows = insp_parse_tree(tsv)
  assert_eq(rows.length(), 2)
  assert_eq(rows[0].kind, "Window")
  assert_eq(rows[0].id, 64)
  assert_eq(rows[1].role, "button")
  assert_eq(rows[1].name, "重置")
  assert_eq(rows[1].x, 123.28)
  assert_eq(rows[1].w, 49.79)
  assert_eq(rows[1].enabled, true)
}

///|
test "insp_depths：父链深度与孤儿按根" {
  let rows = [
    {
      kind: "Window", role: "", name: "", id: 1, parent: 0, x: 0.0, y: 0.0,
      w: 0.0, h: 0.0, state: "", value: "", text: "", enabled: true,
    },
    {
      kind: "View", role: "", name: "", id: 2, parent: 1, x: 0.0, y: 0.0,
      w: 0.0, h: 0.0, state: "", value: "", text: "", enabled: true,
    },
    {
      kind: "Button", role: "button", name: "", id: 3, parent: 2, x: 0.0,
      y: 0.0, w: 0.0, h: 0.0, state: "", value: "", text: "", enabled: true,
    },
    {
      kind: "Text", role: "text", name: "", id: 4, parent: 99, x: 0.0, y: 0.0,
      w: 0.0, h: 0.0, state: "", value: "", text: "", enabled: true,
    },
  ]
  let ds = insp_depths(rows)
  assert_eq(ds[0], 0)
  assert_eq(ds[1], 1)
  assert_eq(ds[2], 2)
  assert_eq(ds[3], 0)
}

///|
test "insp_row_label：缩进 + 类型名·角色「名」 #id" {
  let r = {
    kind: "Button", role: "button", name: "重置", id: 20, parent: 21, x: 0.0,
    y: 0.0, w: 0.0, h: 0.0, state: "", value: "", text: "", enabled: true,
  }
  assert_eq(insp_row_label(r, 0), "Button·button「重置」 #20")
  assert_eq(insp_row_label(r, 2), "    Button·button「重置」 #20")
}

///|
test "样式分组与全量文本：五字段在前、分组标题各一次" {
  let tsv = "#field\tvalue\n" +
    "background\t#f5f5f5\n" +
    "color\t#333333\n" +
    "border_width\t1\n" +
    "text.font_size\t14\n" +
    "text.font_weight\tSemiBold\n" +
    "flex.flex_direction\tcolumn\n" +
    "pos.opacity\t0.5\n"
  let text = insp_style_text(tsv)
  assert_true(text.contains("背景") || text.contains("background"))
  assert_true(text.contains("background = #f5f5f5"))
  assert_true(text.contains("文字"))
  assert_true(text.contains("text.font_size = 14"))
  assert_true(text.contains("布局"))
  assert_true(text.contains("flex.flex_direction = column"))
  assert_true(text.contains("定位层级"))
  assert_true(text.contains("pos.opacity = 0.5"))
  // 分组标题各出现一次
  assert_eq(text.split("文字").count(), 2)
}

///|
test "insp_group_of：前缀映射" {
  assert_eq(insp_group_of("text.color"), "文字")
  assert_eq(insp_group_of("box.width"), "尺寸")
  assert_eq(insp_group_of("edge.padding_top"), "内外边距")
  assert_eq(insp_group_of("border.radius"), "边框圆角")
  assert_eq(insp_group_of("flex.row_gap"), "布局")
  assert_eq(insp_group_of("pos.z_index"), "定位层级")
  assert_eq(insp_group_of("misc.opacity"), "其它")
}

///|
test "insp_find_row：按 id 找行下标" {
  let rows = [
    {
      kind: "Window", role: "", name: "", id: 1, parent: 0, x: 0.0, y: 0.0,
      w: 0.0, h: 0.0, state: "", value: "", text: "", enabled: true,
    },
    {
      kind: "Button", role: "button", name: "A", id: 7, parent: 1, x: 0.0,
      y: 0.0, w: 10.0, h: 10.0, state: "", value: "", text: "A", enabled: true,
    },
  ]
  assert_eq(insp_find_row(rows, 7), Some(1))
  assert_eq(insp_find_row(rows, 99), None)
}

///|
/// 建一个最小可用的检查器页（取数全由用例直接喂响应）。
fn insp_test_page() -> InspPage {
  {
    app_id: "app",
    rows: @base.Store::new([]),
    sel: @base.Store::new([]),
    detail: @base.Store::new([]),
    styles: @base.Store::new(""),
    status: @base.Store::new(""),
    full: @base.Store::new(false),
    last_rows: [],
    last_tree_text: "",
    cur_id: 0,
    busy: 0,
    want_select: 0,
    tick_tree: 0,
    tick_style: 0,
    tree_full_sent: false,
  }
}

///|
test "insp_apply_tree：选中按 id 保位，控件消失即取消" {
  let p = insp_test_page()
  let head = "#kind\trole\tname\tid\tparent\tx\ty\tw\th\tstate\tvalue\ttext\tenabled\n"
  let tsv1 = head +
    "Window\t\t\t1\t0\t0\t0\t100\t100\t\t\t\t1\n" +
    "Button\tbutton\tA\t2\t1\t0\t0\t10\t10\t\t\tA\t1\n"
  insp_apply_tree(p, tsv1)
  assert_eq(p.last_rows.length(), 2)
  assert_eq(p.status.get(), "已连接 app · 节点 2")
  // 树重排（id=2 从第 1 行挪到第 2 行）：选中仍按 id 落在新下标
  p.cur_id = 2
  let tsv2 = head +
    "Window\t\t\t1\t0\t0\t0\t100\t100\t\t\t\t1\n" +
    "Text\ttext\tB\t3\t1\t0\t0\t10\t10\t\t\tB\t1\n" +
    "Button\tbutton\tAA\t2\t1\t0\t0\t10\t10\t\t\tAA\t1\n"
  insp_apply_tree(p, tsv2)
  assert_eq(p.sel.get().length(), 1)
  assert_eq(p.sel.get()[0], 2)
  assert_true(p.detail.get().contains(("id", "2")))
  // 控件从树里消失：取消选中并清空样式
  p.cur_id = 3
  insp_apply_tree(p, tsv1)
  assert_eq(p.cur_id, 0)
  assert_eq(p.sel.get().length(), 0)
  assert_eq(p.detail.get().length(), 0)
}
