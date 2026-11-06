// 终端模型（terminal 控件的数据面）：等宽 cell 网格 + 光标 + 回看滚动。
// 用法：`Terminal::new` 建模型 → `feed` 喂文本 → `terminal()` 控件显示
// （terminal_draw.mbt）；转义序列解析在 terminal_ansi.mbt，本文件只认
// C0 控制符与可打印字符。方案与测试切分见 proposals/terminal-sfc-dx.md §1。

///|
/// 终端色：默认前景/背景、ANSI 索引（0..255，16..231 走 6×6×6 立方）、真彩色。
pub(all) enum TermColor {
  Default
  Indexed(Int)
  Rgb(Int, Int, Int)
} derive(Eq, Debug)

///|
pub extend TermColor with Eq::{equal, not_equal}

///|
pub extend TermColor with Debug::{to_repr}

///|
/// 终端单元格：一个等宽格。零宽字符拼进前一格的 text；宽字符占两格，
/// 第二格 `cont=true`（绘制与取文本时跳过）。字段仅包内可见。
pub struct TermCell {
  mut text : String
  mut wide : Bool
  mut cont : Bool
  mut fg : TermColor
  mut bg : TermColor
  mut attrs : Int
}

///|
/// 回看环形缓冲：定长槽位 + 起点下标，满时覆盖最旧一行（避免整体搬移）。
pub struct ScrollRing {
  slots : Array[Array[TermCell]?]
  mut start : Int
  mut count : Int
}

///|
fn ScrollRing::new(capacity : Int) -> ScrollRing {
  let slots : Array[Array[TermCell]?] = []
  for _ in 0..<capacity.max(1) {
    slots.push(None)
  }
  { slots, start: 0, count: 0 }
}

///|
fn ScrollRing::len(self : ScrollRing) -> Int {
  self.count
}

///|
/// 压入一行快照（满时覆盖最旧）。
fn ScrollRing::push(self : ScrollRing, row : Array[TermCell]) -> Unit {
  let cap = self.slots.length()
  let at = (self.start + self.count) % cap
  self.slots[at] = Some(row)
  if self.count < cap {
    self.count += 1
  } else {
    self.start = (self.start + 1) % cap
  }
}

///|
/// 第 i 行（0 = 最旧）。
fn ScrollRing::get(self : ScrollRing, i : Int) -> Array[TermCell]? {
  if i < 0 || i >= self.count {
    return None
  }
  self.slots[(self.start + i) % self.slots.length()]
}

///|
fn ScrollRing::clear(self : ScrollRing) -> Unit {
  self.start = 0
  self.count = 0
}

///|
/// 终端模型：屏幕网格 + 光标/滚动区/笔色 + 回看偏移。可无头使用——不进控件树
/// 也能 feed 后用 `text()` / `cursor()` 断言；控件经包内 `revision()` 订阅重绘。
pub struct Terminal {
  mut cols : Int
  mut rows : Int
  /// 屏幕行（rows × cols，行定长）
  mut screen : Array[Array[TermCell]]
  ring : ScrollRing
  /// 距底部行数（0 = 贴底）
  mut view_offset : Int
  mut cx : Int
  mut cy : Int
  mut saved_cx : Int
  mut saved_cy : Int
  /// 末列打印后挂起待折（下一次打印先换行）
  mut pending_wrap : Bool
  mut autowrap : Bool
  mut cursor_visible : Bool
  /// 滚动区（闭区间行下标）
  mut scroll_top : Int
  mut scroll_bottom : Int
  /// 当前笔色/属性（SGR 落点，打印时写入 cell）
  mut pen_fg : TermColor
  mut pen_bg : TermColor
  mut pen_attrs : Int
  /// ANSI 解析器状态（跨 feed 保留半截序列）
  ansi : AnsiState
  rev : @base.Store[Int]
}

///|
/// 建终端：`cols/rows` 网格尺寸，`scrollback` 回看容量（行数）。
pub fn Terminal::new(
  cols? : Int = 80,
  rows? : Int = 24,
  scrollback? : Int = 1000,
) -> Terminal {
  let c = cols.max(1)
  let r = rows.max(1)
  let screen : Array[Array[TermCell]] = []
  for _ in 0..<r {
    screen.push(new_row(c, Default))
  }
  {
    cols: c,
    rows: r,
    screen,
    ring: ScrollRing::new(scrollback),
    view_offset: 0,
    cx: 0,
    cy: 0,
    saved_cx: 0,
    saved_cy: 0,
    pending_wrap: false,
    autowrap: true,
    cursor_visible: true,
    scroll_top: 0,
    scroll_bottom: r - 1,
    pen_fg: Default,
    pen_bg: Default,
    pen_attrs: 0,
    ansi: AnsiState::new(),
    rev: @base.Store::new(0),
  }
}

///|
fn Terminal::bump(self : Terminal) -> Unit {
  self.rev.update_always(fn(v) { v + 1 })
}

///|
fn new_row(cols : Int, bg : TermColor) -> Array[TermCell] {
  let row : Array[TermCell] = []
  for _ in 0..<cols {
    row.push({ text: "", wide: false, cont: false, fg: Default, bg, attrs: 0 })
  }
  row
}

///|
/// 喂一段文本：可打印字符进网格，C0 控制符（\n \r \b \t BEL）按终端语义处理，
/// 其余控制字节忽略。跨调用保留状态；调用方保证一次喂进来的是完整 UTF-8。
/// 口径：`\n` = 回行首 + 下移（日志源都是裸 \n，不做 VT 的「只下移留列」，
/// 进度条类重画走 \r 不受影响）；ESC 转义序列由 terminal_ansi.mbt 接手。
pub fn Terminal::feed(self : Terminal, text : String) -> Unit {
  if text.length() == 0 {
    return
  }
  for ch in text {
    if self.ansi.mode != ANSI_GROUND {
      self.ansi_char(ch)
      continue
    }
    if ch == '\u{1b}' {
      self.ansi.mode = ANSI_ESC
      continue
    }
    match ch {
      '\n' => {
        self.cx = 0
        self.linefeed()
      }
      '\r' => {
        self.cx = 0
        self.pending_wrap = false
      }
      '\b' =>
        if self.cx > 0 {
          self.cx -= 1
          self.pending_wrap = false
        }
      '\t' => {
        self.pending_wrap = false
        let next = (self.cx / 8 + 1) * 8
        self.cx = if next >= self.cols { self.cols - 1 } else { next }
      }
      c if c.to_int() < 0x20 => () // BEL / 其余 C0：忽略
      c => self.print_char(c)
    }
  }
  self.bump()
}

///|
/// 下移一行：在滚动区底则区内上滚，否则向下走（不到网格底不越界）。
fn Terminal::linefeed(self : Terminal) -> Unit {
  self.pending_wrap = false
  if self.cy == self.scroll_bottom {
    self.scroll_up(1)
  } else if self.cy < self.rows - 1 {
    self.cy += 1
  }
}

///|
/// 滚动区内上滚 n 行：整屏滚动时离开区顶的行进回看，否则只在区内轮转。
fn Terminal::scroll_up(self : Terminal, n : Int) -> Unit {
  let full = self.scroll_top == 0 && self.scroll_bottom == self.rows - 1
  for _ in 0..<n {
    let top_row = self.screen[self.scroll_top]
    if full {
      self.ring.push(top_row)
      if self.view_offset > 0 {
        // 回看变长时不拽走视口：贴底偏移保持（内容整体变旧一格）
        self.view_offset += 1
      }
    }
    for i in self.scroll_top..<self.scroll_bottom {
      self.screen[i] = self.screen[i + 1]
    }
    self.screen[self.scroll_bottom] = new_row(self.cols, self.pen_bg)
  }
}

///|
/// 落笔前清掉被压住的宽字符另一半（按旧状态判断，避免误清新写内容）。
fn wipe_at(row : Array[TermCell], at : Int) -> Unit {
  let cell = row[at]
  if cell.cont && at > 0 {
    let p = row[at - 1]
    if p.wide {
      p.text = ""
      p.wide = false
      p.cont = false
    }
    cell.cont = false
  } else if cell.wide && at + 1 < row.length() {
    let n = row[at + 1]
    if n.cont {
      n.text = ""
      n.wide = false
      n.cont = false
    }
    cell.wide = false
  }
}

///|
fn Terminal::print_char(self : Terminal, ch : Char) -> Unit {
  let w = term_char_width(ch)
  if w == 0 {
    // 零宽（组合记号等）：拼进前一格；pending_wrap 时前一格是本行最后一列
    let at = if self.pending_wrap { self.cols - 1 } else { self.cx - 1 }
    if at >= 0 && at < self.cols {
      let cell = self.screen[self.cy][at]
      cell.text = cell.text + ch.to_string()
    }
    return
  }
  if self.pending_wrap {
    self.pending_wrap = false
    self.cx = 0
    self.linefeed()
  }
  if w == 2 && self.cx >= self.cols - 1 {
    // 末列放不下宽字符：换行再放（xterm 口径）
    self.cx = 0
    self.linefeed()
  }
  let row = self.screen[self.cy]
  wipe_at(row, self.cx)
  let cell = row[self.cx]
  cell.text = ch.to_string()
  cell.wide = w == 2
  cell.cont = false
  cell.fg = self.pen_fg
  cell.bg = self.pen_bg
  cell.attrs = self.pen_attrs
  if w == 2 {
    let nxt = row[self.cx + 1]
    if nxt.wide && self.cx + 2 < self.cols {
      // 续格自己原本是别的宽字符首格：它的续格在 cx+2，一并清掉
      let nn = row[self.cx + 2]
      if nn.cont {
        nn.text = ""
        nn.wide = false
        nn.cont = false
      }
    }
    nxt.text = ""
    nxt.wide = false
    nxt.cont = true
    nxt.fg = self.pen_fg
    nxt.bg = self.pen_bg
    nxt.attrs = self.pen_attrs
    self.cx += 2
  } else {
    self.cx += 1
  }
  if self.cx >= self.cols {
    if self.autowrap {
      self.cx = self.cols
      self.pending_wrap = true
    } else {
      self.cx = self.cols - 1
    }
  }
}

///|
/// 改网格尺寸：保留左上交集内容，光标与滚动区钳进新范围；不做重排
/// （已写内容不重新折行）。尺寸没变则不动。
pub fn Terminal::resize(self : Terminal, cols : Int, rows : Int) -> Unit {
  let c = cols.max(1)
  let r = rows.max(1)
  if c == self.cols && r == self.rows {
    return
  }
  let screen : Array[Array[TermCell]] = []
  for ri in 0..<r {
    let row = new_row(c, Default)
    if ri < self.rows {
      let old = self.screen[ri]
      let keep = c.min(self.cols)
      for ci in 0..<keep {
        row[ci] = old[ci]
      }
    }
    screen.push(row)
  }
  self.screen = screen
  self.cols = c
  self.rows = r
  self.cx = self.cx.min(c - 1)
  self.cy = self.cy.min(r - 1)
  self.scroll_bottom = self.scroll_bottom.min(r - 1)
  if self.scroll_bottom < self.scroll_top {
    self.scroll_top = 0
    self.scroll_bottom = r - 1
  }
  self.pending_wrap = false
  self.bump()
}

///|
/// 清当前屏：网格重铺空白、光标回左上；回看与滚动区保留。
pub fn Terminal::clear(self : Terminal) -> Unit {
  for ri in 0..<self.rows {
    self.screen[ri] = new_row(self.cols, self.pen_bg)
  }
  self.cx = 0
  self.cy = 0
  self.pending_wrap = false
  self.bump()
}

///|
/// 全复位：屏幕、回看、光标、滚动区、笔色/属性、折行与光标可见全部回缺省。
pub fn Terminal::reset(self : Terminal) -> Unit {
  self.ring.clear()
  self.view_offset = 0
  self.scroll_top = 0
  self.scroll_bottom = self.rows - 1
  self.autowrap = true
  self.cursor_visible = true
  self.saved_cx = 0
  self.saved_cy = 0
  self.pen_fg = Default
  self.pen_bg = Default
  self.pen_attrs = 0
  self.ansi.clear()
  self.clear()
}

///|
/// 回看滚动：正数往上看，0 不动；越界钳到回看区首尾。
pub fn Terminal::scroll_lines(self : Terminal, n : Int) -> Unit {
  if n == 0 {
    return
  }
  let target = (self.view_offset + n).clamp(min=0, max=self.ring.len())
  if target != self.view_offset {
    self.view_offset = target
    self.bump()
  }
}

///|
pub fn Terminal::scroll_to_bottom(self : Terminal) -> Unit {
  self.scroll_lines(-self.view_offset)
}

///|
/// 视口是否贴底（view_offset == 0）。
pub fn Terminal::is_bottom(self : Terminal) -> Bool {
  self.view_offset == 0
}

///|
pub fn Terminal::cols(self : Terminal) -> Int {
  self.cols
}

///|
pub fn Terminal::rows(self : Terminal) -> Int {
  self.rows
}

///|
/// 光标列行（0 基；pending_wrap 时列钳在末列）。
pub fn Terminal::cursor(self : Terminal) -> (Int, Int) {
  (self.cx.min(self.cols - 1), self.cy)
}

///|
/// 回看区 + 当前屏的纯文本：每行去尾随空格、行间 \n；末尾连续空行不产出
/// （空白屏给空串），中间空行保留。
pub fn Terminal::text(self : Terminal) -> String {
  let lines : Array[String] = []
  for i in 0..<self.ring.len() {
    match self.ring.get(i) {
      Some(row) => lines.push(trim_end_spaces(row_text(row)))
      None => ()
    }
  }
  for row in self.screen {
    lines.push(trim_end_spaces(row_text(row)))
  }
  while lines.length() > 0 && lines[lines.length() - 1].length() == 0 {
    let _ = lines.remove(lines.length() - 1)
  }
  lines.join("\n")
}

///|
/// 指定格的前景色（越界回 Default）。调试与无头测试取数用；绘制走包内直读。
pub fn Terminal::cell_fg(self : Terminal, col : Int, row : Int) -> TermColor {
  self.cell_at(col, row).fg
}

///|
/// 指定格的背景色（越界回 Default）。
pub fn Terminal::cell_bg(self : Terminal, col : Int, row : Int) -> TermColor {
  self.cell_at(col, row).bg
}

///|
/// 指定格的属性位（bold/dim/italic/underline/inverse/strike 位掩码，越界回 0）。
pub fn Terminal::cell_attrs(self : Terminal, col : Int, row : Int) -> Int {
  self.cell_at(col, row).attrs
}

///|
fn Terminal::cell_at(self : Terminal, col : Int, row : Int) -> TermCell {
  let empty : TermCell = {
    text: "",
    wide: false,
    cont: false,
    fg: Default,
    bg: Default,
    attrs: 0,
  }
  if row < 0 || row >= self.rows || col < 0 || col >= self.cols {
    return empty
  }
  self.screen[row][col]
}

///|
fn row_text(row : Array[TermCell]) -> String {
  let sb = StringBuilder()
  for cell in row {
    if cell.cont {
      continue
    }
    if cell.text.length() == 0 {
      sb.write_char(' ')
    } else {
      sb.write_string(cell.text)
    }
  }
  sb.to_string()
}

///|
fn trim_end_spaces(s : String) -> String {
  let chars : Array[Char] = []
  for c in s {
    chars.push(c)
  }
  let mut end = chars.length()
  while end > 0 && chars[end - 1] == ' ' {
    end -= 1
  }
  let sb = StringBuilder()
  for i in 0..<end {
    sb.write_char(chars[i])
  }
  sb.to_string()
}

///|
/// 字符占格宽：0 = 零宽（组合记号/变体选择符，拼进前一格）、2 = 宽、1 = 普通。
/// CJK 判据与 mdview 的断行宽字符同源；emoji 平面按终端惯例记宽。
fn term_char_width(ch : Char) -> Int {
  let c = ch.to_int()
  if term_is_zero_width(c) {
    return 0
  }
  if term_is_wide(c) {
    return 2
  }
  1
}

///|
fn term_is_wide(c : Int) -> Bool {
  (c >= 0x1100 && c <= 0x115f) ||
  (c >= 0x2e80 && c <= 0x303e) ||
  (c >= 0x3041 && c <= 0x33ff) ||
  (c >= 0x3400 && c <= 0x4dbf) ||
  (c >= 0x4e00 && c <= 0x9fff) ||
  (c >= 0xa000 && c <= 0xa4cf) ||
  (c >= 0xac00 && c <= 0xd7a3) ||
  (c >= 0xf900 && c <= 0xfaff) ||
  (c >= 0xfe10 && c <= 0xfe19) ||
  (c >= 0xfe30 && c <= 0xfe6f) ||
  (c >= 0xff00 && c <= 0xff60) ||
  (c >= 0xffe0 && c <= 0xffe6) ||
  (c >= 0x1f300 && c <= 0x1f64f) ||
  (c >= 0x1f680 && c <= 0x1f6ff) ||
  (c >= 0x1f900 && c <= 0x1f9ff) ||
  (c >= 0x1fa00 && c <= 0x1faff) ||
  (c >= 0x20000 && c <= 0x2fffd) ||
  (c >= 0x30000 && c <= 0x3fffd)
}

///|
fn term_is_zero_width(c : Int) -> Bool {
  (c >= 0x0300 && c <= 0x036f) ||
  (c >= 0x200b && c <= 0x200f) ||
  (c >= 0x2060 && c <= 0x2064) ||
  (c >= 0x20d0 && c <= 0x20f0) ||
  (c >= 0xfe00 && c <= 0xfe0f) ||
  c == 0xfeff ||
  (c >= 0xe0100 && c <= 0xe01ef)
}
