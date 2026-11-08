// inspector v2 编辑回灌:面板加「样式类」页签,直接改命名类样式值回灌界面。
//
// 通道口径:回灌目标就是 mngdev 样式热更的同一个注册表——`@style.define_class`
// (mngdev 补丁的 classes 数组最终也落到这一口),同名覆盖、样式在绘制期现取,
// define 完 invalidate 一次下一帧就生效。面板是**进程内直灌**,不走 JSON 补丁
// 与单实例通道;要跨进程/走 mng dev 的样式热更,用 `mng dev` 的 reload 通道。
//
// 编辑面 v2 收窄为五样最常用的:背景 / 文字 / 边框色 / 边框宽 / 圆角,
// base 与 :hover 两档各一套;其余字段走模板源码或 mng dev 补丁,不进编辑器。
// 「还原」回本面板首次刷新类列表时抓的快照(会话内积累的回灌可整类撤销)。

///|
/// 编辑字段号:0 背景 / 1 文字 / 2 边框色 / 3 边框宽 / 4 圆角。
let insp_field_count : Int = 5

///|
/// 字段显示名(编辑器行标签)。
fn insp_field_label(i : Int) -> String {
  match i {
    0 => @i18n.t_or("gui.inspector.f_bg", "背景")
    1 => @i18n.t_or("gui.inspector.f_color", "文字")
    2 => @i18n.t_or("gui.inspector.f_border_color", "边框色")
    3 => @i18n.t_or("gui.inspector.f_border_width", "边框宽")
    _ => @i18n.t_or("gui.inspector.f_radius", "圆角")
  }
}

///|
/// 数值解析(整数/小数/负号;空串与非数字给 None)。小数按「整数累积再除
/// 10^k」走,避免逐位乘 0.1 的浮点漂移(-0.75 那类)。纯函数,白盒用例钉住。
pub fn insp_parse_double(s : String) -> Double? {
  let cs = s.to_array()
  let n = cs.length()
  if n == 0 {
    return None
  }
  let mut neg = false
  let mut i = 0
  if cs[0] == '-' {
    neg = true
    i = 1
  }
  let mut v = 0.0
  let mut seen = false
  let mut dot = false
  let mut k = 0
  while i < n {
    let c = cs[i]
    if c >= '0' && c <= '9' {
      v = v * 10.0 + (c.to_int() - '0'.to_int()).to_double()
      if dot {
        k += 1
      }
      seen = true
    } else if c == '.' && !dot {
      dot = true
    } else {
      return None
    }
    i += 1
  }
  if !seen {
    return None
  }
  let mut div = 1.0
  let mut t = 0
  while t < k {
    div = div * 10.0
    t += 1
  }
  let out = v / div
  Some(if neg { -out } else { out })
}

///|
/// 颜色输入折 Color:`#` 前缀按 Hex、其余按 Named(主题 token 或名字);
/// 空串给 None(= 不改该字段)。纯函数,白盒用例钉住。
pub fn insp_color_input(s : String) -> @style.Color? {
  if s.length() == 0 {
    return None
  }
  if s.has_prefix("#") {
    Some(@style.Hex(s))
  } else {
    Some(@style.Named(s))
  }
}

///|
/// 读一个字段的显示值(颜色走 resolve_color,数值直出;未设给空串)。
pub fn insp_field_get(st : @style.Style, i : Int) -> String {
  match i {
    0 =>
      match st.background_color {
        Some(c) => @style.resolve_color(c)
        None => ""
      }
    1 =>
      match st.color {
        Some(c) => @style.resolve_color(c)
        None => ""
      }
    2 =>
      match st.border_color {
        Some(c) => @style.resolve_color(c)
        None => ""
      }
    3 =>
      match st.border_width {
        Some(d) => d.to_string()
        None => ""
      }
    _ =>
      match st.border_radius {
        Some(d) => d.to_string()
        None => ""
      }
  }
}

///|
/// 把一段输入落进字段的样式拷贝:空串 = 不改原样返回;颜色按 insp_color_input、
/// 数值按 insp_parse_double,解析失败也不改(宁可没效果,不写坏样式)。
/// 纯函数,白盒用例钉住。
pub fn insp_field_set(st : @style.Style, i : Int, raw : String) -> @style.Style {
  match i {
    0 =>
      match insp_color_input(raw) {
        Some(c) => { ..st, background_color: Some(c) }
        None => st
      }
    1 =>
      match insp_color_input(raw) {
        Some(c) => { ..st, color: Some(c) }
        None => st
      }
    2 =>
      match insp_color_input(raw) {
        Some(c) => { ..st, border_color: Some(c) }
        None => st
      }
    3 =>
      match insp_parse_double(raw) {
        Some(d) => { ..st, border_width: Some(d) }
        None => st
      }
    _ =>
      match insp_parse_double(raw) {
        Some(d) => { ..st, border_radius: Some(d) }
        None => st
      }
  }
}

///|
/// 一档样式(基档或 hover 档)的五个输入全部落进拷贝。
fn insp_apply_all(st : @style.Style, inputs : Array[@base.Store[String]]) -> @style.Style {
  let mut out = st
  let mut i = 0
  while i < insp_field_count {
    out = insp_field_set(out, i, inputs[i].get())
    i += 1
  }
  out
}

///|
/// 类列表行:类名 + 交互态标签(有 :hover/:active/:focus 档就列出来)。
fn insp_class_row(name : String) -> @ui.TableRow {
  let tags = match @style.lookup_class(name) {
    Some(c) => {
      let t = StringBuilder()
      if c.style.hover is Some(_) {
        t.write_string("hover ")
      }
      if c.style.active is Some(_) {
        t.write_string("active ")
      }
      if c.style.focus is Some(_) {
        t.write_string("focus")
      }
      t.to_string()
    }
    None => ""
  }
  @ui.TableRow::make([name, tags])
}

///|
/// 样式类页签:类列表(点行选中)→ 编辑器(五字段 × base/hover)→ 应用 / 还原。
/// `width` 与 `list_h` 撑表格;快照进 `snap`(首次见到的类抓一份,还原用)。
fn insp_classes_section(
  width : Double,
  list_h : Double,
  snap : Ref[Map[String, @style.Style]],
) -> @widget.Node {
  let names : @base.Store[Array[@ui.TableRow]] = @base.Store::new([])
  let sel_tbl : @base.Store[Array[Int]] = @base.Store::new([])
  let sel_cls : @base.Store[String] = @base.Store::new("")
  let note : @base.Store[String] = @base.Store::new(@i18n.t_or("gui.inspector.cls_hint", "回灌走 @style.define_class(与 mngdev 样式热更同口);空白输入 = 不改该字段"))
  fn list_classes() -> Unit {
    let rows : Array[@ui.TableRow] = []
    for n in @style.registered_classes() {
      match @style.lookup_class(n) {
        Some(c) =>
          if !(snap.val.contains(n)) {
            snap.val[n] = c.style
          }
        None => ()
      }
      rows.push(insp_class_row(n))
    }
    names.set(rows)
    // 选中类还在就保持,不在清掉
    if !(snap.val.contains(sel_cls.get())) {
      sel_cls.set("")
      sel_tbl.set([])
    }
  }
  list_classes()
  let cols : Array[@ui.TableColumn] = [
    @ui.TableColumn::make(@i18n.t_or("gui.inspector.cls_col_name", "类名"), 0.0, sortable=false),
    @ui.TableColumn::make(@i18n.t_or("gui.inspector.cls_col_states", "交互态"), 120.0, sortable=false),
  ]
  // 编辑器的输入行:选中类变化时整块重建(输入 Store 带当前值预填)
  let cls_cols : Array[@ui.TableColumn] = cols
  @ui.view(
    [
      @ui.row(
        [
          @ui.button(@i18n.t_or("gui.inspector.cls_refresh", "刷新类列表"), variant=@ui.Soft, on_click=list_classes),
          @ui.button(@i18n.t_or("gui.inspector.cls_restore", "还原此类"), variant=@ui.Text, on_click=fn() {
            let n = sel_cls.get()
            if n.length() > 0 {
              match snap.val.get(n) {
                Some(s0) => {
                  @style.define_class(n, s0)
                  @widget.invalidate()
                  note.set(@i18n.t_or("gui.inspector.cls_restored", "已还原 \{n}(回会话首见时的样式)"))
                }
                None => note.set(@i18n.t_or("gui.inspector.cls_no_snap", "没有 \{n} 的会话快照——先刷新类列表"))
              }
            }
          }),
          @ui.bind_label(note, fn(s) { s }),
        ],
        column_gap=8.0,
        align_items=@yoga.AlignItems::Center,
      ),
      @ui.table_v(
        cls_cols,
        names,
        width=width,
        height=list_h,
        selection=sel_tbl,
        on_row_click=fn(i : Int, r : @ui.TableRow) -> Unit {
          sel_tbl.set([i])
          match r.cells.get(0) {
            Some(@ui.CellText(n)) => sel_cls.set(n)
            _ => ()
          }
        },
      ),
      @ui.text(@i18n.t_or("gui.inspector.cls_editor_title", "样式类编辑器"), weight=@text.SemiBold),
      @widget.bind_node(sel_cls.signal(), fn(name : String) -> @widget.Node {
        if name.length() == 0 {
          return @ui.text(
            @i18n.t_or("gui.inspector.cls_no_selection", "点上面一行类名开始编辑"),
            font_size=12.0,
            color="text_secondary",
          )
        }
        match @style.lookup_class(name) {
          None =>
            @ui.text(
              @i18n.t_or("gui.inspector.cls_gone", "类 \{name} 已不在注册表里——刷新类列表"),
              font_size=12.0,
              color="text_secondary",
            )
          Some(c) => {
            // 五个输入各带当前值;hover 档存在才摆 hover 行
            fn mk_inputs(st : @style.Style) -> Array[@base.Store[String]] {
              let out : Array[@base.Store[String]] = []
              let mut i = 0
              while i < insp_field_count {
                out.push(@base.Store::new(insp_field_get(st, i)))
                i += 1
              }
              out
            }
            let base_in = mk_inputs(c.style)
            let hover_in : Array[@base.Store[String]] = match c.style.hover {
              Some(h) => mk_inputs(h)
              None => []
            }
            let rows : Array[@widget.Node] = []
            let mut i = 0
            while i < insp_field_count {
              rows.push(
                @ui.row(
                  [
                    @ui.text(insp_field_label(i), font_size=12.0),
                    @ui.input(base_in[i], width=150.0, font_size=12.0),
                  ],
                  column_gap=10.0,
                  align_items=@yoga.AlignItems::Center,
                ),
              )
              i += 1
            }
            if hover_in.length() == insp_field_count {
              rows.push(@ui.text(":", font_size=12.0, color="text_secondary"))
              let mut j = 0
              while j < insp_field_count {
                rows.push(
                  @ui.row(
                    [
                      @ui.text(":hover " + insp_field_label(j), font_size=12.0),
                      @ui.input(hover_in[j], width=150.0, font_size=12.0),
                    ],
                    column_gap=10.0,
                    align_items=@yoga.AlignItems::Center,
                  ),
                )
                j += 1
              }
            }
            rows.push(
              @ui.button(@i18n.t_or("gui.inspector.cls_apply", "应用(下一帧生效)"), variant=@ui.Solid, on_click=fn() {
                let mut nb = insp_apply_all(c.style, base_in)
                if hover_in.length() == insp_field_count {
                  match nb.hover {
                    Some(h) => {
                      let nh = insp_apply_all(h, hover_in)
                      nb = { ..nb, hover: Some(nh) }
                    }
                    None => ()
                  }
                }
                @style.define_class(name, nb)
                @widget.invalidate()
                note.set(@i18n.t_or("gui.inspector.cls_applied", "已回灌 \{name}——用了它的控件下一帧换新样式"))
              }),
            )
            @ui.view(
              rows,
              direction=@yoga.Column,
              row_gap=6.0,
              padding=8.0,
              background_color="bg_panel",
              border_color="border",
              corner_radius=6.0,
            )
          }
        }
      }),
    ],
    direction=@yoga.Column,
    row_gap=10.0,
  )
}
