// 变体默认层收口回归：切深浅后内置变体类重折生效（divider-line 档）、
// 用户 class 仍压在默认层之上。

///|
test "fold_style_variant：切深浅后变体生效（divider-line 档重折）" {
  @theme.theme_apply(@theme.default_theme())
  let (root, w) = mounted(divider(), 200.0, 8.0)
  let _ = paint(root, 200, 8)
  // 浅档：默认层 = border 色
  let light_bg = match @style.style_for(w).background_color {
    Some(@style.Var(name)) => name
    _ => ""
  }
  assert_eq(light_bg, "border")
  // 切深色：订阅重折，深档提亮生效
  @theme.theme_apply(@theme.dark_theme())
  let dark_bg = match @style.style_for(w).background_color {
    Some(@style.Var(name)) => name
    _ => ""
  }
  assert_eq(dark_bg, "text_secondary")
  // 复原浅色基准
  @theme.theme_apply(@theme.default_theme())
}

///|
test "fold_style_variant：用户 class 仍压在变体默认层上" {
  @theme.theme_apply(@theme.default_theme())
  let (root, w) = mounted(
    divider(class=[@style.style(background_color="primary")]),
    200.0,
    8.0,
  )
  let _ = paint(root, 200, 8)
  let bg = match @style.style_for(w).background_color {
    Some(@style.Var(name)) => name
    _ => ""
  }
  assert_eq(bg, "primary")
  @theme.theme_apply(@theme.default_theme())
}
