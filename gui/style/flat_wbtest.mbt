// 圆角总开关：出口统一把半径压 0，关掉后按配置恢复；整窗重绘由调用方广播。

///|
test "圆角总开关：开启后圆角按 0 解析，关闭后恢复" {
  let w = @widget.Widget::new()
  apply(w, style(border_radius=8.0))
  assert_eq(number_of(style_for(w).border_radius, -1.0), 8.0)
  set_square_corners(true)
  assert_eq(number_of(style_for(w).border_radius, -1.0), 0.0)
  assert_eq(number_of(resolved(w).border_radius, -1.0), 0.0)
  set_square_corners(false)
  assert_eq(number_of(style_for(w).border_radius, -1.0), 8.0)
}

///|
test "圆角总开关：没配半径的控件在开启时也读到 0" {
  let w = @widget.Widget::new()
  apply(w, style(background_color="bg_panel"))
  assert_eq(number_of(resolved(w).border_radius, -1.0), -1.0)
  set_square_corners(true)
  assert_eq(number_of(resolved(w).border_radius, -1.0), 0.0)
  set_square_corners(false)
  assert_eq(number_of(resolved(w).border_radius, -1.0), -1.0)
}
