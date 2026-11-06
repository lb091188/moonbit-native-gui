// terminal 绘制面回归：TermTheme 深浅两盘、ANSI 色解析（16/立方/灰度/直通）、
// 绝对行号与视口映射、绘制冒烟（ANSI 色与文本出墨、光标与滚动条不崩）。

///|
test "TermTheme：深浅基底两套盘，16 项齐全且可辨" {
  let dark = term_theme_of(@theme.dark_theme())
  let light = term_theme_of(@theme.default_theme())
  assert_eq(dark.ansi.length(), 16)
  assert_eq(light.ansi.length(), 16)
  // 深浅盘的「黑」位不同（深底提亮、浅底压暗），白位同理
  assert_false(dark.ansi[0] == light.ansi[0])
  for c in dark.ansi {
    assert_true(c.has_prefix("#"))
  }
  // 光标/选区随主色
  assert_eq(dark.cursor, @theme.dark_theme().primary)
}

///|
test "ANSI 色解析：16 盘/立方端点/灰度端点/直通/默认" {
  let tt = term_theme_current()
  assert_eq(term_color_hex(tt, Indexed(3), true), tt.ansi[3])
  assert_eq(term_color_hex(tt, Indexed(15), false), tt.ansi[15])
  assert_eq(term_color_hex(tt, Indexed(16), true), "#000000")
  assert_eq(term_color_hex(tt, Indexed(231), true), "#ffffff")
  assert_eq(term_color_hex(tt, Indexed(232), true), "#080808")
  assert_eq(term_color_hex(tt, Indexed(255), true), "#eeeeee")
  assert_eq(term_color_hex(tt, Rgb(1, 2, 3), true), "#010203")
  assert_eq(term_color_hex(tt, Default, true), tt.fg)
  assert_eq(term_color_hex(tt, Default, false), tt.bg)
  // 越界索引兜底
  assert_eq(term_color_hex(tt, Indexed(999), true), tt.fg)
}

///|
test "绝对行号与视口映射：滚上后 ring/屏幕统一编址" {
  let t = Terminal::new(cols=10, rows=2, scrollback=10)
  t.feed("a\nb\nc")
  // ring=[a]，屏幕=[b, c]，total_rows=1
  assert_eq(t.total_rows, 1)
  assert_eq(t.view_abs(0), Some(1))
  assert_eq(t.view_abs(1), Some(2))
  match t.row_by_abs(0) {
    Some(row) => assert_eq(trim_end_spaces(row_text(row)), "a")
    None => assert_true(false)
  }
  t.scroll_lines(1)
  assert_eq(t.view_abs(0), Some(0))
  assert_eq(t.view_abs(1), Some(1))
  // 滚到顶：视口停在最旧一回看行（越不过缓冲头）
  t.scroll_lines(9)
  assert_eq(t.view_offset, 1)
  assert_eq(t.view_abs(0), Some(0))
  assert_eq(t.view_abs(1), Some(1))
}

///|
test "绘制冒烟：ANSI 色文本与光标出墨，不崩" {
  let term = Terminal::new(cols=20, rows=6)
  term.feed("\u{1b}[31mred\u{1b}[32mgreen\u{1b}[0m plain\n第二行中文\n")
  term.feed("\u{1b}[1;44mbold on blue\u{1b}[0m\n")
  let root = @widget.Widget::new()
  root.set_size(320.0, 160.0)
  root.set_column()
  let n = terminal(term, height=140.0, focus_id=1, blink=false)
  let w = n.mount_into(root)
  root.relayout(320.0, 160.0)
  let bm = @render.Bitmap::new(320, 160)
  let p = @render.Painter::new(bm)
  root.paint(p)
  p.end()
  let bg = bm.pixel(2, 2)
  let mut ink = 0
  for y = 0; y < 160; y = y + 1 {
    for x = 0; x < 320; x = x + 1 {
      let c = bm.pixel(x, y)
      if (c.r, c.g, c.b, c.a) != (bg.r, bg.g, bg.b, bg.a) {
        ink = ink + 1
      }
    }
  }
  assert_true(ink > 200, msg="终端绘制冒烟：整帧近乎空白")
  assert_eq(w.role, "terminal")
}

///|
test "resize 随矩形：窄盒列数变少不崩" {
  let term = Terminal::new(cols=80, rows=24)
  term.feed("长长的一行内容超出窄盒宽度也会被列数截断显示 abcdefg\n")
  let root = @widget.Widget::new()
  root.set_size(120.0, 80.0)
  root.set_column()
  let n = terminal(term, height=60.0, blink=false)
  let _ = n.mount_into(root)
  root.relayout(120.0, 80.0)
  let bm = @render.Bitmap::new(120, 80)
  let p = @render.Painter::new(bm)
  root.paint(p)
  p.end()
  assert_true(term.cols() < 80, msg="窄盒应收列数")
}

///|
test "滚轮：向上滚改 view_offset，无回看时不消费" {
  let term = Terminal::new(cols=10, rows=2, scrollback=10)
  term.feed("1\n2\n3\n4\n5")
  let root = @widget.Widget::new()
  root.set_size(200.0, 80.0)
  root.set_column()
  let n = terminal(term, height=60.0, blink=false)
  let w = n.mount_into(root)
  root.relayout(200.0, 80.0)
  let before = term.view_offset
  let _ = root.dispatch_scroll({
    x: w.rect.x + 50.0,
    y: w.rect.y + 30.0,
    dx: 0.0,
    dy: 3.0,
    mods: 0,
  })
  assert_true(term.view_offset > before)
  // 滚回底部
  term.scroll_to_bottom()
  assert_true(term.is_bottom())
}
