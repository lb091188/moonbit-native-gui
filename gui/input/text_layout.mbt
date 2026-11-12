// 文本偏移映射（TextLayout）：字节偏移 ↔ 屏幕几何。
//
// `Editor` 是编辑状态半边（文本、插入点、选区），这里是几何半边（显示行、命中、
// 光标位置）。两者都不碰平台桥：行宽由调用方注入的测宽函数给，于是这层能在无显示
// 环境下断言，绘制面与量版面天然同一份行模型。
//
// 下标口径全文统一：`text` 的 **UTF-8 字节下标**，与 `Editor` 的插入点/选区同源。

///|
/// 一行显示行：`start`/`end` 是全文的字节下标（`end` 不含行尾换行符），
/// `width` 是该行的自然宽度（画选区与命中换算都用它）。
pub(all) struct TextLine {
  start : Int32
  end : Int32
  width : Double
}

///|
/// 折行断点单位（纯函数）：空格连续成一段、拉丁词（字母数字下划线）连续成一段、
/// 其余 ASCII 标点连续成一段、非 ASCII 码点各自一段（中日韩因此可逐字断行）。
/// 段是「不可拆的最小块」，断行只发生在段边界。
pub fn wrap_units(
  text : String,
  from : Int32,
  to : Int32,
) -> Array[(Int32, Int32)] {
  let b = @utf8.encode(text)
  let n = b.length()
  let lo = if from < 0 { 0 } else if from > n { n } else { from }
  let hi = if to > n { n } else if to < lo { lo } else { to }
  let units : Array[(Int32, Int32)] = []
  let mut i = lo
  while i < hi {
    let v = b[i].to_int()
    let is_space = v == 0x20
    let is_word = (v >= 48 && v <= 57) ||
      (v >= 65 && v <= 90) ||
      (v >= 97 && v <= 122) ||
      v == 95
    let mut j = i + 1
    if v >= 0x80 {
      // 非 ASCII：一个码点即一段
      j = i + 1
      while j < hi && (b[j].to_int() & 0xc0) == 0x80 {
        j = j + 1
      }
    } else {
      let mut go = true
      while go && j < hi {
        let c = b[j].to_int()
        let same = if is_space {
          c == 0x20
        } else if is_word {
          (c >= 48 && c <= 57) ||
          (c >= 65 && c <= 90) ||
          (c >= 97 && c <= 122) ||
          c == 95
        } else {
          c >= 0x21 &&
          c <= 0x7e &&
          !((c >= 48 && c <= 57) ||
          (c >= 65 && c <= 90) ||
          (c >= 97 && c <= 122) ||
          c == 95)
        }
        if same {
          j = j + 1
        } else {
          go = false
        }
      }
    }
    units.push((i, j))
    i = j
  }
  units
}

///|
/// 显示行布局（纯函数）：先按 `\n` 切逻辑行，再把每行按 `width` 贪心折行。
/// 空文本也给一行（插入点要有家）；单个断点段比一行还宽时**不拆词**（宁可溢出，
/// 与 CSS 的 `overflow-wrap: normal` 同口径）。
/// `measure(text, from, to)` 给字节区间 `[from,to)` 的自然宽，由调用方注入。
pub fn layout_lines(
  text : String,
  width : Double,
  measure : (String, Int32, Int32) -> Double,
) -> Array[TextLine] {
  let b = @utf8.encode(text)
  let n = b.length()
  let avail = if width > 1.0 { width } else { 1.0 }
  let lines : Array[TextLine] = []
  let mut lo = 0
  let mut go = true
  while go {
    // 找这一逻辑行的末尾（下一个换行符之前）
    let mut k = lo
    let mut nl = -1
    while k < n {
      if b[k].to_int() == 0x0a {
        nl = k
        k = n
      } else {
        k = k + 1
      }
    }
    let to = if nl < 0 { n } else { nl }
    let units = wrap_units(text, lo, to)
    let mut start = lo
    let mut cur = 0.0
    for u in units {
      let uw = measure(text, u.0, u.1)
      if cur + uw > avail && u.0 > start {
        lines.push({ start, end: u.0, width: cur, })
        // 断行处不留行首空格：跳过被折断的那一段空格
        let mut s = u.0
        while s < u.1 && b[s].to_int() == 0x20 {
          s = s + 1
        }
        start = s
        cur = measure(text, s, u.1)
      } else {
        cur = cur + uw
      }
    }
    lines.push({ start, end: to, width: cur, })
    if nl < 0 {
      go = false
      lo = n
    } else {
      lo = nl + 1
      if lo > n {
        go = false
      }
    }
  }
  lines
}

///|
/// 字节下标落在第几行（越界夹到首末行）。
pub fn line_of_caret(lines : Array[TextLine], at : Int32) -> Int32 {
  let n = lines.length()
  if n == 0 {
    0
  } else {
    let mut i = 0
    while i < n {
      if at <= lines[i].end {
        return i
      }
      i = i + 1
    }
    n - 1
  }
}

///|
/// 一段文本的显示几何：文本 + 行模型 + 内边距 + 行高 + 垂直滚动偏移 + 测宽器。
/// 由 `build` 折出行，之后 `hit`/`caret_x`/`caret_y` 都按这份行模型答，绘制与命中
/// 因此不会分叉。`offset_y` 是内容已滚出去的距离，无滚动传 0。
pub(all) struct TextLayout {
  text : String
  lines : Array[TextLine]
  pad : Double
  line_h : Double
  offset_y : Double
  measure : (String, Int32, Int32) -> Double
}

///|
/// 按可用宽 `width` 折好一段文本（`pad` 是文本起点内边距，`line_h` 由调用方按字体
/// 定；两者与 `offset_y` 一起决定像素↔字节的换算）。
pub fn TextLayout::build(
  text : String,
  width : Double,
  measure : (String, Int32, Int32) -> Double,
  line_h : Double,
  pad~ : Double = 0.0,
  offset_y~ : Double = 0.0,
) -> TextLayout {
  let inner = if width - pad * 2.0 > 1.0 { width - pad * 2.0 } else { 1.0 }
  {
    text,
    lines: layout_lines(text, inner, measure),
    pad,
    line_h,
    offset_y,
    measure,
  }
}

///|
/// 字节下标落在第几显示行（越界夹到首末行）。
pub fn TextLayout::line_of(self : TextLayout, at : Int32) -> Int32 {
  line_of_caret(self.lines, at)
}

///|
/// 插入点的 x（控件内坐标）。
pub fn TextLayout::caret_x(self : TextLayout, at : Int32) -> Double {
  let i = self.line_of(at)
  if i < self.lines.length() {
    self.pad + (self.measure)(self.text, self.lines[i].start, at)
  } else {
    self.pad
  }
}

///|
/// 插入点的 y（控件内坐标，已扣掉滚动偏移）。
pub fn TextLayout::caret_y(self : TextLayout, at : Int32) -> Double {
  self.pad + self.line_of(at).to_double() * self.line_h - self.offset_y
}

///|
/// 选区 `[start,end)` 的绘制矩形：按显示行切开，每段给「行内起算 x / 行顶 y / 宽 / 行高」
/// （控件内坐标，已扣滚动偏移）。调用方只管照矩形填色——**量与画同一份行模型**，
/// 不再各算各的（选区高亮与命中错位就是这么来的）。空区间给空数组。
pub fn TextLayout::rects(
  self : TextLayout,
  start : Int32,
  end : Int32,
) -> Array[@base.Rect] {
  let out : Array[@base.Rect] = []
  if end <= start {
    return out
  }
  for i = 0; i < self.lines.length(); i = i + 1 {
    let ln = self.lines[i]
    let a = if start > ln.start { start } else { ln.start }
    let b = if end < ln.end { end } else { ln.end }
    if b > a {
      out.push({
        x: self.pad + (self.measure)(self.text, ln.start, a),
        y: self.pad + i.to_double() * self.line_h - self.offset_y,
        w: (self.measure)(self.text, a, b),
        h: self.line_h,
      })
    }
  }
  out
}

///|
/// 像素 → 字节：先按 y 定行，再在行内逐段量到不超过 x 的最右边界；返回值一定落在
/// 码点起点（不会停在多字节序列中间）。
pub fn TextLayout::hit(self : TextLayout, x : Double, y : Double) -> Int32 {
  let lines = self.lines
  if lines.length() == 0 {
    return 0
  }
  let i = ((y - self.pad + self.offset_y) / self.line_h)
    .floor()
    .to_int()
    .clamp(min=0, max=lines.length() - 1)
  let ln = lines[i]
  let b = @utf8.encode(self.text)
  let n = b.length()
  let mut best = ln.start
  let mut k = ln.start
  while k < ln.end {
    let next = if k + 1 < n && (b[k + 1].to_int() & 0xc0) == 0x80 {
      let mut j = k + 1
      while j < ln.end && (b[j].to_int() & 0xc0) == 0x80 {
        j = j + 1
      }
      j
    } else {
      k + 1
    }
    if (self.measure)(self.text, ln.start, next) + self.pad <= x {
      best = next
    }
    if next <= k {
      k = ln.end
    } else {
      k = next
    }
  }
  best
}
