// SVG path d 解析 + 就地归一化：任何命令在扫描时即折算成绝对 M/L/C/Z 段。
// 折算口径：H/V→L；S→C（首控制点反射上一 C/S 的第二控制点）；
// Q→C（二次→三次 2/3 公式）；T→C（反射上一 Q/T 控制点后再按 Q→C）。
// A/a（圆弧）本层 v1 不折算，记告警并跳过其 7 个参数。

///|
pub(all) struct Seg {
  cmd : Char   // 'M' | 'L' | 'C' | 'Z'，一律绝对
  args : Array[Double]
}

///|
fn codes(s : String) -> Array[Int] {
  let a : Array[Int] = []
  for c in s {
    a.push(c.to_int())
  }
  a
}

///|
fn is_command(x : Int) -> Bool {
  (x >= 65 && x <= 90) || (x >= 97 && x <= 122)
}

///|
fn to_upper(x : Int) -> Int {
  if x >= 97 && x <= 122 { x - 32 } else { x }
}

///|
fn skip_sep(cs : Array[Int], start : Int) -> Int {
  let n = cs.length()
  let mut j = start
  while j < n {
    let c = cs[j]
    if c == 32 || c == 44 || c == 9 || c == 10 || c == 13 {
      j += 1
    } else {
      break
    }
  }
  j
}

///|
// 读一个数：跳过前置分隔符后解析 [+-][digits][.digits][e[+-]digits]。
// 解析不到数字时返回 (0.0, 原起点)——调用方以「起点未推进」判失败。
fn readnum(cs : Array[Int], start : Int) -> (Double, Int) {
  let n = cs.length()
  let mut i = skip_sep(cs, start)
  let mut neg = false
  if i < n && cs[i] == 45 {
    neg = true
    i += 1
  } else if i < n && cs[i] == 43 {
    i += 1
  }
  let mut intpart = 0.0
  let mut seen = false
  while i < n && cs[i] >= 48 && cs[i] <= 57 {
    intpart = intpart * 10.0 + Double::from_int(cs[i] - 48)
    seen = true
    i += 1
  }
  let mut frac = 0.0
  let mut scale = 1.0
  if i < n && cs[i] == 46 {
    i += 1
    while i < n && cs[i] >= 48 && cs[i] <= 57 {
      scale = scale * 10.0
      frac = frac * 10.0 + Double::from_int(cs[i] - 48)
      seen = true
      i += 1
    }
    frac = frac / scale
  }
  if !seen {
    return (0.0, start)
  }
  let mut val = intpart + frac
  if i < n && (cs[i] == 101 || cs[i] == 69) {
    let save = i
    i += 1
    let mut eneg = false
    if i < n && cs[i] == 45 {
      eneg = true
      i += 1
    } else if i < n && cs[i] == 43 {
      i += 1
    }
    let mut eint = 0
    let mut eseen = false
    while i < n && cs[i] >= 48 && cs[i] <= 57 {
      eint = eint * 10 + (cs[i] - 48)
      eseen = true
      i += 1
    }
    if eseen {
      let mut p = 1.0
      for _k in 0..<eint {
        p = p * 10.0
      }
      val = if eneg { val / p } else { val * p }
    } else {
      i = save
    }
  }
  (if neg { -val } else { val }, i)
}

///|
// 读一个点（一对数），rel 时相对当前点 (cx,cy)。
fn readpoint(
  cs : Array[Int],
  i : Int,
  rel : Bool,
  cx : Double,
  cy : Double,
) -> (Double, Double, Int, Bool) {
  let (x0, i1) = readnum(cs, i)
  let (y0, i2) = readnum(cs, i1)
  if i1 == i || i2 == i1 {
    return (0.0, 0.0, i, false)
  }
  let x = if rel { cx + x0 } else { x0 }
  let y = if rel { cy + y0 } else { y0 }
  (x, y, i2, true)
}

///|
// 读 `count` 个数（arc 用），推进游标；缺数即返回当前。
fn skip_nums(cs : Array[Int], i : Int, count : Int) -> Int {
  let mut j = i
  for _k in 0..<count {
    let (_, nj) = readnum(cs, j)
    if nj == j {
      break
    }
    j = nj
  }
  j
}

///|
/// 解析 path d 并归一化为绝对 M/L/C/Z 段；返回（段序列，告警）。
pub fn parse_path(d : String) -> (Array[Seg], Array[String]) {
  let cs = codes(d)
  let n = cs.length()
  let out : Array[Seg] = []
  let warns : Array[String] = []
  let mut cx = 0.0
  let mut cy = 0.0
  let mut sx = 0.0
  let mut sy = 0.0
  let mut has_prev = false
  let mut prev_is_quad = false
  let mut px = 0.0
  let mut py = 0.0
  let mut next_letter = -1
  let mut i = skip_sep(cs, 0)

  while i < n {
    i = skip_sep(cs, i)
    if i >= n {
      break
    }
    let ch = cs[i]
    if !is_command(ch) && next_letter < 0 {
      warns.push("number without command")
      break
    }
    let letter = if is_command(ch) { ch } else { next_letter }
    if is_command(ch) {
      i += 1
    }
    let up = to_upper(letter)
    let rel = up != letter

    if up == 90 {
      // Z
      out.push({ cmd: 'Z', args: [] })
      cx = sx
      cy = sy
      has_prev = false
      next_letter = -1
    } else if up == 77 || up == 76 {
      // M / L
      let (x, y, ni, ok) = readpoint(cs, i, rel, cx, cy)
      if !ok {
        break
      }
      let cmd : Char = if up == 77 { 'M' } else { 'L' }
      out.push({ cmd, args: [x, y] })
      cx = x
      cy = y
      if up == 77 {
        sx = x
        sy = y
      }
      has_prev = false
      next_letter = if rel { 108 } else { 76 } // l / L
      i = ni
    } else if up == 72 {
      // H → L
      let (v, ni) = readnum(cs, i)
      if ni == i {
        break
      }
      let x = if rel { cx + v } else { v }
      out.push({ cmd: 'L', args: [x, cy] })
      cx = x
      has_prev = false
      next_letter = letter
      i = ni
    } else if up == 86 {
      // V → L
      let (v, ni) = readnum(cs, i)
      if ni == i {
        break
      }
      let y = if rel { cy + v } else { v }
      out.push({ cmd: 'L', args: [cx, y] })
      cy = y
      has_prev = false
      next_letter = letter
      i = ni
    } else if up == 67 {
      // C
      let (x1, y1, ia, ok1) = readpoint(cs, i, rel, cx, cy)
      let (x2, y2, ib, ok2) = readpoint(cs, ia, rel, cx, cy)
      let (x3, y3, ic, ok3) = readpoint(cs, ib, rel, cx, cy)
      if !(ok1 && ok2 && ok3) {
        break
      }
      out.push({ cmd: 'C', args: [x1, y1, x2, y2, x3, y3] })
      px = x2
      py = y2
      has_prev = true
      prev_is_quad = false
      cx = x3
      cy = y3
      next_letter = letter
      i = ic
    } else if up == 83 {
      // S → C
      let rx = if has_prev && !prev_is_quad { 2.0 * cx - px } else { cx }
      let ry = if has_prev && !prev_is_quad { 2.0 * cy - py } else { cy }
      let (x2, y2, ia, ok2) = readpoint(cs, i, rel, cx, cy)
      let (x3, y3, ic, ok3) = readpoint(cs, ia, rel, cx, cy)
      if !(ok2 && ok3) {
        break
      }
      out.push({ cmd: 'C', args: [rx, ry, x2, y2, x3, y3] })
      px = x2
      py = y2
      has_prev = true
      prev_is_quad = false
      cx = x3
      cy = y3
      next_letter = letter
      i = ic
    } else if up == 81 {
      // Q → C
      let (qx, qy, ia, ok1) = readpoint(cs, i, rel, cx, cy)
      let (ex, ey, ib, ok2) = readpoint(cs, ia, rel, cx, cy)
      if !(ok1 && ok2) {
        break
      }
      let c1x = cx + (2.0 / 3.0) * (qx - cx)
      let c1y = cy + (2.0 / 3.0) * (qy - cy)
      let c2x = ex + (2.0 / 3.0) * (qx - ex)
      let c2y = ey + (2.0 / 3.0) * (qy - ey)
      out.push({ cmd: 'C', args: [c1x, c1y, c2x, c2y, ex, ey] })
      px = qx
      py = qy
      has_prev = true
      prev_is_quad = true
      cx = ex
      cy = ey
      next_letter = letter
      i = ib
    } else if up == 84 {
      // T → C
      let qx = if has_prev && prev_is_quad { 2.0 * cx - px } else { cx }
      let qy = if has_prev && prev_is_quad { 2.0 * cy - py } else { cy }
      let (ex, ey, ni, ok) = readpoint(cs, i, rel, cx, cy)
      if !ok {
        break
      }
      let c1x = cx + (2.0 / 3.0) * (qx - cx)
      let c1y = cy + (2.0 / 3.0) * (qy - cy)
      let c2x = ex + (2.0 / 3.0) * (qx - ex)
      let c2y = ey + (2.0 / 3.0) * (qy - ey)
      out.push({ cmd: 'C', args: [c1x, c1y, c2x, c2y, ex, ey] })
      px = qx
      py = qy
      has_prev = true
      prev_is_quad = true
      cx = ex
      cy = ey
      next_letter = letter
      i = ni
    } else if up == 65 {
      // A：v1 不折算，跳 7 数
      warns.push("arc (A/a) not supported")
      i = skip_nums(cs, i, 7)
      next_letter = letter
    } else {
      warns.push("unknown command")
      break
    }
  }
  (out, warns)
}
