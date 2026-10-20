// 圆角总开关（落点在 `@theme` 令牌，默认开圆角）：`set_square_corners(true)`
// 关圆角，样式槽半径按 0 解析；`false` 恢复圆角后按配置回值。
// 没配半径的控件样式槽保持「未设」——各组件绘制期自己现取 `@theme.radius_*()` 令牌。

///|
test "圆角总开关：关圆角后样式槽半径按 0 解析，恢复后回值" {
  set_square_corners(false)
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
test "圆角总开关：没配半径的槽位保持未设，令牌回落由组件负责" {
  set_square_corners(false)
  let w = @widget.Widget::new()
  apply(w, style(background_color="bg_panel"))
  assert_eq(number_of(resolved(w).border_radius, -1.0), -1.0)
  set_square_corners(true)
  assert_eq(number_of(resolved(w).border_radius, -1.0), -1.0)
  set_square_corners(false)
  assert_eq(number_of(resolved(w).border_radius, -1.0), -1.0)
}

///|
test "圆角令牌：开关联动 radius_ctrl / radius_card / radius_overlay" {
  set_square_corners(false)
  assert_eq(@theme.radius_ctrl(), 4.0)
  set_square_corners(true)
  assert_eq(@theme.radius_ctrl(), 0.0)
  assert_eq(@theme.radius_card(), 0.0)
  assert_eq(@theme.radius_overlay(), 0.0)
  set_square_corners(false)
  assert_eq(@theme.radius_ctrl(), 4.0)
  assert_eq(@theme.radius_card(), 6.0)
  assert_eq(@theme.radius_overlay(), 8.0)
}
