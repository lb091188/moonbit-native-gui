// 内置托盘图标回归：单色紧版（黑/白两档）的像素口径——纯色、四角透明、
// 内容框收紧；以及默认档与黑档一致。

///|
fn icon_bbox(px : Bytes, w : Int32, h : Int32) -> (Int32, Int32, Int32, Int32) {
  let mut x0 = w
  let mut y0 = h
  let mut x1 = -1
  let mut y1 = -1
  for y in 0..<h {
    for x in 0..<w {
      if px[(y * w + x) * 4].to_int() > 0 {
        if x < x0 {
          x0 = x
        }
        if x > x1 {
          x1 = x
        }
        if y < y0 {
          y0 = y
        }
        if y > y1 {
          y1 = y
        }
      }
    }
  }
  (x0, y0, x1, y1)
}

///|
test "mono_icon_pixmap：黑白两档纯色、四角透明、内容框收紧" {
  let (lw, lh, light) = mono_icon_pixmap(false)
  let (dw, dh, dark) = mono_icon_pixmap(true)
  assert_eq(lw, 32)
  assert_eq(lh, 32)
  assert_eq(dw, 32)
  assert_eq(dh, 32)
  // 四角全透明（内容框收紧后不应再顶到画布边缘）
  for p in [(0, 0), (31, 0), (0, 31), (31, 31)] {
    let (x, y) = p
    assert_eq(light[(y * 32 + x) * 4].to_int(), 0)
    assert_eq(dark[(y * 32 + x) * 4].to_int(), 0)
  }
  // 每个不透明像素 RGB 为纯黑 / 纯白；alpha 落在 0/63/127/191/255 五档
  for i in 0..<(32 * 32) {
    let o = i * 4
    let a = light[o].to_int()
    assert_true(a == 0 || a == 63 || a == 127 || a == 191 || a == 255)
    if a > 0 {
      assert_eq(light[o + 1].to_int(), 0)
      assert_eq(light[o + 2].to_int(), 0)
      assert_eq(light[o + 3].to_int(), 0)
      assert_eq(dark[o + 1].to_int(), 255)
      assert_eq(dark[o + 2].to_int(), 255)
      assert_eq(dark[o + 3].to_int(), 255)
    }
  }
  // 内容框收紧：横向留白 ≤ 4px、纵向 ≤ 2px，且不是缩成一小团
  let (x0, y0, x1, y1) = icon_bbox(light, 32, 32)
  assert_true(x0 <= 4)
  assert_true(32 - 1 - x1 <= 4)
  assert_true(y0 <= 2)
  assert_true(32 - 1 - y1 <= 2)
  assert_true(x1 - x0 + 1 >= 24)
  assert_true(y1 - y0 + 1 >= 28)
}

///|
test "default_icon_pixmap：默认即浅色档黑色单色" {
  let (w, h, def) = default_icon_pixmap()
  let (_, _, light) = mono_icon_pixmap(false)
  assert_eq(w, 32)
  assert_eq(h, 32)
  let mut same = true
  for i in 0..<def.length() {
    if def[i] != light[i] {
      same = false
    }
  }
  assert_true(same)
}
