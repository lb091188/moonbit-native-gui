// 盒式模糊原语的像素级回归：均匀图不变、硬边出渐变、半径 <1 无操作。

///|
fn fill_cols(bm : Bitmap, x0 : Int32, x1 : Int32, hex : String) -> Unit {
  let p = Painter::new(bm)
  p.set_fill_color(hex)
  p.fill_rect(x0.to_double(), 0.0, (x1 - x0).to_double(), bm.height.to_double())
  p.end()
}

///|
fn rgb_at(bm : Bitmap, x : Int32, y : Int32) -> (Int32, Int32, Int32) {
  let c = bm.pixel(x, y)
  (c.r, c.g, c.b)
}

///|
test "box_blur_region：均匀图不变" {
  let bm = Bitmap::new(8, 8)
  fill_cols(bm, 0, 8, "#c8281e")
  bm.box_blur_region(0, 0, 8, 8, 3)
  assert_eq(rgb_at(bm, 0, 0), (200, 40, 30))
  assert_eq(rgb_at(bm, 7, 7), (200, 40, 30))
}

///|
test "box_blur_region：硬边变渐变，远场不变，半径 <1 无操作" {
  let bm = Bitmap::new(8, 8)
  fill_cols(bm, 0, 4, "#ffffff")
  fill_cols(bm, 4, 8, "#000000")
  // 无操作档
  bm.box_blur_region(0, 0, 8, 8, 0)
  assert_eq(rgb_at(bm, 3, 3), (255, 255, 255))
  assert_eq(rgb_at(bm, 4, 4), (0, 0, 0))
  // 模糊后：边界两侧变灰；远场大体保持本色——三趟盒式模糊下边界渐变会
  // 向内渗几格（clamp 窗的标准行为），左缘仍偏白、右缘仍偏黑即可
  bm.box_blur_region(0, 0, 8, 8, 2)
  let l = rgb_at(bm, 3, 3)
  let r = rgb_at(bm, 4, 4)
  // 边界左侧仍是偏白、右侧偏黑、都不是纯端值
  assert_true(l.0 < 255 && l.0 > 127)
  assert_true(r.0 > 0 && r.0 < 128)
  assert_true(rgb_at(bm, 0, 3).0 > 200)
  assert_true(rgb_at(bm, 7, 3).0 < 55)
  // 单调面：越靠近边界越接近中灰
  let l2 = rgb_at(bm, 2, 3)
  assert_true(l2.0 > l.0)
}

///|
test "box_blur_region：区域越界裁到位图" {
  let bm = Bitmap::new(4, 4)
  fill_cols(bm, 0, 4, "#0a141e")
  // 区域越界不出错、均匀图仍不变
  bm.box_blur_region(-3, -3, 20, 20, 2)
  assert_eq(rgb_at(bm, 0, 0), (10, 20, 30))
  assert_eq(rgb_at(bm, 3, 3), (10, 20, 30))
}

///|
test "shift_rows：上下平移对位、列范围外的像素不动、越界夹取" {
  let bm = Bitmap::new(8, 6)
  // 每行一个灰阶：行 y 填 y*20
  let colors = ["#000000", "#141414", "#282828", "#3C3C3C", "#505050", "#646464"]
  for y = 0; y < 6; y = y + 1 {
    let p = Painter::new(bm)
    p.set_fill_color(colors[y])
    p.fill_rect(0.0, y.to_double(), 8.0, 1.0)
    p.end()
  }
  // 下移 2 行：目标行 y 取源行 y-2；顶部两行保留原值
  bm.shift_rows(0, 8, 0, 6, 2)
  assert_eq(rgb_at(bm, 0, 0), (0, 0, 0))
  assert_eq(rgb_at(bm, 0, 2), (0, 0, 0))
  assert_eq(rgb_at(bm, 0, 3), (20, 20, 20))
  assert_eq(rgb_at(bm, 0, 5), (60, 60, 60))
  // 上移 2 行：目标行 y 取源行 y+2
  bm.shift_rows(0, 8, 0, 6, -2)
  assert_eq(rgb_at(bm, 0, 0), (0, 0, 0))
  assert_eq(rgb_at(bm, 0, 1), (20, 20, 20))
  assert_eq(rgb_at(bm, 0, 3), (60, 60, 60))
  // 列范围限制：只搬 [2,4)，列 0 不动
  let before = rgb_at(bm, 0, 4)
  bm.shift_rows(2, 4, 0, 6, -1)
  assert_eq(rgb_at(bm, 0, 4), before)
  // 越界：整幅落在位图外也不崩、不动
  bm.shift_rows(100, 200, 0, 6, 3)
}
