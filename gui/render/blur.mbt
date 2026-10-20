// 柔焦模糊：固定「1/8 块平均降采样 + 双线性回放」，无参数、无平台依赖。
// 只作用于本栈自有的位图；在预乘域上做平均，避免透明边缘发暗。

///|
const SOFT_BLUR_BLOCK : Int = 8

///|
fn clamp_i(v : Int, lo : Int, hi : Int) -> Int {
  if v < lo {
    lo
  } else if v > hi {
    hi
  } else {
    v
  }
}

///|
/// 写预乘分量的原始像素（BGRA 字节序，与内部布局一致）。
fn put_premul(
  out : Bitmap,
  x : Int,
  y : Int,
  b : Int,
  g : Int,
  r : Int,
  a : Int,
) -> Unit {
  let i = (y * out.width + x) * 4
  out.data[i] = b.to_byte()
  out.data[i + 1] = g.to_byte()
  out.data[i + 2] = r.to_byte()
  out.data[i + 3] = a.to_byte()
}

///|
/// 固定一档的柔焦模糊：返回同尺寸新位图。用于背景图、封面等面积可控的内容；
/// 不做全屏实时处理。
pub fn Bitmap::soft_blur(self : Bitmap) -> Bitmap {
  let out = Bitmap::new(self.width, self.height)
  if self.width == 0 || self.height == 0 {
    return out
  }
  let k = SOFT_BLUR_BLOCK
  let bw = (self.width + k - 1) / k
  let bh = (self.height + k - 1) / k
  let sums_b = FixedArray::make(bw * bh, 0)
  let sums_g = FixedArray::make(bw * bh, 0)
  let sums_r = FixedArray::make(bw * bh, 0)
  let sums_a = FixedArray::make(bw * bh, 0)
  let counts = FixedArray::make(bw * bh, 0)
  let src = self.data
  for y = 0; y < self.height; y = y + 1 {
    let by = y / k
    for x = 0; x < self.width; x = x + 1 {
      let i = (y * self.width + x) * 4
      let bi = by * bw + x / k
      sums_b[bi] = sums_b[bi] + src[i].to_int()
      sums_g[bi] = sums_g[bi] + src[i + 1].to_int()
      sums_r[bi] = sums_r[bi] + src[i + 2].to_int()
      sums_a[bi] = sums_a[bi] + src[i + 3].to_int()
      counts[bi] = counts[bi] + 1
    }
  }
  // 块均值落成浮点，供双向线性插值
  let mb = FixedArray::make(bw * bh, 0.0)
  let mg = FixedArray::make(bw * bh, 0.0)
  let mr = FixedArray::make(bw * bh, 0.0)
  let ma = FixedArray::make(bw * bh, 0.0)
  for i = 0; i < bw * bh; i = i + 1 {
    let n = counts[i]
    if n > 0 {
      mb[i] = sums_b[i].to_double() / n.to_double()
      mg[i] = sums_g[i].to_double() / n.to_double()
      mr[i] = sums_r[i].to_double() / n.to_double()
      ma[i] = sums_a[i].to_double() / n.to_double()
    }
  }
  let half = k.to_double() / 2.0
  let last_x = bw - 1
  let last_y = bh - 1
  for y = 0; y < self.height; y = y + 1 {
    let v = (y.to_double() + 0.5 - half) / k.to_double()
    let y0 = clamp_i(v.floor().to_int(), 0, last_y)
    let y1 = clamp_i(y0 + 1, 0, last_y)
    let fy = v - y0.to_double()
    for x = 0; x < self.width; x = x + 1 {
      let u = (x.to_double() + 0.5 - half) / k.to_double()
      let x0 = clamp_i(u.floor().to_int(), 0, last_x)
      let x1 = clamp_i(x0 + 1, 0, last_x)
      let fx = u - x0.to_double()
      let i00 = y0 * bw + x0
      let i10 = y0 * bw + x1
      let i01 = y1 * bw + x0
      let i11 = y1 * bw + x1
      let w00 = (1.0 - fx) * (1.0 - fy)
      let w10 = fx * (1.0 - fy)
      let w01 = (1.0 - fx) * fy
      let w11 = fx * fy
      let b = mb[i00] * w00 + mb[i10] * w10 + mb[i01] * w01 + mb[i11] * w11
      let g = mg[i00] * w00 + mg[i10] * w10 + mg[i01] * w01 + mg[i11] * w11
      let r = mr[i00] * w00 + mr[i10] * w10 + mr[i01] * w01 + mr[i11] * w11
      let a = ma[i00] * w00 + ma[i10] * w10 + ma[i01] * w01 + ma[i11] * w11
      put_premul(
        out,
        x,
        y,
        clamp_i(b.round().to_int(), 0, 255),
        clamp_i(g.round().to_int(), 0, 255),
        clamp_i(r.round().to_int(), 0, 255),
        clamp_i(a.round().to_int(), 0, 255),
      )
    }
  }
  out
}
