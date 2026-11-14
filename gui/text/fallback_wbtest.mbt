// 回退测量器白盒：纯 MoonBit 估算、零 FFI，任何后端形态（含裸容器占位档）
// 都可跑。只断言「合理 + 单调 + 约束收敛」，不断言与任何真字体的绝对值一致。

test "回退：全角一字一倍字号、半角约 0.55 倍" {
  let cjk = fallback_char_w('甲', 20.0)
  let lat = fallback_char_w('A', 20.0)
  assert_eq(cjk, 20.0)
  assert_eq(lat, 20.0 * 0.55)
  // 省略号按全角保守估
  assert_eq(fallback_char_w('…', 20.0), 20.0)
}

test "回退：文本更长更宽、字号更大更宽更高（单调性）" {
  let short = fallback_measure("甲", 13.0, "", 0, false, false, 0.0)
  let long = fallback_measure("甲甲甲", 13.0, "", 0, false, false, 0.0)
  let big = fallback_measure("甲甲甲", 26.0, "", 0, false, false, 0.0)
  assert_eq(long.width > short.width, true)
  assert_eq(big.width > long.width, true)
  assert_eq(big.height > long.height, true)
}

test "回退：空文本宽 0、高一行行盒" {
  let m = fallback_measure("", 13.0, "", 0, false, false, 0.0)
  assert_eq(m.width, 0.0)
  assert_eq(m.height, fallback_line_h(13.0))
  assert_eq(m.baseline, fallback_ascent(13.0))
}

test "回退：字距逐字累加" {
  let no_sp = fallback_measure("甲甲", 13.0, "", 0, false, false, 0.0)
  let sp = fallback_measure("甲甲", 13.0, "", 0, false, false, 2.0)
  assert_eq(sp.width - no_sp.width, 4.0)
}

test "回退：窄约束折行，行高按行数增长" {
  // 一个汉字 13px：约束 30px 时每行最多 2 字，3 字折 2 行
  let one = fallback_measure("甲甲", 13.0, "", 30, false, true, 0.0)
  let two = fallback_measure("甲甲甲", 13.0, "", 30, false, true, 0.0)
  assert_eq(one.height, fallback_line_h(13.0))
  assert_eq(two.height, fallback_line_h(13.0) * 2)
  // 折行后的整段宽不超约束
  assert_eq(two.width <= 30.0, true)
}

test "回退：省略截断收敛到约束内且补 …" {
  let m = fallback_measure("甲甲甲甲甲", 13.0, "", 40, true, false, 0.0)
  assert_eq(m.width <= 40.0, true)
  // 40px 放两个全角（26px）+ …（13px）= 39px，正好 3 字宽
  assert_eq(m.width, 39.0)
}

test "回退：拉丁在空格处断行，行首无残空格" {
  let lines = fallback_wrap_lines("ab cd ef", 13.0, 0.0, 15)
  // 半角 7.15px/字：约束 15px 每行 2 字——"ab" / "cd" / "ef"
  assert_eq(lines.length(), 3)
  assert_eq(lines[0], "ab")
  assert_eq(lines[1], "cd")
  assert_eq(lines[2], "ef")
}

test "回退：字体版与族名版同口径（字重斜体不参与估算）" {
  let plain = Font::new("", 13.0)
  let bold_italic = Font::new("", 13.0, weight=Bold, style=Italic)
  let a = fallback_measure_font("甲甲", plain, 0, false, false)
  let b = fallback_measure_font("甲甲", bold_italic, 0, false, false)
  assert_eq(a.width, b.width)
  assert_eq(a.height, b.height)
}

test "回退：clamp_lines 在回退档也工作（行数钳制补 …）" {
  // 复合入口：真后端不可用时走估算，3 行限 1 行应截断补 …
  let font = Font::new("", 13.0)
  let clamped = clamp_lines("甲甲甲甲甲", font, 15, 1)
  assert_eq(clamped.contains("…"), true)
  let m = measure_font(clamped, font, max_width=15, wrap=true)
  assert_eq(m is Some(_), true)
  match m {
    Some(mm) => assert_eq(mm.height <= fallback_line_h(13.0), true)
    None => assert_eq(false, true)
  }
}
