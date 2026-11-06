// 终端 ANSI 解析器：ESC/CSI/OSC/DCS 状态机 + SGR 笔色 + 光标/擦除/滚动操作。
// 口径见 proposals/terminal-sfc-dx.md §1.5：OSC/DCS/PM/APC 整段丢弃（标题、
// 剪贴板、超链一律不消费）；半截序列跨 feed 保留；未知 CSI 静默忽略。

///|
const ANSI_GROUND : Int = 0
const ANSI_ESC : Int = 1
const ANSI_CSI : Int = 2
const ANSI_OSC : Int = 3
const ANSI_OSC_ESC : Int = 4
const ANSI_STR : Int = 5
const ANSI_STR_ESC : Int = 6
const ANSI_CHARSET : Int = 7
/// 超长 CSI：不再积攒参数，吞到 final 为止（防把残余参数当正文打印）。
const ANSI_CSI_SKIP : Int = 8

///|
/// SGR 属性位（cell.attrs 掩码）。
const TERM_ATTR_BOLD : Int = 1
const TERM_ATTR_DIM : Int = 2
const TERM_ATTR_ITALIC : Int = 4
const TERM_ATTR_UNDERLINE : Int = 8
const TERM_ATTR_INVERSE : Int = 16
const TERM_ATTR_STRIKE : Int = 32

/// CSI 参数积攒上限（防失控序列），超长整段丢弃。
const ANSI_PARAMS_MAX : Int = 128

///|
/// 解析器状态（跨 feed 保留）：当前模式与积攒中的 CSI 参数字节。
pub struct AnsiState {
  mut mode : Int
  mut params : String
}

///|
fn AnsiState::new() -> AnsiState {
  { mode: ANSI_GROUND, params: "" }
}

///|
fn AnsiState::clear(self : AnsiState) -> Unit {
  self.mode = ANSI_GROUND
  self.params = ""
}

///|
/// 空白格（擦除/新行用）：默认前景，背景取当前笔色（BCE 口径）。
fn blank_cell_bg(bg : TermColor) -> TermCell {
  { text: "", wide: false, cont: false, fg: Default, bg, attrs: 0 }
}

///|
/// 非 Ground 态的字符消费（含各模式间的转移）。
fn Terminal::ansi_char(self : Terminal, ch : Char) -> Unit {
  match self.ansi.mode {
    ANSI_ESC => {
      self.ansi.mode = ANSI_GROUND
      match ch {
        '[' => {
          self.ansi.mode = ANSI_CSI
          self.ansi.params = ""
        }
        ']' => self.ansi.mode = ANSI_OSC
        'P' | 'X' | '^' | '_' => self.ansi.mode = ANSI_STR
        '(' | ')' | '*' | '+' => self.ansi.mode = ANSI_CHARSET
        '7' => {
          self.saved_cx = self.cx
          self.saved_cy = self.cy
        }
        '8' => self.restore_cursor()
        'D' => self.linefeed() // IND：只下移留列
        'E' => {
          // NEL：回行首 + 下移
          self.cx = 0
          self.linefeed()
        }
        'M' => self.reverse_index()
        'c' => self.reset()
        _ => () // 未知单字节序列：忽略
      }
    }
    ANSI_CHARSET => () // 字符集指定符：吃掉一个字符即回 Ground（转移已在上面置回）
    ANSI_CSI => {
      let c = ch.to_int()
      if c >= 0x40 && c <= 0x7e {
        self.ansi.mode = ANSI_GROUND
        self.csi_dispatch(ch)
      } else if self.ansi.params.length() >= ANSI_PARAMS_MAX {
        // 超长序列：参数封顶，吞到 final 为止（不派发、不外泄）
        self.ansi.mode = ANSI_CSI_SKIP
      } else {
        self.ansi.params = self.ansi.params + ch.to_string()
      }
    }
    ANSI_CSI_SKIP => {
      // 吞到 final 字节为止
      let c = ch.to_int()
      if c >= 0x40 && c <= 0x7e {
        self.ansi.mode = ANSI_GROUND
      }
    }
    ANSI_OSC =>
      match ch {
        '\u{7}' => self.ansi.mode = ANSI_GROUND
        '\u{1b}' => self.ansi.mode = ANSI_OSC_ESC
        _ => () // OSC 内容整段丢弃（标题/剪贴板/超链不消费）
      }
    ANSI_OSC_ESC => {
      // ST（ESC \）或任何其他字节都结束 OSC
      self.ansi.mode = ANSI_GROUND
    }
    ANSI_STR =>
      match ch {
        '\u{7}' => self.ansi.mode = ANSI_GROUND
        '\u{1b}' => self.ansi.mode = ANSI_STR_ESC
        _ => ()
      }
    ANSI_STR_ESC => self.ansi.mode = ANSI_GROUND
    _ => self.ansi.mode = ANSI_GROUND
  }
}

///|
fn Terminal::restore_cursor(self : Terminal) -> Unit {
  self.cx = self.saved_cx.clamp(min=0, max=self.cols - 1)
  self.cy = self.saved_cy.clamp(min=0, max=self.rows - 1)
  self.pending_wrap = false
}

///|
/// 反向下移（ESC M / RI）：区顶则区内下滚，否则上移一格。
fn Terminal::reverse_index(self : Terminal) -> Unit {
  if self.cy == self.scroll_top {
    self.scroll_down(1)
  } else if self.cy > 0 {
    self.cy -= 1
  }
}

///|
/// 滚动区内下滚 n 行（SD / RI 在区顶触发）。
fn Terminal::scroll_down(self : Terminal, n : Int) -> Unit {
  for _ in 0..<n {
    let mut i = self.scroll_bottom
    while i > self.scroll_top {
      self.screen[i] = self.screen[i - 1]
      i -= 1
    }
    self.screen[self.scroll_top] = new_row(self.cols, self.pen_bg)
  }
}

///|
/// CSI 参数串 → 整数数组（`;`/`:` 分隔；空段与非数字段记 0；私有前缀字节忽略）。
fn csi_nums(s : String) -> Array[Int] {
  let out : Array[Int] = []
  let mut cur = 0
  let mut got = false
  for c in s {
    if c >= '0' && c <= '9' {
      cur = cur * 10 + (c.to_int() - '0'.to_int())
      got = true
    } else if c == ';' || c == ':' {
      out.push(if got { cur } else { 0 })
      cur = 0
      got = false
    }
    // 其余（'?' 私有标记、中间字节）忽略
  }
  out.push(if got { cur } else { 0 })
  out
}

///|
fn nums_at(nums : Array[Int], i : Int, default : Int) -> Int {
  if i < nums.length() {
    let v = nums[i]
    if v > 0 {
      return v
    }
  }
  default
}

///|
fn Terminal::csi_dispatch(self : Terminal, code : Char) -> Unit {
  let raw = self.ansi.params
  let body = if raw.has_prefix("?") {
    raw[1:].to_owned()
  } else {
    raw
  }
  let private = raw.has_prefix("?")
  let nums = csi_nums(body)
  match code {
    'A' => self.cursor_up(nums_at(nums, 0, 1))
    'B' => self.cursor_down(nums_at(nums, 0, 1))
    'C' => self.cursor_right(nums_at(nums, 0, 1))
    'D' => self.cursor_left(nums_at(nums, 0, 1))
    'E' => {
      self.cx = 0
      self.cursor_down(nums_at(nums, 0, 1))
    }
    'F' => {
      self.cx = 0
      self.cursor_up(nums_at(nums, 0, 1))
    }
    'G' => {
      self.cx = (nums_at(nums, 0, 1) - 1).clamp(min=0, max=self.cols - 1)
      self.pending_wrap = false
    }
    'H' | 'f' => {
      self.cx = (nums_at(nums, 1, 1) - 1).clamp(min=0, max=self.cols - 1)
      self.cy = (nums_at(nums, 0, 1) - 1).clamp(min=0, max=self.rows - 1)
      self.pending_wrap = false
    }
    'd' => {
      self.cy = (nums_at(nums, 0, 1) - 1).clamp(min=0, max=self.rows - 1)
      self.pending_wrap = false
    }
    'J' => self.erase_display(nums_at(nums, 0, 0))
    'K' => self.erase_line(nums_at(nums, 0, 0))
    'X' => self.erase_chars(nums_at(nums, 0, 1))
    '@' => self.insert_chars(nums_at(nums, 0, 1))
    'P' => self.delete_chars(nums_at(nums, 0, 1))
    'L' => self.insert_lines(nums_at(nums, 0, 1))
    'M' => self.delete_lines(nums_at(nums, 0, 1))
    'S' => self.scroll_up(nums_at(nums, 0, 1))
    'T' => self.scroll_down(nums_at(nums, 0, 1))
    'r' => {
      // DECSTBM：滚动区（1 基，闭区间）；游标回左上
      let top = (nums_at(nums, 0, 1) - 1).clamp(min=0, max=self.rows - 1)
      let bottom = (nums_at(nums, 1, self.rows) - 1).clamp(min=0, max=self.rows - 1)
      if top < bottom {
        self.scroll_top = top
        self.scroll_bottom = bottom
        self.cx = 0
        self.cy = 0
        self.pending_wrap = false
      }
    }
    'h' | 'l' =>
      if private {
        let on = code == 'h'
        for n in nums {
          match n {
            25 => self.cursor_visible = on
            7 => self.autowrap = on
            _ => () // 其余私有模式静默忽略
          }
        }
      }
    'm' => self.sgr(nums)
    's' => {
      self.saved_cx = self.cx
      self.saved_cy = self.cy
    }
    'u' => self.restore_cursor()
    _ => () // 未知 final：忽略
  }
}

///|
fn Terminal::cursor_up(self : Terminal, n : Int) -> Unit {
  let floor = if self.cy >= self.scroll_top { self.scroll_top } else { 0 }
  self.cy = (self.cy - n).max(floor)
  self.pending_wrap = false
}

///|
fn Terminal::cursor_down(self : Terminal, n : Int) -> Unit {
  let ceiling = if self.cy <= self.scroll_bottom { self.scroll_bottom } else { self.rows - 1 }
  self.cy = (self.cy + n).min(ceiling)
  self.pending_wrap = false
}

///|
fn Terminal::cursor_left(self : Terminal, n : Int) -> Unit {
  self.cx = (self.cx - n).max(0)
  self.pending_wrap = false
}

///|
fn Terminal::cursor_right(self : Terminal, n : Int) -> Unit {
  self.cx = (self.cx + n).min(self.cols - 1)
  self.pending_wrap = false
}

///|
/// ED：0=光标到屏尾、1=屏首到光标、2=整屏、3=整屏并清回看。
fn Terminal::erase_display(self : Terminal, mode : Int) -> Unit {
  match mode {
    0 => {
      self.erase_line(0)
      for ri in (self.cy + 1)..<self.rows {
        self.screen[ri] = new_row(self.cols, self.pen_bg)
      }
    }
    1 => {
      for ri in 0..<self.cy {
        self.screen[ri] = new_row(self.cols, self.pen_bg)
      }
      self.erase_line(1)
    }
    3 => self.ring.clear()
    _ => {
      // 2（及未知值）：整屏重铺
      for ri in 0..<self.rows {
        self.screen[ri] = new_row(self.cols, self.pen_bg)
      }
    }
  }
}

///|
/// EL：0=光标到行尾、1=行首到光标（含光标格）、2=整行。
fn Terminal::erase_line(self : Terminal, mode : Int) -> Unit {
  let row = self.screen[self.cy]
  match mode {
    0 =>
      for ci in self.cx..<self.cols {
        row[ci] = blank_cell_bg(self.pen_bg)
      }
    1 =>
      for ci in 0..=(self.cx.min(self.cols - 1)) {
        row[ci] = blank_cell_bg(self.pen_bg)
      }
    _ =>
      for ci in 0..<self.cols {
        row[ci] = blank_cell_bg(self.pen_bg)
      }
  }
}

///|
/// ECH：从光标起擦 n 格（光标不动）。
fn Terminal::erase_chars(self : Terminal, n : Int) -> Unit {
  let row = self.screen[self.cy]
  let end = (self.cx + n).min(self.cols)
  for ci in self.cx..<end {
    row[ci] = blank_cell_bg(self.pen_bg)
  }
}

///|
/// ICH：光标处插 n 个空白格，行内右移溢出丢弃。
fn Terminal::insert_chars(self : Terminal, n : Int) -> Unit {
  let row = self.screen[self.cy]
  let mut at = self.cols - 1
  while at >= self.cx + n {
    row[at] = row[at - n]
    at -= 1
  }
  let end = (self.cx + n).min(self.cols)
  for ci in self.cx..<end {
    row[ci] = blank_cell_bg(self.pen_bg)
  }
}

///|
/// DCH：光标处删 n 格，行内左移、尾部补空白。
fn Terminal::delete_chars(self : Terminal, n : Int) -> Unit {
  let row = self.screen[self.cy]
  let mut at = self.cx
  while at + n < self.cols {
    row[at] = row[at + n]
    at += 1
  }
  for ci in at..<self.cols {
    row[ci] = blank_cell_bg(self.pen_bg)
  }
}

///|
/// IL：光标行起在滚动区内插 n 行（光标在区外不动作）。
fn Terminal::insert_lines(self : Terminal, n : Int) -> Unit {
  if self.cy < self.scroll_top || self.cy > self.scroll_bottom {
    return
  }
  for _ in 0..<n {
    let mut i = self.scroll_bottom
    while i > self.cy {
      self.screen[i] = self.screen[i - 1]
      i -= 1
    }
    self.screen[self.cy] = new_row(self.cols, self.pen_bg)
  }
}

///|
/// DL：光标行起在滚动区内删 n 行（光标在区外不动作）。
fn Terminal::delete_lines(self : Terminal, n : Int) -> Unit {
  if self.cy < self.scroll_top || self.cy > self.scroll_bottom {
    return
  }
  for _ in 0..<n {
    let mut i = self.cy
    while i < self.scroll_bottom {
      self.screen[i] = self.screen[i + 1]
      i += 1
    }
    self.screen[self.scroll_bottom] = new_row(self.cols, self.pen_bg)
  }
}

///|
/// SGR：笔色与属性。38/48 的扩展档（5;n / 2;r;g;b）连带消费后续参数。
fn Terminal::sgr(self : Terminal, nums : Array[Int]) -> Unit {
  let n = nums.length()
  let mut i = 0
  while i < n {
    let v = nums[i]
    if v == 38 || v == 48 {
      let mut advanced = false
      if i + 1 < n {
        match nums[i + 1] {
          5 =>
            if i + 2 < n {
              let idx = nums[i + 2].clamp(min=0, max=255)
              if v == 38 {
                self.pen_fg = Indexed(idx)
              } else {
                self.pen_bg = Indexed(idx)
              }
              i += 2
              advanced = true
            }
          2 =>
            if i + 4 < n {
              let r = nums[i + 2].clamp(min=0, max=255)
              let g = nums[i + 3].clamp(min=0, max=255)
              let b = nums[i + 4].clamp(min=0, max=255)
              if v == 38 {
                self.pen_fg = Rgb(r, g, b)
              } else {
                self.pen_bg = Rgb(r, g, b)
              }
              i += 4
              advanced = true
            }
          _ => ()
        }
      }
      if !advanced {
        // 残缺扩展序列：这一条 SGR 剩余参数整段作废（xterm 口径：坏 38/48
        // 不回落逐位解析，否则 2/1/5 会被误读成属性位）
        i = n
      }
    } else {
      match v {
        0 => {
          self.pen_fg = Default
          self.pen_bg = Default
          self.pen_attrs = 0
        }
        1 => self.pen_attrs = self.pen_attrs | TERM_ATTR_BOLD
        2 => self.pen_attrs = self.pen_attrs | TERM_ATTR_DIM
        3 => self.pen_attrs = self.pen_attrs | TERM_ATTR_ITALIC
        4 => self.pen_attrs = self.pen_attrs | TERM_ATTR_UNDERLINE
        7 => self.pen_attrs = self.pen_attrs | TERM_ATTR_INVERSE
        9 => self.pen_attrs = self.pen_attrs | TERM_ATTR_STRIKE
        22 => self.pen_attrs = self.pen_attrs.land(TERM_ATTR_BOLD.lor(TERM_ATTR_DIM).lnot())
        23 => self.pen_attrs = self.pen_attrs.land(TERM_ATTR_ITALIC.lnot())
        24 => self.pen_attrs = self.pen_attrs.land(TERM_ATTR_UNDERLINE.lnot())
        27 => self.pen_attrs = self.pen_attrs.land(TERM_ATTR_INVERSE.lnot())
        29 => self.pen_attrs = self.pen_attrs.land(TERM_ATTR_STRIKE.lnot())
        fg if fg >= 30 && fg <= 37 => self.pen_fg = Indexed(fg - 30)
        39 => self.pen_fg = Default
        bg if bg >= 40 && bg <= 47 => self.pen_bg = Indexed(bg - 40)
        49 => self.pen_bg = Default
        fg if fg >= 90 && fg <= 97 => self.pen_fg = Indexed(fg - 90 + 8)
        bg if bg >= 100 && bg <= 107 => self.pen_bg = Indexed(bg - 100 + 8)
        _ => () // 未知 SGR：忽略
      }
    }
    i += 1
  }
}
