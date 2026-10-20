// 柔焦模糊：同尺寸、块平均回放、边缘变软而整体色调不变。

///|
test "soft_blur：尺寸不变，纯色区域保持原色" {
  let bm = Bitmap::new(32, 24)
  bm.fill_area(0, 0, 32, 24, { r: 200, g: 80, b: 40, a: 255 })
  let out = bm.soft_blur()
  assert_eq((out.width, out.height), (32, 24))
  let c = out.pixel(10, 10)
  assert_eq((c.r, c.g, c.b, c.a), (200, 80, 40, 255))
}

///|
test "soft_blur：硬边界两侧互相渗透（模糊真的扩散了）" {
  let bm = Bitmap::new(64, 16)
  bm.fill_area(0, 0, 32, 16, { r: 255, g: 0, b: 0, a: 255 })
  bm.fill_area(32, 0, 64, 16, { r: 0, g: 0, b: 255, a: 255 })
  let out = bm.soft_blur()
  // 边界外一像素仍应接近纯色；边界附近应出现双色混合
  let near = out.pixel(32, 8)
  assert_true(near.r > 16 && near.b > 16)
  let far_left = out.pixel(4, 8)
  assert_true(far_left.r > 240 && far_left.b < 16)
}

///|
test "soft_blur：全透明输入得到全透明输出" {
  let bm = Bitmap::new(16, 16)
  let out = bm.soft_blur()
  assert_eq(out.pixel(8, 8).a, 0)
}

///|
test "backdrop_blur：只糊矩形内已画内容，矩形外保持原样" {
  let bm = Bitmap::new(80, 40)
  let p = Painter::new(bm)
  p.set_fill_color("#ff0000")
  p.fill_rect(0.0, 0.0, 40.0, 40.0)
  p.set_fill_color("#0000ff")
  p.fill_rect(40.0, 0.0, 40.0, 40.0)
  let ok = p.backdrop_blur(20.0, 10.0, 40.0, 20.0)
  p.end()
  assert_true(ok)
  // 矩形内、边界附近应出现红蓝混合
  let mixed = bm.pixel(41, 20)
  assert_true(mixed.r > 32 && mixed.b > 32)
  // 矩形外保持原样：上边一行仍是纯红/纯蓝
  assert_eq((bm.pixel(5, 2).r, bm.pixel(5, 2).b), (255, 0))
  assert_eq((bm.pixel(70, 2).b, bm.pixel(70, 2).r), (255, 0))
}
