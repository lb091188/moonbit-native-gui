// 代码编辑器（code_editor）：等宽 + 高亮 + 行号 + 编辑合体（P1）。
//
// 三积木拼装（proposals/code-stack.md 定案二）：`@input.Editor` 是文本唯一
// 权威（编辑/选区/撤销/剪贴板/IME 五接缝与 textarea 同源）；`CodeScan` 是
// 行级增量着色缓存（前缀/后缀对齐 + 渐进扫描，见 code_editor_scan.mbt）；
// 命中与光标坐标按等宽逻辑行现算——代码行不折（与 code_view 同一口径），
// 超宽行交横向滚动，所以不走折行 `TextLayout`。
//
// 与 textarea 的分工：textarea=比例字体纯文本；code_editor=等宽+高亮+行号。
// 与 code_view 的分工：code_view=静态只读预排版；code_editor=编辑态增量。
//
// 滚动：纵向/横向共用一个 `ScrollState`（textarea 的纵向画层平移 + scroll_view
// 的横向画层平移同款，偏移不进布局，绘制期 `坐标 - offset` 现算）；滚动条是
// 视口的绝对定位子控件（贴右缘/底缘，压在内容之上才吃得到命中）。
//
// 底色跟 `CodeTheme`（主题深浅各一套，与 code_view 同源）；描边/焦点框走样式
// 槽（class 可覆盖）。Tab 插入两格缩进（编辑区吃掉 Tab，不做焦点跳转）。

///|
/// 行首到行内字节列 `col` 的宽（逐码点真值量，CJK 不按等宽踩坑）。
fn code_prefix_w(doc : CodeScan, row : Int, col : Int, font : @text.Font) -> Double {
  text_width(byte_slice(doc.line_at(row), 0, col), font)
}

///|
/// 控件内 x（内容系，已含横滚回补）→ 行内字节列：逐码点量前缀取不超过 x 的
/// 最右码点边界。`content_x` 是行内容坐标（不含行号列与横滚偏移）。
fn code_col_at(doc : CodeScan, row : Int, content_x : Double, font : @text.Font) -> Int {
  let line = doc.line_at(row)
  let b = @utf8.encode(line)
  let n = b.length()
  let mut at = 0
  let mut w = 0.0
  while at < n {
    let mut next = at + 1
    while next < n && (b[next].to_int() & 0xc0) == 0x80 {
      next = next + 1
    }
    let cw = text_width(byte_slice(line, at, next), font)
    if w + cw <= content_x {
      w = w + cw
      at = next
    } else {
      break
    }
  }
  at
}

///|
/// 代码编辑器。文本经 `store` 双向投影；`lang` 走 code_view 的语言表
/// （"moonbit" 缺省，另支持 js/ts/python/rust/c/go/bash/sql）。
pub fn code_editor(
  /// 双向绑定这段文本。
  store : @base.Store[String],
  /// 高亮语言（code_view 的关键字表同名）。
  lang? : String = "moonbit",
  /// 设字号（逻辑像素，等宽字族）。
  font_size? : Double = 13.0,
  /// 行号列（默认开）。
  line_numbers? : Bool = true,
  /// 设为只读：可选中不可改。
  read_only? : Bool = false,
  /// 按行数撑出初始高度（height 优先）。
  rows? : Int = 12,
  /// 定死高度，0 = 按 rows。
  height? : Double = 0.0,
  /// 进 Tab 焦点链的序号；传正数才可 Tab 到，0 = 自动领号。
  focus_id? : Int = 0,
  /// 决定光标是否可见的谓词。
  caret_on? : () -> Bool = fn() -> Bool { true },
  /// 值变化时回调（每次编辑给全文）。
  on_change? : (String) -> Unit = fn(_s : String) -> Unit { () },
  /// 挂命名样式类（`class_of([...])`）；类排在散参数之后，覆盖散参数。
  class? : Array[@style.Style] = [],
  /// 挂载后把宿主 Widget 句柄交给调用方（逃生舱）。
  handle? : (@widget.Widget) -> Unit = default_handle,
) -> @widget.Node {
  let ed = @input.Editor::new()
  attach_system_clipboard(ed)
  ed.set_undo_limit(100)
  let _ = ed.insert_text(store.get())
  let doc = CodeScan::new(store.get(), lang)
  let font = @text.Font::new("Monospace", font_size)
  let line_h = (@text.line_height_font(font).unwrap_or(18).to_double() + 5.0).max(14.0)
  let pad_top = 4.0
  let ro = read_only
  let is_mac = @shell.platform_is_macos()
  let change_cb = on_change
  let want_numbers = line_numbers
  let st = ScrollState::new()
  // 行号列宽随行数档位走（每次绘制现算，命中/光标同一来源）
  let digit_w = text_width("8", font)
  let text_pad = 4.0
  let gutter_of = fn() -> Double {
    if want_numbers {
      let digits = doc.line_count().to_string().length().max(2)
      digit_w * digits.to_double() + 16.0
    } else {
      0.0
    }
  }
  let text_left = fn() -> Double {
    gutter_of() + text_pad
  }
  // 全文字节号 → 控件内坐标（已扣滚动偏移）
  let caret_xy = fn(caret : Int) -> (Double, Double) {
    let row = doc.row_of(caret)
    let col = caret - doc.start_of(row)
    (
      text_left() + code_prefix_w(doc, row, col, font) - st.offset_x,
      pad_top + row.to_double() * line_h - st.offset,
    )
  }
  // 控件内坐标 → 全文字节号
  let hit_at = fn(x : Double, y : Double) -> Int {
    let n = doc.line_count()
    let row = (((y - pad_top + st.offset) / line_h).floor().to_int()).clamp(
      min=0,
      max=n - 1,
    )
    let content_x = x - text_left() + st.offset_x
    doc.start_of(row) + code_col_at(doc, row, content_x, font)
  }
  // 把插入点滚进可视区（键入、点击、移动后都调）
  let ensure_caret = fn() -> Unit {
    let caret = ed.caret_pos()
    let row = doc.row_of(caret)
    let top = row.to_double() * line_h
    if top < st.offset {
      st.set_offset(top)
    } else if top + line_h > st.offset + st.view_h {
      st.set_offset(top + line_h - st.view_h)
    }
    let col = caret - doc.start_of(row)
    let cx = code_prefix_w(doc, row, col, font)
    let vis = (st.view_w - text_left() - 12.0).max(20.0)
    if cx < st.offset_x + 16.0 {
      st.set_offset_x((cx - 16.0).max(0.0))
    } else if cx > st.offset_x + vis {
      st.set_offset_x(cx - vis)
    }
    @widget.invalidate()
  }
  let push = fn() -> Unit {
    let t = ed.get_text()
    let _ = doc.sync(t)
    store.set(t)
    change_cb(t)
  }
  let box_h = if height > 0.0 {
    height
  } else {
    line_h * rows.to_double() + pad_top * 2.0
  }
  @widget.node_of_new(fn(w : @widget.Widget) -> @widget.Widget {
    watch_theme()
    w.role = "code_editor"
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
    w.node.set_width(@yoga.percent(100.0))
    w.node.set_height(@yoga.fixed(box_h))
    w.node.set_min_height(@yoga.fixed(0.0))
    // 纵向移动一行（上下键与 PageUp/Down 共用）：按起算 x 落列，短行不漂
    let move_row = fn(ev : @widget.KeyEvent, r : @base.Rect) -> Unit {
      let caret = ed.caret_pos()
      let row = doc.row_of(caret)
      let x = if pref_x.val >= 0.0 {
        pref_x.val
      } else {
        caret_xy(caret).0 - text_left() + st.offset_x
      }
      let step = if ev.keysym == 65365 || ev.keysym == 65366 {
        ((r.h - pad_top * 2.0) / line_h).floor().to_int().max(1)
      } else {
        1
      }
      let j = if ev.keysym == @base.KS_UP || ev.keysym == 65365 {
        row - step
      } else {
        row + step
      }
      let n = doc.line_count()
      if j < 0 || j >= n {
        pref_x.val = -1.0
        return
      }
      let at = doc.start_of(j) + code_col_at(doc, j, x, font)
      pref_x.val = x
      if (ev.mods & @base.MOD_SHIFT) != 0 {
        let a = match ed.selection() {
          Some((s, _)) => s
          None => caret
        }
        ed.select_range(a, at)
      } else {
        ed.select_range(at, at)
      }
      anchor.val = at
      ensure_caret()
      @widget.invalidate()
    }
    w.on_draw = Some(fn(
      self : @widget.Widget,
      p : @render.Painter,
      r : @base.Rect,
    ) -> Unit {
      let ct = code_theme_current()
      // 几何抄进状态（滚动条比例与夹取都用它）
      st.view_h = r.h
      st.content_h = doc.line_count().to_double() * line_h + pad_top * 2.0
      st.view_w = r.w
      st.content_w = (doc.max_width() + text_left() + 24.0).max(r.w)
      let gl = gutter_of()
      let tl = text_left()
      let sty = @style.style_for(self)
      let rad = @style.number_of(sty.border_radius, @theme.radius_ctrl())
      self.clip_rounded = rad > 0.0
      self.style_clip_radius = rad
      // 底色跟 CodeTheme（深浅各一套，与 code_view 同源）；描边/焦点走样式槽
      p.set_fill_color(ct.bg)
      if rad > 0.0 {
        p.fill_round_rect(0.0, 0.0, r.w, r.h, rad)
      } else {
        p.fill_rect(0.0, 0.0, r.w, r.h)
      }
      let sel = ed.selection()
      let caret = ed.caret_pos()
      let n = doc.line_count()
      let first = ((st.offset / line_h).floor().to_int()).clamp(min=0, max=n - 1)
      let last = (((st.offset + r.h - pad_top) / line_h).ceil().to_int()).clamp(
        min=0,
        max=n - 1,
      )
      doc.ensure(last)
      // 选区高亮（铺在 token 之下）
      match sel {
        Some((s, e)) =>
          for row = first; row <= last; row = row + 1 {
            let rs = doc.start_of(row)
            let re_ = rs + doc.len_of(row)
            let a = s.max(rs)
            let b = e.min(re_)
            if b > a {
              let y = pad_top + row.to_double() * line_h - st.offset
              let x0 = code_prefix_w(doc, row, a - rs, font)
              let x1 = code_prefix_w(doc, row, b - rs, font)
              p.set_fill_color(@theme.theme_primary_light())
              p.fill_rect(
                (tl - st.offset_x + x0).max(gl),
                y,
                (x1 - x0).max(1.0),
                line_h,
              )
            }
          }
        None => ()
      }
      // 行号 + token（裁剪到文本区，横向滚动时不压行号列）
      p.save()
      p.clip_rect(gl, 0.0, (r.w - gl).max(0.0), r.h)
      for row = first; row <= last; row = row + 1 {
        let y = pad_top + row.to_double() * line_h - st.offset
        if y + line_h < 0.0 || y > r.h {
          continue
        }
        if want_numbers {
          let num = (row + 1).to_string()
          let nw = text_width(num, font)
          let _ = @text.draw_box_at(
            p,
            gl - 8.0 - nw,
            y,
            nw + 2.0,
            line_h,
            num,
            font,
            ct.line_no,
            align=@text.Start,
            valign=@text.Center,
            wrap=false,
          )
        }
        let toks = doc.tokens_of(row)
        let laid = doc.measure_row(row, font)
        let mut x = tl - st.offset_x
        for i = 0; i < toks.length(); i = i + 1 {
          let tw = if i < laid.length() { laid[i] } else { 0.0 }
          if x + tw >= gl && x <= r.w && tw > 0.0 {
            let _ = @text.draw_box_at(
              p,
              x,
              y,
              tw + 4.0,
              line_h,
              toks[i].text,
              font,
              role_color(ct, toks[i].role),
              align=@text.Start,
              valign=@text.Center,
              wrap=false,
            )
          }
          x = x + tw
        }
      }
      p.restore()
      // 光标与组合串
      let (cx, cy) = caret_xy(caret)
      let pe = ed.preedit_text()
      if pe.length() > 0 {
        let _ = @text.draw_at(p, cx, cy, pe, font, @theme.theme_warning())
        let pw = text_width(pe, font)
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
      let meta = (ev.mods & @base.MOD_META) != 0
      let primary = if is_mac { meta } else { ctrl }
      if ev.keysym == @base.KS_RETURN {
        if ro {
          return false
        }
        let _ = ed.insert_text("\n")
        pref_x.val = -1.0
        push()
        ensure_caret()
        @widget.invalidate()
        return true
      }
      if ev.keysym == @base.KS_UP ||
        ev.keysym == @base.KS_DOWN ||
        ev.keysym == 65365 ||
        ev.keysym == 65366 {
        // PageUp/PageDown（65365/65366）：按可视行数翻页
        move_row(ev, w.rect)
        return true
      }
      if !ctrl && !meta && (ev.keysym == @base.KS_HOME || ev.keysym == @base.KS_END) {
        let caret = ed.caret_pos()
        let row = doc.row_of(caret)
        let at = if ev.keysym == @base.KS_HOME {
          doc.start_of(row)
        } else {
          doc.start_of(row) + doc.len_of(row)
        }
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
        ensure_caret()
        @widget.invalidate()
        return true
      }
      // Tab 在编辑区插入两格缩进（Shift+Tab 反缩进归 P2，此处不消费走焦点链）
      if ev.keysym == @base.KS_TAB && !shift && !ro {
        let _ = ed.insert_text("  ")
        push()
        ensure_caret()
        @widget.invalidate()
        return true
      }
      let editing = ev.keysym == @base.KS_BACKSPACE || ev.keysym == @base.KS_DELETE
      // 只读时导航与复制照旧：带 Ctrl/Cmd 的组合要放行（mac 的选全、复制靠 Cmd）
      let nav = primary ||
        shift ||
        (ev.keysym >= 65360 && ev.keysym <= 65367) ||
        ev.keysym == @base.KS_TAB
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
        ensure_caret()
        @widget.invalidate()
      }
      handled
    })
    w.on_commit = Some(fn(t : String) -> Bool {
      let _ = ed.insert_text(t)
      push()
      ensure_caret()
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
              can_copy=true,
              changed=fn() -> Unit {
                push()
                ensure_caret()
                @widget.invalidate()
              },
            )
          }
          let now = @shell.now_ms()
          let dbl = (now - last_down.val) < 400L &&
            (ev.x - last_xy.val.0).abs() < 4.0 &&
            (ev.y - last_xy.val.1).abs() < 4.0
          last_down.val = now
          last_xy.val = (ev.x, ev.y)
          dragging.val = true
          pref_x.val = -1.0
          let at = hit_at(ev.x, ev.y)
          if dbl {
            let (s, e) = word_range(ed.get_text(), at)
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
            ed.select_range(anchor.val, hit_at(ev.x, ev.y))
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
      // 横向分量先走（触控板横滑/滚轮 dx），有横滚余量时消费掉
      if ev.dx != 0.0 && st.max_x() > 0.0 {
        let bx = st.offset_x
        st.set_offset_x(bx - ev.dx * 30.0)
        if st.offset_x != bx {
          return true
        }
      }
      let before = st.offset
      st.scroll_by(0.0 - ev.dy * line_h * 3.0)
      st.offset != before
    })
    w.im_context = Some(fn() -> (String, Int)? {
      Some((ed.get_text(), ed.caret_pos()))
    })
    w.im_cursor = Some(fn(self : @widget.Widget) -> @base.Rect? {
      let (cx, cy) = caret_xy(ed.caret_pos())
      Some({
        x: self.rect.x + cx,
        y: self.rect.y + cy,
        w: 1.0,
        h: line_h,
      })
    })
    // 滚动条：视口的绝对定位子控件（纵贴右缘、横贴底缘，压在内容之上）
    w.append_child(scroll_bar(st))
    w.append_child(scroll_bar_h(st))
    scroll_bar_hover(w, st)
    // Store 被外部改动时回灌内核（内核才是文本权威）
    let sid = store.subscribe_id(fn(t : String) -> Unit {
      if t != ed.get_text() {
        ed.set_text(t)
        let _ = doc.sync(t)
        @widget.invalidate()
      }
    })
    @base.sub_bag_register(fn() { store.remove(sid) })
    fold_style(
      w,
      @style.empty_style(),
      @style.style(border_color="border", border_width=1.0).focus(border_color="primary"),
      class,
    )
    handle(w)
    w
  })
}
