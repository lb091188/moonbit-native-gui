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
