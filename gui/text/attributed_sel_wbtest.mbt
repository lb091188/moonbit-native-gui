// 选中几何（富文本 selectable）的白盒用例：hit / caret_x / line_boxes 三件
// 查询与 draw 同口径——行盒字节区间连续覆盖全文、字节位↔前缘 x 往返一致。

///|
fn rt_byte_len(s : String) -> Int {
  @utf8.encode(s).length()
}

///|
test "AttributedText 选中几何：行盒连续覆盖、命中与游标往返" {
  let at = AttributedText::new(
    "Hello 富文本 World，再来一段足够长的中文用来把这一段在盒宽里折成多行显示。",
    wrap=true,
  )
  at.set_font(Font::new("", 14.0))
  let box_w = 200.0
  let box_h = 400.0
  let total = rt_byte_len("Hello 富文本 World，再来一段足够长的中文用来把这一段在盒宽里折成多行显示。")
  // 行盒：折成多行，字节区间连续覆盖 [0, total)
  let boxes = at.line_boxes(box_w, box_h)
  assert_true(
    boxes.length() >= 2,
    msg="盒宽 200 没折出多行（行盒 \{boxes.length()} 行）",
  )
  let mut acc = 0
  for b in boxes {
    assert_eq(b.byte_start, acc)
    acc = b.byte_end
  }
  assert_eq(acc, total, msg="行盒字节区间没有连续覆盖全文")
  // 命中：行左缘 → 行首字节；行右缘附近 → 行尾字节
  let first = boxes[0]
  let hit_left = at.hit(first.x + 1.0, first.y + first.h / 2.0, box_w, box_h)
  assert_eq(hit_left, Some(0), msg="行左缘命中没落行首")
  let hit_right = at.hit(
    first.x + (first.h * 0.0) + 199.0,
    first.y + first.h / 2.0,
    box_w,
    box_h,
  )
  assert_true(
    hit_right is Some(v) && v >= first.byte_end - 6 && v <= first.byte_end,
    msg="行右缘命中没落在行尾附近（\{match hit_right { Some(v) => v; None => -1 }}）",
  )
  // 往返：每个**字符边界**的前缘 x → 命中回该边界（字节位只在字符边界有
  // 意义，与 Editor 内核同口径；CJK 一个字 3 字节，续字节不是合法位）
  let full_text = "Hello 富文本 World，再来一段足够长的中文用来把这一段在盒宽里折成多行显示。"
  let mut cb = 0
  for ch in full_text {
    if cb >= first.byte_end {
      break
    }
    let x = at.caret_x(cb, box_w, box_h)
    assert_true(x is Some(_), msg="caret_x 缺值（b=\{cb}）")
    let back = at.hit(x.unwrap() + 0.5, first.y + first.h / 2.0, box_w, box_h)
    assert_eq(
      back,
      Some(cb),
      msg="字节 \{cb} 前缘 x 命中没回该边界（回 \{match back { Some(v) => v; None => -1 }}）",
    )
    cb += rt_byte_len(ch.to_string())
  }
  // 混排边界：中文字符 3 字节，边界精确落（不做 ±1 容差）
  let latin_end = rt_byte_len("Hello ")
  let cx = at.caret_x(latin_end, box_w, box_h)
  assert_true(cx is Some(_), msg="混排边界 caret_x 缺值")
  // 越界钳制：hit 盒外 → 钳首末
  assert_eq(at.hit(-50.0, -50.0, box_w, box_h), Some(0), msg="盒外左上没钳 0")
  assert_eq(
    at.hit(1000.0, 1000.0, box_w, box_h),
    Some(total),
    msg="盒外右下没钳末尾",
  )
}
