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
/// on_key 关键拍落 stdout：`LIBYUE_CODEEDIT_LOG` / `NATIVEGUI_CODEEDIT_LOG`
/// 任一设了就打印（真机取证「按键进没进控件、焦点在不在、修饰码是什么」）。
fn codeedit_diag(msg : String) -> Unit {
  let on = match @sys.sys_getenv("LIBYUE_CODEEDIT_LOG") {
    Some(_) => true
    None => @sys.sys_getenv("NATIVEGUI_CODEEDIT_LOG") is Some(_)
  }
  if on {
    println("[codeedit] \{msg}")
  }
}

///|
/// 行首到行内字节列 `col` 的宽：**逐码点累积**（与 `code_col_at` 同一条链，
/// 点击定位与光标/选区绘制才不会因「整串一次量 vs 逐码点累加」的分叉错位）。
fn code_prefix_w(doc : CodeScan, row : Int, col : Int, font : @text.Font) -> Double {
  let line = doc.line_at(row)
  let b = @utf8.encode(line)
  let n = b.length()
  let mut at = 0
  let mut w = 0.0
  while at < col && at < n {
    let mut next = at + 1
    while next < n && (b[next].to_int() & 0xc0) == 0x80 {
      next = next + 1
    }
    w = w + text_width(byte_slice(line, at, next), font)
    at = next
  }
  w
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
/// 自动缩进：Enter 后新行的行首空白——继承上一行行首空白；上一行去掉尾随
/// 空白后以 `(`/`[`/`{` 结尾再进一格（两空格）。
fn code_auto_indent(line : String) -> String {
  let b = @utf8.encode(line)
  let n = b.length()
  let mut i = 0
  while i < n && (b[i].to_int() == 0x20 || b[i].to_int() == 0x09) {
    i = i + 1
  }
  let indent = @utf8.decode_lossy(b[0:i])
  let mut j = n - 1
  while j >= 0 && b[j].to_int() == 0x20 {
    j = j - 1
  }
  let last = if j >= 0 { b[j].to_int() } else { -1 }
  if last == 40 || last == 91 || last == 123 {
    indent + "  "
  } else {
    indent
  }
}

///|
/// 查找全部匹配：ASCII 大小写不敏感逐字节比对（多字节序列不会误配——
/// UTF-8 各字节 ≥ 0x80 原样比较）；空 query 给空表。
fn find_all_matches(text : String, query : String) -> Array[(Int, Int)] {
  let out : Array[(Int, Int)] = []
  let q = @utf8.encode(query)
  let m = q.length()
  if m == 0 {
    return out
  }
  let t = @utf8.encode(text)
  let n = t.length()
  let lower = fn(v : Int) -> Int {
    if v >= 65 && v <= 90 {
      v + 32
    } else {
      v
    }
  }
  let ql : Array[Int] = []
  for i in 0..<m {
    ql.push(lower(q[i].to_int()))
  }
  for i = 0; i + m <= n; i = i + 1 {
    let mut ok = true
    let mut j = 0
    while ok && j < m {
      if lower(t[i + j].to_int()) != ql[j] {
        ok = false
      }
      j = j + 1
    }
    if ok {
      out.push((i, i + m))
    }
  }
  out
}

///|
/// 括号匹配：caret 处字符是开括号 → 向后找配对闭括号；caret 前一字符是
/// 闭括号 → 向前找配对开括号。字符串/注释 token 内的括号不参与；两侧各限
/// 400 行，找不到给 None。返回 (开括号字节号, 闭括号字节号)。
fn code_bracket_pair(doc : CodeScan, caret : Int) -> (Int, Int)? {
  let n = doc.line_count()
  let anchor_row = doc.row_of(caret)
  doc.ensure((anchor_row + 400).min(n - 1))
  let col0 = caret - doc.start_of(anchor_row)
  let is_open = fn(v : Int) -> Bool { v == 40 || v == 91 || v == 123 }
  let is_close = fn(v : Int) -> Bool { v == 41 || v == 93 || v == 125 }
  let close_of = fn(v : Int) -> Int {
    match v {
      40 => 41
      91 => 93
      _ => 125
    }
  }
  let open_of = fn(v : Int) -> Int {
    match v {
      41 => 40
      93 => 91
      _ => 123
    }
  }
  let line_bytes = fn(row : Int) -> Bytes {
    @utf8.encode(doc.line_at(row))
  }
  let skipped = fn(byte : Int) -> Bool {
    match doc.role_at(byte) {
      Some(StrLit) | Some(Comment) => true
      _ => false
    }
  }
  let g = fn(row : Int, col : Int) -> Int {
    doc.start_of(row) + col
  }
  // 锚点口径：caret 处是开括号 → 向后找闭；caret 前一字符是闭括号 → 向前
  // 找开；caret 前一字符是开括号 → 也向后找闭（紧贴开括号右侧高亮配对，
  // 编辑器通例）。
  let b0 = line_bytes(anchor_row)
  let c0 = if col0 < b0.length() { b0[col0].to_int() } else { -1 }
  let mut frow = anchor_row
  let mut fcol = col0
  let mut fbyte = caret
  let mut fopen = c0
  let mut backward : (Int, Int, Int)? = None
  if caret > 0 {
    let prow = doc.row_of(caret - 1)
    let pcol = caret - 1 - doc.start_of(prow)
    let bp = line_bytes(prow)
    let cp = if pcol < bp.length() { bp[pcol].to_int() } else { -1 }
    if !is_open(c0) && is_open(cp) {
      frow = prow
      fcol = pcol
      fbyte = caret - 1
      fopen = cp
    } else if is_close(cp) {
      backward = Some((prow, pcol, cp))
    }
  }
  if is_open(fopen) {
    // 锚点自身在字符串/注释里：不参与匹配
    if skipped(fbyte) {
      return None
    }
    let want = close_of(fopen)
    let mut depth = 0
    let hi = (frow + 400).min(n - 1)
    for r = frow; r <= hi; r = r + 1 {
      let b = line_bytes(r)
      let mut c = if r == frow { fcol } else { 0 }
      while c < b.length() {
        let v = b[c].to_int()
        if !skipped(g(r, c)) {
          if v == fopen {
            depth = depth + 1
          } else if v == want {
            depth = depth - 1
            if depth == 0 {
              return Some((fbyte, g(r, c)))
            }
          }
        }
        c = c + 1
        while c < b.length() && (b[c].to_int() & 0xc0) == 0x80 {
          c = c + 1
        }
      }
    }
    return None
  }
  // caret 前一字符是闭括号 → 向前找开
  match backward {
    Some((prow, pcol, cp)) => {
      // 锚点自身在字符串/注释里：不参与匹配
      if skipped(caret - 1) {
        return None
      }
      let want = open_of(cp)
      let mut depth = 0
      let lo = (prow - 400).max(0)
      let mut r = prow
      while r >= lo {
        let b = line_bytes(r)
        let mut c = if r == prow { pcol } else { b.length() - 1 }
        if c >= b.length() {
          c = b.length() - 1
        }
        // 对齐到码点首（从行尾起或锚点可能落中间）
        while c > 0 && (b[c].to_int() & 0xc0) == 0x80 {
          c = c - 1
        }
        while c >= 0 {
          let v = b[c].to_int()
          if !skipped(g(r, c)) {
            if v == cp {
              depth = depth + 1
            } else if v == want {
              depth = depth - 1
              if depth == 0 {
                return Some((g(r, c), caret - 1))
              }
            }
          }
          // 退到前一码点首
          c = c - 1
          while c > 0 && (b[c].to_int() & 0xc0) == 0x80 {
            c = c - 1
          }
        }
        r = r - 1
      }
    }
    None => ()
  }
  None
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
  // —— P2：查找与括号匹配的状态 ——
  let find_store = @base.Store::new("")
  let find_open = Ref(false)
  let find_matches : Ref[Array[(Int, Int)]] = Ref([])
  let find_cur = Ref(-1)
  let pair_key = Ref(-1)
  let pair_val : Ref[(Int, Int)?] = Ref(None)
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
    // —— 查找（P2）：浮层条 + 全文匹配高亮 + 上/下一个 ——
    let recompute_find = fn() -> Unit {
      find_matches.val = find_all_matches(ed.get_text(), find_store.get())
      find_cur.val = if find_matches.val.length() > 0 { 0 } else { -1 }
    }
    let jump_find = fn(dir : Int) -> Unit {
      let ms = find_matches.val
      if ms.length() == 0 {
        return
      }
      let cur = if find_cur.val < 0 {
        0
      } else {
        (find_cur.val + dir + ms.length()) % ms.length()
      }
      find_cur.val = cur
      let (a, b) = ms[cur]
      ed.select_range(a, b)
      ensure_caret()
      @widget.invalidate()
    }
    let close_find = fn() -> Unit {
      find_open.val = false
      find_matches.val = []
      find_cur.val = -1
      @widget.overlay_hide_top()
      @widget.invalidate()
    }
    let open_find = fn() -> Unit {
      find_open.val = true
      recompute_find()
      let pane = overlay_pane(
        [
          view(
            [
              input(
                find_store,
                width=150.0,
                placeholder="查找…",
                on_enter=fn() -> Unit { jump_find(1) },
              ),
              // 图标按钮（无默认底色、悬停浅底）：查找条要紧凑，普通按钮
              // 的底色与左右衬垫会把浮层撑出搜索框范围
              icon_button(
                @icons.ArrowUp,
                on_click=fn() -> Unit { jump_find(0 - 1) },
                icon_size=14.0,
                box_size=24.0,
              ),
              icon_button(
                @icons.ArrowDown,
                on_click=fn() -> Unit { jump_find(1) },
                icon_size=14.0,
                box_size=24.0,
              ),
              icon_button(
                @icons.Close2,
                on_click=close_find,
                icon_size=14.0,
                box_size=24.0,
              ),
            ],
            direction=@yoga.Row,
            column_gap=6.0,
            padding=8.0,
            align_items=@yoga.AlignItems::Center,
          ),
        ],
        268.0,
        0.0,
      )
      let _ = @widget.overlay_show_at(
        pane,
        w.rect.x + w.rect.w - 288.0,
        w.rect.y + 6.0,
      )
      @widget.invalidate()
    }
    let fsid = find_store.subscribe_id(fn(_q : String) -> Unit {
      if find_open.val {
        recompute_find()
        @widget.invalidate()
      }
    })
    @base.sub_bag_register(fn() { find_store.remove(fsid) })
    w.focus_id = auto_focus_id(focus_id)
    // Tab 是输入（两格缩进）：向宿主声明，别让焦点栈把 Tab 抢走
    w.wants_tab = true
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
      // 当前行高亮（聚焦时；画在选区与 token 之下）
      if self.focused && !off.off {
        let crow = doc.row_of(caret)
        let y = pad_top + crow.to_double() * line_h - st.offset
        p.set_fill_color(@theme.theme_fill_hover())
        p.fill_rect(gl, y, (r.w - gl).max(0.0), line_h)
      }
      // 括号匹配（P2）：caret 动了才重算
      if caret != pair_key.val {
        pair_key.val = caret
        pair_val.val = code_bracket_pair(doc, caret)
      }
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
      // 行号列（不进 clip：坐标在文本区左侧，裁剪区从 gl 起会把它们整列裁没）
      if want_numbers {
        for row = first; row <= last; row = row + 1 {
          let y = pad_top + row.to_double() * line_h - st.offset
          if y + line_h < 0.0 || y > r.h {
            continue
          }
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
      }
      // token（裁剪到文本区，横向滚动时不压行号列）
      p.save()
      p.clip_rect(gl, 0.0, (r.w - gl).max(0.0), r.h)
      // 查找匹配高亮（P2；token 之下，当前匹配更浓）
      if find_open.val {
        let ms = find_matches.val
        if ms.length() > 0 {
          let top_b = doc.start_of(first)
          let bot_b = doc.start_of(last) + doc.len_of(last)
          for i, m in ms {
            let (a, b) = m
            if b <= top_b || a > bot_b {
              continue
            }
            p.set_global_alpha(if i == find_cur.val { 0.55 } else { 0.26 })
            p.set_fill_color(@theme.theme_warning())
            for row = doc.row_of(a); row <= doc.row_of(b - 1); row = row + 1 {
              let rs = doc.start_of(row)
              let re_ = rs + doc.len_of(row)
              let lo = (a - rs).max(0)
              let hi2 = (b - rs).min(re_ - rs)
              if hi2 > lo {
                let y = pad_top + row.to_double() * line_h - st.offset
                let x0 = code_prefix_w(doc, row, lo, font)
                let x1 = code_prefix_w(doc, row, hi2, font)
                p.fill_rect(tl - st.offset_x + x0, y, (x1 - x0).max(1.0), line_h)
              }
            }
          }
          p.set_global_alpha(1.0)
        }
      }
      for row = first; row <= last; row = row + 1 {
        let y = pad_top + row.to_double() * line_h - st.offset
        if y + line_h < 0.0 || y > r.h {
          continue
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
      // 括号匹配标记（token 之上淡档块）
      match pair_val.val {
        Some((oa, ob)) =>
          for byte in [oa, ob] {
            let brow = doc.row_of(byte)
            if brow < first || brow > last {
              continue
            }
            let bcol = byte - doc.start_of(brow)
            let x0 = code_prefix_w(doc, brow, bcol, font)
            let x1 = code_prefix_w(doc, brow, bcol + 1, font)
            let y = pad_top + brow.to_double() * line_h - st.offset
            p.set_global_alpha(0.4)
            p.set_fill_color(@theme.theme_warning())
            p.fill_rect(tl - st.offset_x + x0, y, (x1 - x0).max(1.0), line_h)
            p.set_global_alpha(1.0)
          }
        None => ()
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
      codeedit_diag(
        "key keysym=\{ev.keysym} mods=\{ev.mods} press=\{ev.press} focused=\{w.focused} ro=\{ro}",
      )
      if !ev.press || off.off {
        return false
      }
      let shift = (ev.mods & @base.MOD_SHIFT) != 0
      let ctrl = (ev.mods & @base.MOD_CTRL) != 0
      let meta = (ev.mods & @base.MOD_META) != 0
      let primary = if is_mac { meta } else { ctrl }
      // 小键盘回车（KP_Enter，mac 桩给 65421）与主回车同档
      if ev.keysym == @base.KS_RETURN || ev.keysym == 65421 {
        if ro {
          return false
        }
        // 自动缩进：继承 caret 所在行的行首空白，开括号行再进一格
        let caret = ed.caret_pos()
        let indent = code_auto_indent(doc.line_at(doc.row_of(caret)))
        let _ = ed.insert_text("\n" + indent)
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
      // 主修饰键+F 开查找（只读也可用）；Esc 关
      let alt_on = (ev.mods & @base.MOD_ALT) != 0
      let other = if is_mac { ctrl || alt_on } else { meta || alt_on }
      if primary && !other && ev.keysym == 'f'.to_int() {
        open_find()
        return true
      }
      if ev.keysym == @base.KS_ESCAPE && find_open.val {
        close_find()
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
      codeedit_diag("key handled=\{handled} via=kernel")
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
