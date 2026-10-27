// 纯 MoonBit 光栅器的路径层：命令模型、设备空间展平、弧→贝塞尔。
//
// 口径与 cairo 桩对齐（W4 的验收基准就是 cairo）：
// - 路径命令按**用户空间**记录，fill/stroke 时经当前矩阵变换到设备空间再展平；
// - 贝塞尔用自适应 de Casteljau 细分（扁平阈值按设备像素），同一输入三平台
//   展平结果逐位一致（纯 MoonBit 无平台差异，这正是像素断言跨平台共用的前提）；
// - 弧转贝塞尔用整圆四分 kappa；cairo_arc 的语义（有当前点先 line_to 弧起点、
//   ea < sa 规范化为顺时针长弧）在 add_arc 里复刻。

///|
const RASTER_PI : Double = 3.14159265358979323846

///|
/// 整圆四分的贝塞尔控制系数（4/3·tan(π/8)）。
const RASTER_KAPPA : Double = 0.5522847498307936

///|
/// 贝塞尔展平阈值（设备像素）：控制点到弦中点距离小于该值即停。
/// 与 cairo 默认 tolerance 同为 0.1；阈值放宽到 0.25 时小半径的圆只切成十二段，
/// 段间接头在细描边上留下可见缺口。
const RASTER_FLAT_TOLERANCE : Double = 0.1

///|
pub(all) enum PathSeg {
  SegMove(Double, Double)
  SegLine(Double, Double)
  SegBezier(Double, Double, Double, Double, Double, Double)
  SegClose
}

///|
/// 用户空间路径。约定与 cairo 相同：`close_path` 回到当前子路径起点并把
/// 该子路径标记为闭合；fill 对未闭合子路径自动闭线（cairo_fill 语义）。
pub(all) struct Path {
  segs : Array[PathSeg]
  // 当前点（move/line/bezier/arc 更新；close 回起点）
  mut cur_x : Double
  mut cur_y : Double
  // 当前子路径起点（close 用）
  mut start_x : Double
  mut start_y : Double
  mut has_cur : Bool
}

///|
pub fn Path::new() -> Path {
  {
    segs: [],
    cur_x: 0.0,
    cur_y: 0.0,
    start_x: 0.0,
    start_y: 0.0,
    has_cur: false,
  }
}

///|
pub fn Path::clear(self : Path) -> Unit {
  self.segs.clear()
  self.has_cur = false
}

///|
pub fn Path::move_to(self : Path, x : Double, y : Double) -> Unit {
  self.segs.push(SegMove(x, y))
  self.cur_x = x
  self.cur_y = y
  self.start_x = x
  self.start_y = y
  self.has_cur = true
}

///|
pub fn Path::line_to(self : Path, x : Double, y : Double) -> Unit {
  if !self.has_cur {
    self.move_to(x, y)
    return
  }
  self.segs.push(SegLine(x, y))
  self.cur_x = x
  self.cur_y = y
}

///|
pub fn Path::bezier_curve_to(
  self : Path,
  c1x : Double,
  c1y : Double,
  c2x : Double,
  c2y : Double,
  x : Double,
  y : Double,
) -> Unit {
  if !self.has_cur {
    self.move_to(c1x, c1y)
  }
  self.segs.push(SegBezier(c1x, c1y, c2x, c2y, x, y))
  self.cur_x = x
  self.cur_y = y
}

///|
pub fn Path::close(self : Path) -> Unit {
  if self.has_cur {
    self.segs.push(SegClose)
    self.cur_x = self.start_x
    self.cur_y = self.start_y
  }
}

///|
/// 仿射矩阵（cairo 语义的行主序展开）：x' = a·x + c·y + e；y' = b·x + d·y + f。
pub(all) struct Mat2x3 {
  mut a : Double
  mut b : Double
  mut c : Double
  mut d : Double
  mut e : Double
  mut f : Double
}

///|
fn Mat2x3::identity() -> Mat2x3 {
  { a: 1.0, b: 0.0, c: 0.0, d: 1.0, e: 0.0, f: 0.0 }
}

///|
/// CTM ← CTM ∘ M（与 cairo_translate/scale/rotate 的「先加变换后作用」一致）。
fn Mat2x3::mul(self : Mat2x3, a2 : Double, b2 : Double, c2 : Double, d2 : Double, e2 : Double, f2 : Double) -> Unit {
  let a1 = self.a
  let b1 = self.b
  let c1 = self.c
  let d1 = self.d
  self.a = a1 * a2 + c1 * b2
  self.b = b1 * a2 + d1 * b2
  self.c = a1 * c2 + c1 * d2
  self.d = b1 * c2 + d1 * d2
  self.e = a1 * e2 + c1 * f2 + self.e
  self.f = b1 * e2 + d1 * f2 + self.f
}

///|
fn Mat2x3::apply(self : Mat2x3, x : Double, y : Double) -> (Double, Double) {
  (self.a * x + self.c * y + self.e, self.b * x + self.d * y + self.f)
}

///|
fn Mat2x3::det(self : Mat2x3) -> Double {
  self.a * self.d - self.b * self.c
}

///|
/// 变换只含平移与轴对齐缩放（无斜切/旋转）——矩形类取整语义的前提。
fn Mat2x3::axis_aligned(self : Mat2x3) -> Bool {
  self.b == 0.0 && self.c == 0.0
}

///|
/// 圆弧：有当前点先 line_to 弧起点（cairo_arc 语义）；ea < sa 规范化为
/// 顺时针长弧（本栈 arc 契约的 ccw 参数两层后端都不可用，见 painter.mbt 注）。
/// 弧拆成 ≤90° 的贝塞尔段。
pub fn Path::add_arc(
  self : Path,
  cx : Double,
  cy : Double,
  r : Double,
  a0 : Double,
  a1 : Double,
) -> Unit {
  if r <= 0.0 {
    return
  }
  // 规范化：ea < sa 时加整圈（cairo_arc 对 ea<sa 的顺时针长弧语义）
  let mut end = a1
  if end < a0 {
    end = end + 2.0 * RASTER_PI
  }
  let sx = cx + r * @math.cos(a0)
  let sy = cy + r * @math.sin(a0)
  if self.has_cur {
    if self.cur_x != sx || self.cur_y != sy {
      self.line_to(sx, sy)
    }
  } else {
    self.move_to(sx, sy)
  }
  // 每段 ≤ 90°：段数取上限
  let sweep = end - a0
  let raw_n = (sweep / (0.5 * RASTER_PI)).ceil().to_int()
  let n = if raw_n < 1 {
    1
  } else if raw_n > 1024 {
    1024
  } else {
    raw_n
  }
  let step = sweep / n.to_double()
  let k = RASTER_KAPPA
  let mut ang = a0
  for _i = 0; _i < n; _i = _i + 1 {
    let nang = ang + step
    let t = (nang - ang) / (0.5 * RASTER_PI) * k
    let c1x = cx + r * (@math.cos(ang) - t * @math.sin(ang))
    let c1y = cy + r * (@math.sin(ang) + t * @math.cos(ang))
    let c2x = cx + r * (@math.cos(nang) + t * @math.sin(nang))
    let c2y = cy + r * (@math.sin(nang) - t * @math.cos(nang))
    let ex = cx + r * @math.cos(nang)
    let ey = cy + r * @math.sin(nang)
    self.bezier_curve_to(c1x, c1y, c2x, c2y, ex, ey)
    ang = nang
  }
}

///|
/// 三次贝塞尔自适应细分：控制多边形到弦的最大距离小于阈值即收。
fn bezier_flat(
  x0 : Double,
  y0 : Double,
  x1 : Double,
  y1 : Double,
  x2 : Double,
  y2 : Double,
  x3 : Double,
  y3 : Double,
  out : Array[(Double, Double)],
) -> Unit {
  // 控制点到弦（p0→p3）的距离平方
  let dx = x3 - x0
  let dy = y3 - y0
  let d2 = dx * dx + dy * dy
  let d1 = (x1 - x0) * dy - (y1 - y0) * dx
  let d2p = (x2 - x0) * dy - (y2 - y0) * dx
  let err = if d1 * d1 + d2p * d2p > 0.0 {
    let l = if d2 > 0.0 { d2 } else { 1.0 }
    // 距离² ≤ (叉积)²/|弦|²，与阈值²比较
    (d1 * d1 + d2p * d2p) / l
  } else {
    0.0
  }
  let tol2 = RASTER_FLAT_TOLERANCE * RASTER_FLAT_TOLERANCE
  if err <= tol2 || (dx * dx + dy * dy) < 0.000000000001 {
    out.push((x3, y3))
    return
  }
  // de Casteljau 一分为二
  let ax = (x0 + x1) * 0.5
  let ay = (y0 + y1) * 0.5
  let bx = (x1 + x2) * 0.5
  let by = (y1 + y2) * 0.5
  let cx = (x2 + x3) * 0.5
  let cy = (y2 + y3) * 0.5
  let abx = (ax + bx) * 0.5
  let aby = (ay + by) * 0.5
  let bcx = (bx + cx) * 0.5
  let bcy = (by + cy) * 0.5
  let mx = (abx + bcx) * 0.5
  let my = (aby + bcy) * 0.5
  bezier_flat(x0, y0, ax, ay, abx, aby, mx, my, out)
  bezier_flat(mx, my, bcx, bcy, cx, cy, x3, y3, out)
}

///|
/// 展平后的子路径：设备空间折线 + 是否闭合。
pub(all) struct Poly {
  pts : Array[(Double, Double)]
  mut closed : Bool
}

///|
/// 圆心 (cx,cy)、半径 r 的正 24 边形（设备坐标）——Round 端帽的墨点。
/// r 是亚像素到几像素的小半径（dotted 点 = 线宽一半），24 边对 AA 覆盖的
/// 误差在 1/2 档以下，与贝塞尔展平容差同档。
fn cap_circle(cx : Double, cy : Double, r : Double) -> Poly {
  let pts : Array[(Double, Double)] = []
  let n = 24
  for i in 0..<n {
    let a = 6.283185307179586 * i.to_double() / n.to_double()
    pts.push((cx + r * @math.cos(a), cy + r * @math.sin(a)))
  }
  { pts, closed: true }
}

///|
/// 把折线按虚线图案切成「实段」：`pattern` 是 on/off 交替的长度表（设备像素），
/// `offset` 是相位偏移。返回的子路径都是**开口**折线（段端 butt 端帽），交给
/// `stroke_polys` 走常规描边。
///
/// 两条口径（与 cairo 的 dash 状态机对齐，也是两后端能做像素级对照的前提）：
/// - 相位在每个子路径起点重置（`offset` 只描述「从图案的第几段开始」）；
/// - 闭合子路径不绕回补相位，首尾接缝处照图案留缝（不强行对齐成整周期）。
fn dash_polys(
  polys : Array[Poly],
  pattern : Array[Double],
  offset : Double,
) -> Array[Poly] {
  let out : Array[Poly] = []
  // 周期：图案总和；全 0 时退回实线（不切）
  let n = pattern.length()
  let mut period = 0.0
  for v in pattern {
    period = period + v
  }
  if n == 0 || period <= 0.0 {
    return polys
  }
  // 相位归一到 [0, period)：跳过整周期后落进某一段
  let mut phase = offset - (offset / period).floor() * period
  let mut k = 0
  let mut on = true
  let mut remain = pattern[0]
  let mut guard_n = 0
  while phase > 0.0 && guard_n < n * 4 + 8 {
    if phase >= remain {
      phase = phase - remain
      k = (k + 1) % n
      remain = pattern[k]
      on = !on
    } else {
      remain = remain - phase
      phase = 0.0
    }
    guard_n = guard_n + 1
  }
  // 图案里 0 长段会卡住状态机：起点先越过它们
  let mut spin = 0
  while remain <= 0.0 && spin < n * 4 + 8 {
    k = (k + 1) % n
    remain = pattern[k]
    on = !on
    spin = spin + 1
  }
  for poly in polys {
    let pts = poly.pts
    let m = pts.length()
    if m < 2 {
      continue
    }
    // 每子路径重置相位
    let mut pk = k
    let mut pon = on
    let mut cur : Array[(Double, Double)] = []
    let edges = m - 1
    for i = 0; i < edges; i = i + 1 {
      let (ax, ay) = pts[i]
      let (bx, by) = pts[i + 1]
      let dx = bx - ax
      let dy = by - ay
      let len = (dx * dx + dy * dy).sqrt()
      if len < 0.000000001 {
        continue
      }
      let ux = dx / len
      let uy = dy / len
      let mut t = 0.0
      let mut steps = 0
      while t < len && steps < 1024 {
        steps = steps + 1
        let seg = remain.min(len - t)
        if pon {
          if cur.length() == 0 {
            cur.push((ax + ux * t, ay + uy * t))
          }
          cur.push((ax + ux * (t + seg), ay + uy * (t + seg)))
        }
        t = t + seg
        remain = remain - seg
        if remain <= 0.000000001 {
          if pon && cur.length() >= 2 {
            out.push({ pts: cur.copy(), closed: false })
          }
          cur = []
          // 越到下一段；跳过 0 长段
          let mut g2 = 0
          let mut nr = 0.0
          while nr <= 0.0 && g2 < n * 4 + 8 {
            pk = (pk + 1) % n
            nr = pattern[pk]
            pon = !pon
            g2 = g2 + 1
          }
          remain = nr
        }
      }
    }
    if pon && cur.length() >= 2 {
      out.push({ pts: cur, closed: false })
    }
  }
  out
}

///|
/// 路径 → 设备空间折线集合（经矩阵变换 + 展平）。未闭合子路径在 fill 侧
/// 自动闭线（stroke 侧保持开口、上端帽）。
pub fn Path::flatten(self : Path, m : Mat2x3) -> Array[Poly] {  let polys : Array[Poly] = []
  let cur : Array[(Double, Double)] = []
  let mut open = false
  let mut sx = 0.0
  let mut sy = 0.0
  for seg in self.segs {
    match seg {
      SegMove(x, y) => {
        if open && cur.length() >= 2 {
          polys.push({ pts: cur.copy(), closed: false })
        }
        cur.clear()
        let (dx, dy) = m.apply(x, y)
        cur.push((dx, dy))
        sx = dx
        sy = dy
        open = true
      }
      SegLine(x, y) => {
        if !open {
          let (dx, dy) = m.apply(x, y)
          cur.push((dx, dy))
          sx = dx
          sy = dy
          open = true
        } else {
          cur.push(m.apply(x, y))
        }
      }
      SegBezier(c1x, c1y, c2x, c2y, x, y) => {
        if !open {
          let (dx, dy) = m.apply(c1x, c1y)
          cur.push((dx, dy))
          sx = dx
          sy = dy
          open = true
        }
        let (lx, ly) = cur[cur.length() - 1]
        let (d1x, d1y) = m.apply(c1x, c1y)
        let (d2x, d2y) = m.apply(c2x, c2y)
        let (dx, dy) = m.apply(x, y)
        bezier_flat(lx, ly, d1x, d1y, d2x, d2y, dx, dy, cur)
      }
      SegClose => {
        if open {
          cur.push((sx, sy))
          if cur.length() >= 2 {
            polys.push({ pts: cur.copy(), closed: true })
          }
          cur.clear()
          open = false
        }
      }
    }
  }
  if open && cur.length() >= 2 {
    polys.push({ pts: cur.copy(), closed: false })
  }
  polys
}
