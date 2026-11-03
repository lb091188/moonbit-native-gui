// 可选中静态文本（`text` / `text_dyn` 的 selectable 档）。
//
// 缺省档一行不动——测量与绘制仍是 @text 的整段排版。这一档把几何半边交给
// `@input.TextLayout`：行模型、像素命中、选区矩形出自同一份 layout，绘制只是
// 「把 rects 填色 + 逐行画字」，量与画不会再分叉。选区状态是那件自己的只读
// `@input.Editor`（字节偏移是唯一权威，行矩形每帧按当前 layout 现算），跨件互斥
// 与 Ctrl/Cmd+C 归 `@widget` 的选区持有者登记（textsel）。
//
// 三条已知边界（写死在这里，不留隐坑）：
// - 折行块内不逐行对齐：整块按 `text_align` 偏移，块内各行贴块左缘。
// - 选中期间文本或盒宽变了就清选区（`Editor::set_text` 的既定行为），不做偏移迁移。
// - 行数钳制与省略号与缺省档同一把刀（`@text.clamp_lines`），故选中范围=可见范围。

///|
/// 一件可选中文本的状态：只读 Editor（选区/插入点权威）+ 拖选旗标。
/// 混排件（markdown 富文本）复用同一份状态与交互链，几何自己给——见本文件尾
/// `text_sel_new` / `TextSel::pointer` 公开面。
pub(all) struct TextSel {
  ed : @input.Editor
  dragging : Ref[Bool]
  anchor : Ref[Int]
  last_down : Ref[Int64]
  last_xy : Ref[(Double, Double)]
}

///|
/// 控件 id → 「文本变了」的收尾口。`relabel` 是动态文本的唯一变化点
/// （`bind` / `bind_label` / `text_dyn` 都汇到这里）：注册过的件走本档收尾
/// （标脏重排 + 让出选区），没注册的走原路 `attach_text_measure`。
let sel_hooks : Ref[Map[Int, () -> Unit]] = Ref(Map([]))

///|
/// 控件 id → 这一件的状态（本包内的读回口：白盒用例断言选区/ caret 用）。
let sel_states : Ref[Map[Int, TextSel]] = Ref(Map([]))

///|
/// 本档实际可见的文本：`max_lines` 钳制与单行省略都复用 @text 那一把刀。
fn sel_visible_text(
  src : TextSource,
  font : @text.Font,
  box_w : Double,
) -> String {
  let need = src.max_lines > 0 || (!src.wrap && src.ellipsis)
  if need && box_w > 1.0 {
    let n = if src.max_lines > 0 { src.max_lines } else { 1 }
    @text.clamp_lines(src.text, font, box_w.floor().to_int(), n)
  } else {
    src.text
  }
}

///|
/// 本档的行盒高：样式给了 `line_height` 用它，否则取引擎行高。
fn sel_line_h(font : @text.Font, line_h : Double) -> Double {
  if line_h > 0.0 { line_h } else { @text.line_height_font(font).unwrap_or(18).to_double() }
}

///|
/// 按控件当前样式与盒宽出一份 TextLayout——**绘制、命中、选区矩形都吃它**。
/// 横向块偏移记在 `pad`，纵向居中偏移折进 `offset_y`（`pad - top`），于是
/// `caret_y` 与 `hit` 的换算自动把居中算对。
fn sel_layout(w : @widget.Widget, src : TextSource) -> @input.TextLayout {
  let (font, align, wrap, lh_raw, _deco) = text_eff(@style.style_for(w), src)
  let r = w.rect
  let box_w = if src.max_width > 0.0 { src.max_width.min(r.w) } else { r.w }
  let text = sel_visible_text(src, font, box_w)
  let measure = fn(t : String, from : Int, to : Int) -> Double {
    seg_width(t, from, to, font)
  }
  let line_h = sel_line_h(font, lh_raw)
  // 不折行档给一个量不到的宽：断行只由 `\n` 决定（贪心折行自然不触发）
  let avail = if wrap { box_w } else { 1000000.0 }
  let lines = @input.layout_lines(text, avail, measure)
  let mut widest = 0.0
  for ln in lines {
    if ln.width > widest {
      widest = ln.width
    }
  }
  let pad = if align is @text.TextAlign::Center {
    ((box_w - widest) / 2.0).max(0.0)
  } else if align is @text.TextAlign::End {
    (box_w - widest).max(0.0)
  } else {
    0.0
  }
  let top = ((r.h - lines.length().to_double() * line_h) / 2.0).max(0.0)
  { text, lines, pad, line_h, offset_y: pad - top, measure }
}

///|
/// 盒宽上限（与缺省档同式：`max_width` 是上限不是定值）。
fn sel_box_w(w : @widget.Widget, src : TextSource) -> Double {
  if src.max_width > 0.0 { src.max_width.min(w.rect.w) } else { w.rect.w }
}

///|
/// 最宽一行（内容宽）：测量面与绘制面都用它答，块偏移也从它推。
fn sel_widest(lines : Array[@input.TextLine]) -> Double {
  let mut m = 0.0
  for ln in lines {
    if ln.width > m {
      m = ln.width
    }
  }
  m
}

///|
/// 测量面（本档）：内容尺寸由同一份行模型答。min-content 探询（yoga 请求轴
/// `Some(0.0)`）按 1px 箱折——最宽单元自然浮出来，与缺省档「按最窄可折答」同口径。
fn attach_sel_measure(node : @yoga.Node, id : Int, src : TextSource) -> Unit {
  node.set_measure(fn(avail_w : Double?, _avail_h : Double?) -> (
    Double,
    Double,
  ) {
    let (font, _align, wrap, lh_raw, _d) = text_eff(@style.resolved_for_measure(id), src)
    let avail = match avail_w {
      Some(v) if v > 0.0 => v
      _ => 0.0
    }
    let cap = match (src.max_width > 0.0, avail > 0.0) {
      (true, true) => src.max_width.min(avail)
      (true, false) => src.max_width
      (false, true) => avail
      (false, false) => 0.0
    }
    let measure = fn(t : String, from : Int, to : Int) -> Double {
      seg_width(t, from, to, font)
    }
    let probing = match avail_w {
      Some(v) => v <= 0.0 && wrap
      None => false
    }
    if probing {
      let ls = @input.layout_lines(src.text, 1.0, measure)
      (sel_widest(ls), font.size * 1.6)
    } else {
      let text = sel_visible_text(src, font, cap)
      let box = if wrap && cap > 0.0 { cap } else { 1000000.0 }
      let ls = @input.layout_lines(text, box, measure)
      let line_h = sel_line_h(font, lh_raw)
      (sel_widest(ls), ls.length().to_double() * line_h)
    }
  })
  node.set_baseline(fn(_a : Double?, _b : Double?) -> Double? {
    let (font, _align, _wrap, _lh, _u) = text_eff(@style.resolved_for_measure(id), src)
    @text.line_ascent_font(font).map(fn(v : Int) -> Double { v.to_double() })
  })
}

///|
/// 文本变了就把 Editor 换成可见文本（内核换文即清选区，与本档口径一致）。
fn sel_sync(st : TextSel, lay : @input.TextLayout) -> Unit {
  if lay.text != st.ed.get_text() {
    st.ed.set_text(lay.text)
  }
}

///|
/// 认领选区：复制走内核（装了系统槽就落系统剪贴板），让位时清自己的选区。
fn sel_claim(id : Int, st : TextSel) -> Unit {
  @widget.text_sel_claim(
    id,
    fn() {
      let _ = st.ed.copy()
    },
    fn() {
      let p = st.ed.caret_pos()
      st.ed.select_range(p, p)
    },
  )
}

///|
/// 绘制（本档）：先铺选区底色再逐行画字，装饰线与缺省档同一个函数。
fn draw_sel_text(
  w : @widget.Widget,
  p : @render.Painter,
  src : TextSource,
  st : TextSel,
) -> Unit {
  let lay = sel_layout(w, src)
  sel_sync(st, lay)
  let sty = @style.style_for(w)
  let (font, align, _wrap, _lh, deco) = text_eff(sty, src)
  let fg1 = match sty.color {
    Some(c) => @style.resolve_color(c)
    None => src.fg()
  }
  match st.ed.selection() {
    Some((a, b)) => {
      for rc in lay.rects(a, b) {
        p.set_fill_color(@theme.theme_primary_light())
        p.fill_rect(rc.x, rc.y, rc.w.max(1.0), rc.h)
      }
    }
    None => ()
  }
  for i = 0; i < lay.lines.length(); i = i + 1 {
    let ln = lay.lines[i]
    if ln.end > ln.start {
      let _ = @text.draw_at(
        p,
        lay.pad,
        lay.caret_y(ln.start),
        byte_slice(lay.text, ln.start, ln.end),
        font,
        fg1,
      )
    }
  }
  let has_line = match deco {
    @style.Underline | @style.LineThrough | @style.Overline => true
    _ => false
  }
  if has_line && lay.text.length() > 0 {
    draw_text_deco(p, w, src, font, sel_box_w(w, src), fg1, align, deco)
  }
}

///|
/// 建一份选中态（只读 Editor 为唯一权威；`ed` 由调用方备好文本）。
fn sel_new_state(ed : @input.Editor) -> TextSel {
  attach_system_clipboard(ed)
  {
    ed,
    dragging: Ref(false),
    anchor: Ref(0),
    last_down: Ref(-1000000L),
    last_xy: Ref((-1000.0, -1000.0)),
  }
}

///|
/// 指针四交互的共用链（静态文本与代码视图同一条）：单击折叠定位、双击选词、
/// 按下拖选（出件不丢靠宿主按下捕获）、Shift+点击扩选；右键开内置编辑菜单
/// （can_edit=false·can_copy=true）。`hit` 把控件内坐标换成字节偏移，选词参照
/// 用 Editor 自己的全文。双击按 textarea 同款手算（400ms + 4px），不挂
/// `on_double_click`。
fn sel_pointer(
  w : @widget.Widget,
  ev : @widget.PointerEvent,
  st : TextSel,
  hit : (Double, Double) -> Int,
) -> Bool {
  match ev.kind {
    @widget.PointerKind::Down => {
      if ev.button == 3 {
        return show_edit_menu(
          w,
          ev.x,
          ev.y,
          st.ed,
          can_edit=false,
          can_copy=true,
          changed=fn() -> Unit { @widget.invalidate() },
        )
      }
      let at = hit(ev.x, ev.y)
      let now = @shell.now_ms()
      let dbl = (now - st.last_down.val) < 400L && (ev.x - st.last_xy.val.0).abs() < 4.0 && (
        ev.y - st.last_xy.val.1
      ).abs() < 4.0
      st.last_down.val = now
      st.last_xy.val = (ev.x, ev.y)
      let shift = (ev.mods & @base.MOD_SHIFT) != 0
      if shift {
        let a = st.anchor.val
        st.ed.select_range(a.min(at), a.max(at))
        sel_claim(w.id, st)
      } else if dbl {
        let (s, e) = word_range(st.ed.get_text(), at)
        st.ed.select_range(s, e)
        st.anchor.val = s
        sel_claim(w.id, st)
      } else {
        st.ed.select_range(at, at)
        st.anchor.val = at
        st.dragging.val = true
        @widget.text_sel_release(w.id)
      }
      @widget.invalidate()
      true
    }
    @widget.PointerKind::Move => {
      if st.dragging.val {
        st.ed.select_range(st.anchor.val, hit(ev.x, ev.y))
        sel_claim(w.id, st)
        @widget.invalidate()
      }
      st.dragging.val
    }
    @widget.PointerKind::Up => {
      st.dragging.val = false
      false
    }
    @widget.PointerKind::Leave => false
  }
}

///|
/// 装配一件可选中文本：只读 Editor + 测量面 + 指针 + 变化收尾口 + 摘除清理。
fn sel_setup(w : @widget.Widget, src : TextSource) -> TextSel {
  let st = sel_new_state(@input.Editor::new())
  let node = w.node
  let id = w.id
  attach_sel_measure(node, id, src)
  w.cursor = @widget.CURSOR_TEXT
  w.on_pointer = Some(fn(
    self : @widget.Widget,
    ev : @widget.PointerEvent,
  ) -> Bool {
    sel_pointer(self, ev, st, fn(x : Double, y : Double) -> Int {
      let lay = sel_layout(self, src)
      sel_sync(st, lay)
      lay.hit(x, y)
    })
  })
  // 收尾口只捕节点句柄与 id，不捕 Widget（回调禁捕铁律）：重设测量即标脏，
  // 与本档的行模型同一口径
  sel_hooks.val.set(id, fn() -> Unit {
    attach_sel_measure(node, id, src)
    // 文本变了就清选区（偏移迁移不做，与定案一致）
    st.ed.set_text(src.text)
    @widget.text_sel_release(id)
  })
  sel_states.val.set(id, st)
  w.on_discard = Some(fn(self : @widget.Widget) -> Unit {
    let _ = sel_hooks.val.remove(self.id)
    let _ = sel_states.val.remove(self.id)
    @widget.text_sel_release(self.id)
  })
  st
}

// ---- 混排件复用面（markdown 富文本等自带几何的绘制件）----

///|
/// 建一份复用状态：调用方备好只读 Editor（全文即选中范围），复制走系统槽。
pub fn text_sel_new(ed : @input.Editor) -> TextSel {
  sel_new_state(ed)
}

///|
/// 全文变了就同步（换文即清选区，与 selectable 档同一口径，不做偏移迁移）。
pub fn TextSel::sync(self : TextSel, text : String) -> Unit {
  if text != self.ed.get_text() {
    self.ed.set_text(text)
  }
}

///|
/// 指针四交互（单击折叠定位 / 双击选词 / 按下拖选 / Shift 扩选 / 右键复制菜单）。
/// `hit` 把控件内坐标换成字节偏移——混排件的逐字几何在这里接进来。
pub fn TextSel::pointer(
  self : TextSel,
  w : @widget.Widget,
  ev : @widget.PointerEvent,
  hit : (Double, Double) -> Int,
) -> Bool {
  sel_pointer(w, ev, self, hit)
}

///|
/// 当前选区（字节区间）；没有选区给 None。绘制方据此铺底色。
pub fn TextSel::range(self : TextSel) -> (Int, Int)? {
  self.ed.selection()
}

///|
/// 让出选区持有者（控件摘除时调用；同一条注册表保证跨件互斥）。
pub fn TextSel::give_up(self : TextSel, id : Int) -> Unit {
  let _ = self
  @widget.text_sel_release(id)
}
