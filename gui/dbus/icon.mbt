// 程序生成的托盘图标：不依赖任何图片资源与解码器。
// 品牌图标造型——玫红月兔双耳探出靛蓝应用窗口（几何常数按
// assets/brand/app-icon.svg 的 1024 master 等比缩到 32 视口），
// 2x2 超采样抗锯齿，输出 SNI 规范要求的 ARGB 大端序位图。

///|
/// 托盘图标几何：点是否落在旋转椭圆内（dx/dy 为点相对椭圆中心的偏移）。
fn tray_ellipse_hit(
  rx : Double,
  ry : Double,
  ca : Double,
  sa : Double,
  dx : Double,
  dy : Double,
) -> Bool {
  let u = ca * dx + sa * dy
  let v = -sa * dx + ca * dy
  u * u / (rx * rx) + v * v / (ry * ry) <= 1.0
}

///|
/// 托盘图标几何：圆角矩形（扩展矩形 ∩ 圆角盘）。
fn tray_round_rect_hit(
  cx : Double,
  cy : Double,
  hw : Double,
  hh : Double,
  r : Double,
  qx : Double,
  qy : Double,
) -> Bool {
  let dx = if qx < cx { cx - qx } else { qx - cx }
  let dy = if qy < cy { cy - qy } else { qy - cy }
  if dx > hw || dy > hh {
    return false
  }
  let ex = if dx > hw - r { dx - (hw - r) } else { 0.0 }
  let ey = if dy > hh - r { dy - (hh - r) } else { 0.0 }
  ex * ex + ey * ey <= r * r
}

///|
/// 默认托盘图标：32×32 品牌图标，返回 (宽, 高, ARGB 字节)。
pub fn default_icon_pixmap() -> (Int, Int, Bytes) {
  let w = 32
  let h = 32
  let px : FixedArray[Byte] = FixedArray::make(w * h * 4, b'\x00')
  // 造型常数（32 视口）：双耳玫红含浅耳窝，从窗口上沿探出；
  // 不画面部——32px 下五官糊成污点（几何预览定稿时验证过）
  let ear_cy = 6.3
  let ear_rx = 2.0
  let ear_ry = 5.4
  let bowl_rx = 0.75
  let bowl_ry = 3.75
  let cos_a = 0.9743700647852352 // cos(13°)；左耳取 -sin、右耳取 +sin
  let sin_a = 0.2249510543438650
  let head_cx = 16.0
  let head_cy = 12.5
  let head_rx = 5.6
  let head_ry = 5.0
  let win_cx = 16.0
  let win_cy = 20.2
  let win_hw = 10.5
  let win_hh = 5.8
  let win_r = 2.5
  let win_title_y = 18.0
  for y in 0..<h {
    for x in 0..<w {
      let mut n = 0.0
      let mut sr = 0.0
      let mut sg = 0.0
      let mut sb = 0.0
      for sy in 0..<2 {
        for sx in 0..<2 {
          let sxp = x.to_double() + 0.25 + sx.to_double() * 0.5
          let syp = y.to_double() + 0.25 + sy.to_double() * 0.5
          // 层优先级（高层覆盖低层，与 master 绘制顺序一致）：窗口 > 头 > 耳窝 > 耳
          let in_ear_l = tray_ellipse_hit(ear_rx, ear_ry, cos_a, -sin_a, sxp - 12.4, syp - ear_cy)
          let in_ear_r = tray_ellipse_hit(ear_rx, ear_ry, cos_a, sin_a, sxp - 19.6, syp - ear_cy)
          let in_bowl_l = tray_ellipse_hit(bowl_rx, bowl_ry, cos_a, -sin_a, sxp - 12.4, syp - ear_cy)
          let in_bowl_r = tray_ellipse_hit(bowl_rx, bowl_ry, cos_a, sin_a, sxp - 19.6, syp - ear_cy)
          let mut cr = 0.0
          let mut cg = 0.0
          let mut cb = 0.0
          let mut hit = false
          if tray_round_rect_hit(win_cx, win_cy, win_hw, win_hh, win_r, sxp, syp) {
            if syp < win_title_y {
              cr = 36.0 // #2428A5 标题栏
              cg = 40.0
              cb = 165.0
            } else {
              cr = 46.0 // #2E33C9 内容区
              cg = 51.0
              cb = 201.0
            }
            hit = true
          } else if tray_ellipse_hit(head_rx, head_ry, 1.0, 0.0, sxp - head_cx, syp - head_cy) {
            cr = 199.0 // #C73E94
            cg = 62.0
            cb = 148.0
            hit = true
          } else if in_bowl_l || in_bowl_r {
            cr = 241.0 // #F1D3E6 耳窝
            cg = 211.0
            cb = 230.0
            hit = true
          } else if in_ear_l || in_ear_r {
            cr = 199.0 // #C73E94
            cg = 62.0
            cb = 148.0
            hit = true
          }
          if hit {
            n += 1.0
            sr += cr
            sg += cg
            sb += cb
          }
        }
      }
      if n > 0.0 {
        let a = (n / 4.0 * 255.0).to_int()
        let off = (y * w + x) * 4
        // 大端序 AARRGGBB；命中层颜色取平均（跨层边缘 1px 混色，32px 下不可辨）
        px[off] = a.to_byte()
        px[off + 1] = (sr / n).to_int().to_byte()
        px[off + 2] = (sg / n).to_int().to_byte()
        px[off + 3] = (sb / n).to_int().to_byte()
      }
    }
  }
  (w, h, Bytes::makei(w * h * 4, fn(i) { px[i] }))
}

///|
/// 由大图最近邻缩放出小尺寸位图（供 IconPixmap 提供多档尺寸）。
/// 退化尺寸（set_icon_name 清空后的 0×0 空 pixmap、缓冲区短于声明
/// 宽高）直接返空：0 宽高下的「钳到 h-1」会产出 -1 负索引，在 DBus
/// 属性回调里即 PanicError（实测点「切主题图标」后面板查 IconPixmap
/// 触发，定案见 adaptation.md「托盘空 pixmap 属性回调 panic」条）。
pub fn downscale_pixmap(
  w : Int,
  h : Int,
  px : Bytes,
  nw : Int,
  nh : Int,
) -> (Int, Int, Bytes) {
  if w <= 0 || h <= 0 || nw <= 0 || nh <= 0 || px.length() < w * h * 4 {
    return (0, 0, Bytes::make(0, 0))
  }
  let out : FixedArray[Byte] = FixedArray::make(nw * nh * 4, b'\x00')
  for y in 0..<nh {
    let sy = y * h / nh
    for x in 0..<nw {
      let sx = x * w / nw
      let src = (sy * w + sx) * 4
      let dst = (y * nw + x) * 4
      for c in 0..<4 {
        out[dst + c] = px[src + c]
      }
    }
  }
  (nw, nh, Bytes::makei(nw * nh * 4, fn(i) { out[i] }))
}
