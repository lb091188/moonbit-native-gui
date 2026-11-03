// TextLayout 回归：折行、像素↔字节命中、光标坐标——全部用注入的假测宽器，
// 不碰平台桥，无显示环境也能判定（1 字节 = 10 逻辑像素）。

///|
/// 假测宽器：按字节数线性给宽，好让断言写得出整数。
fn fake_width(_t : String, from : Int, to : Int) -> Double {
  (to - from).to_double() * 10.0
}

///|
test "build：pad 从可用宽里扣，单段超宽不拆词" {
  // 盒宽 45、pad 5 → 可用 35；"abcd" 是一个拉丁词段（40 > 35）→ 整段留一行
  let lay = TextLayout::build("abcd", 45.0, fake_width, 20.0, pad=5.0)
  assert_eq(lay.lines.length(), 1)
  assert_eq(lay.lines[0].width, 40.0)
}

///|
test "build：按段贪心折行，断行处不留行首空格" {
  let lay = TextLayout::build("ab cd", 45.0, fake_width, 20.0, pad=5.0)
  assert_eq(lay.lines.length(), 2)
  assert_eq((lay.lines[0].start, lay.lines[0].end), (0, 3))
  assert_eq((lay.lines[1].start, lay.lines[1].end), (3, 5))
}

///|
test "line_of / caret_x / caret_y：行序换算与滚动平移" {
  let lay = TextLayout::build("ab cd", 45.0, fake_width, 20.0, pad=5.0)
  assert_eq(lay.line_of(0), 0)
  assert_eq(lay.line_of(4), 1)
  // 越界夹到末行
  assert_eq(lay.line_of(99), 1)
  assert_eq(lay.caret_x(1), 15.0)
  assert_eq(lay.caret_x(4), 15.0)
  assert_eq(lay.caret_y(4), 25.0)
  // 滚出去 20 像素：同一插入点上移一行
  let scrolled = TextLayout::build(
    "ab cd",
    45.0,
    fake_width,
    20.0,
    pad=5.0,
    offset_y=20.0,
  )
  assert_eq(scrolled.caret_y(4), 5.0)
}

///|
test "hit：按 y 定行、行内取不超过 x 的最右边界" {
  let lay = TextLayout::build("ab cd", 45.0, fake_width, 20.0, pad=5.0)
  assert_eq(lay.hit(25.0, 5.0), 2)
  assert_eq(lay.hit(35.0, 5.0), 3)
  // 第二行：行首字节是 3，x 只按行内相对宽算
  assert_eq(lay.hit(15.0, 25.0), 4)
  // y 越界夹到首末行
  assert_eq(lay.hit(15.0, -100.0), 1)
  assert_eq(lay.hit(15.0, 10000.0), 4)
}

///|
test "hit：不停在多字节码点中间" {
  // "中a"：'中' 占 3 字节（0..2 是续字节），按假宽度 1 字节 10 像素
  let lay = TextLayout::build("中a", 1000.0, fake_width, 20.0)
  assert_eq(lay.lines.length(), 1)
  assert_eq(lay.hit(25.0, 0.0), 0)
  assert_eq(lay.hit(35.0, 0.0), 3)
}

///|
test "空文本也给一行，命中与光标都答 0" {
  let lay = TextLayout::build("", 45.0, fake_width, 20.0, pad=5.0)
  assert_eq(lay.lines.length(), 1)
  assert_eq(lay.caret_x(0), 5.0)
  assert_eq(lay.caret_y(0), 5.0)
  assert_eq(lay.hit(20.0, 10.0), 0)
}

///|
test "wrap_units：非 ASCII 码点各自一段，ASCII 按类成段" {
  let u = wrap_units("ab 中c", 0, 7)
  assert_eq(u, [(0, 2), (2, 3), (3, 6), (6, 7)])
}

///|
test "rects：选区按显示行切开，坐标含 pad 并扣滚动偏移" {
  let lay = TextLayout::build("ab cd", 45.0, fake_width, 20.0, pad=5.0)
  let all = lay.rects(0, 5)
  assert_eq(all.length(), 2)
  assert_eq((all[0].x, all[0].y, all[0].w, all[0].h), (5.0, 5.0, 30.0, 20.0))
  assert_eq((all[1].x, all[1].y, all[1].w), (5.0, 25.0, 20.0))
  // 单行内一段：起算 x 按行首到 start 的宽度推
  let one = lay.rects(1, 2)
  assert_eq((one.length(), one[0].x, one[0].w), (1, 15.0, 10.0))
  // 跨行区间各出一段
  let cross = lay.rects(2, 4)
  assert_eq((cross.length(), cross[0].x, cross[1].x), (2, 25.0, 5.0))
  // 空区间与反向区间都给空数组（调用方不画）
  assert_eq(lay.rects(3, 3).length(), 0)
  assert_eq(lay.rects(4, 1).length(), 0)
  // 滚出去 20 像素：每段上移一行
  let scrolled = TextLayout::build(
    "ab cd",
    45.0,
    fake_width,
    20.0,
    pad=5.0,
    offset_y=20.0,
  )
  assert_eq(scrolled.rects(0, 5)[1].y, 5.0)
}
