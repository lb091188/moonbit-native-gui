// 检查器模式（--inspect）：仿 Chrome DevTools 的独立检查器窗。
// 数据全走 @insp.call 连应用内检查服务：tree 轮询（300ms）、选中取 style
// 全量字段、选中即发 highlight 在目标应用上画高亮框。mng 侧的
// `mng inspect --gui` 经 hop 进本模式，本进程链 GUI 库、mng 本体不链。

///|
/// 一行树数据（与服务端 tree 命令的 13 列一一对应）。
struct InspRow {
  kind : String
  role : String
  name : String
  id : Int32
  parent : Int32
  x : Double
  y : Double
  w : Double
  h : Double
  state : String
  value : String
  text : String
  enabled : Bool
}

///|
/// 检查器页状态（静态树 + Store 驱动刷新）。
struct InspPage {
  app_id : String
  rows : @base.Store[Array[@ui.TableRow]]
  sel : @base.Store[Array[Int32]]
  detail : @base.Store[String]
  styles : @base.Store[String]
  status : @base.Store[String]
  auto : @base.Store[Bool]
  mut last_rows : Array[InspRow]
}

///|
/// 整数解析（id 列；失败给 0）。
fn insp_p_int(s : String) -> Int32 {
  let mut v = 0
  let mut neg = false
  let mut i = 0
  for c in s.to_array() {
    if i == 0 && c == '-' {
      neg = true
    } else if c >= '0' && c <= '9' {
      v = v * 10 + (c.to_int() - '0'.to_int())
    }
    i += 1
  }
  if neg {
    -v
  } else {
    v
  }
}

///|
/// 浮点解析（矩形列；负号/整数/小数三档，其余字符忽略）。
fn insp_p_double(s : String) -> Double {
  let t = s.trim().to_owned()
  let mut i = 0
  let mut neg = false
  let mut whole = 0.0
  let mut frac = 0.0
  let mut scale = 1.0
  let mut in_frac = false
  for c in t.to_array() {
    if i == 0 && c == '-' {
      neg = true
    } else if c == '.' {
      in_frac = true
    } else if c >= '0' && c <= '9' {
      let d = (c.to_int() - '0'.to_int()).to_double()
      if in_frac {
        scale = scale * 10.0
        frac = frac + d / scale
      } else {
        whole = whole * 10.0 + d
      }
    }
    i += 1
  }
  let r = whole + frac
  if neg {
    -r
  } else {
    r
  }
}

///|
/// 按 `\n` 切行（跳过空行）。
fn insp_lines(s : String) -> Array[String] {
  let out : Array[String] = []
  for line in s.split("\n") {
    let l = line.trim().to_owned()
    if l.length() > 0 {
      out.push(l)
    }
  }
  out
}

///|
/// 按 `\t` 切字段。
fn insp_tabs(s : String) -> Array[String] {
  let out : Array[String] = []
  for p in s.split("\t") {
    out.push(p.to_owned())
  }
  out
}

///|
/// 解析 tree 响应（首行 # 列头跳过；列序
/// kind/role/name/id/parent/x/y/w/h/state/value/text/enabled）。
fn insp_parse_tree(s : String) -> Array[InspRow] {
  let out : Array[InspRow] = []
  for line in insp_lines(s) {
    if line.has_prefix("#") {
      continue
    }
    let f = insp_tabs(line)
    if f.length() < 13 {
      continue
    }
    out.push({
      kind: f[0],
      role: f[1],
      name: f[2],
      id: insp_p_int(f[3]),
      parent: insp_p_int(f[4]),
      x: insp_p_double(f[5]),
      y: insp_p_double(f[6]),
      w: insp_p_double(f[7]),
      h: insp_p_double(f[8]),
      state: f[9],
      value: f[10],
      text: f[11],
      enabled: f[12] == "1",
    })
  }
  out
}

///|
/// 按父链算每行深度（父不在表里视作根；有环防护按表长截断）。
fn insp_depths(rows : Array[InspRow]) -> Array[Int32] {
  let n = rows.length()
  let idx : Map[Int32, Int32] = Map([])
  let mut i = 0
  while i < n {
    idx[rows[i].id] = i
    i += 1
  }
  let out : Array[Int32] = []
  let mut k = 0
  while k < n {
    let mut d = 0
    let mut cur = rows[k].parent
    let mut steps = 0
    while steps < n {
      match idx.get(cur) {
        Some(pi) if pi != k => {
          d += 1
          cur = rows[pi].parent
          steps += 1
        }
        _ => steps = n
      }
    }
    out.push(d)
    k += 1
  }
  out
}

///|
/// 树列行文本：缩进 + 类型名（空省略）+ 角色 + 「名」+ #id。
fn insp_row_label(r : InspRow, depth : Int32) -> String {
  let b = StringBuilder()
  let mut i = 0
  while i < depth {
    b.write_string("  ")
    i += 1
  }
  if r.kind.length() > 0 {
    b.write_string(r.kind)
    b.write_string("·")
  }
  b.write_string(r.role)
  if r.name.length() > 0 {
    b.write_string("「")
    b.write_string(r.name)
    b.write_string("」")
  }
  b.write_string(" #")
  b.write_string(r.id.to_string())
  b.to_string()
}

///|
/// 树表行（列：控件 / id）。
fn insp_table_rows(rows : Array[InspRow]) -> Array[@ui.TableRow] {
  let depths = insp_depths(rows)
  let out : Array[@ui.TableRow] = []
  let mut i = 0
  while i < rows.length() {
    out.push(
      @ui.TableRow::make([
        insp_row_label(rows[i], depths[i]),
        rows[i].id.to_string(),
      ]),
    )
    i += 1
  }
  out
}

///|
/// 选中行详情读数（多行文本）。
fn insp_detail_text(r : InspRow) -> String {
  let b = StringBuilder()
  b.write_string("id=\{r.id}  parent=\{r.parent}  enabled=\{r.enabled}\n")
  b.write_string(
    "kind=\{if r.kind.length() > 0 { r.kind } else { "(无)" }}\n",
  )
  b.write_string("role=\{r.role}\n")
  b.write_string(
    "name=\{if r.name.length() > 0 { r.name } else { "(空)" }}\n",
  )
  b.write_string(
    "state=\{if r.state.length() > 0 { r.state } else { "(无)" }}\n",
  )
  b.write_string(
    "value=\{if r.value.length() > 0 { r.value } else { "(无)" }}\n",
  )
  b.write_string(
    "text=\{if r.text.length() > 0 { r.text } else { "(无)" }}\n",
  )
  b.write_string(
    "rect=\{r.x.round().to_int()},\{r.y.round().to_int()} \{r.w.round().to_int()}×\{r.h.round().to_int()}",
  )
  b.to_string()
}

///|
/// 样式字段分组名（字段名点分前缀 → 组标题）。
fn insp_group_of(field : String) -> String {
  let mut pre = ""
  for part in field.split(".") {
    pre = part.to_owned()
    break
  }
  match pre {
    "text" => "文字"
    "box" => "尺寸"
    "edge" => "内外边距"
    "border" => "边框圆角"
    "flex" => "布局"
    "pos" => "定位层级"
    _ => "其它"
  }
}

///|
/// 解析 style 响应（`field\tvalue` 行；# 列头跳过）。
fn insp_parse_style(s : String) -> Array[(String, String)] {
  let out : Array[(String, String)] = []
  for line in insp_lines(s) {
    if line.has_prefix("#") {
      continue
    }
    let f = insp_tabs(line)
    if f.length() >= 2 {
      out.push((f[0], f[1]))
    }
  }
  out
}

///|
/// 样式全量文本：编辑器五字段在前，其余按组归档（组标题行 + 缩进行）。
fn insp_style_text(s : String) -> String {
  let fields = insp_parse_style(s)
  let b = StringBuilder()
  b.write_string("样式（编辑器五字段）\n")
  let five = [
    "background", "color", "border_color", "border_width", "border_radius",
  ]
  for f in fields {
    if five.contains(f.0) {
      b.write_string("  \{f.0} = \{f.1}\n")
    }
  }
  let groups = ["文字", "尺寸", "内外边距", "边框圆角", "布局", "定位层级", "其它"]
  for g in groups {
    let mut head = false
    for f in fields {
      if five.contains(f.0) {
        continue
      }
      if insp_group_of(f.0) == g {
        if !head {
          b.write_string(g + "\n")
          head = true
        }
        b.write_string("  \{f.0} = \{f.1}\n")
      }
    }
  }
  b.to_string()
}

///|
/// 发命令收响应（短超时：轮询里卡帧上限压低）。
fn insp_call_short(app_id : String, req : String) -> Result[String, String] {
  @insp.call(app_id, req, timeout_ms=1500)
}

///|
/// 选中一行：详情 + 样式 + 目标应用高亮。
fn insp_select(p : InspPage, i : Int32) -> Unit {
  if i < 0 || i >= p.last_rows.length() {
    return
  }
  let row = p.last_rows[i]
  p.sel.set([i])
  p.detail.set(insp_detail_text(row))
  match insp_call_short(p.app_id, "style \{row.id}") {
    Ok(s) => p.styles.set(insp_style_text(s))
    Err(e) => p.styles.set("样式读取失败：" + e)
  }
  let _ = insp_call_short(p.app_id, "highlight \{row.id}")
}

///|
/// 拉一次树：成功刷新表与状态，失败清空并提示；选中行按下标保位。
fn insp_refresh(p : InspPage) -> Unit {
  match insp_call_short(p.app_id, "tree") {
    Ok(resp) => {
      let rows = insp_parse_tree(resp)
      p.last_rows = rows
      p.rows.set(insp_table_rows(rows))
      p.status.set(
        "已连接 \{p.app_id} · 节点 \{rows.length()} · 300ms 轮询",
      )
      let sel = p.sel.get()
      if sel.length() == 1 && sel[0] < rows.length() {
        insp_select(p, sel[0])
      }
    }
    Err(e) => {
      p.last_rows = []
      p.rows.set([])
      p.status.set("未连接：" + e)
    }
  }
}

///|
/// 多行文本 → 一行一个 text 节点（12px 次要色）。
fn insp_text_block(sig : @base.Signal[String]) -> @widget.Node {
  @widget.bind_node(sig, fn(s : String) -> @widget.Node {
    let lines : Array[@widget.Node] = []
    for t in insp_lines(s) {
      lines.push(@ui.text(t, font_size=12.0, class=[@style.text_secondary]))
    }
    @ui.view(lines, row_gap=2.0)
  })
}

///|
/// 检查器窗主入口：起窗、装 300ms 轮询泵、跑事件循环。
/// 无显示服务与向导同口径回 3（mng 侧据此提示）。
pub fn run_inspector(app_id : String) -> Unit {
  let p : InspPage = {
    app_id,
    rows: @base.Store::new([]),
    sel: @base.Store::new([]),
    detail: @base.Store::new("点左侧一行看读数"),
    styles: @base.Store::new("点左侧一行看样式"),
    status: @base.Store::new(
      if app_id.length() > 0 {
        "连接中 \{app_id}…"
      } else {
        "没有应用 id——用 `mng inspect --gui --app <id>` 指定"
      },
    ),
    auto: @base.Store::new(true),
    last_rows: [],
  }
  let cols : Array[@ui.TableColumn] = [
    @ui.TableColumn::make("控件", 0.0, sortable=false),
    @ui.TableColumn::make("id", 56.0, sortable=false),
  ]
  let tree_section = @ui.view(
    [
      @ui.table_v(
        cols,
        p.rows,
        width=460.0,
        height=620.0,
        selection=p.sel,
        on_row_click=fn(i : Int32, _r : @ui.TableRow) -> Unit {
          insp_select(p, i)
        },
      ),
    ],
    grow=1.0,
  )
  let detail_section = @ui.scroll_view(
    [
      @ui.text("详情", class=[@style.text_heading]),
      insp_text_block(p.detail.signal()),
      @ui.divider(),
      insp_text_block(p.styles.signal()),
    ],
    @ui.ScrollState::new(),
    width=560.0,
    height=620.0,
    handle=fn(v) {
      v.node.set_flex_grow(1.0)
    },
  )
  let toolbar = @ui.row(
    [
      @ui.button("刷新", variant=@ui.Soft, on_click=fn() { insp_refresh(p) }),
      @ui.switch(
        p.auto,
        on_text="自动刷新",
        off_text="自动刷新",
      ),
      @ui.bind_label(p.status, fn(s) { s }),
    ],
    column_gap=12.0,
  )
  let root = @ui.col(
    [toolbar, @ui.divider(), @ui.row([tree_section, detail_section], column_gap=12.0)],
    padding=16.0,
    row_gap=10.0,
    grow=1.0,
  )
  let mounted = @ui.mount_window(
    [root],
    title=if app_id.length() > 0 {
      "mng 检查器 — " + app_id
    } else {
      "mng 检查器"
    },
    width=1080,
    height=720,
    handle=fn(h : @widget.WindowHost) {
      let tick : Ref[() -> Unit] = Ref(fn() { () })
      tick.val = fn() -> Unit {
        if p.auto.get() {
          insp_refresh(p)
        }
        let _ = h.timer(300, tick.val)
      }
      // 首拍立即拉一次（不等 300ms）
      insp_refresh(p)
      let _ = h.timer(300, tick.val)
    },
  )
  match mounted {
    None => {
      println("mngui: 本平台无窗口后端或无显示服务")
      @sys.exit(3)
    }
    Some(host) => {
      host.run()
      // 关窗时取消目标应用上的高亮（尽力而为，应用可能已退出）
      let _ = insp_call_short(app_id, "highlight 0")
    }
  }
}
