// 纯 MoonBit 光栅器的合成层：25 混合模式逐像素算术 + 渐变求值。
//
// 口径（与 cairo 对拍，容差吸收实现差）：
// - Porter-Duff 九式在**预乘域**有闭式整数公式（o = cs·k + ds·m），逐位确定；
// - 16 个 W3C 混合模式按 compositing-1 规范在**非预乘域**算 B(Cb,Cs)，再按
//   Co = αs·B + αb·(1−αs)·Cb + αs·(1−αb)·Cs 回预乘（cairo 同公式，内部
//   精度不同，8bit 舍入差落在容差带）；
// - 渐变 stop 按**非预乘**插值（CSS/W3C 口径；cairo 在预乘域插值，半透明
//   stop 的中间色有差，容差带内——结构断言只用不透明 stop 避开）；
// - 超出 [0,1] 按 PAD 复现端点色（cr_blit 的 EXTEND_PAD 同语义）。

///|
/// 绘制源：纯色、渐变（含求值逆矩阵），或位图像素（blit 用：逆映射矩阵 +
/// 采样域钳制边界）。渐变坐标定义在设源时的用户空间（cairo pattern 语义：
/// set_source 瞬间的 CTM 被图案捕获），采样时设备像素经逆矩阵求值。
pub(all) enum RSource {
  SrcSolid(Color)
  SrcGrad(Gradient, Mat2x3)
  /// 末位 sscale：缩小采样的步长（源像素/目标像素，如 3× 文字离屏缩回 = 3）。
  /// 大于 1 走区域滤波（n×n 均匀网格双线性、预乘域平均），等于 1 单点双线性，
  /// 0 保持最近邻——放大与 1:1 的逐位口径不变。
  SrcPixels(Bitmap, Mat2x3, Int32, Int32, Int32, Int32, Double)
}

///|
fn Mat2x3::inverse(self : Mat2x3) -> Mat2x3 {
  let det = self.det()
  if det == 0.0 {
    return Mat2x3::identity()
  }
  let inv = 1.0 / det
  {
    a: self.d * inv,
    b: -self.b * inv,
    c: -self.c * inv,
    d: self.a * inv,
    e: (self.c * self.f - self.d * self.e) * inv,
    f: (self.b * self.e - self.a * self.f) * inv,
  }
}

///|
fn clamp01(v : Double) -> Double {
  if v < 0.0 {
    0.0
  } else if v > 1.0 {
    1.0
  } else {
    v
  }
}

///|
fn grad_color_at(g : Gradient, t : Double) -> Color {
  let stops = g.stops
  if stops.length() == 0 {
    return color_transparent
  }
  if t <= stops[0].0 {
    return stops[0].1
  }
  let last = stops.length() - 1
  if t >= stops[last].0 {
    return stops[last].1
  }
  // 找 t 所在段：stops 按构造序假定有序（add_stop 单调使用）；乱序时本段
  // 线性查找首个 offset >= t 的前一对，等价于 cairo 排序后语义的超集。
  let mut i = 0
  while i < last && stops[i + 1].0 < t {
    i = i + 1
  }
  let (o0, c0) = stops[i]
  let (o1, c1) = stops[i + 1]
  if o1 <= o0 {
    return c1
  }
  let f = (t - o0) / (o1 - o0)
  let mr = c0.r.to_double() + (c1.r - c0.r).to_double() * f
  let mg = c0.g.to_double() + (c1.g - c0.g).to_double() * f
  let mb = c0.b.to_double() + (c1.b - c0.b).to_double() * f
  let ma = c0.a.to_double() + (c1.a - c0.a).to_double() * f
  {
    r: raster_clamp255(mr.to_int()),
    g: raster_clamp255(mg.to_int()),
    b: raster_clamp255(mb.to_int()),
    a: raster_clamp255(ma.to_int()),
  }
}

///|
fn raster_clamp255(v : Int32) -> Int32 {
  if v < 0 {
    0
  } else if v > 255 {
    255
  } else {
    v
  }
}

///|
/// 设备像素 (x, y) 处的源色（非预乘分量）。
fn source_at(s : RSource, x : Double, y : Double) -> Color {
  match s {
    SrcSolid(c) => c
    SrcPixels(bm, inv, lox, loy, hix, hiy, sscale) => {
      let (mx, my) = inv.apply(x, y)
      // 单点双线性（预乘域），四角按界钳制——透明邻居不串色
      fn tap(px : Double, py : Double) -> (Double, Double, Double, Double) {
        let fx = px - px.floor()
        let fy = py - py.floor()
        let x0 = px.floor().to_int()
        let y0 = py.floor().to_int()
        let xa = if x0 < lox { lox } else if x0 > hix { hix } else { x0 }
        let xb = if x0 + 1 < lox {
          lox
        } else if x0 + 1 > hix {
          hix
        } else {
          x0 + 1
        }
        let ya = if y0 < loy { loy } else if y0 > hiy { hiy } else { y0 }
        let yb = if y0 + 1 < loy {
          loy
        } else if y0 + 1 > hiy {
          hiy
        } else {
          y0 + 1
        }
        let w00 = (1.0 - fx) * (1.0 - fy)
        let w10 = fx * (1.0 - fy)
        let w01 = (1.0 - fx) * fy
        let w11 = fx * fy
        let i00 = (ya * bm.width + xa) * 4
        let i10 = (ya * bm.width + xb) * 4
        let i01 = (yb * bm.width + xa) * 4
        let i11 = (yb * bm.width + xb) * 4
        let b = bm.data[i00].to_int().to_double() * w00 +
          bm.data[i10].to_int().to_double() * w10 +
          bm.data[i01].to_int().to_double() * w01 +
          bm.data[i11].to_int().to_double() * w11
        let g = bm.data[i00 + 1].to_int().to_double() * w00 +
          bm.data[i10 + 1].to_int().to_double() * w10 +
          bm.data[i01 + 1].to_int().to_double() * w01 +
          bm.data[i11 + 1].to_int().to_double() * w11
        let r = bm.data[i00 + 2].to_int().to_double() * w00 +
          bm.data[i10 + 2].to_int().to_double() * w10 +
          bm.data[i01 + 2].to_int().to_double() * w01 +
          bm.data[i11 + 2].to_int().to_double() * w11
        let a = bm.data[i00 + 3].to_int().to_double() * w00 +
          bm.data[i10 + 3].to_int().to_double() * w10 +
          bm.data[i01 + 3].to_int().to_double() * w01 +
          bm.data[i11 + 3].to_int().to_double() * w11
        (b, g, r, a)
      }
      let color_of = fn(
        pb : Double,
        pg : Double,
        pr : Double,
        pa : Double,
      ) -> Color {
        let a = pa.round().to_int()
        if a <= 0 {
          color_transparent
        } else {
          {
            r: unpremul_ch(pr.round().to_int(), a),
            g: unpremul_ch(pg.round().to_int(), a),
            b: unpremul_ch(pb.round().to_int(), a),
            a,
          }
        }
      }
      if sscale > 1.0 {
        // 区域滤波：n×n 均匀网格盖住footprint（3× 离屏缩回 = 3×3 盒），
        // 预乘域平均——缩回边缘拿到接近解析的抗锯齿
        let n = sscale.ceil().to_int()
        let step = sscale / n.to_double()
        let mut sb = 0.0
        let mut sg = 0.0
        let mut sr = 0.0
        let mut sa = 0.0
        for iy = 0; iy < n; iy = iy + 1 {
          let py = my - sscale * 0.5 + (iy.to_double() + 0.5) * step
          for ix = 0; ix < n; ix = ix + 1 {
            let px = mx - sscale * 0.5 + (ix.to_double() + 0.5) * step
            let (b, g, r, a) = tap(px, py)
            sb = sb + b
            sg = sg + g
            sr = sr + r
            sa = sa + a
          }
        }
        let cnt = (n * n).to_double()
        color_of(sb / cnt, sg / cnt, sr / cnt, sa / cnt)
      } else if sscale > 0.0 {
        let (b, g, r, a) = tap(mx, my)
        color_of(b, g, r, a)
      } else {
        let mut sxi = mx.floor().to_int()
        let mut syi = my.floor().to_int()
        if sxi < lox {
          sxi = lox
        } else if sxi > hix {
          sxi = hix
        }
        if syi < loy {
          syi = loy
        } else if syi > hiy {
          syi = hiy
        }
        let i = (syi * bm.width + sxi) * 4
        let a = bm.data[i + 3].to_int()
        // 预乘字节 → 非预乘色（合成层再预乘；±1 舍入在容差带，结构断言用
        // 不透明/全透明像素保证逐位）
        if a <= 0 {
          color_transparent
        } else {
          {
            r: unpremul_ch(bm.data[i + 2].to_int(), a),
            g: unpremul_ch(bm.data[i + 1].to_int(), a),
            b: unpremul_ch(bm.data[i].to_int(), a),
            a,
          }
        }
      }
    }
    SrcGrad(g, inv) => {
      let (ux, uy) = inv.apply(x, y)
      match g.kind {
        Linear(x0, y0, x1, y1) => {
          let dx = x1 - x0
          let dy = y1 - y0
          let len2 = dx * dx + dy * dy
          if len2 <= 0.0 {
            grad_color_at(g, 0.0)
          } else {
            let t = ((ux - x0) * dx + (uy - y0) * dy) / len2
            grad_color_at(g, clamp01(t))
          }
        }
        Radial(cx, cy, r0, r1) => {
          let span = r1 - r0
          if span <= 0.0 {
            grad_color_at(g, 1.0)
          } else {
            let d = ((ux - cx) * (ux - cx) + (uy - cy) * (uy - cy)).sqrt()
            grad_color_at(g, clamp01((d - r0) / span))
          }
        }
      }
    }
  }
}

// ---- 预乘域读写 ----

///|
fn premul_bytes(c : Color, cov : Int32) -> (Int32, Int32, Int32, Int32) {
  // 两步取整，不能合并：预乘是 255 域（(v·a+127)/255），覆盖是 256 域
  // （·cov/256）——合并成 65536 域会把 255/256 的比例差吞成 -1（不透明源
  // 满覆盖实测 254 而非 255）。
  let a = (c.a * cov + 128) / 256
  if a <= 0 {
    (0, 0, 0, 0)
  } else {
    let pr = (c.r * c.a + 127) / 255
    let pg = (c.g * c.a + 127) / 255
    let pb = (c.b * c.a + 127) / 255
    ((pr * cov + 128) / 256, (pg * cov + 128) / 256, (pb * cov + 128) / 256, a)
  }
}

///|
fn unpremul_ch(p : Int32, a : Int32) -> Int32 {
  if a <= 0 {
    0
  } else {
    (p * 255 + a / 2) / a
  }
}

// ---- 16 个 W3C 混合函数（非预乘 [0,1] 域） ----

///|
fn blend_separable(mode_id : Int32, cb : Double, cs : Double) -> Double {
  if mode_id == 1 {
    cb * cs
  } else if mode_id == 2 {
    cb + cs - cb * cs
  } else if mode_id == 3 {
    hard_light(cs, cb)
  } else if mode_id == 4 {
    if cb < cs {
      cb
    } else {
      cs
    }
  } else if mode_id == 5 {
    if cb > cs {
      cb
    } else {
      cs
    }
  } else if mode_id == 6 {
    if cb <= 0.0 {
      0.0
    } else if cs >= 1.0 {
      1.0
    } else {
      let v = cb / (1.0 - cs)
      if v > 1.0 {
        1.0
      } else {
        v
      }
    }
  } else if mode_id == 7 {
    if cb >= 1.0 {
      1.0
    } else if cs <= 0.0 {
      0.0
    } else {
      let v = 1.0 - (1.0 - cb) / cs
      if v < 0.0 {
        0.0
      } else {
        v
      }
    }
  } else if mode_id == 8 {
    soft_light(cb, cs)
  } else if mode_id == 9 {
    hard_light(cb, cs)
  } else if mode_id == 10 {
    let v = cb - cs
    if v < 0.0 {
      -v
    } else {
      v
    }
  } else {
    cb + cs - 2.0 * cb * cs
  }
}

///|
fn hard_light(cb : Double, cs : Double) -> Double {
  if cs <= 0.5 {
    cb * cs * 2.0
  } else {
    let s2 = 2.0 * cs - 1.0
    cb + s2 - cb * s2
  }
}

///|
fn soft_light(cb : Double, cs : Double) -> Double {
  if cs <= 0.5 {
    cb - (1.0 - 2.0 * cs) * cb * (1.0 - cb)
  } else {
    let d = if cb <= 0.25 {
      ((16.0 * cb - 12.0) * cb + 4.0) * cb
    } else {
      cb.sqrt()
    }
    cb + (2.0 * cs - 1.0) * (d - cb)
  }
}

///|
fn lum_of(r : Double, g : Double, b : Double) -> Double {
  0.3 * r + 0.59 * g + 0.11 * b
}

///|
fn clip_color(r : Double, g : Double, b : Double) -> (Double, Double, Double) {
  let l = lum_of(r, g, b)
  let n = if r < g { if r < b { r } else { b } } else if g < b { g } else { b }
  let x = if r > g { if r > b { r } else { b } } else if g > b { g } else { b }
  let (r2, g2, b2) = if n < 0.0 {
    let k = l / (l - n)
    (l + (r - l) * k, l + (g - l) * k, l + (b - l) * k)
  } else {
    (r, g, b)
  }
  if x > 1.0 {
    let k = (1.0 - l) / (x - l)
    (l + (r2 - l) * k, l + (g2 - l) * k, l + (b2 - l) * k)
  } else {
    (r2, g2, b2)
  }
}

///|
fn set_lum(
  r : Double,
  g : Double,
  b : Double,
  l : Double,
) -> (Double, Double, Double) {
  let d = l - lum_of(r, g, b)
  clip_color(r + d, g + d, b + d)
}

///|
fn sat_of(r : Double, g : Double, b : Double) -> Double {
  let n = if r < g { if r < b { r } else { b } } else if g < b { g } else { b }
  let x = if r > g { if r > b { r } else { b } } else if g > b { g } else { b }
  x - n
}

///|
/// W3C SetSat：最大分量置 s、最小置 0、中间按比例；max==min（饱和度 0）全置 0。
fn set_sat(
  r : Double,
  g : Double,
  b : Double,
  s : Double,
) -> (Double, Double, Double) {
  // 找 min/max 通道下标
  let idx_min = if r <= g && r <= b {
    0
  } else if g <= r && g <= b {
    1
  } else {
    2
  }
  let idx_max = if r >= g && r >= b {
    0
  } else if g >= r && g >= b {
    1
  } else {
    2
  }
  let vals = [r, g, b]
  let maxv = vals[idx_max]
  let minv = vals[idx_min]
  if maxv <= minv {
    return (0.0, 0.0, 0.0)
  }
  let midv = vals[0] + vals[1] + vals[2] - maxv - minv
  let mid = (midv - minv) * s / (maxv - minv)
  let out = [0.0, 0.0, 0.0]
  out[idx_min] = 0.0
  out[idx_max] = s
  let idx_mid = 3 - idx_min - idx_max
  out[idx_mid] = mid
  (out[0], out[1], out[2])
}

///|
/// 非分离混合（HSL 系）：mode_id 12..15。
fn blend_nonseparable(
  mode_id : Int32,
  cb_r : Double,
  cb_g : Double,
  cb_b : Double,
  cs_r : Double,
  cs_g : Double,
  cs_b : Double,
) -> (Double, Double, Double) {
  if mode_id == 12 {
    // Hue: SetLum(SetSat(Cs, Sat(Cb)), Lum(Cb))
    let (r, g, b) = set_sat(cs_r, cs_g, cs_b, sat_of(cb_r, cb_g, cb_b))
    set_lum(r, g, b, lum_of(cb_r, cb_g, cb_b))
  } else if mode_id == 13 {
    // Saturation: SetLum(SetSat(Cb, Sat(Cs)), Lum(Cb))
    let (r, g, b) = set_sat(cb_r, cb_g, cb_b, sat_of(cs_r, cs_g, cs_b))
    set_lum(r, g, b, lum_of(cb_r, cb_g, cb_b))
  } else if mode_id == 14 {
    // Color: SetLum(Cs, Lum(Cb))
    set_lum(cs_r, cs_g, cs_b, lum_of(cb_r, cb_g, cb_b))
  } else {
    // Luminosity: SetLum(Cb, Lum(Cs))
    set_lum(cb_r, cb_g, cb_b, lum_of(cs_r, cs_g, cs_b))
  }
}

///|
fn to_byte01(v : Double) -> Int32 {
  let b = (v * 255.0 + 0.5).floor().to_int()
  if b < 0 {
    0
  } else if b > 255 {
    255
  } else {
    b
  }
}

///|
/// 纯色**不透明**源 + Normal 算子的整段直写快路径：免掉逐像素取源/预乘/
/// 混合的函数调用（背景填充是每帧最大宗的绘制，实测 400×120 一张 1.8ms，
/// 通用路径逐像素 blend 是热点）。不适用（非 Normal、透明或非纯色源）返回
/// false 走 composite_span。
fn composite_solid_span(
  d : FixedArray[Byte],
  width : Int32,
  y : Int32,
  x0 : Int32,
  x1 : Int32,
  op : BlendMode,
  src : RSource,
) -> Bool {
  if blend_mode_id(op) != 0 {
    return false
  }
  match src {
    SrcSolid(c) =>
      if c.a >= 255 {
        // 预乘 BGRA 字节序：不透明源预乘即原色
        let b = c.b.to_byte()
        let g = c.g.to_byte()
        let r = c.r.to_byte()
        let a = c.a.to_byte()
        let mut i = (y * width + x0) * 4
        let end = (y * width + x1) * 4
        while i < end {
          d[i] = b
          d[i + 1] = g
          d[i + 2] = r
          d[i + 3] = a
          i += 4
        }
        return true
      }
    _ => ()
  }
  false
}

///|
/// 一行像素的合成：cov 为每像素 0..256 覆盖，x0..x1 为列区间（已含裁剪）。
/// 源色按设备像素求值（渐变），op 决定合成式。out 为位图数据句柄（B,G,R,A
/// 预乘序），width 为位图宽。
fn composite_span(
  d : FixedArray[Byte],
  width : Int32,
  y : Int32,
  x0 : Int32,
  x1 : Int32,
  cov : FixedArray[Int32],
  op : BlendMode,
  src : RSource,
) -> Unit {
  let mode_id = blend_mode_id(op)
  let yf = y.to_double() + 0.5
  // 纯色不透明 + Normal：满覆盖段（cov==256 的连续 run）直写，免逐像素取源/
  // 预乘/混合（图表与描边的墨迹内部都是这种段）
  if mode_id == 0 {
    match src {
      SrcSolid(c) =>
        if c.a >= 255 {
          let b = c.b.to_byte()
          let g = c.g.to_byte()
          let r = c.r.to_byte()
          let a = c.a.to_byte()
          let mut i = x0
          while i < x1 {
            if cov[i] == 256 {
              let mut j = i + 1
              while j < x1 && cov[j] == 256 {
                j += 1
              }
              let mut k = (y * width + i) * 4
              let end = (y * width + j) * 4
              while k < end {
                d[k] = b
                d[k + 1] = g
                d[k + 2] = r
                d[k + 3] = a
                k += 4
              }
              i = j
            } else if cov[i] <= 0 {
              i += 1
            } else {
              // 部分覆盖：与通用分支同式（SrcSolid 不透明，premul_bytes 展开）
              let c2 = cov[i]
              let sa = (c2 * 255 + 128) / 256
              let sr = (c.r * c2 + 128) / 256
              let sg = (c.g * c2 + 128) / 256
              let sb = (c.b * c2 + 128) / 256
              let inv = 255 - sa
              let pi = (y * width + i) * 4
              d[pi] = (sb + (d[pi].to_int() * inv + 127) / 255).to_byte()
              d[pi + 1] = (sg + (d[pi + 1].to_int() * inv + 127) / 255).to_byte()
              d[pi + 2] = (sr + (d[pi + 2].to_int() * inv + 127) / 255).to_byte()
              d[pi + 3] = (sa + (d[pi + 3].to_int() * inv + 127) / 255).to_byte()
              i += 1
            }
          }
          return
        }
      _ => ()
    }
  }
  for x = x0; x < x1; x = x + 1 {
    let c = cov[x]
    if c <= 0 {
      continue
    }
    let sc = source_at(src, x.to_double() + 0.5, yf)
    let (sr, sg, sb, sa) = premul_bytes(sc, c)
    let i = (y * width + x) * 4
    let db = d[i].to_int()
    let dg = d[i + 1].to_int()
    let dr = d[i + 2].to_int()
    let da = d[i + 3].to_int()
    let (ob, og, or_, oa) : (Int32, Int32, Int32, Int32) = if mode_id == 0 {
      // Normal(Over)
      let inv = 255 - sa
      (
        sb + (db * inv + 127) / 255,
        sg + (dg * inv + 127) / 255,
        sr + (dr * inv + 127) / 255,
        sa + (da * inv + 127) / 255,
      )
    } else if mode_id >= 16 && mode_id != 21 {
      // Porter-Duff 其余八式：预乘域闭式（Xor 单列在 21 之外处理）
      if mode_id == 16 {
        (0, 0, 0, 0)
      } else if mode_id == 17 {
        (sb, sg, sr, sa)
      } else if mode_id == 18 {
        // SourceIn: cs·αb
        (sb * da / 255, sg * da / 255, sr * da / 255, sa * da / 255)
      } else if mode_id == 19 {
        // SourceOut: cs·(1−αb)
        let inv = 255 - da
        (sb * inv / 255, sg * inv / 255, sr * inv / 255, sa * inv / 255)
      } else if mode_id == 20 {
        // SourceAtop: cs·αb + ds·(1−αs)
        let inv_s = 255 - sa
        (
          sb * da / 255 + db * inv_s / 255,
          sg * da / 255 + dg * inv_s / 255,
          sr * da / 255 + dr * inv_s / 255,
          da,
        )
      } else if mode_id == 22 {
        // DestinationIn: ds·αs
        (db * sa / 255, dg * sa / 255, dr * sa / 255, da * sa / 255)
      } else if mode_id == 23 {
        // DestinationAtop: ds·αs + cs·(1−αb)
        let inv_d = 255 - da
        (
          db * sa / 255 + sb * inv_d / 255,
          dg * sa / 255 + sg * inv_d / 255,
          dr * sa / 255 + sr * inv_d / 255,
          sa,
        )
      } else {
        // 24 Xor: cs·(1−αb) + ds·(1−αs)
        let inv_d = 255 - da
        let inv_s = 255 - sa
        (
          sb * inv_d / 255 + db * inv_s / 255,
          sg * inv_d / 255 + dg * inv_s / 255,
          sr * inv_d / 255 + dr * inv_s / 255,
          sa * inv_d / 255 + da * inv_s / 255,
        )
      }
    } else if mode_id == 21 {
      // DestinationOver: ds + cs·(1−αb)
      let inv_d = 255 - da
      (
        db + sb * inv_d / 255,
        dg + sg * inv_d / 255,
        dr + sr * inv_d / 255,
        da + sa * inv_d / 255,
      )
    } else {
      // 16 个 W3C 混合模式（1..15）：非预乘域 B(Cb,Cs) + 规范合成式
      let cbr = unpremul_ch(dr, da).to_double() / 255.0
      let cbg = unpremul_ch(dg, da).to_double() / 255.0
      let cbb = unpremul_ch(db, da).to_double() / 255.0
      let csr = unpremul_ch(sr, sa).to_double() / 255.0
      let csg = unpremul_ch(sg, sa).to_double() / 255.0
      let csb = unpremul_ch(sb, sa).to_double() / 255.0
      let (br, bg, bb) = if mode_id >= 12 {
        blend_nonseparable(mode_id, cbr, cbg, cbb, csr, csg, csb)
      } else {
        (
          blend_separable(mode_id, cbr, csr),
          blend_separable(mode_id, cbg, csg),
          blend_separable(mode_id, cbb, csb),
        )
      }
      let as_ = sa.to_double() / 255.0
      let ab = da.to_double() / 255.0
      let out_ch = fn(cs : Double, b : Double, cb : Double) -> Int32 {
        let co = as_ * b + ab * (1.0 - as_) * cb + as_ * (1.0 - ab) * cs
        to_byte01(co)
      }
      (
        out_ch(csb, bb, cbb),
        out_ch(csg, bg, cbg),
        out_ch(csr, br, cbr),
        to_byte01(as_ + ab * (1.0 - as_)),
      )
    }
    d[i] = ob.to_byte()
    d[i + 1] = og.to_byte()
    d[i + 2] = or_.to_byte()
    d[i + 3] = oa.to_byte()
  }
}
