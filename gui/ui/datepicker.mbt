// 日期/时间选择器四只：字段 + 弹层。弹层一律开在浮层图层上（`overlay.mbt` 那套：
// 整窗图层、空则不可见、点外收起），日历面板与网格复用 `datetime.mbt` 的
// `build_calendar`/`month_grid`/`range_state_of`。字段自动进 Tab 链，键盘开合
// 走 `attach_field_toggle_key`（空格/回车/↓ 开层、回车/Esc 收层）。
//
// 两条口径：① 弹层用自绘面板；② 时间是「时/分步进器」——自绘栈没有原生输入框
// 语义，键盘编辑要另配一套焦点与输入法通道，性价比低（要键盘输入的文本用
// `input` / `textarea`）。

///|
/// 把控件配成选择器字段（EP DatePicker 的输入框样式）：面板底 + 描边 + 文本 +
/// 右侧下拉箭头；`clearable` 且悬停且有值时，箭头左侧画 ✕。
/// `on_click` 收到的是**本地 x**：调用方据此区分「点 ✕ 清空」与「点其余处开合」。
fn setup_picker_field(
  w : @widget.Widget,
  width : Double,
  text_of : () -> String,
  filled : () -> Bool,
  clearable : Bool,
  on_click : (Double) -> Unit,
  skin~ : @style.Style = @style.empty_style(),
) -> Unit {
  let font = @text.Font::new("", 13.0)
  watch_theme()
  w.node.set_width(@yoga.fixed(width))
  w.node.set_height(@yoga.fixed(32.0))
  w.cursor = @widget.CURSOR_HAND
  // 字段底色/描边/文字色先折内置再读槽；「有没有填值」是数据态，留在 filled() 分支当回落
  @style.apply(
    w,
    @style.merge_all([
      @style.style(
        background_color="bg_panel",
        border_color="border",
        border_width=1.0,
        color="text_primary",
      ).hover(background_color="fill_hover"),
      skin,
    ]),
  )
  w.on_draw = Some(fn(
    self : @widget.Widget,
    p : @render.Painter,
    r : @base.Rect,
  ) -> Unit {
    let st = @style.style_for(self)
    let rad = @style.number_of(st.border_radius, @theme.radius_ctrl())

    self.clip_rounded = rad > 0.0
    self.style_clip_radius = rad
    p.set_fill_color(@style.color_of(st.background_color, @theme.theme_bg_panel()))
    p.fill_round_rect(0.0, 0.0, r.w, r.h, rad)
    p.set_stroke_color(@style.color_of(st.border_color, @theme.theme_border()))
    p.set_line_width(@style.number_of(st.border_width, 1.0))
    if rad > 0.0 {
      p.round_rect_path(0.5, 0.5, r.w - 1.0, r.h - 1.0, rad)
      p.stroke()
    } else {
      p.stroke_rect(0.0, 0.0, r.w, r.h)
    }
    let txt = text_of()
    let _ = @text.draw_box_at(
      p,
      10.0,
      0.0,
      (r.w - 44.0).max(1.0),
      r.h,
      txt,
      font,
      if filled() {
        @style.color_of(st.color, @theme.theme_text_primary())
      } else {
        @theme.theme_text_secondary()
      },
      align=@text.Start,
      valign=@text.Center,
    )
    // 下拉箭头（矢量自绘）
    p.set_fill_color(@theme.theme_text_secondary())
    p.begin_path()
    p.move_to(r.w - 20.0, r.h / 2.0 - 2.0)
    p.line_to(r.w - 12.0, r.h / 2.0 - 2.0)
    p.line_to(r.w - 16.0, r.h / 2.0 + 3.0)
    p.close_path()
    p.fill()
    if clearable && self.hovered && filled() {
      p.set_stroke_color(@theme.theme_text_secondary())
      p.set_line_width(1.3)
      p.begin_path()
      p.move_to(r.w - 33.0, r.h / 2.0 - 3.5)
      p.line_to(r.w - 26.0, r.h / 2.0 + 3.5)
      p.move_to(r.w - 26.0, r.h / 2.0 - 3.5)
      p.line_to(r.w - 33.0, r.h / 2.0 + 3.5)
      p.stroke()
    }
    // 聚焦指示与输入框同口径：描边转主题色（覆盖在常态描边之上）
    if self.focused {
      p.set_stroke_color(@theme.theme_primary())
      if rad > 0.0 {
        p.round_rect_path(0.5, 0.5, r.w - 1.0, r.h - 1.0, rad)
        p.stroke()
      } else {
        p.stroke_rect(0.0, 0.0, r.w, r.h)
      }
    }
  })
  w.on_pointer = Some(fn(
    _self : @widget.Widget,
    ev : @widget.PointerEvent,
  ) -> Bool {
    match ev.kind {
      @widget.PointerKind::Down => true
      @widget.PointerKind::Up => {
        on_click(ev.x)
        @widget.invalidate()
        false
      }
      _ => false
    }
  })
}

///|
/// ✕ 热区（箭头左侧 20px 带宽）。
fn clear_hit(local_x : Double, width : Double, clearable : Bool, filled : Bool) -> Bool {
  clearable && filled && local_x >= width - 40.0 && local_x <= width - 20.0
}

///|
/// 选择器字段的键盘开合：关着时空格/回车/↓ 开层，开着时回车/空格/Esc 收层
/// （日历内部的方向键导航不在这层做，日历弹层里只保留点选）。
fn attach_field_toggle_key(
  w : @widget.Widget,
  open_id : Ref[Int],
  open_pop : () -> Unit,
  close_pop : () -> Unit,
) -> Unit {
  w.on_key = Some(fn(ev : @widget.KeyEvent) -> Bool {
    if !ev.press {
      return false
    }
    let ks = ev.keysym
    if overlay_alive(open_id.val) {
      if ks == @base.KS_RETURN ||
        ks == @base.KS_SPACE ||
        ks == @base.KS_ESCAPE {
        close_pop()
        true
      } else {
        false
      }
    } else if ks == @base.KS_RETURN ||
      ks == @base.KS_SPACE ||
      ks == @base.KS_DOWN {
      open_pop()
      true
    } else {
      false
    }
  })
}

///|
/// 日历弹层（面板形态与 `calendar` 相同，但开在浮层图层上）。
fn calendar_popup(
  today : DateYMD,
  state_of : (DateYMD) -> CalCell,
  on_cell : (DateYMD) -> Unit,
  skin~ : @style.Style = @style.empty_style(),
) -> @widget.Node {
  @widget.node_of_new(fn(panel : @widget.Widget) -> @widget.Widget {
    let _ = build_calendar(panel, today, state_of, on_cell, skin=skin)
    panel
  })
}

///|
/// 时间弹层：每列自上而下「+ / 数值 / − / 单位」，列间以 `:` 分隔；
/// 时 0-23、分 0-59、秒 0-59，到界回绕（+ 过顶回 0，− 到底回满）。
/// `show_seconds=true` 多一列秒。底部「取消 / 确定」两条文案随语言取译。
fn time_popup(
  initial : TimeHMS,
  on_confirm : (TimeHMS) -> Unit,
  on_cancel : () -> Unit,
  show_seconds? : Bool = false,
  skin~ : @style.Style = @style.empty_style(),
) -> @widget.Node {
  let cur : @base.Store[TimeHMS] = @base.Store::new(initial)
  let with_s = show_seconds
  let col_w = 44.0
  let sep_w = 14.0
  let n_cols = if with_s { 3 } else { 2 }
  let body_w = col_w * n_cols.to_double() + sep_w * (n_cols - 1).to_double()
  let panel_w = body_w.max(160.0) + 20.0
  // 到界回绕：模 24 / 60 取正余
  fn wrap_add(v : Int, d : Int, mod : Int) -> Int {
    let x = (v + d) % mod
    if x < 0 { x + mod } else { x }
  }

  fn bump(which : Int, d : Int) -> Unit {
    let t = cur.get()
    let h = if which == 0 { wrap_add(t.h, d, 24) } else { t.h }
    let m = if which == 1 { wrap_add(t.m, d, 60) } else { t.m }
    let s = if which == 2 { wrap_add(t.s, d, 60) } else { t.s }
    cur.set(time_clamp(h, m, s=s))
    @widget.invalidate()
  }

  // 一格定宽容器：所有行走同一条交叉轴口径，列与列天然对齐
  fn cell(node : @widget.Node, w : Double) -> @widget.Node {
    view(
      [node],
      direction=@yoga.Column,
      width=w,
      align_items=@yoga.AlignItems::Center,
    )
  }

  fn tick(d : Int, which : Int, glyph : String) -> @widget.Node {
    button(
      glyph,
      variant=Text,
      font_size=15.0,
      min_width=col_w,
      on_click=fn() { bump(which, d) },
    )
  }

  fn value_cell(get : (TimeHMS) -> Int) -> @widget.Node {
    cell(
      bind_label(cur, fn(t : TimeHMS) -> String { pad_two(get(t)) }, font_size=16.0),
      col_w,
    )
  }

  fn caption_cell(key : String, zh : String) -> @widget.Node {
    cell(text(@i18n.t_or(key, zh), font_size=11.0, role=Secondary), col_w)
  }

  fn sep(mark : String) -> @widget.Node {
    cell(text(mark, font_size=16.0), sep_w)
  }

  fn row_of(items : Array[@widget.Node]) -> @widget.Node {
    view(items, direction=@yoga.Row, align_items=@yoga.AlignItems::Center)
  }

  let plus_items : Array[@widget.Node] = [
    tick(1, 0, "+"),
    sep(""),
    tick(1, 1, "+"),
  ]
  let value_items : Array[@widget.Node] = [
    value_cell(fn(t : TimeHMS) -> Int { t.h }),
    sep(":"),
    value_cell(fn(t : TimeHMS) -> Int { t.m }),
  ]
  let minus_items : Array[@widget.Node] = [
    tick(-1, 0, "-"),
    sep(""),
    tick(-1, 1, "-"),
  ]
  let caption_items : Array[@widget.Node] = [
    caption_cell("gui.ui.datepicker.unit.h", "时"),
    sep(""),
    caption_cell("gui.ui.datepicker.unit.m", "分"),
  ]
  if with_s {
    plus_items.push(sep(""))
    plus_items.push(tick(1, 2, "+"))
    value_items.push(sep(":"))
    value_items.push(value_cell(fn(t : TimeHMS) -> Int { t.s }))
    minus_items.push(sep(""))
    minus_items.push(tick(-1, 2, "-"))
    caption_items.push(sep(""))
    caption_items.push(caption_cell("gui.ui.datepicker.unit.s", "秒"))
  }
  @widget.node_of_new(fn(panel : @widget.Widget) -> @widget.Widget {
    watch_theme()
    panel.node.set_flex_direction(@yoga.Column)
    panel.node.set_width(@yoga.fixed(panel_w))
    panel.set_padding(top=10.0, left=10.0, right=10.0, bottom=10.0)
    @style.apply(
      panel,
      @style.merge_all([
        @style.style(background_color="bg_panel", border_color="border", border_width=1.0),
        skin,
      ]),
    )
    panel.on_draw = Some(fn(
      self : @widget.Widget,
      p : @render.Painter,
      r : @base.Rect,
    ) -> Unit {
      let st = @style.style_for(self)
      let rad = @style.number_of(st.border_radius, @theme.radius_overlay())

      self.clip_rounded = rad > 0.0
      self.style_clip_radius = rad
      p.set_fill_color(@style.color_of(st.background_color, @theme.theme_bg_panel()))
      p.fill_round_rect(0.0, 0.0, r.w, r.h, rad)
      p.set_stroke_color(@style.color_of(st.border_color, @theme.theme_border()))
      p.set_line_width(@style.number_of(st.border_width, 1.0))
      if rad > 0.0 {
        p.round_rect_path(0.5, 0.5, r.w - 1.0, r.h - 1.0, rad)
        p.stroke()
      } else {
        p.stroke_rect(0.0, 0.0, r.w, r.h)
      }
    })
    let _ = row_of(plus_items).mount_into(panel)
    let _ = row_of(value_items).mount_into(panel)
    let _ = row_of(minus_items).mount_into(panel)
    let _ = row_of(caption_items).mount_into(panel)
    let _ = view(
      [
        @widget.node_of_new(fn(b : @widget.Widget) -> @widget.Widget {
          watch_theme()
          b.node.set_width(@yoga.fixed(70.0))
          b.node.set_height(@yoga.fixed(28.0))
          @style.apply(
            b,
            @style.merge_all([
              @style.style(
                background_color="bg_panel",
                border_color="border",
                border_width=1.0,
                border_radius=@theme.radius_ctrl(),
                color="text_regular",
              ).hover(background_color="fill_hover"),
              skin,
            ]),
          )
          b.on_draw = Some(fn(
            self : @widget.Widget,
            p : @render.Painter,
            r : @base.Rect,
          ) -> Unit {
            let st = @style.style_for(self)
            p.set_fill_color(@style.color_of(st.background_color, @theme.theme_bg_panel()))
            let rad = @style.number_of(st.border_radius, @theme.radius_ctrl())

            self.clip_rounded = rad > 0.0
            self.style_clip_radius = rad
            fill_round_rect(p, 0.0, 0.0, r.w, r.h, rad)
            p.set_stroke_color(@style.color_of(st.border_color, @theme.theme_border()))
            p.set_line_width(@style.number_of(st.border_width, 1.0))
            if rad > 0.0 {
              p.round_rect_path(0.5, 0.5, r.w - 1.0, r.h - 1.0, rad)
              p.stroke()
            } else {
              p.stroke_rect(0.0, 0.0, r.w, r.h)
            }
            let f = @text.Font::new("", 12.0)
            let _ = @text.draw_box_at(
              p,
              0.0,
              0.0,
              r.w,
              r.h,
              @i18n.t_or("gui.ui.datepicker.cancel", "取消"),
              f,
              @style.color_of(st.color, @theme.theme_text_regular()),
              align=@text.Center,
              valign=@text.Center,
            )
          })
          b.cursor = @widget.CURSOR_HAND
          b.on_pointer = Some(fn(
            _s : @widget.Widget,
            ev : @widget.PointerEvent,
          ) -> Bool {
            match ev.kind {
              @widget.PointerKind::Down => true
              @widget.PointerKind::Up => {
                on_cancel()
                false
              }
              _ => false
            }
          })
          b
        }),
        @widget.node_of_new(fn(b : @widget.Widget) -> @widget.Widget {
          watch_theme()
          b.node.set_width(@yoga.fixed(70.0))
          b.node.set_height(@yoga.fixed(28.0))
          @style.apply(
            b,
            @style.merge_all([
              @style.style(
                background_color="primary",
                border_radius=@theme.radius_ctrl(),
                color="#ffffff",
              ).hover(background_color="primary_hover"),
              skin,
            ]),
          )
          b.on_draw = Some(fn(
            self : @widget.Widget,
            p : @render.Painter,
            r : @base.Rect,
          ) -> Unit {
            let st = @style.style_for(self)
            p.set_fill_color(@style.color_of(st.background_color, @theme.theme_primary()))
            fill_round_rect(p, 0.0, 0.0, r.w, r.h, @style.number_of(st.border_radius, @theme.radius_ctrl()))
            let f = @text.Font::new("", 12.0)
            let _ = @text.draw_box_at(
              p,
              0.0,
              0.0,
              r.w,
              r.h,
              @i18n.t_or("gui.ui.datepicker.ok", "确定"),
              f,
              "#ffffff",
              align=@text.Center,
              valign=@text.Center,
            )
          })
          b.cursor = @widget.CURSOR_HAND
          b.on_pointer = Some(fn(
            _s : @widget.Widget,
            ev : @widget.PointerEvent,
          ) -> Bool {
            match ev.kind {
              @widget.PointerKind::Down => true
              @widget.PointerKind::Up => {
                on_confirm(cur.get())
                false
              }
              _ => false
            }
          })
          b
        }),
      ],
      direction=@yoga.Row,
      column_gap=8.0,
      justify_content=@yoga.JustifyContent::FlexEnd,
      width=160.0,
      align_items=@yoga.AlignItems::Center,
    ).mount_into(panel)
    panel
  })
}

///|
/// 日期选择器（EP DatePicker）：字段 + 日历弹层，点选回填并收起；`clearable`
/// 时字段悬停且有值显示 ✕，点它清空（清空不触发 `on_change`）。
/// 键盘口径：空格/回车/↓ 开层、回车/Esc 收层（见 `attach_field_toggle_key`）；
/// 字段自动进 Tab 链。
pub fn date_picker(
  value : @base.Store[DateYMD?],
  on_change? : (DateYMD) -> Unit = fn(_d : DateYMD) -> Unit { () },
  placeholder? : String = "请选择日期",
  clearable? : Bool = true,
  today? : DateYMD = today_date(),
  width? : Double = 180.0,
  focus_id? : Int = 0,
  class? : Array[@style.Style] = [],
  handle? : (@widget.Widget) -> Unit = default_handle,
) -> @widget.Node {
  follow_store(value)
  let t = today
  @widget.node_of_new(fn(w : @widget.Widget) -> @widget.Widget {
    let open_id : Ref[Int] = Ref(0)
    w.focus_id = auto_focus_id(focus_id)
    let close_pop = fn() -> Unit {
      if open_id.val != 0 {
        @widget.overlay_hide(open_id.val)
        open_id.val = 0
      }
    }
    let open_pop = fn() -> Unit {
      open_id.val = @widget.overlay_show_at(
        calendar_popup(
          t,
          fn(d : DateYMD) -> CalCell {
            match value.get() {
              Some(s) => if DateYMD::same(s, d) { Selected } else { Plain }
              None => Plain
            }
          },
          fn(d : DateYMD) -> Unit {
            value.set(Some(d))
            on_change(d)
            close_pop()
          },
          skin=paint_subset(class),
        ),
        w.rect.x,
        w.rect.y + w.rect.h + 2.0,
        anchor=Some(w.rect),
      )
    }

    setup_picker_field(
      w,
      width,
      fn() -> String {
        match value.get() {
          Some(d) => d.format()
          None => @i18n.t_or("gui.ui.datepicker.placeholder", placeholder)
        }
      },
      fn() -> Bool {
        match value.get() {
          Some(_) => true
          None => false
        }
      },
      clearable,
      skin=paint_subset(class),
      fn(local_x : Double) -> Unit {
        let filled = match value.get() {
          Some(_) => true
          None => false
        }
        if clear_hit(local_x, width, clearable, filled) {
          value.set(None)
          close_pop()
        } else if overlay_alive(open_id.val) {
          close_pop()
        } else {
          open_pop()
        }
      },
    )
    attach_field_toggle_key(w, open_id, open_pop, close_pop)
    fold_style(w, @style.empty_style(), class)
    handle(w)
    w
  })
}

///|
/// 日期区间选择器（EP DatePicker 区间形态）：字段 + 日历弹层，两段式点击
/// （先起点、再终点；已有完整区间时再从新起点开始），端点实心、区间内浅底。
/// 键盘口径同 `date_picker`（开/收层），字段自动进 Tab 链。
pub fn date_range_picker(
  value : @base.Store[DateRange],
  on_change? : (DateRange) -> Unit = fn(_r : DateRange) -> Unit { () },
  placeholder? : String = "请选择日期区间",
  clearable? : Bool = true,
  today? : DateYMD = today_date(),
  width? : Double = 220.0,
  handle? : (@widget.Widget) -> Unit = default_handle,
) -> @widget.Node {
  follow_store(value)
  let t = today
  @widget.node_of_new(fn(w : @widget.Widget) -> @widget.Widget {
    let open_id : Ref[Int] = Ref(0)
    w.focus_id = auto_focus_id(0)
    let close_pop = fn() -> Unit {
      if open_id.val != 0 {
        @widget.overlay_hide(open_id.val)
        open_id.val = 0
      }
    }
    let open_pop = fn() -> Unit {
      open_id.val = @widget.overlay_show_at(
        calendar_popup(
          t,
          fn(d : DateYMD) -> CalCell { range_state_of(value.get(), d) },
          fn(d : DateYMD) -> Unit {
            let r = value.get()
            match (r.start, r.end) {
              (None, _) => value.set({ start: Some(d), end: None })
              (Some(_), None) => {
                value.set({ start: r.start, end: Some(d) })
                on_change(value.get())
                close_pop()
              }
              (Some(_), Some(_)) => value.set({ start: Some(d), end: None })
            }
          },
        ),
        w.rect.x,
        w.rect.y + w.rect.h + 2.0,
        anchor=Some(w.rect),
      )
    }

    setup_picker_field(
      w,
      width,
      fn() -> String {
        let r = value.get()
        match (r.start, r.end) {
          (None, None) => @i18n.t_or("gui.ui.datepicker.range_placeholder", placeholder)
          _ => {
            let s = match r.start {
              Some(x) => x.format()
              None => "?"
            }
            let e = match r.end {
              Some(x) => x.format()
              None => "?"
            }
            s + " ~ " + e
          }
        }
      },
      fn() -> Bool {
        let r = value.get()
        match (r.start, r.end) {
          (Some(_), Some(_)) => true
          (Some(_), None) => true
          _ => false
        }
      },
      clearable,
      fn(local_x : Double) -> Unit {
        let filled = match value.get().start {
          Some(_) => true
          None => false
        }
        if clear_hit(local_x, width, clearable, filled) {
          value.set({ start: None, end: None })
          close_pop()
        } else if overlay_alive(open_id.val) {
          close_pop()
        } else {
          open_pop()
        }
      },
    )
    attach_field_toggle_key(w, open_id, open_pop, close_pop)
    handle(w)
    w
  })
}

///|
/// 一行「标签 + 时间字段」：点字段开时间弹层，确定后写回。
/// 键盘口径同 `date_picker`（空格/回车/↓ 开、回车/Esc 收），字段自动进 Tab 链。
fn time_field(
  width : Double,
  get : () -> TimeHMS?,
  set : (TimeHMS) -> Unit,
  placeholder? : String = "?:?",
  show_seconds? : Bool = false,
) -> @widget.Node {
  let secs = show_seconds
  @widget.node_of_new(fn(field : @widget.Widget) -> @widget.Widget {
    let open_id : Ref[Int] = Ref(0)
    field.focus_id = auto_focus_id(0)
    let close_pop = fn() -> Unit {
      if open_id.val != 0 {
        @widget.overlay_hide(open_id.val)
        open_id.val = 0
      }
    }
    let open_pop = fn() -> Unit {
      let init = match get() {
        Some(t) => t
        None => TimeHMS::{ h: 9, m: 0, s: 0 }
      }
      open_id.val = @widget.overlay_show_at(
        time_popup(
          init,
          fn(t : TimeHMS) -> Unit {
            set(t)
            close_pop()
          },
          close_pop,
          show_seconds=secs,
        ),
        field.rect.x - 40.0,
        field.rect.y + field.rect.h + 2.0,
        anchor=Some(field.rect),
      )
    }

    // 字段本体（标签由外层容器画）
    setup_picker_field(
      field,
      width,
      fn() -> String {
        match get() {
          Some(t) => t.format(show_seconds=secs)
          None => placeholder
        }
      },
      fn() -> Bool {
        match get() {
          Some(_) => true
          None => false
        }
      },
      false,
      fn(_local_x : Double) -> Unit {
        if overlay_alive(open_id.val) {
          close_pop()
        } else {
          open_pop()
        }
      },
    )
    attach_field_toggle_key(field, open_id, open_pop, close_pop)
    field
  })
}

///|
/// 时间区间选择器（EP TimePicker 区间形态）：起止两个时间字段（步进式弹层）。
pub fn time_range_picker(
  value : @base.Store[TimeRange],
  on_change? : (TimeRange) -> Unit = fn(_r : TimeRange) -> Unit { () },
  width? : Double = 110.0,
  show_seconds? : Bool = false,
  handle? : (@widget.Widget) -> Unit = default_handle,
) -> @widget.Node {
  follow_store(value)
  @widget.node_of_new(fn(w : @widget.Widget) -> @widget.Widget {
    watch_theme()
    w.node.set_flex_direction(@yoga.Row)
    w.node.set_align_items(@yoga.AlignItems::Center)
    w.node.set_gap(0.0, 8.0)
    let _ = time_field(
      width,
      fn() -> TimeHMS? { value.get().start },
      fn(t : TimeHMS) -> Unit {
        let r = value.get()
        value.set({ start: Some(t), end: r.end })
        on_change(value.get())
      },
      show_seconds=show_seconds,
    ).mount_into(w)
    let _ = text("~", font_size=13.0).mount_into(w)
    let _ = time_field(
      width,
      fn() -> TimeHMS? { value.get().end },
      fn(t : TimeHMS) -> Unit {
        let r = value.get()
        value.set({ start: r.start, end: Some(t) })
        on_change(value.get())
      },
      show_seconds=show_seconds,
    ).mount_into(w)
    handle(w)
    w
  })
}

///|
/// 日期时间区间选择器：起止各一对「日期字段 + 时间字段」，日期走日历弹层、
/// 时间走步进弹层；任一侧任一维改动都会把整份区间写回 Store 并回调。
pub fn datetime_range_picker(
  value : @base.Store[DateTimeRange],
  on_change? : (DateTimeRange) -> Unit = fn(_r : DateTimeRange) -> Unit { () },
  today? : DateYMD = today_date(),
  date_width? : Double = 130.0,
  time_width? : Double = 86.0,
  show_seconds? : Bool = false,
  handle? : (@widget.Widget) -> Unit = default_handle,
) -> @widget.Node {
  follow_store(value)
  let t = today
  @widget.node_of_new(fn(w : @widget.Widget) -> @widget.Widget {
    watch_theme()
    w.node.set_flex_direction(@yoga.Row)
    w.node.set_align_items(@yoga.AlignItems::Center)
    w.node.set_gap(0.0, 6.0)
    fn date_field(is_start : Bool) -> @widget.Node {
      @widget.node_of_new(fn(field : @widget.Widget) -> @widget.Widget {
        let open_id : Ref[Int] = Ref(0)
        field.focus_id = auto_focus_id(0)
        let close_pop = fn() -> Unit {
          if open_id.val != 0 {
            @widget.overlay_hide(open_id.val)
            open_id.val = 0
          }
        }
        let open_pop = fn() -> Unit {
          open_id.val = @widget.overlay_show_at(
            calendar_popup(
              t,
              fn(d : DateYMD) -> CalCell {
                let pair = if is_start { value.get().start } else { value.get().end }
                match pair {
                  Some(p) => if DateYMD::same(p.0, d) { Selected } else { Plain }
                  None => Plain
                }
              },
              fn(d : DateYMD) -> Unit {
                let r = value.get()
                if is_start {
                  let tm = match r.start {
                    Some(p) => p.1
                    None => TimeHMS::{ h: 9, m: 0, s: 0 }
                  }
                  value.set({ start: Some((d, tm)), end: r.end })
                } else {
                  let tm = match r.end {
                    Some(p) => p.1
                    None => TimeHMS::{ h: 18, m: 0, s: 0 }
                  }
                  value.set({ start: r.start, end: Some((d, tm)) })
                }
                on_change(value.get())
                close_pop()
              },
            ),
            field.rect.x,
            field.rect.y + field.rect.h + 2.0,
            anchor=Some(field.rect),
          )
        }

        setup_picker_field(
          field,
          date_width,
          fn() -> String {
            let pair = if is_start { value.get().start } else { value.get().end }
            match pair {
              Some(p) => p.0.format()
              None => @i18n.t_or("gui.ui.datepicker.title", "选择日期")
            }
          },
          fn() -> Bool {
            match (if is_start { value.get().start } else { value.get().end }) {
              Some(_) => true
              None => false
            }
          },
          false,
          fn(_local_x : Double) -> Unit {
            if overlay_alive(open_id.val) {
              close_pop()
            } else {
              open_pop()
            }
          },
        )
        attach_field_toggle_key(field, open_id, open_pop, close_pop)
        field
      })
    }

    let _ = date_field(true).mount_into(w)
    let _ = time_field(
      time_width,
      fn() -> TimeHMS? {
        match value.get().start {
          Some(p) => Some(p.1)
          None => None
        }
      },
      fn(tm : TimeHMS) -> Unit {
        let r = value.get()
        match r.start {
          Some(p) => value.set({ start: Some((p.0, tm)), end: r.end })
          None => ()
        }
        on_change(value.get())
      },
      show_seconds=show_seconds,
    ).mount_into(w)
    let _ = text("~", font_size=13.0).mount_into(w)
    let _ = date_field(false).mount_into(w)
    let _ = time_field(
      time_width,
      fn() -> TimeHMS? {
        match value.get().end {
          Some(p) => Some(p.1)
          None => None
        }
      },
      fn(tm : TimeHMS) -> Unit {
        let r = value.get()
        match r.end {
          Some(p) => value.set({ start: r.start, end: Some((p.0, tm)) })
          None => ()
        }
        on_change(value.get())
      },
      show_seconds=show_seconds,
    ).mount_into(w)
    handle(w)
    w
  })
}
