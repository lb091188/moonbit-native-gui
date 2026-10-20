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
