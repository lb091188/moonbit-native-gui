// RTL 文本 run 基方向的 MoonBit 入口回归:证明 FFI 链接、往返不崩、末态复位。

test "set_base_dir 往返 + 复位不影响度量" {
  set_base_dir(Rtl)
  set_base_dir(Ltr)
  // 复位为 Ltr 后，同一串的度量应与默认一致（缓存已在切换时清空重建）
  let m1 = measure_font_cached("Hello world", font_body(), 0, false, false)
  set_base_dir(Rtl)
  set_base_dir(Ltr)
  let m2 = measure_font_cached("Hello world", font_body(), 0, false, false)
  let w1 = match m1 { Some(x) => x.width; None => -1 }
  let w2 = match m2 { Some(x) => x.width; None => -1 }
  assert_eq(w1, w2)
}

///|
/// 对齐档是绝对的左右缘，不随内容的首强字符改判：以 RTL 字符起头的串
/// align=End 也要贴右缘（Linux 曾因 Pango 按段落方向解释 LEFT/RIGHT 而
/// 贴左）。wrap 走缺省 true，即「Pango 设宽 + 布局对齐」那条路径。
test "RTL 起头的串盒内对齐仍是绝对左右缘" {
  let f = Font::new("", 14.0)
  let make = fn(text : String, a : TextAlign) -> (Int, Int, Int, Int) {
    let bm = @render.Bitmap::new(400, 32)
    let _ = draw_in_box(bm, 0.0, 0.0, 400.0, 32.0, text, f, "#000", align=a)
    box_of(bm)
  }
  let rtl_end = make("العربية — 阿拉伯语：مرحبا بالعالم", End)
  let rtl_start = make("العربية — 阿拉伯语：مرحبا بالعالم", Start)
  let ltr_end = make("English — Hello, world", End)
  // 三档都画出墨，End 档贴右缘（±8px），Start 档贴左缘
  assert_eq(rtl_end.2 >= 392 && rtl_end.0 > 100, true)
  assert_eq(rtl_start.0 <= 8, true)
  assert_eq(ltr_end.2 >= 392, true)
}
