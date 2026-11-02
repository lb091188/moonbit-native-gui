// 背景渐变（style-css-expansion S2）：Style 的渐变字段。stop 颜色复用
// style 的 `Color`（token 名合法，绘制期现取当前主题——与纯色同口径）；
// 几何用归一化坐标（0..1 相对盒子矩形），绘制期乘上实际宽高，组件矩形
// 怎么变渐变都跟着铺满。

///|
/// 渐变几何：线性端点 (x0,y0)→(x1,y1)、径向圆心 (cx,cy) 与半径比例 r，
/// 全部归一化（相对盒子宽高；径向 r=1.0 即盒子短边的一半）。
pub(all) enum GradientKindSpec {
  Linear(Double, Double, Double, Double)
  Radial(Double, Double, Double)
}

///|
pub(all) struct GradientSpec {
  kind : GradientKindSpec
  stops : Array[(Double, Color)]
}

///|
/// 线性渐变（归一化端点）：上→下 = (0,0,0,1)、左→右 = (0,0,1,0)。
pub fn gradient_linear(
  x0 : Double,
  y0 : Double,
  x1 : Double,
  y1 : Double,
) -> GradientSpec {
  { kind: Linear(x0, y0, x1, y1), stops: [] }
}

///|
/// 径向渐变（归一化圆心与半径比例；r=1.0 即短边一半）。
pub fn gradient_radial(cx : Double, cy : Double, r : Double) -> GradientSpec {
  { kind: Radial(cx, cy, r), stops: [] }
}

///|
/// 追加停靠点：offset 钳制 [0,1]；颜色按样式颜色口径（token 名 / hex / 命名色，
/// 非法名在绘制期 resolve 时回落，与纯色同口径）。
pub fn GradientSpec::add_stop(self : GradientSpec, offset : Double, color : String) -> Unit {
  let at = if offset < 0.0 {
    0.0
  } else if offset > 1.0 {
    1.0
  } else {
    offset
  }
  self.stops.push((at, parse_color(color)))
}

///|
/// 绘制期落色：token 现取当前主题、归一化几何乘盒子尺寸，`set_fill_gradient`
/// 后返回 true。有效 stop 不足两个（画不出渐变）返回 false，调用方回落纯色。
pub fn apply_gradient_bg(
  p : @render.Painter,
  spec : GradientSpec,
  w : Double,
  h : Double,
) -> Bool {
  let g = match spec.kind {
    Linear(x0, y0, x1, y1) =>
      @render.Gradient::linear(x0 * w, y0 * h, x1 * w, y1 * h)
    Radial(cx, cy, r) => {
      let short = if w < h { w } else { h }
      @render.Gradient::radial(cx * w, cy * h, 0.0, r * short / 2.0)
    }
  }
  for s in spec.stops {
    g.add_stop(s.0, resolve_color(s.1))
  }
  if g.stops.length() < 2 {
    return false
  }
  p.set_fill_gradient(g)
  true
}
