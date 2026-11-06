// 终端控件（绘制面）：TermTheme 配色 + 等宽网格绘制 + 光标 + 滚动条 + 选区。
// 模型在 terminal.mbt、解析在 terminal_ansi.mbt、按键映射在 terminal_input.mbt。
// 几何口径：cell_w = 等宽 "M" 测宽、cell_h = line_height + 2、内边距 6。

///|
/// 终端配色：默认前景/背景、光标、选区、16 色 ANSI 盘（0-7 常规，8-15 亮色）。
/// ANSI 是设备直接色值，不走 CodeTheme 语义角色；深浅基底各一套内置盘。
pub(all) struct TermTheme {
  fg : String
  bg : String
  cursor : String
  selection : String
  ansi : Array[String]
}

///|
/// 深底 ANSI 盘（黑位提亮保证可辨）。
fn term_ansi_dark() -> Array[String] {
  [
    "#4b5263", "#e06c75", "#98c379", "#e5c07b", "#61afef", "#c678dd",
    "#56b6c2", "#abb2bf", "#5c6370", "#ff7b86", "#b5e890", "#ffd48a",
    "#7cc4ff", "#d9a0ea", "#7cd9e6", "#e6e6e6",
  ]
}

///|
/// 浅底 ANSI 盘（白位压暗保证可辨）。
fn term_ansi_light() -> Array[String] {
  [
    "#3a3f46", "#c0392b", "#1f8f4e", "#9a6a00", "#2d68c4", "#8e44ad",
    "#199fb0", "#7f8c8d", "#55595f", "#d64550", "#2e9e5b", "#b8860b",
    "#5b8def", "#a55bc4", "#0f8a9e", "#3a3f46",
  ]
}

///|
/// 从主题派生终端配色：按 bg_panel 亮度判深浅基底（与 code_theme_of 同判据）。
pub fn term_theme_of(t : @theme.Theme) -> TermTheme {
  let dark = match @theme.parse_hex(t.bg_panel) {
    Some((r, g, b)) =>
      (0.299 * r.to_double() + 0.587 * g.to_double() + 0.114 * b.to_double()) /
      255.0 < 0.5
    None => false
  }
  if dark {
    {
      fg: t.text_primary,
      bg: "#141821",
      cursor: t.primary,
      selection: t.primary_light,
      ansi: term_ansi_dark(),
    }
  } else {
    {
      fg: t.text_primary,
      bg: t.bg_panel,
      cursor: t.primary,
      selection: t.primary_light,
      ansi: term_ansi_light(),
    }
  }
}

///|
/// 当前主题的终端配色（绘制期现取的默认源）。
pub fn term_theme_current() -> TermTheme {
  term_theme_of(@theme.theme_current())
}

///|
/// 256 色立方/灰度阶（xterm 口径）。
fn term_cube_level(i : Int) -> Int {
  let levels = [0, 95, 135, 175, 215, 255]
  levels[i]
}

///|
/// TermColor → hex（Indexed 16..231 走 6×6×6 立方、232..255 走灰度）。
fn term_color_hex(tt : TermTheme, c : TermColor, is_fg : Bool) -> String {
  match c {
    Default => if is_fg { tt.fg } else { tt.bg }
    Indexed(i) =>
      if i >= 0 && i < 16 {
        tt.ansi[i]
      } else if i < 232 {
        let n = i - 16
        term_rgb_hex(
          term_cube_level(n / 36),
          term_cube_level((n % 36) / 6),
          term_cube_level(n % 6),
        )
      } else if i < 256 {
        let v = 8 + (i - 232) * 10
        term_rgb_hex(v, v, v)
      } else {
        if is_fg { tt.fg } else { tt.bg }
      }
    Rgb(r, g, b) => term_rgb_hex(r, g, b)
  }
}

///|
fn term_rgb_hex(r : Int, g : Int, b : Int) -> String {
  @render.Color::rgb(
    r.clamp(min=0, max=255),
    g.clamp(min=0, max=255),
    b.clamp(min=0, max=255),
  ).to_hex()
}

///|
/// hex 颜色按比例混合（dim 档把前景往背景压）。
fn term_blend_hex(a : String, b : String, k : Double) -> String {
  match (@render.Color::parse(a), @render.Color::parse(b)) {
    (Some(ca), Some(cb)) => {
      let f = fn(x : Int, y : Int) -> Int {
        (x.to_double() * (1.0 - k) + y.to_double() * k).round().to_int()
      }
      @render.Color::rgb(f(ca.r, cb.r), f(ca.g, cb.g), f(ca.b, cb.b)).to_hex()
    }
    _ => a
  }
}

///|
/// 终端控件：尺寸跟随布局（width 100%；`height` 0 = flex_grow 撑满剩余）。
/// 网格列行数在绘制期按控件矩形现算并回写 `term.resize`。
pub fn terminal(
  term : Terminal,
  /// 字号（逻辑像素，等宽字族）。
  font_size? : Double = 13.0,
  /// 定死高度；0 = flex_grow 撑满容器剩余空间。
  height? : Double = 0.0,
  /// 进 Tab 焦点链的序号；传正数才可 Tab 到，0 = 自动领号。
  focus_id? : Int = 0,
  /// 光标闪烁（聚焦时）；false 常亮。
  blink? : Bool = true,
  /// 应用接管光标可见性时给谓词；给了就完全按它画，不走内部 blink。
  cursor_on? : (() -> Bool)? = None,
  /// 开关鼠标选区（拖选高亮）。
  selectable? : Bool = true,
  /// 终端配色；缺省跟当前主题。
  theme? : TermTheme = term_theme_current(),
  /// 挂命名样式类（`class_of([...])`）；类排在散参数之后，覆盖散参数。
  class? : Array[@style.Style] = [],
  /// 挂载后把宿主 Widget 句柄交给调用方（逃生舱）。
  handle? : (@widget.Widget) -> Unit = default_handle,
) -> @widget.Node {
  let font = @text.Font::new("Monospace", font_size)
  let font_bold = @text.Font::new("Monospace", font_size, weight=@text.FontWeight::Bold)
  let font_italic = @text.Font::new("Monospace", font_size, style=@text.FontStyle::Italic)
  let font_bold_italic = @text.Font::new(
    "Monospace",
    font_size,
    weight=@text.FontWeight::Bold,
    style=@text.FontStyle::Italic,
  )
  let cell_w = text_width("M", font).max(1.0)
  let cell_h = match @text.line_height_font(font) {
    Some(h) => (h.to_double() + 2.0).max(14.0)
    None => (font_size * 1.7).max(14.0)
  }
  let pad = 6.0
  let tt = theme
  let want_blink = blink
  let selectable = selectable
  // 选区：绝对行号坐标（col, abs），跨滚动稳定
  let sel_anchor : Ref[(Int, Int)?] = Ref(None)
  let sel_head : Ref[(Int, Int)?] = Ref(None)
  let dragging : Ref[Bool] = Ref(false)
  let dragging_sb : Ref[Bool] = Ref(false)
  let blink_on : Ref[Bool] = Ref(true)
  let timer_id : Ref[Int] = Ref(0)
  let timer_alive : Ref[Bool] = Ref(false)
  @widget.node_of_new(fn(w : @widget.Widget) -> @widget.Widget {
    w.role = "terminal"
    w.node.set_width(@yoga.percent(100.0))
    if height > 0.0 {
      w.node.set_height(@yoga.fixed(height))
    } else {
      w.node.set_flex_grow(1.0)
      w.node.set_min_height(@yoga.fixed(80.0))
    }
    w.focus_id = auto_focus_id(focus_id)
    // 模型一变就重绘（feed/resize/滚动都 bump）
    let rev_sig = term.revision()
    let sid = rev_sig.subscribe(fn(_v) { @widget.invalidate() })
    @base.sub_bag_register(fn() { rev_sig.remove(sid) })
    // 光标闪烁：自重排定时器；不 paints 停表，回到视口由 on_draw 复活
    let tick : Ref[() -> Unit] = Ref(fn() { () })
    let arm = fn() -> Unit {
      timer_alive.val = true
      timer_id.val = @shell.set_timeout(530, tick.val)
    }
    tick.val = fn() -> Unit {
      timer_alive.val = false
      if !w.is_painted() {
        return
      }
      blink_on.val = !blink_on.val
      @widget.invalidate()
      arm()
    }
    if want_blink && cursor_on is None {
      arm()
      @base.sub_bag_register(fn() {
        let _ = @shell.clear_timeout(timer_id.val)
        timer_alive.val = false
      })
    }
    // 命中 → (列, 绝对行)
    let hit_cell = fn(x : Double, y : Double) -> (Int, Int)? {
      let col = (((x - pad) / cell_w).floor().to_int()).clamp(
        min=0,
        max=term.cols() - 1,
      )
      let v = (((y - pad) / cell_h).floor().to_int()).clamp(
        min=0,
        max=term.rows() - 1,
      )
      match term.view_abs(v) {
        Some(a) => Some((col, a))
        None => None
      }
    }
    let sel_range = fn() -> ((Int, Int), (Int, Int))? {
      match (sel_anchor.val, sel_head.val) {
        (Some(a), Some(h)) =>
          if a.1 < h.1 || (a.1 == h.1 && a.0 <= h.0) {
            Some((a, h))
          } else {
            Some((h, a))
          }
        _ => None
      }
    }
    let sb_geom = fn(rw : Double, rh : Double) -> (Double, Double, Double, Double, Double) {
      // (track_x, track_y, track_w, track_h, thumb_len)
      let sh = (rh - 4.0).max(0.0)
      let content = (term.ring.len() + term.rows()).max(1)
      let thumb = ((term.rows().to_double() / content.to_double()) * sh).max(
        24.0,
      ).min(sh)
      (rw - 9.0, 2.0, 5.0, sh, thumb)
    }
    w.on_draw = Some(fn(self_w : @widget.Widget, p : @render.Painter, r : @base.Rect) -> Unit {
      let st = @style.resolved(self_w)
      let bg_hex = @style.color_of(st.background_color, tt.bg)
      // 网格随矩形现算（resize 内部判同不做重复 bump）
      let cols = (((r.w - 2.0 * pad) / cell_w).floor().to_int()).max(2)
      let rows = (((r.h - 2.0 * pad) / cell_h).floor().to_int()).max(1)
      term.resize(cols, rows)
      let cols = term.cols()
      let rows = term.rows()
      p.set_fill_color(bg_hex)
      p.fill_rect(0.0, 0.0, r.w, r.h)
      let sel = sel_range()
      let ring_len = term.ring.len()
      let top_abs = term.view_top_abs()
      // 逐行 → 逐 run（同 fg/bg/attrs/选中 合并一次画）
      for li in 0..<rows {
        let abs = top_abs + li
        let row = match term.row_by_abs(abs) {
          Some(row) => row
          None => continue
        }
        let y = pad + li.to_double() * cell_h
        let mut ci = 0
        while ci < cols {
          let cell = row[ci]
          if cell.cont {
            ci += 1
            continue
          }
          let attrs = cell.attrs
          let mut fg_hex = term_color_hex(tt, cell.fg, true)
          let mut bg_hex_c = term_color_hex(tt, cell.bg, false)
          if attrs.land(TERM_ATTR_INVERSE) != 0 {
            let t2 = fg_hex
            fg_hex = bg_hex_c
            bg_hex_c = t2
          }
          if attrs.land(TERM_ATTR_DIM) != 0 {
            fg_hex = term_blend_hex(fg_hex, bg_hex_c, 0.45)
          }
          let selected = match sel {
            Some((a, b2)) =>
              abs >= a.1 && abs <= b2.1 && ci >= (if abs == a.1 { a.0 } else { 0 }) &&
              ci < (if abs == b2.1 { b2.0 + 1 } else { cols })
            None => false
          }
          // run 向右合并（同色同属性同选中态；遇宽字符跨两格）
          let mut end = ci
          let mut width_cells = 0
          while end < cols {
            let c2 = row[end]
            if c2.cont {
              break
            }
            let a2 = c2.attrs
            let mut f2 = term_color_hex(tt, c2.fg, true)
            let mut g2 = term_color_hex(tt, c2.bg, false)
            if a2.land(TERM_ATTR_INVERSE) != 0 {
              let t3 = f2
              f2 = g2
              g2 = t3
            }
            if a2.land(TERM_ATTR_DIM) != 0 {
              f2 = term_blend_hex(f2, g2, 0.45)
            }
            let sel2 = match sel {
              Some((a, b3)) =>
                abs >= a.1 && abs <= b3.1 && end >= (if abs == a.1 { a.0 } else { 0 }) &&
                end < (if abs == b3.1 { b3.0 + 1 } else { cols })
              None => false
            }
            if f2 != fg_hex || g2 != bg_hex_c || a2 != attrs || sel2 != selected {
              break
            }
            width_cells += if c2.wide { 2 } else { 1 }
            end += 1
          }
          if width_cells == 0 {
            // 当前格是宽字符首格但 run 被截断的情况不会发生；0 只在异常时兜底
            width_cells = 1
          }
          let rx = pad + ci.to_double() * cell_w
          let rw = width_cells.to_double() * cell_w
          if selected {
            p.set_fill_color(tt.selection)
            p.fill_rect(rx, y, rw, cell_h)
          } else if bg_hex_c != bg_hex {
            p.set_fill_color(bg_hex_c)
            p.fill_rect(rx, y, rw, cell_h)
          }
          if cell.text.length() > 0 {
            let f = match (
              attrs.land(TERM_ATTR_BOLD) != 0,
              attrs.land(TERM_ATTR_ITALIC) != 0,
            ) {
              (true, true) => font_bold_italic
              (true, false) => font_bold
              (false, true) => font_italic
              (false, false) => font
            }
            let _ = @text.draw_at(p, rx, y + 1.0, cell.text, f, fg_hex)
          }
          if attrs.land(TERM_ATTR_UNDERLINE) != 0 {
            p.set_fill_color(fg_hex)
            p.fill_rect(rx, y + cell_h - 2.0, rw, 1.0)
          }
          if attrs.land(TERM_ATTR_STRIKE) != 0 {
            p.set_fill_color(fg_hex)
            p.fill_rect(rx, y + cell_h * 0.55, rw, 1.0)
          }
          ci = end
        }
      }
      // 光标：聚焦实心块（反白当前格），失焦空心框；闪烁按谓词/内部状态
      let cursor_show = match cursor_on {
        Some(f) => f()
        None => blink_on.val
      }
      if term.cursor_visible && cursor_show {
        let (cc, cr) = term.cursor()
        let cabs = term.abs_of_screen(cr)
        if cabs >= top_abs && cabs < top_abs + rows {
          let ly = cabs - top_abs
          let crow = term.screen[cr]
          let ccell = crow[cc]
          let cw = (if ccell.wide { 2.0 } else { 1.0 }) * cell_w
          let cx0 = pad + cc.to_double() * cell_w
          let cy0 = pad + ly.to_double() * cell_h
          if self_w.focused {
            p.set_fill_color(tt.cursor)
            p.fill_rect(cx0, cy0, cw, cell_h)
            if ccell.text.length() > 0 {
              let _ = @text.draw_at(
                p,
                cx0,
                cy0 + 1.0,
                ccell.text,
                font,
                bg_hex,
              )
            }
          } else {
            p.set_stroke_color(tt.cursor)
            p.set_line_width(1.0)
            p.stroke_rect(cx0 + 0.5, cy0 + 0.5, cw - 1.0, cell_h - 1.0)
          }
        }
      }
      // 滚动条：有回看内容才画
      if ring_len > 0 {
        let (sx2, sy2, _sw2, sh2, thumb) = sb_geom(r.w, r.h)
        let ratio = term.view_offset.to_double() / ring_len.to_double()
        let ty2 = sy2 + ratio * (sh2 - thumb)
        p.set_fill_color(term_blend_hex(tt.fg, bg_hex, 0.85))
        p.fill_rect(sx2, sy2, 5.0, sh2)
        p.set_fill_color(term_blend_hex(tt.fg, bg_hex, 0.45))
        p.fill_rect(sx2, ty2, 5.0, thumb)
      }
      // 描边（样式槽可覆盖）
      let border_hex = @style.color_of(st.border_color, @theme.theme_border())
      match st.border_width {
        Some(bw) =>
          if bw > 0.0 {
            p.set_stroke_color(border_hex)
            p.set_line_width(bw)
            p.stroke_rect(0.5, 0.5, r.w - 1.0, r.h - 1.0)
          }
        None => ()
      }
      // 闪烁表停了（曾被挪出视口）且现在画得到：复活
      if want_blink && cursor_on is None && !timer_alive.val && self_w.is_painted() {
        arm()
      }
    })
    w.on_scroll = Some(fn(ev : @widget.ScrollEvent) -> Bool {
      // dy 正 = 向上滚（看更早的内容）
      if term.ring.len() == 0 {
        return false
      }
      let lines = (ev.dy * 3.0).to_int()
      if lines == 0 && ev.dy != 0.0 {
        term.scroll_lines(if ev.dy > 0.0 { 1 } else { -1 })
        return true
      }
      if lines != 0 {
        term.scroll_lines(lines)
        return true
      }
      false
    })
    w.on_pointer = Some(fn(self_w : @widget.Widget, ev : @widget.PointerEvent) -> Bool {
      match ev.kind {
        @widget.PointerKind::Down => {
          if ev.x >= self_w.rect.w - 12.0 && term.ring.len() > 0 {
            // 滚动条：点按/拖动跳位
            dragging_sb.val = true
            let (_, sy2, _sw2, sh2, thumb) = sb_geom(self_w.rect.w, self_w.rect.h)
            let ratio = ((ev.y - sy2 - thumb / 2.0) / (sh2 - thumb).max(1.0)).clamp(min=0.0, max=1.0)
            let target = (ratio * term.ring.len().to_double()).round().to_int()
            term.scroll_lines(target - term.view_offset)
            return true
          }
          if selectable && ev.button == 1 {
            dragging.val = true
            let hit = hit_cell(ev.x, ev.y)
            sel_anchor.val = hit
            sel_head.val = hit
            @widget.invalidate()
            return true
          }
          false
        }
        @widget.PointerKind::Move => {
          if dragging_sb.val {
            let (_, sy2, _sw2, sh2, thumb) = sb_geom(self_w.rect.w, self_w.rect.h)
            let ratio = ((ev.y - sy2 - thumb / 2.0) / (sh2 - thumb).max(1.0)).clamp(min=0.0, max=1.0)
            let target = (ratio * term.ring.len().to_double()).round().to_int()
            term.scroll_lines(target - term.view_offset)
            return true
          }
          if dragging.val && selectable {
            match hit_cell(ev.x, ev.y) {
              Some(h) =>
                if sel_head.val != Some(h) {
                  sel_head.val = Some(h)
                  @widget.invalidate()
                }
              None => ()
            }
            return true
          }
          false
        }
        @widget.PointerKind::Up => {
          if dragging_sb.val {
            dragging_sb.val = false
            return true
          }
          if dragging.val {
            dragging.val = false
            return true
          }
          false
        }
        _ => false
      }
    })
    fold_style(
      w,
      @style.empty_style(),
      @style.style(background_color="bg_panel", border_color="border", border_width=1.0).focus(
        border_color="primary",
      ),
      class,
    )
    handle(w)
    w
  })
}
