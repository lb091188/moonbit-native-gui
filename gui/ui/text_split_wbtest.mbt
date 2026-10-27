// 文本族与分隔布局回归：按宽量高、字阶预设、标签按宽折行、
// 分隔把手拖动改首栏尺寸与两端夹取。

///|
test "按宽量高：给宽换行后更高、字号越大行越高" {
  if !ui_text_guard() {
    return
  }
  let long = "这是一段足够长的文字，用来验证按盒宽折行之后量到的高度会明显变高，而不是永远按一行算。"
  let one_line = measure_text_height(long)
  let wrapped = measure_text_height(long, width=120.0)
  assert_true(wrapped > one_line * 1.5)
  // 字号档：18 比 12 高
  let t = measure_text_height(
    "短",
    font=@text.Font::new("", 18.0, weight=@text.SemiBold),
  )
  let s = measure_text_height("短", font=@text.Font::new("", 12.0))
  assert_true(t > s)
}

///|
test "字阶预设：字号读 theme 字阶令牌，颜色键在绘制期现取主题" {
  assert_eq(@style.text_heading.font_size, Some(@theme.font_size_title))
  assert_eq(@style.text_secondary.font_size, Some(@theme.font_size_secondary))
  assert_eq(@theme.font_size_title, 18.0)
  assert_eq(@theme.font_size_section, 14.0)
  assert_eq(@theme.font_size_body, 13.0)
  assert_eq(@theme.font_size_secondary, 12.0)
  // Accent 落主色、Secondary 落次要色（预设存 token 键，现取才见色值）
  assert_eq(
    @style.resolve_color(@style.text_accent.color.unwrap()),
    @theme.theme_primary(),
  )
  assert_eq(
    @style.resolve_color(@style.text_secondary.color.unwrap()),
    @theme.theme_text_secondary(),
  )
  let base_c = @style.resolve_color(@style.text_base.color.unwrap())
  let sec_c = @style.resolve_color(@style.text_secondary.color.unwrap())
  assert_true(base_c != sec_c)
}

///|
test "主题化标签：按 max_width 折行（高度随之变高），固定色覆盖角色色" {
  if !ui_text_guard() {
    return
  }
  let long = "标签文字很长很长很长很长很长很长很长很长很长很长很长很长"
  let (_, narrow) = mounted(
    text(long, max_width=80.0),
    200.0,
    300.0,
  )
  let (_, wide) = mounted(text(long, max_width=0.0), 200.0, 300.0)
  assert_true(narrow.rect.h > wide.rect.h)
  assert_true(wide.rect.w > 100.0)
  // 固定色：绘制像素取色（Accent 是主色，这里给死灰色）
  let (root, fixed) = mounted(
    text("固定色", color="#888888", wrap=false),
    160.0,
    40.0,
  )
  let bm = @render.Bitmap::new(160, 40)
  let p = @render.Painter::new(bm)
  root.paint(p)
  p.end()
  let mut found = false
  for x = 0; x < 160; x = x + 1 {
    for y = 0; y < 40; y = y + 1 {
      if bm.pixel(x, y).a > 0 && bm.pixel(x, y).r == 0x88 {
        found = true
      }
    }
  }
  assert_eq(found, true)
  let _ = fixed
}

///|
test "水平分隔：把手拖动改首栏宽，两端按最小尺寸夹取" {
  let (root, sp) = mounted(
    split(
      view([text("左")], background_color="bg_panel"),
      view([text("右")], background_color="fill_zebra"),
      ratio=0.5,
      min_first=80.0,
      min_second=80.0,
    ),
    400.0,
    200.0,
  )
  let first = sp.children()[0]
  let bar = sp.children()[1]
  assert_eq(bar.rect.w, 8.0)
  assert_eq(first.rect.w, 200.0)
  assert_eq(sp.children()[2].rect.w, 400.0 - 200.0 - 8.0)
  // 往右拖 60：首栏 260
  let _ = root.dispatch_pointer({
    kind: @widget.PointerKind::Down,
    x: bar.rect.x + 4.0,
    y: bar.rect.y + 40.0,
    button: 1,
    mods: 0,
  })
  let _ = root.dispatch_pointer_to(bar.id, {
    kind: @widget.PointerKind::Move,
    x: bar.rect.x + 4.0 + 60.0,
    y: bar.rect.y + 40.0,
    button: 1,
    mods: 0,
  })
  root.relayout(400.0, 200.0)
  assert_eq(first.rect.w, 260.0)
  // 拖到极右：夹在「总宽 − 把手 − 次栏最小」
  let _ = root.dispatch_pointer_to(bar.id, {
    kind: @widget.PointerKind::Move,
    x: bar.rect.x + 4000.0,
    y: bar.rect.y + 40.0,
    button: 1,
    mods: 0,
  })
  root.relayout(400.0, 200.0)
  assert_eq(first.rect.w, 312.0)
  // 拖到极左：夹在首栏最小
  let _ = root.dispatch_pointer_to(bar.id, {
    kind: @widget.PointerKind::Move,
    x: bar.rect.x - 4000.0,
    y: bar.rect.y + 40.0,
    button: 1,
    mods: 0,
  })
  root.relayout(400.0, 200.0)
  assert_eq(first.rect.w, 80.0)
  // 松手后再移动不再改
  let _ = root.dispatch_pointer_to(bar.id, {
    kind: @widget.PointerKind::Up,
    x: bar.rect.x + 4.0,
    y: bar.rect.y + 40.0,
    button: 1,
    mods: 0,
  })
  let _ = root.dispatch_pointer_to(bar.id, {
    kind: @widget.PointerKind::Move,
    x: bar.rect.x + 200.0,
    y: bar.rect.y + 40.0,
    button: 1,
    mods: 0,
  })
  root.relayout(400.0, 200.0)
  assert_eq(first.rect.w, 80.0)
}

///|
test "垂直分隔：把手上下拖动改首栏高，按最小高度夹取" {
  let (root, sp) = mounted(
    split(
      view([text("上")], background_color="bg_panel"),
      view([text("下")], background_color="fill_zebra"),
      direction=Vertical,
      ratio=0.5,
      min_first=50.0,
      min_second=50.0,
    ),
    300.0,
    240.0,
  )
  let first = sp.children()[0]
  let bar = sp.children()[1]
  assert_eq(bar.rect.h, 8.0)
  assert_eq(first.rect.h, 120.0)
  let _ = root.dispatch_pointer({
    kind: @widget.PointerKind::Down,
    x: bar.rect.x + 40.0,
    y: bar.rect.y + 4.0,
    button: 1,
    mods: 0,
  })
  let _ = root.dispatch_pointer_to(bar.id, {
    kind: @widget.PointerKind::Move,
    x: bar.rect.x + 40.0,
    y: bar.rect.y + 4.0 + 40.0,
    button: 1,
    mods: 0,
  })
  root.relayout(300.0, 240.0)
  assert_eq(first.rect.h, 160.0)
  let _ = root.dispatch_pointer_to(bar.id, {
    kind: @widget.PointerKind::Move,
    x: bar.rect.x + 40.0,
    y: bar.rect.y + 4000.0,
    button: 1,
    mods: 0,
  })
  root.relayout(300.0, 240.0)
  assert_eq(first.rect.h, 240.0 - 8.0 - 50.0)
}
