// 内建回退测量器：文本后端不可用（Linux 缺开发包的占位降级档、Windows
// DirectWrite 未接、无字体服务）时的纯 MoonBit 估算兜底。布局层经复合入口
// （measure / measure_font / font_metrics 等）自动获得它——尺寸从各控件的
// 常数兜底变为按字符宽表估算；探针与守卫走 measure_real 一族，回退档不冒充
// 真后端。
//
// 口径：
// - 半角字符（拉丁/数字/常见半角标点）按 0.55×字号估宽，全角字符（CJK 统一
//   表意、假名、谚文、全角标点）按 1.0×字号估宽；
// - 行盒与 LINE_HEIGHT_K 地板同源（行高 = ceil(size×1.36)，基线取行盒的
//   0.78），估算值只求「合理且随字号与文本长度单调」，不追求与任何真字体
//   逐像素一致；
// - wrap 按空格贪心断行、CJK 逐字断行；ellipsize 截断补 …；max_lines 钳制。

///|
const FALLBACK_HALF : Double = 0.55

///|
const FALLBACK_ASCENT_RATIO : Double = 0.78

///|
/// 全角判定：CJK 统一表意（含扩展 A）、假名、谚文、全角 ASCII、CJK 标点等。
/// 省略号 … 按全角宽保守估（西文字体里它不足一倍字号，估宽只影响截断点）。
fn fallback_is_fullwidth(ch : Char) -> Bool {
  let c = ch.to_int()
  if c >= 0x1100 && c <= 0x115F {
    return true // 谚文字母
  }
  if c >= 0x2E80 && c <= 0x303E {
    return true // CJK 部首、注音与标点
  }
  if c >= 0x3041 && c <= 0x33FF {
    return true // 假名与兼容区
  }
  if c >= 0x3400 && c <= 0x4DBF {
    return true // 统一表意扩展 A
  }
  if c >= 0x4E00 && c <= 0x9FFF {
    return true // 统一表意
  }
  if c >= 0xAC00 && c <= 0xD7A3 {
    return true // 谚文音节
  }
  if c >= 0xF900 && c <= 0xFAFF {
    return true // 兼容表意
  }
  if c >= 0xFE30 && c <= 0xFE4F {
    return true // CJK 兼容形式
  }
  if c >= 0xFF00 && c <= 0xFF60 {
    return true // 全角 ASCII
  }
  if c >= 0xFFE0 && c <= 0xFFE6 {
    return true // 全角符号
  }
  c == 0x2026
}

///|
/// 单字符估宽（不含字距）。
fn fallback_char_w(ch : Char, size : Double) -> Double {
  if fallback_is_fullwidth(ch) {
    size
  } else {
    size * FALLBACK_HALF
  }
}

///|
/// 整串估宽（含字距；字距同真语义按每字符追加）。
fn fallback_str_w(s : String, size : Double, spacing : Double) -> Double {
  let mut w = 0.0
  let mut n = 0
  for ch in s {
    w += fallback_char_w(ch, size)
    n += 1
  }
  w + spacing * n.to_double()
}

///|
/// 回退行盒高（与 LINE_HEIGHT_K 地板同源）。
fn fallback_line_h(size : Double) -> Int32 {
  line_floor(size)
}

///|
/// 回退基线（行盒的 0.78）。
fn fallback_ascent(size : Double) -> Int32 {
  (fallback_line_h(size).to_double() * FALLBACK_ASCENT_RATIO).floor().to_int()
}

///|
/// 回退字体度量。
fn fallback_metrics(font : Font) -> FontMetrics {
  let h = fallback_line_h(font.size)
  let a = (h.to_double() * FALLBACK_ASCENT_RATIO).floor().to_int()
  { ascent: a, descent: h - a, }
}

///|
/// 单行截断：超宽时从头保留尽可能多的字符再补 …，估宽回到 max_width 内。
fn fallback_ellipsize(
  s : String,
  size : Double,
  spacing : Double,
  max_width : Int32,
) -> String {
  let limit = max_width.to_double()
  if fallback_str_w(s, size, spacing) <= limit {
    return s
  }
  let ell = fallback_char_w('…', size)
  let out = StringBuilder()
  let mut w = 0.0
  for ch in s {
    let cw = fallback_char_w(ch, size) + spacing
    if w + cw + ell > limit {
      break
    }
    out.write_char(ch)
    w += cw
  }
  out.write_char('…')
  out.to_string()
}

///|
/// 贪心断行：行宽不超 max_width。空格触发超宽时断行并丢弃该空格（行尾
/// 空格不占下一行行首）；非空格触发超宽时断在行内最近空格处（空格后的
/// 词挪到下一行）；无空格（CJK/超长词）就地断。返回各行字符串。
fn fallback_wrap_lines(s : String, size : Double, spacing : Double, max_width : Int32) -> Array[String] {
  let limit = max_width.to_double()
  let lines : Array[String] = []
  let cur = StringBuilder()
  let mut cur_w = 0.0
  for ch in s {
    if ch == '\n' {
      lines.push(cur.to_string())
      cur.reset()
      cur_w = 0.0
      continue
    }
    let cw = fallback_char_w(ch, size) + spacing
    if cur_w + cw > limit && cur_w > 0.0 {
      let line = cur.to_string()
      if ch == ' ' {
        // 空格装不下：断行并丢弃空格
        lines.push(line)
        cur.reset()
        cur_w = 0.0
        continue
      }
      // 断在行内最近空格处；无空格就地断
      let mut last_space = -1
      let mut idx = 0
      for c in line {
        if c == ' ' {
          last_space = idx
        }
        idx += 1
      }
      if last_space >= 0 {
        let head = slice_to(line, last_space)
        let tail = drop_to(line, last_space + 1)
        lines.push(head)
        cur.reset()
        for t in tail {
          cur.write_char(t)
        }
        cur_w = fallback_str_w(tail, size, spacing)
      } else {
        lines.push(line)
        cur.reset()
        cur_w = 0.0
      }
    }
    cur.write_char(ch)
    cur_w += cw
  }
  lines.push(cur.to_string())
  lines
}

///|
fn slice_to(s : String, n : Int) -> String {
  let out = StringBuilder()
  let mut i = 0
  for ch in s {
    if i >= n {
      break
    }
    out.write_char(ch)
    i += 1
  }
  out.to_string()
}

///|
fn drop_to(s : String, n : Int) -> String {
  let out = StringBuilder()
  let mut i = 0
  for ch in s {
    if i >= n {
      out.write_char(ch)
    }
    i += 1
  }
  out.to_string()
}

///|
/// 回退测量主入口：真后端 None 时的估算。字重/斜体不参与估算（无字形概念），
/// 字距与字号参与；空文本量出「宽 0 + 一行行盒」。
fn fallback_measure(
  text : String,
  size : Double,
  family : String,
  max_width : Int32,
  ellipsize : Bool,
  wrap : Bool,
  spacing : Double,
) -> TextMetrics {
  let _ = family
  let line_h = fallback_line_h(size)
  let baseline = fallback_ascent(size)
  // 空文本：宽 0，高按一行行盒（与 Pango 空 layout 的口径一致）
  if text.length() == 0 {
    return { width: 0.0, height: line_h, baseline, }
  }
  // 不换行（或无宽度约束）：单行，ellipsize 只在有约束时截断
  if !wrap || max_width <= 0 {
    let single = if ellipsize && max_width > 0 {
      fallback_ellipsize(text, size, spacing, max_width)
    } else {
      text
    }
    return {
      width: fallback_str_w(single, size, spacing),
      height: line_h,
      baseline,
    }
  }
  // 换行：贪心断行；ellipsize 时最后一行截断（行数不增，语义同单行省略）
  let lines = fallback_wrap_lines(text, size, spacing, max_width)
  if ellipsize {
    let n = lines.length()
    lines[n - 1] = fallback_ellipsize(
        lines[n - 1],
        size,
        spacing,
        max_width,
      )
  }
  let mut w = 0.0
  for l in lines {
    let lw = fallback_str_w(l, size, spacing)
    if lw > w {
      w = lw
    }
  }
  {
    width: w,
    height: line_h * lines.length(),
    baseline,
  }
}

///|
/// 回退测量（字体版）：转发到族名版，字重/斜体/族名不参与估算。
fn fallback_measure_font(
  text : String,
  font : Font,
  max_width : Int32,
  ellipsize : Bool,
  wrap : Bool,
) -> TextMetrics {
  fallback_measure(
    text,
    font.size,
    font.name,
    max_width,
    ellipsize,
    wrap,
    font.spacing,
  )
}
