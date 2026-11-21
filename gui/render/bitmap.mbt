// RGBA8888 位图：本栈唯一拥有的像素缓冲。
//
// 内部布局与 Cairo 的 `CAIRO_FORMAT_ARGB32` 一致（小端 = 字节序 B,G,R,A，
// 且颜色分量**预乘** alpha）——这样 Cairo 光栅器可以直接画进这块内存，
// 上屏也可以直拷，全链路单一格式、零转换。默认格式是 CGBA(预乘)，`pixel`
// 负责反预乘，所以对外语义仍是普通的 RGBA 分量（0~255，独立于 alpha）。

///|
pub(all) struct Bitmap {
  width : Int32
  height : Int32
  data : FixedArray[Byte]
}

///|
/// 建新位图并清成全透明；尺寸非正时得到空位图（任何写入被丢弃）。
pub fn Bitmap::new(width : Int32, height : Int32) -> Bitmap {
  let w = if width < 0 { 0 } else { width }
  let h = if height < 0 { 0 } else { height }
  { width: w, height: h, data: FixedArray::make(w * h * 4, b'\x00'), }
}

///|
/// 整幅深拷贝（增量重绘模拟、模糊干净源快照这类「要一份位图现状」的场合用）。
pub fn Bitmap::copy(self : Bitmap) -> Bitmap {
  // FixedArray::copy 走底层整块拷贝（逐字节循环在 debug 档是几十毫秒级，
  // 滚动条带快路径每帧要拍一次快照）
  { width: self.width, height: self.height, data: self.data.copy() }
}

///|
pub fn Bitmap::inside(self : Bitmap, x : Int32, y : Int32) -> Bool {
  x >= 0 && y >= 0 && x < self.width && y < self.height
}

// 反预乘：预乘分量 p、alpha a → 独立分量 p*255/a（a=0 视为全透明）。

///|
fn unpremul(p : Int32, a : Int32) -> Int32 {
  if a == 0 {
    0
  } else {
    (p * 255 + a / 2) / a
  }
}

///|
/// 取像素（反预乘后的独立 RGBA 分量）；越界返回全透明。
pub fn Bitmap::pixel(self : Bitmap, x : Int32, y : Int32) -> Color {
  if !self.inside(x, y) {
    color_transparent
  } else {
    let i = (y * self.width + x) * 4
    let bs = self.data
    let b = bs[i].to_int()
    let g = bs[i + 1].to_int()
    let r = bs[i + 2].to_int()
    let a = bs[i + 3].to_int()
    if a == 0 {
      color_transparent
    } else {
      { r: unpremul(r, a), g: unpremul(g, a), b: unpremul(b, a), a, }
    }
  }
}

///|
/// source-over 覆盖一个像素（在预乘域上混合，与 Cairo 同一套算术）。
pub fn Bitmap::paint(self : Bitmap, x : Int32, y : Int32, c : Color) -> Unit {
  if !self.inside(x, y) {
    return ()
  }
  let i = (y * self.width + x) * 4
  let sa = c.a
  // 写像素一律经局部句柄：Bytes 的 op_set 只接受可变接收者，
  // 直接 self.data[..] = .. 会让整个方法要求 `Bitmap &mut`，调用点就得写 mut。
  let d = self.data
  if sa == 255 {
    d[i] = c.b.to_byte()
    d[i + 1] = c.g.to_byte()
    d[i + 2] = c.r.to_byte()
    d[i + 3] = b'\xff'
  } else if sa == 0 {
    ()
  } else {
    // src 预乘
    let sr = (c.r * sa + 127) / 255
    let sg = (c.g * sa + 127) / 255
    let sb = (c.b * sa + 127) / 255
    let inv = 255 - sa
    let mix = fn(s : Int32, dst : Int32) -> Int32 {
      s + (dst * inv + 127) / 255
    }
    let db = d[i].to_int()
    let dg = d[i + 1].to_int()
    let dr = d[i + 2].to_int()
    let da = d[i + 3].to_int()
    d[i] = mix(sb, db).to_byte()
    d[i + 1] = mix(sg, dg).to_byte()
    d[i + 2] = mix(sr, dr).to_byte()
    d[i + 3] = mix(sa, da).to_byte()
  }
}

///|
/// 导出为独立分量 RGBA（非预乘、行主序，长度 width*height*4）——
/// PNG 编码等对外格式用；内部绘制一律走预乘缓冲，不经过这里。
pub fn Bitmap::to_rgba_bytes(self : Bitmap) -> Bytes {
  let out = FixedArray::make(self.width * self.height * 4, b'\x00')
  for y = 0; y < self.height; y = y + 1 {
    for x = 0; x < self.width; x = x + 1 {
      let c = self.pixel(x, y)
      let i = (y * self.width + x) * 4
      out[i] = c.r.to_byte()
      out[i + 1] = c.g.to_byte()
      out[i + 2] = c.b.to_byte()
      out[i + 3] = c.a.to_byte()
    }
  }
  Bytes::from_array(out)
}

///|
/// 在闭区间 [x0,x1) × [y0,y1) 内逐像素覆盖；非法区间不做任何事。
pub fn Bitmap::fill_area(
  self : Bitmap,
  x0 : Int32,
  y0 : Int32,
  x1 : Int32,
  y1 : Int32,
  c : Color,
) -> Unit {
  if x1 <= x0 || y1 <= y0 {
    return ()
  }
  let ly = if y0 < 0 { 0 } else { y0 }
  let hy = if y1 > self.height { self.height } else { y1 }
  let lx = if x0 < 0 { 0 } else { x0 }
  let hx = if x1 > self.width { self.width } else { x1 }
  for y = ly; y < hy; y = y + 1 {
    for x = lx; x < hx; x = x + 1 {
      self.paint(x, y, c)
    }
  }
}

///|
/// 区域盒式模糊（三趟逼近高斯）：就地模糊位图上 [x, x+w) × [y, y+h) 的**已画
/// 内容**，预乘 BGRA 四通道同窗滑动求和，窗口越界按边缘像素补位（clamp）。
/// 毛玻璃（Painter::backdrop_blur）与将来的投影模糊共用这一口——cairo 表面
/// 就建在本位图数据上，两后端同效。区域越界裁到位图；半径 <1 或区域空为
/// 无操作。成本随面积 × 半径线性，只给控件级小半径用（大面积归 GPU 档）。
pub fn Bitmap::box_blur_region(
  self : Bitmap,
  rx : Int32,
  ry : Int32,
  rw : Int32,
  rh : Int32,
  radius : Int32,
) -> Unit {
  if radius < 1 || rw < 1 || rh < 1 || self.width < 1 || self.height < 1 {
    return
  }
  let x0 = if rx < 0 { 0 } else { rx }
  let y0 = if ry < 0 { 0 } else { ry }
  let x1 = if rx + rw > self.width { self.width } else { rx + rw }
  let y1 = if ry + rh > self.height { self.height } else { ry + rh }
  let w = x1 - x0
  let h = y1 - y0
  if w < 1 || h < 1 {
    return
  }
  let n = w * h * 4
  let buf_a : FixedArray[Int32] = FixedArray::make(n, 0)
  let buf_b : FixedArray[Int32] = FixedArray::make(n, 0)
  // 装载区域（字节 → int，四通道交错）
  for y = 0; y < h; y = y + 1 {
    let srow = (y0 + y) * self.width * 4 + x0 * 4
    let drow = y * w * 4
    for x = 0; x < w; x = x + 1 {
      let si = srow + x * 4
      let di = drow + x * 4
      buf_a[di] = self.data[si].to_int()
      buf_a[di + 1] = self.data[si + 1].to_int()
      buf_a[di + 2] = self.data[si + 2].to_int()
      buf_a[di + 3] = self.data[si + 3].to_int()
    }
  }
  // 三趟「横向 + 纵向」，结果每趟都回到 buf_a
  for _pass = 0; _pass < 3; _pass = _pass + 1 {
    blur_box_axis(buf_a, buf_b, w, h, radius, true)
    blur_box_axis(buf_b, buf_a, w, h, radius, false)
  }
  // 写回
  for y = 0; y < h; y = y + 1 {
    let drow = (y0 + y) * self.width * 4 + x0 * 4
    let srow = y * w * 4
    for x = 0; x < w; x = x + 1 {
      let si = srow + x * 4
      let di = drow + x * 4
      self.data[di] = buf_a[si].to_byte()
      self.data[di + 1] = buf_a[si + 1].to_byte()
      self.data[di + 2] = buf_a[si + 2].to_byte()
      self.data[di + 3] = buf_a[si + 3].to_byte()
    }
  }
}

///|
/// 单向盒式滑动窗：横向（horizontal=true，沿 x）或纵向一趟，窗口出界按
/// 边缘像素补位（clamp），逐通道滑动和。src/dst 不得同数组。
fn blur_box_axis(
  src : FixedArray[Int32],
  dst : FixedArray[Int32],
  w : Int32,
  h : Int32,
  r : Int32,
  horizontal : Bool,
) -> Unit {
  let win = r * 2 + 1
  if horizontal {
    for y = 0; y < h; y = y + 1 {
      let base = y * w * 4
      // 逐像素直接求窗（窗口出界按边缘补位）：滑动和与边缘 clamp 不相容——
      // 窗口压在边界上时含重复样本，滑动减法会错位（实测远场被拉灰）
      for x = 0; x < w; x = x + 1 {
        let mut t0 = 0
        let mut t1 = 0
        let mut t2 = 0
        let mut t3 = 0
        for k = x - r; k <= x + r; k = k + 1 {
          let xk = if k < 0 {
            0
          } else if k >= w {
            w - 1
          } else {
            k
          }
          let i = base + xk * 4
          t0 = t0 + src[i]
          t1 = t1 + src[i + 1]
          t2 = t2 + src[i + 2]
          t3 = t3 + src[i + 3]
        }
        let di = base + x * 4
        dst[di] = t0 / win
        dst[di + 1] = t1 / win
        dst[di + 2] = t2 / win
        dst[di + 3] = t3 / win
      }
    }
  } else {
    for x = 0; x < w; x = x + 1 {
      let col = x * 4
      for y = 0; y < h; y = y + 1 {
        let mut t0 = 0
        let mut t1 = 0
        let mut t2 = 0
        let mut t3 = 0
        for k = y - r; k <= y + r; k = k + 1 {
          let yk = if k < 0 {
            0
          } else if k >= h {
            h - 1
          } else {
            k
          }
          let i = yk * w * 4 + col
          t0 = t0 + src[i]
          t1 = t1 + src[i + 1]
          t2 = t2 + src[i + 2]
          t3 = t3 + src[i + 3]
        }
        let di = y * w * 4 + col
        dst[di] = t0 / win
        dst[di + 1] = t1 / win
        dst[di + 2] = t2 / win
        dst[di + 3] = t3 / win
      }
    }
  }
}
