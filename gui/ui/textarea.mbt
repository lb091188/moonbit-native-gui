// 多行输入框（textarea）：换行布局 + 垂直滚动 + 与单行 `input` 同源的编辑语义。
//
// 文本权威仍是 `@input.Editor`（组件不另存一份），`Store[String]` 是它的对外投影；
// 与宿主的接缝还是那五个回调（`on_key`/`on_commit`/`on_preedit`/`im_context`/
// `im_cursor`）。多行比单行多的只有两件事：**显示行**（按 `\n` 断行后再按盒宽折行）
// 与**垂直滚动**（复用 `scroll.mbt` 的 `ScrollState` 与滚动条控件）。
//
// 行模型、像素↔字节命中、光标坐标都在 `@input.TextLayout`（几何半边，测宽由这里
// 注入）；本文件只管把它按当前文本/盒宽/滚动偏移装配出来。
//
// 滚动偏移不进布局：显示行是本控件自己画的一层文字，不是子控件，所以平移发生在
// 绘制期（`y = 行序 × 行高 − 偏移`），滚动条则是视口的绝对定位子控件（与滚动容器
// 同一理由：压在内容之上才吃得到命中）。

///|
/// 取字节下标 `[from,to)` 的子串（调用方保证落在码点边界；越界由切片夹住）。
fn byte_slice(text : String, from : Int, to : Int) -> String {
  if to <= from {
    ""
  } else {
    @utf8.decode_lossy(@utf8.encode(text)[from:to])
  }
}

///|
/// 一行文本的自然宽（测量失败按 0）。
fn seg_width(text : String, from : Int, to : Int, font : @text.Font) -> Double {
  if to <= from {
    0.0
  } else {
    match @text.measure_font(byte_slice(text, from, to), font) {
      Some(m) => m.width
      None => 0.0
    }
  }
}

///|
/// 多行输入框。`rows` 只决定初始高度（每行 `row_height`）；`height` 传正数按它。
/// 键入、选区、拖动选词、undo/redo、Ctrl+A/C/V（内核内部剪贴板）、IME commit 与
/// preedit 内联与单行框同源；换行键插入 `\n`，上下键按**显示行**移动（记住起算 x，
/// 短行移动后仍回到该 x），Home/End 走行首行尾（带 Ctrl 仍是全文首末）。
pub fn textarea(
  /// 双向绑定这段文本。
  store : @base.Store[String],
  /// 没输入时显示占位文字。
  placeholder? : String = "",
  /// 按行数撑出初始高度（每行一个行高）。
  rows? : Int = 3,
  /// 定死宽度，0 = 按内容测量。
  width? : Double = 260.0,
  /// 定死高度，0 = 按内容测量。
  height? : Double = 0.0,
  /// 设字号（逻辑像素）。
  font_size? : Double = 13.0,
  /// 指定字族，空串走系统默认字族。
  family? : String = "",
  /// 设为只读：可选中不可改。
  read_only? : Bool = false,
  /// 进 Tab 焦点链的序号；传正数才可 Tab 到，0 = 自动领号。
  focus_id? : Int = 0,
  /// 决定光标是否可见的谓词。
  caret_on? : () -> Bool = fn() -> Bool { true },
  /// 值变化时回调。
  on_change? : (String) -> Unit = fn(_s : String) -> Unit { () },
  /// 挂命名样式类（`class_of([...])`）；类排在散参数之后，覆盖散参数。
  class? : Array[@style.Style] = [],
  /// 挂载后把宿主 Widget 句柄交给调用方（逃生舱）。
  handle? : (@widget.Widget) -> Unit = default_handle,
) -> @widget.Node {
  let ed = @input.Editor::new()
  attach_system_clipboard(ed)
  let _ = ed.insert_text(store.get())
  let font = @text.Font::new(family, font_size)
  let pad = 4.0
  let ro = read_only
  // 主修饰键跟着平台走（mac=Cmd），探测一次存下，别每个按键问一遍
  let is_mac = @shell.platform_is_macos()
  let ph = placeholder
  let change_cb = on_change
  let line_h = (@text.line_height_font(font).unwrap_or(18).to_double() + 2.0).max(14.0)
  let box_h = if height > 0.0 { height } else { line_h * rows.to_double() + pad * 2.0 }
  let st = ScrollState::new()
  // 测宽器注入给 @input.TextLayout：字节区间的自然宽按本控件的字体量
  let measure = fn(t : String, from : Int, to : Int) -> Double {
    seg_width(t, from, to, font)
  }
  // 布局缓存：文本或盒宽变了才重排显示行（每帧都重折一遍是白烧）
  let cache : Ref[(String, Double, Array[@input.TextLine])] = Ref(("", -1.0, []))
  let lines_of = fn(text : String, w : Double) -> Array[@input.TextLine] {
    let key = cache.val
    if key.0 == text && key.1 == w {
      key.2
    } else {
      let ls = @input.layout_lines(text, w - pad * 2.0, measure)
      cache.val = (text, w, ls)
      ls
    }
  }

  @widget.node_of_new(fn(w : @widget.Widget) -> @widget.Widget {
    watch_theme()
    w.role = "text_area"
    w.a11y_text = Some(fn(_self : @widget.Widget) -> String? { Some(ed.get_text()) })
    w.a11y_state = Some(fn(_self : @widget.Widget) -> (String, String)? {
      if ro {
        Some(("read_only", ""))
      } else {
        None
      }
    })
    let off = enabled_cell(None, false)
    let last_down = Ref(-1000000L)
    let last_xy = Ref((-1000.0, -1000.0))
    let dragging = Ref(false)
    let anchor = Ref(0)
    let pref_x : Ref[Double] = Ref(-1.0)
    w.focus_id = auto_focus_id(focus_id)
    w.cursor = @widget.CURSOR_TEXT
    w.node.set_width(@yoga.fixed(width))
    w.node.set_height(@yoga.fixed(box_h))
    w.node.set_flex_shrink(0.0)
    let text_of = fn() -> String { ed.get_text() }
    // 按当前文本/盒宽/滚动偏移装配几何（行模型走缓存，不重折）
    let layout_at = fn(text : String, w : Double) -> @input.TextLayout {
      { text, lines: lines_of(text, w), pad, line_h, offset_y: st.offset, measure }
    }
    // 把插入点滚进可视区（键入、点击、上下移动后都调）
    let ensure_visible = fn(lay : @input.TextLayout) -> Unit {
      let i = lay.line_of(ed.caret_pos())
      let top = i.to_double() * line_h
      let view = st.view_h
      if top < st.offset {
        st.set_offset(top)
      } else if top + line_h > st.offset + view {
        st.set_offset(top + line_h - view)
      }
    }
    let push = fn() -> Unit {
      let t = ed.get_text()
      store.set(t)
      change_cb(t)
    }

    w.on_draw = Some(fn(
      self : @widget.Widget,
      p : @render.Painter,
      r : @base.Rect,
    ) -> Unit {
      let t = text_of()
      let lay = layout_at(t, r.w)
      let lines = lay.lines
      // 几何抄进状态（滚动条比例与夹取都用它）：内容高 = 行数 × 行高
      st.view_h = (r.h - pad).max(1.0)
      st.content_h = lines.length().to_double() * line_h + pad * 2.0
      let sty = @style.style_for(self)
      let rad = @style.number_of(sty.border_radius, @theme.radius_ctrl())

      self.clip_rounded = rad > 0.0
      self.style_clip_radius = rad
      p.set_fill_color(@style.color_of(sty.background_color, @theme.theme_bg_panel()))
      p.fill_round_rect(0.0, 0.0, r.w, r.h, rad)
      let sel = ed.selection()
      let caret = ed.caret_pos()
      for i = 0; i < lines.length(); i = i + 1 {
        let ln = lines[i]
        let y = pad + i.to_double() * line_h - st.offset
        if y + line_h < 0.0 || y > r.h {
          continue
        }
        match sel {
          Some((s, e)) => {
            let a = s.max(ln.start)
            let b = e.min(ln.end)
            if b > a {
              p.set_fill_color(@theme.theme_primary_light())
              p.fill_rect(
                pad + seg_width(t, ln.start, a, font),
                y,
                seg_width(t, a, b, font).max(1.0),
                line_h,
              )
            }
          }
          None => ()
        }
        if t.length() == 0 && i == 0 && ph.length() > 0 {
          let _ = @text.draw_at(p, pad, y, ph, font, @theme.theme_text_secondary())
        } else if ln.end > ln.start {
          let _ = @text.draw_at(
            p,
            pad,
            y,
            byte_slice(t, ln.start, ln.end),
            font,
            if off.off {
              @theme.theme_text_secondary()
            } else {
              @style.color_of(sty.color, @theme.theme_text_regular())
            },
          )
        }
      }
      // preedit 画在插入点所在行的插入点处（组合串只此一份，内核不并入文本）
      let pe = ed.preedit_text()
      let cy = lay.caret_y(caret)
      let cx = lay.caret_x(caret)
      if pe.length() > 0 {
        let _ = @text.draw_at(p, cx, cy, pe, font, @theme.theme_warning())
        let pw = seg_width(pe, 0, pe.length(), font)
        p.set_fill_color(@theme.theme_warning())
        p.fill_rect(cx, cy + line_h - 2.0, pw, 1.0)
      }
      if self.focused && !off.off && caret_on() {
        p.set_fill_color(@theme.theme_text_primary())
        p.fill_rect(cx, cy, 1.0, line_h)
      }
      // 焦点框色由 focus 桶供（样式没给就回落主题描边色）
      p.set_stroke_color(@style.color_of(sty.border_color, @theme.theme_border()))
      p.set_line_width(@style.number_of(sty.border_width, 1.0))
      if rad > 0.0 {
        p.round_rect_path(0.5, 0.5, r.w - 1.0, r.h - 1.0, rad)
        p.stroke()
      } else {
        p.stroke_rect(0.0, 0.0, r.w, r.h)
      }
    })
    w.on_key = Some(fn(ev : @widget.KeyEvent) -> Bool {
      if !ev.press || off.off {
        return false
      }
      let shift = (ev.mods & @base.MOD_SHIFT) != 0
      let ctrl = (ev.mods & @base.MOD_CTRL) != 0
      // 主修饰键跟平台走：mac 上 Cmd 才是「选全/复制/粘贴」那一族，Ctrl 不是
      let meta = (ev.mods & @base.MOD_META) != 0
      let primary = if is_mac { meta } else { ctrl }
      let t = text_of()
      let lay = layout_at(t, w.rect.w)
      let lines = lay.lines
      if ev.keysym == @base.KS_RETURN {
        if ro {
          return false
        }
        let _ = ed.insert_text("\n")
        pref_x.val = -1.0
        push()
        ensure_visible(layout_at(ed.get_text(), w.rect.w))
        @widget.invalidate()
        return true
      }
      if ev.keysym == @base.KS_UP || ev.keysym == @base.KS_DOWN {
        let caret = ed.caret_pos()
        let i = lay.line_of(caret)
        let x = if pref_x.val >= 0.0 {
          pref_x.val
        } else {
          lay.caret_x(caret)
        }
        let j = if ev.keysym == @base.KS_UP { i - 1 } else { i + 1 }
        if j < 0 || j >= lines.length() {
          pref_x.val = -1.0
          return false
        }
        let ln = lines[j]
        let mut at = ln.start
        while at < ln.end && measure(t, ln.start, at + 1) + pad <= x {
          at = at + 1
        }
        // 逐字节推进可能停在码点中间：退回到码点起点（at 可能等于文本末尾，
        // 那里没有字节可读）
        let bs = @utf8.encode(t)
        let n = bs.length()
        while at > ln.start && at < n && (bs[at].to_int() & 0xc0) == 0x80 {
          at = at - 1
        }
        pref_x.val = x
        if shift {
          let a = match ed.selection() {
            Some((s, _)) => s
            None => caret
          }
          ed.select_range(a, at)
        } else {
          ed.select_range(at, at)
        }
        anchor.val = at
        ensure_visible(lay)
        @widget.invalidate()
        return true
      }
      if !ctrl && !meta && (ev.keysym == @base.KS_HOME || ev.keysym == @base.KS_END) {
        let caret = ed.caret_pos()
        let ln = lines[lay.line_of(caret)]
        let at = if ev.keysym == @base.KS_HOME { ln.start } else { ln.end }
        pref_x.val = -1.0
        if shift {
          let a = match ed.selection() {
            Some((s, _)) => s
            None => caret
          }
          ed.select_range(a, at)
        } else {
          ed.select_range(at, at)
        }
        ensure_visible(lay)
        @widget.invalidate()
        return true
      }
      let editing = ev.keysym == @base.KS_BACKSPACE || ev.keysym == @base.KS_DELETE
      // 只读时导航与复制照旧：带 Ctrl/Cmd 的组合要放行（mac 的选全、复制靠 Cmd）
      let nav = primary || (ev.mods & @base.MOD_SHIFT) != 0 || (
        ev.keysym >= 65360 && ev.keysym <= 65367
      ) || ev.keysym == @base.KS_TAB
      if ro && (editing || !nav) {
        return false
      }
      let before = ed.get_text()
      let handled = ed.handle_key(ev.keysym, ev.mods, mac=is_mac)
      if handled {
        pref_x.val = -1.0
        if ed.get_text() != before {
          push()
        }
        ensure_visible(layout_at(ed.get_text(), w.rect.w))
        @widget.invalidate()
      }
      handled
    })
    w.on_commit = Some(fn(t : String) -> Bool {
      let _ = ed.insert_text(t)
      push()
      ensure_visible(layout_at(ed.get_text(), w.rect.w))
      @widget.invalidate()
      true
    })
    w.on_preedit = Some(fn(t : String, _caret : Int) -> Unit {
      ed.set_preedit(t)
      @widget.invalidate()
    })
    w.on_pointer = Some(fn(
      self : @widget.Widget,
      ev : @widget.PointerEvent,
    ) -> Bool {
      match ev.kind {
        @widget.PointerKind::Down => {
          if ev.button == 3 {
            // 右键开内置编辑菜单（祖先挂了自定义 context_menu_for 时先轮到祖先）
            return show_edit_menu(
              self,
              ev.x,
              ev.y,
              ed,
              can_edit=!ro,
              can_copy=!ro,
              changed=fn() -> Unit {
                push()
                ensure_visible(layout_at(ed.get_text(), self.rect.w))
                @widget.invalidate()
              },
            )
          }
          let lay = layout_at(text_of(), self.rect.w)
          let now = @shell.now_ms()
          let dbl = (now - last_down.val) < 400L &&
            (ev.x - last_xy.val.0).abs() < 4.0 && (ev.y - last_xy.val.1).abs() < 4.0
          last_down.val = now
          last_xy.val = (ev.x, ev.y)
          dragging.val = true
          pref_x.val = -1.0
          let at = lay.hit(ev.x, ev.y)
          if dbl {
            let (s, e) = word_range(text_of(), at)
            ed.select_range(s, e)
          } else {
            ed.select_range(at, at)
            anchor.val = at
          }
          @widget.invalidate()
          true
        }
        @widget.PointerKind::Move => {
          if dragging.val {
            let lay = layout_at(text_of(), self.rect.w)
            ed.select_range(anchor.val, lay.hit(ev.x, ev.y))
            @widget.invalidate()
          }
          dragging.val
        }
        @widget.PointerKind::Up => {
          dragging.val = false
          false
        }
        @widget.PointerKind::Leave => false
      }
    })
    w.on_scroll = Some(fn(ev : @widget.ScrollEvent) -> Bool {
      let before = st.offset
      st.scroll_by(0.0 - ev.dy * line_h * 3.0)
      st.offset != before
    })
    w.im_context = Some(fn() -> (String, Int)? {
      Some((ed.get_text(), ed.caret_pos()))
    })
    w.im_cursor = Some(fn(self : @widget.Widget) -> @base.Rect? {
      let lay = layout_at(text_of(), self.rect.w)
      let caret = ed.caret_pos()
      Some({
        x: self.rect.x + lay.caret_x(caret),
        y: self.rect.y + lay.caret_y(caret),
        w: 1.0,
        h: line_h,
      })
    })
    // 滚动条：视口的绝对定位子控件（贴右缘、压在文字之上，才吃得到命中）
    w.append_child(scroll_bar(st))
    scroll_bar_hover(w, st)
    // Store 被外部改动时回灌内核（内核才是文本权威）
    let sid = store.subscribe_id(fn(t : String) -> Unit {
      if t != ed.get_text() {
        ed.set_text(t)
        @widget.invalidate()
      }
    })
    @base.sub_bag_register(fn() { store.remove(sid) })
    fold_style(
      w,
      @style.empty_style(),
      @style.style(background_color="bg_panel", border_color="border", border_width=1.0, color="text_regular").focus(border_color="primary"),
      class,
    )
    handle(w)
    w
  })
}
