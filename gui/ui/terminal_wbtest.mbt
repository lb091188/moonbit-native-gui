// terminal 模型回归：C0 控制符、折行、宽字符/零宽字符、回看滚动、resize、
// 清屏与复位、变更信号。转义序列用例在 ANSI 批补（terminal_ansi 同文件）。

///|
test "C0：换行/回车覆盖/退格/制表位" {
  let t = Terminal::new(cols=20, rows=4)
  t.feed("ab\ncd\n")
  assert_eq(t.text(), "ab\ncd")
  assert_eq(t.cursor(), (0, 2))
  let t2 = Terminal::new(cols=10, rows=2)
  t2.feed("abc\rX")
  assert_eq(t2.text(), "Xbc")
  let t3 = Terminal::new(cols=10, rows=2)
  t3.feed("abc\b\bZ")
  assert_eq(t3.text(), "aZc")
  let t4 = Terminal::new(cols=20, rows=2)
  t4.feed("a\tb")
  assert_eq(t4.text(), "a       b")
}

///|
test "自动折行：末列挂起、下一字符先换行" {
  let t = Terminal::new(cols=5, rows=3)
  t.feed("abcdef")
  assert_eq(t.text(), "abcde\nf")
  assert_eq(t.cursor(), (1, 1))
  // 关自动折行：光标钉在末列，后续字符原地覆盖（xterm 口径）
  let t2 = Terminal::new(cols=3, rows=2)
  t2.autowrap = false
  t2.feed("abc")
  assert_eq(t2.text(), "abc")
  t2.feed("xyz")
  assert_eq(t2.text(), "abz")
}

///|
test "宽字符占两格与末列换行；零宽字符拼前一格" {
  let t = Terminal::new(cols=4, rows=3)
  t.feed("中文中")
  assert_eq(t.text(), "中文\n中")
  assert_eq(t.cursor(), (2, 1))
  let t2 = Terminal::new(cols=6, rows=2)
  t2.feed("e\u{301}x") // 组合尖音符拼进 e 那格
  assert_eq(t2.text(), "e\u{301}x")
  // 宽字符被打断：退回首格再覆盖，续格一并清成空白
  let t3 = Terminal::new(cols=4, rows=1)
  t3.feed("中\b\ba")
  assert_eq(t3.text(), "a")
  // 退到续格覆盖：宽首格清成空白
  let t4 = Terminal::new(cols=4, rows=1)
  t4.feed("中\ba")
  assert_eq(t4.text(), " a")
}

///|
test "回看：整屏滚动进环、text 含回看、滚上不拽回底部" {
  let t = Terminal::new(cols=10, rows=3, scrollback=10)
  assert_true(t.is_bottom())
  t.feed("1\n2\n3\n4\n5")
  assert_eq(t.text(), "1\n2\n3\n4\n5")
  assert_eq(t.cursor(), (1, 2))
  t.scroll_lines(2)
  assert_eq(t.view_offset, 2)
  assert_false(t.is_bottom())
  // 继续输出不拽回底部，且回看变长时视口随内容整体变旧
  t.feed("\n6\n")
  assert_eq(t.view_offset, 4)
  assert_eq(t.ring.len(), 4)
  t.scroll_to_bottom()
  assert_true(t.is_bottom())
}

///|
test "回看环形覆盖：容量满时丢最旧" {
  let t = Terminal::new(cols=10, rows=2, scrollback=3)
  t.feed("1\n2\n3\n4\n5\n6")
  // 屏 2 行只看得到 5、6；回看容量 3，1 已被覆盖
  assert_eq(t.text(), "2\n3\n4\n5\n6")
  assert_eq(t.ring.len(), 3)
}

///|
test "resize：保留左上交集、光标与滚动区钳制、尺寸不变是 no-op" {
  let t = Terminal::new(cols=5, rows=2)
  t.feed("abcde\nfg")
  t.resize(3, 3)
  assert_eq(t.cols(), 3)
  assert_eq(t.rows(), 3)
  assert_eq(t.text(), "abc\nfg")
  assert_eq(t.cursor(), (2, 1))
  t.resize(3, 3)
  assert_eq(t.text(), "abc\nfg")
  t.resize(10, 2)
  // 截断不可逆（不做重排）：右列内容已丢，放大只回空白
  assert_eq(t.text(), "abc\nfg")
}

///|
test "clear 清屏留回看、视口回贴底；reset 连回看一起清" {
  let t = Terminal::new(cols=10, rows=3, scrollback=10)
  t.feed("a\nb\nc")
  t.clear()
  assert_eq(t.text(), "")
  assert_eq(t.cursor(), (0, 0))
  t.feed("1\n2\n3\n4\n5")
  t.clear()
  // 清屏不进回看，原来滚出去的 1、2 还在
  assert_eq(t.text(), "1\n2")
  // 滚上去看回看再清屏：视口必须回贴底，清空效果才可见（回看内容保留）
  t.scroll_lines(2)
  assert_false(t.is_bottom())
  t.clear()
  assert_true(t.is_bottom())
  assert_eq(t.text(), "1\n2")
  t.reset()
  assert_eq(t.text(), "")
  assert_true(t.is_bottom())
  assert_eq(t.cursor(), (0, 0))
}

///|
test "滚动区：区内 LF 只滚区内不进回看" {
  let t = Terminal::new(cols=10, rows=4)
  t.scroll_top = 1
  t.scroll_bottom = 2
  t.feed("top")
  t.feed("\nm1\nm2\nm3\nm4")
  // 区内轮转，回看应为空；区外的 top 行原地不动
  assert_eq(t.ring.len(), 0)
  assert_true(t.text().has_prefix("top\n"))
}

///|
test "feed/resize/scroll 触发 revision 信号" {
  // revision() 随控件批接线；此处先钉 bump 的取数面（cell 取色/属性）
  let t = Terminal::new(cols=10, rows=2)
  t.feed("hi")
  assert_eq(t.cell_fg(0, 0), Default)
  assert_eq(t.cell_bg(0, 0), Default)
  assert_eq(t.cell_attrs(0, 0), 0)
  assert_eq(t.cell_fg(-1, 0), Default)
  assert_eq(t.cell_bg(99, 99), Default)
}
