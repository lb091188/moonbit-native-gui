// 程序生成的托盘图标：不依赖任何图片资源与解码器。
// 品牌图标造型——纯月兔头脸剪影（几何常数按
// assets/brand/app-icon-mono.svg 的 1024 视口等比缩到 32）；
// 窗口不进托盘——同色剪影会与兔头连成一团，定案见 experience/brand.md。
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
/// 内置托盘图标（单色紧版）：按 mono 内容框缩放居中，32 视口下剪影约
/// 22×29、四边留白 2–5px；`dark` 选白色档（深色面板）或黑色档。
/// 造型只留头 + 双耳剪影，耳窝挖空成透明，不做异色填充。
/// 返回 (宽, 高, ARGB 字节)——SNI 口径大端 AARRGGBB、不预乘。
pub fn mono_icon_pixmap(dark : Bool) -> (Int32, Int32, Bytes) {
  let w = 32
  let h = 32
  let px : FixedArray[Byte] = FixedArray::make(w * h * 4, b'\x00')
  // 造型常数（32 视口，按 1024 mono 内容框 x~312..712 / y~268..808 等比放入 28px 高）
  let ear_cy = 10.11
  let ear_rx = 3.21
  let ear_ry = 8.30
  let ear_dx_l = 9.36
  let ear_dx_r = 22.64
  let bowl_rx = 1.35
  let bowl_ry = 5.81
  let cos_a = 0.9743700647852352 // cos(13°)；左耳取 -sin、右耳取 +sin
  let sin_a = 0.2249510543438650
  let head_cx = 16.0
  let head_cy = 20.64
  let head_rx = 10.37
  let head_ry = 9.33
  let ink = if dark { 255.0 } else { 0.0 }
  for y in 0..<h {
    for x in 0..<w {
      let mut n = 0.0
      for sy in 0..<2 {
        for sx in 0..<2 {
          let sxp = x.to_double() + 0.25 + sx.to_double() * 0.5
          let syp = y.to_double() + 0.25 + sy.to_double() * 0.5
          let in_ear_l = tray_ellipse_hit(
            ear_rx,
            ear_ry,
            cos_a,
            -sin_a,
            sxp - ear_dx_l,
            syp - ear_cy,
          )
          let in_ear_r = tray_ellipse_hit(
            ear_rx,
            ear_ry,
            cos_a,
            sin_a,
            sxp - ear_dx_r,
            syp - ear_cy,
          )
          let in_bowl_l = tray_ellipse_hit(
            bowl_rx,
            bowl_ry,
            cos_a,
            -sin_a,
            sxp - ear_dx_l,
            syp - ear_cy,
          )
          let in_bowl_r = tray_ellipse_hit(
            bowl_rx,
            bowl_ry,
            cos_a,
            sin_a,
            sxp - ear_dx_r,
            syp - ear_cy,
          )
          let in_head = tray_ellipse_hit(
            head_rx,
            head_ry,
            1.0,
            0.0,
            sxp - head_cx,
            syp - head_cy,
          )
          // 层序：头 > 耳窝挖空 > 耳；耳窝只挖耳内，不挖头覆盖区
          if in_head || ((in_ear_l || in_ear_r) && !(in_bowl_l || in_bowl_r)) {
            n += 1.0
          }
        }
      }
      if n > 0.0 {
        let a = (n / 4.0 * 255.0).to_int()
        let off = (y * w + x) * 4
        px[off] = a.to_byte()
        px[off + 1] = ink.to_int().to_byte()
        px[off + 2] = ink.to_int().to_byte()
        px[off + 3] = ink.to_int().to_byte()
      }
    }
  }
  (w, h, Bytes::makei(w * h * 4, fn(i) { px[i] }))
}

///|
/// 默认托盘图标：浅色面板档的黑色单色图标（深色档用 [mono_icon_pixmap])。
pub fn default_icon_pixmap() -> (Int32, Int32, Bytes) {
  mono_icon_pixmap(false)
}

///|
/// 由大图最近邻缩放出小尺寸位图（供 IconPixmap 提供多档尺寸）。
/// 退化尺寸（set_icon_name 清空后的 0×0 空 pixmap、缓冲区短于声明
/// 宽高）直接返空：0 宽高下的「钳到 h-1」会产出 -1 负索引，在 DBus
/// 属性回调里即 PanicError（实测点「切主题图标」后面板查 IconPixmap
/// 触发，定案见 adaptation.md「托盘空 pixmap 属性回调 panic」条）。
pub fn downscale_pixmap(
  w : Int32,
  h : Int32,
  px : Bytes,
  nw : Int32,
  nh : Int32,
) -> (Int32, Int32, Bytes) {
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
