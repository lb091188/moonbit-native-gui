// 检查器附窗（应用内）：F12 开/关。数据直调本包服务核（同进程零 socket）：
// 树与样式每秒一拍直读，点行 `select`（样式读数 + 高亮一次完成），样式五字段
// 表单直改选中件（style set/reset）。独立进程版走 mngui --inspect（socket，
// 连别人的进程用）。布局与交互口径与 mngui 检查器窗一致。

///|
/// 轮询节拍（毫秒）：直调无网络等待，拍只做节流。
const DEVTLS_TICK_MS : Int = 50

///|
/// 树刷新周期（拍数）：50ms × 20 ≈ 1s。
const DEVTLS_TREE_TICKS : Int = 20

///|
/// 选中样式重读周期（拍数）：≈1s。
const DEVTLS_STYLE_TICKS : Int = 20

///|
let g_devtls_host : Ref[@widget.WindowHost?] = Ref(None)

///|
/// 编辑器五字段名（样式响应前五行；style set 的同名字段）。
let devtls_form_fields : Array[String] = [
  "background", "color", "border_color", "border_width", "border_radius",
]

///|
priv struct DevPage {
  rows : @base.Store[Array[@ui.TableRow]]
  sel : @base.Store[Array[Int32]]
  detail : @base.Store[Array[(String, String)]]
  styles : @base.Store[String]
  status : @base.Store[String]
  full : @base.Store[Bool]
  f_bg : @base.Store[String]
  f_color : @base.Store[String]
  f_bc : @base.Store[String]
  f_bw : @base.Store[String]
  f_br : @base.Store[String]
  mut last_nodes : Array[@widget.A11yNode]
  /// 上一份树的指纹（id:parent 串）：没变不重建表
  mut last_sig : String
  mut cur_id : Int32
  mut want_select : Int32
  mut tree_full_sent : Bool
  mut tick_tree : Int
  mut tick_style : Int
  mut want_write : String
  mut prefill : Array[String]
  mut expect_prefill : Bool
}

///|
fn devtls_new_page() -> DevPage {
  {
    rows: @base.Store::new([]),
    sel: @base.Store::new([]),
    detail: @base.Store::new([]),
    styles: @base.Store::new("点左侧一行看样式"),
    status: @base.Store::new("检查器就绪"),
    full: @base.Store::new(false),
    f_bg: @base.Store::new(""),
    f_color: @base.Store::new(""),
    f_bc: @base.Store::new(""),
    f_bw: @base.Store::new(""),
    f_br: @base.Store::new(""),
    last_nodes: [],
    last_sig: "",
    cur_id: 0,
    want_select: 0,
    tree_full_sent: false,
    tick_tree: DEVTLS_TREE_TICKS,
    tick_style: 0,
    want_write: "",
    prefill: [],
    expect_prefill: false,
  }
}

///|
/// 按 id 找节点下标（树增删后选中按 id 保位）。
fn devtls_find(
  nodes : Array[@widget.A11yNode],
  id : Int32,
) -> Int32? {
  let mut i = 0
  while i < nodes.length() {
    if nodes[i].id == id {
      return Some(i)
    }
    i += 1
  }
  None
}

///|
/// 树列行文本：缩进 + 类型名（空省略）+ 角色 + 「名」+ #id。
/// kind 与 role 双空显示 `(无)`（裸容器占行时不至于只剩 #id）。
fn devtls_row_label(n : @widget.A11yNode, depth : Int32) -> String {
  let b = StringBuilder()
  let mut i = 0
  while i < depth {
    b.write_string("  ")
    i += 1
  }
  if n.kind.length() > 0 {
    b.write_string(n.kind)
    b.write_string("·")
  }
  if n.role.length() > 0 || n.kind.length() > 0 {
    b.write_string(n.role)
  } else {
    b.write_string("(无)")
  }
  if n.name.length() > 0 {
    b.write_string("「")
    b.write_string(n.name)
    b.write_string("」")
  }
  b.write_string(" #")
  b.write_string(n.id.to_string())
  b.to_string()
}

///|
/// 树表行（列：控件，行文本自带 #id）。
fn devtls_table_rows(
  nodes : Array[@widget.A11yNode],
) -> Array[@ui.TableRow] {
  let depths = insp_depths(nodes)
  let out : Array[@ui.TableRow] = []
  let mut i = 0
  while i < nodes.length() {
    out.push(
      @ui.TableRow::make([devtls_row_label(nodes[i], depths[i])]),
    )
    i += 1
  }
  out
}

///|
/// 选中节点详情读数（desc 列表项）。
fn devtls_detail_items(n : @widget.A11yNode) -> Array[(String, String)] {
  [
    ("id", n.id.to_string()),
    ("parent", n.parent.to_string()),
    ("kind", if n.kind.length() > 0 { n.kind } else { "(无)" }),
    ("role", n.role),
    ("name", if n.name.length() > 0 { n.name } else { "(空)" }),
    ("enabled", if n.enabled { "是" } else { "否" }),
    ("state", if n.state.length() > 0 { n.state } else { "(无)" }),
    ("value", if n.value.length() > 0 { n.value } else { "(无)" }),
    ("text", if n.text.length() > 0 { n.text } else { "(无)" }),
    (
      "rect",
      "\{n.x.round().to_int()},\{n.y.round().to_int()} \{n.w.round().to_int()}×\{n.h.round().to_int()}",
    ),
  ]
}

///|
/// 解析样式响应（`field\tvalue` 行；# 列头跳过）。
fn devtls_parse_style(s : String) -> Array[(String, String)] {
  let out : Array[(String, String)] = []
  for line in s.split("\n") {
    let l = line.trim().to_owned()
    if l.length() == 0 || l.has_prefix("#") {
      continue
    }
    let parts : Array[String] = []
    for p in l.split("\t") {
      parts.push(p.to_owned())
    }
    if parts.length() >= 2 {
      out.push((parts[0], parts[1]))
    }
  }
  out
}

///|
/// 编辑器五字段取值（缺项空串）。
fn devtls_form_values(fields : Array[(String, String)]) -> Array[String] {
  let out : Array[String] = []
  for name in devtls_form_fields {
    let mut v = ""
    for kv in fields {
      if kv.0 == name {
        v = kv.1
      }
    }
    out.push(v)
  }
  out
}

///|
/// 应用树响应：指纹没变不重建表；变了按 id 保住选中。
fn devtls_apply_tree(p : DevPage, nodes : Array[@widget.A11yNode]) -> Unit {
  p.last_nodes = nodes
  p.rows.set(devtls_table_rows(nodes))
  p.status.set("节点 \{nodes.length()}")
  if p.cur_id != 0 {
    match devtls_find(nodes, p.cur_id) {
      Some(i) => {
        p.sel.set([i])
        p.detail.set(devtls_detail_items(nodes[i]))
      }
      None => {
        p.cur_id = 0
        p.sel.set([])
        p.detail.set([])
        p.styles.set("")
      }
    }
  }
}

///|
/// 应用样式响应（select 与 style 同一格式）；expect_prefill 时回填表单。
fn devtls_apply_style_text(p : DevPage, resp : String) -> Unit {
  if resp.has_prefix("error:") {
    p.styles.set(resp.trim().to_owned())
    return
  }
  let fields = devtls_parse_style(resp)
  if p.expect_prefill {
    p.expect_prefill = false
    let values = devtls_form_values(fields)
    p.prefill = values
    p.f_bg.set(values[0])
    p.f_color.set(values[1])
    p.f_bc.set(values[2])
    p.f_bw.set(values[3])
    p.f_br.set(values[4])
  }
  // 只读读数：去掉五字段行（表单里已经有了），其余按响应原样列
  let b = StringBuilder()
  b.write_string("全部已设字段\n")
  for line in resp.split("\n") {
    let l = line.trim().to_owned()
    if l.length() == 0 || l.has_prefix("#") {
      continue
    }
    let parts : Array[String] = []
    for t in l.split("\t") {
      parts.push(t.to_owned())
    }
    if parts.length() < 2 {
      continue
    }
    let mut is_form = false
    for name in devtls_form_fields {
      if parts[0] == name {
        is_form = true
      }
    }
    if !is_form {
      b.write_string("  \{parts[0]} = \{parts[1]}\n")
    }
  }
  p.styles.set(b.to_string())
}

///|
/// 点一行：详情本地即时出，`select <id>` 一拍内完成样式读数 + 高亮。
fn devtls_select(p : DevPage, i : Int32) -> Unit {
  if i < 0 || i >= p.last_nodes.length() {
    return
  }
  let n = p.last_nodes[i]
  p.sel.set([i])
  p.cur_id = n.id
  p.detail.set(devtls_detail_items(n))
  p.styles.set("样式读取中…")
  p.want_select = n.id
  p.expect_prefill = true
  p.tick_style = 0
}

///|
/// 状态机一拍：直调服务核（同步瞬时），只做节流与选样时机。
fn devtls_tick(p : DevPage, host : @widget.WindowHost) -> Unit {
  if !host.is_running() {
    return
  }
  if p.full.get() != p.tree_full_sent {
    p.tree_full_sent = p.full.get()
    p.last_sig = ""
  }
  p.tick_tree += 1
  if p.cur_id != 0 {
    p.tick_style += 1
  }
  if p.want_select != 0 {
    let id = p.want_select
    p.want_select = 0
    p.cur_id = id
    devtls_apply_style_text(p, inspect_handle("select \{id}"))
  }
  if p.want_write.length() > 0 {
    let req = p.want_write
    p.want_write = ""
    let resp = inspect_handle(req)
    if resp.has_prefix("ok") {
      p.status.set(resp.trim().to_owned())
      p.expect_prefill = true
      p.tick_style = DEVTLS_STYLE_TICKS
      devtls_apply_style_text(p, inspect_handle("style \{p.cur_id}"))
    } else {
      p.styles.set(resp.trim().to_owned())
    }
  }
  if p.tick_tree >= DEVTLS_TREE_TICKS {
    p.tick_tree = 0
    let nodes = insp_tree_snapshot(full=p.full.get())
    let b = StringBuilder()
    for n in nodes {
      b.write_string("\{n.id}:\{n.parent} ")
    }
    let sig = b.to_string()
    if sig != p.last_sig {
      p.last_sig = sig
      devtls_apply_tree(p, nodes)
    } else {
      p.status.set("节点 \{nodes.length()}")
    }
  }
  if p.cur_id != 0 && p.tick_style >= DEVTLS_STYLE_TICKS {
    p.tick_style = 0
    devtls_apply_style_text(p, inspect_handle("style \{p.cur_id}"))
  }
}

///|
/// 附窗整页：头部（内部实现开关 + 状态）+ 左树右详情分栏 + 样式表单。
fn devtls_root(p : DevPage) -> @widget.Node {
  let cols : Array[@ui.TableColumn] = [
    @ui.TableColumn::make("控件", 0.0, sortable=false),
  ]
  let tree_section = @ui.table_v(
    cols,
    p.rows,
    width=0.0,
    height=620.0,
    selection=p.sel,
    on_row_click=fn(i : Int32, _r : @ui.TableRow) -> Unit {
      devtls_select(p, i)
    },
  )
  let detail_section = @ui.view(
    [
      @ui.text("详情", class=[@style.text_heading]),
      @widget.bind_node(p.detail.signal(), fn(items : Array[(String, String)]) -> @widget.Node {
        if items.length() == 0 {
          return @ui.text("点左侧一行看读数", font_size=12.0, class=[
            @style.text_secondary,
          ])
        }
        @ui.descriptions(items, label_width=64.0)
      }),
    ],
    row_gap=6.0,
  )
  // 样式表单（编辑器五字段直改选中件）+ 全部已设字段只读读数
  let stores : Array[@base.Store[String]] = [
    p.f_bg, p.f_color, p.f_bc, p.f_bw, p.f_br,
  ]
  let labels = ["背景", "文字", "边框色", "边框宽", "圆角"]
  let form_rows : Array[@widget.Node] = []
  for k = 0; k < 5; k = k + 1 {
    form_rows.push(
      @ui.row(
        [
          @ui.text(labels[k], font_size=12.0, class=[@style.text_secondary],
            handle=fn(w : @widget.Widget) -> Unit {
              // label 列最小宽与详情描述一致，输入框起点对齐
              w.node.set_min_width(@yoga.fixed(64.0))
            }),
          @ui.input(stores[k], width=170.0),
        ],
        column_gap=8.0,
      ),
    )
  }
  form_rows.push(
    @ui.row(
      [
        @ui.button(
          "应用",
          variant=@ui.Solid,
          on_click=fn() -> Unit {
            if p.cur_id == 0 {
              p.status.set("先在左侧选中一个控件")
              return
            }
            if p.prefill.length() != 5 {
              p.status.set("还没读到该控件的样式")
              return
            }
            let pairs : Array[String] = []
            for k = 0; k < 5; k = k + 1 {
              let v = stores[k].get()
              if v != p.prefill[k] {
                pairs.push(devtls_form_fields[k] + "=" + v)
              }
            }
            if pairs.length() == 0 {
              p.status.set("样式没有改动")
              return
            }
            let b = StringBuilder()
            b.write_string("style set \{p.cur_id}")
            for pr in pairs {
              b.write_string(" \{pr}")
            }
            p.want_write = b.to_string()
          },
        ),
        @ui.button(
          "还原",
          variant=@ui.Soft,
          on_click=fn() -> Unit {
            if p.cur_id == 0 {
              p.status.set("先在左侧选中一个控件")
              return
            }
            p.want_write = "style reset \{p.cur_id}"
          },
        ),
      ],
      column_gap=8.0,
    ),
  )
  let readout = @widget.bind_node(p.styles.signal(), fn(s : String) -> @widget.Node {
    let lines : Array[@widget.Node] = []
    for t in s.split("\n") {
      let l = t.trim().to_owned()
      if l.length() > 0 {
        lines.push(@ui.text(l, font_size=12.0, class=[@style.text_secondary]))
      }
    }
    @ui.view(lines, row_gap=2.0)
  })
  let styles_section = @ui.scroll_view(
    [
      @ui.col(
        [@ui.col(form_rows, row_gap=6.0), @ui.divider(), readout],
        row_gap=8.0,
      ),
    ],
    @ui.ScrollState::new(),
    handle=fn(v : @widget.Widget) -> Unit {
      v.node.set_flex_grow(1.0)
      v.node.set_min_height(@yoga.fixed(0.0))
    },
  )
  let right_section = @ui.col(
    [
      detail_section,
      @ui.divider(),
      @ui.text("样式", class=[@style.text_heading]),
      styles_section,
    ],
    row_gap=8.0,
    grow=1.0,
  )
  let toolbar = @ui.row(
    [
      @ui.switch(
        p.full,
        on_text="内部实现",
        off_text="内部实现",
      ),
      @ui.bind_label(p.status, fn(s) { s }),
    ],
    column_gap=12.0,
  )
  @ui.col(
    [
      @ui.split(
        tree_section,
        right_section,
        ratio=2.0 / 3.0,
        min_first=320.0,
        min_second=320.0,
      ),
      @ui.divider(),
      // 状态栏在底部：开关与状态一行贴底，留白收紧
      toolbar,
    ],
    padding=10.0,
    row_gap=8.0,
    grow=1.0,
  )
}

///|
/// 附窗挂哪扇：触发窗优先——活动窗（刚收输入的那扇）为主，没有再退进程里
/// 第一扇还在的窗（单窗应用两者是同一扇）。
fn devtls_pick_owner() -> @widget.WindowHost? {
  match @widget.host_active() {
    Some(h) => Some(h)
    None => @widget.primary_host()
  }
}

///|
/// F12 开/关检查器附窗：没开就起一扇（挂在触发窗下），开着就关（关时顺手
/// 取消目标高亮、清取数指定）。
pub fn devtools_toggle() -> Unit {
  match g_devtls_host.val {
    Some(h) => {
      g_devtls_host.val = None
      h.close_window()
    }
    None =>
      match devtls_pick_owner() {
        Some(h) => {
          let title = match @env.get_env_var("MNG_INSPECT_APP") {
            Some(a) => "检查器 — " + a
            None => "检查器"
          }
          match h.open_window(1080, 720, title) {
            Some(child) => {
              g_devtls_host.val = Some(child)
              // 附窗自己是取数工具不是被查对象：不进最近帧登记，取数锁在
              // 触发窗上——否则附窗一上屏就把检查目标顶成它自己
              child.frame_untracked = true
              @widget.inspect_target_set(Some(h))
              let p = devtls_new_page()
              child.on_close(fn() -> Unit {
                g_devtls_host.val = None
                @widget.inspect_target_set(None)
                let _ = insp_highlight(0)
              })
              // 触发窗关了附窗跟着关（close_window 幂等，回调里清登记）
              h.on_close(fn() -> Unit {
                match g_devtls_host.val {
                  Some(c) => {
                    g_devtls_host.val = None
                    c.close_window()
                  }
                  None => ()
                }
              })
              child.mount([devtls_root(p)])
              let tick : Ref[() -> Unit] = Ref(fn() { () })
              tick.val = fn() -> Unit {
                devtls_tick(p, child)
                let _ = child.timer(DEVTLS_TICK_MS, tick.val)
              }
              devtls_tick(p, child)
              let _ = child.timer(DEVTLS_TICK_MS, tick.val)
            }
            None => ()
          }
        }
        None => ()
      }
  }
}

///|
/// 进程里有没有开着检查器附窗（测试与将来「关闭时收尾」用）。
pub fn devtools_open() -> Bool {
  g_devtls_host.val is Some(_)
}
