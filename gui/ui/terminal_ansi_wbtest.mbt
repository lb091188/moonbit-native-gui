// terminal ANSI 解析回归：SGR（16/亮色/256/truecolor/属性位）、光标定位与
// 移动、擦除（ED/EL/ECH）、插删（ICH/DCH/IL/DL）、滚动区与 SU/SD、OSC/DCS
// 清洗（安全口径）、跨 feed 半截序列、私有模式、存取光标。

///|
test "SGR：16 色/亮色/复位" {
  let t = Terminal::new(cols=10, rows=2)
  t.feed("\u{1b}[31;44mAB\u{1b}[0mC")
  assert_eq(t.cell_fg(0, 0), Indexed(1))
  assert_eq(t.cell_bg(0, 0), Indexed(4))
  assert_eq(t.cell_fg(1, 0), Indexed(1))
  assert_eq(t.cell_fg(2, 0), Default)
  assert_eq(t.cell_bg(2, 0), Default)
  assert_eq(t.text(), "ABC")
  let t2 = Terminal::new(cols=10, rows=2)
  t2.feed("\u{1b}[91;105mA\u{1b}[39;49mB")
  assert_eq(t2.cell_fg(0, 0), Indexed(9))
  assert_eq(t2.cell_bg(0, 0), Indexed(13))
  assert_eq(t2.cell_fg(1, 0), Default)
  assert_eq(t2.cell_bg(1, 0), Default)
}

///|
test "SGR：256 色与 truecolor（残缺序列不吞后续参数）" {
  let t = Terminal::new(cols=10, rows=2)
  t.feed("\u{1b}[38;5;196;48;5;21mA")
  assert_eq(t.cell_fg(0, 0), Indexed(196))
  assert_eq(t.cell_bg(0, 0), Indexed(21))
  t.feed("\u{1b}[38;2;12;34;56mB")
  assert_eq(t.cell_fg(1, 0), Rgb(12, 34, 56))
  t.feed("\u{1b}[48;2;1;2mC\u{1b}[0mD")
  // 48;2 只有 2 个分量：残缺档连剩余参数整段作废，bg 保持上一次的 21，不误读成属性
  assert_eq(t.cell_bg(2, 0), Indexed(21))
  assert_eq(t.cell_attrs(2, 0), 0)
  assert_eq(t.cell_fg(3, 0), Default)
}

///|
test "SGR：属性位置位与复位" {
  let t = Terminal::new(cols=10, rows=2)
  t.feed("\u{1b}[1;3;4;7;9mX\u{1b}[22;23;24;27;29mY")
  assert_eq(
    t.cell_attrs(0, 0),
    TERM_ATTR_BOLD
    .lor(TERM_ATTR_ITALIC)
    .lor(TERM_ATTR_UNDERLINE)
    .lor(TERM_ATTR_INVERSE)
    .lor(TERM_ATTR_STRIKE),
  )
  assert_eq(t.cell_attrs(1, 0), 0)
  let t2 = Terminal::new(cols=10, rows=2)
  t2.feed("\u{1b}[1;2mX\u{1b}[22mY")
  assert_eq(t2.cell_attrs(0, 0).land(1), 1)
  assert_eq(t2.cell_attrs(1, 0).land(2), 0)
}

///|
test "光标定位：CUP/HVP/行钳制/列钳制" {
  let t = Terminal::new(cols=10, rows=4)
  t.feed("\u{1b}[3;4HX")
  assert_eq(t.cursor(), (4, 2))
  let t2 = Terminal::new(cols=10, rows=4)
  t2.feed("\u{1b}[HX")
  assert_eq(t2.cursor(), (1, 0))
  assert_eq(t2.cell_fg(0, 0), Default)
  let t3 = Terminal::new(cols=6, rows=3)
  t3.feed("\u{1b}[99;99f")
  assert_eq(t3.cursor(), (5, 2))
}

///|
test "光标移动：A/B/C/D 带边界钳制" {
  let t = Terminal::new(cols=10, rows=4)
  t.feed("\u{1b}[2;5H")
  t.feed("\u{1b}[2A")
  assert_eq(t.cursor(), (4, 0))
  t.feed("\u{1b}[5A")
  assert_eq(t.cursor(), (4, 0))
  t.feed("\u{1b}[9D")
  assert_eq(t.cursor(), (0, 0))
  t.feed("\u{1b}[20C")
  assert_eq(t.cursor(), (9, 0))
  t.feed("\u{1b}[9B")
  assert_eq(t.cursor(), (9, 3))
}

///|
test "ED：0 光标到屏尾 / 1 屏首到光标 / 2 整屏 / 3 清回看；擦除吃笔色底" {
  let t = Terminal::new(cols=6, rows=3)
  t.feed("AAAAAA\nBBBBBB\nCCCCCC")
  t.feed("\u{1b}[2;4H")
  t.feed("\u{1b}[J")
  assert_eq(t.text(), "AAAAAA\nBBB")
  let t2 = Terminal::new(cols=6, rows=3)
  t2.feed("AAAAAA\nBBBBBB\nCCCCCC")
  t2.feed("\u{1b}[2;4H")
  t2.feed("\u{1b}[1J")
  // 行首到光标（含光标格）：row0 整行清、row1 前 4 格清（前导空白保留）
  assert_eq(t2.text(), "\n    BB\nCCCCCC")
  let t3 = Terminal::new(cols=6, rows=2)
  t3.feed("1\n2\n3")
  assert_eq(t3.ring.len(), 1)
  t3.feed("\u{1b}[3J")
  assert_eq(t3.ring.len(), 0)
  // BCE：擦除格吃当前笔色底
  let t4 = Terminal::new(cols=4, rows=2)
  t4.feed("\u{1b}[44m\u{1b}[2J")
  assert_eq(t4.cell_bg(0, 0), Indexed(4))
  assert_eq(t4.cell_bg(3, 1), Indexed(4))
}

///|
test "EL：0 光标到行尾 / 1 行首到光标 / 2 整行" {
  let t = Terminal::new(cols=6, rows=1)
  t.feed("ABCDEF")
  t.feed("\u{1b}[1;2H")
  t.feed("\u{1b}[K")
  assert_eq(t.text(), "A")
  let t2 = Terminal::new(cols=6, rows=1)
  t2.feed("ABCDEF")
  t2.feed("\u{1b}[1;3H")
  t2.feed("\u{1b}[1K")
  assert_eq(t2.text(), "   DEF")
  let t3 = Terminal::new(cols=6, rows=1)
  t3.feed("ABCDEF")
  t3.feed("\u{1b}[2K")
  assert_eq(t3.text(), "")
}

///|
test "ECH/ICH/DCH：行内擦除与插删" {
  let t = Terminal::new(cols=8, rows=1)
  t.feed("ABCDE")
  t.feed("\u{1b}[1;2H")
  t.feed("\u{1b}[2X")
  assert_eq(t.text(), "A  DE")
  let t2 = Terminal::new(cols=8, rows=1)
  t2.feed("ABC\r")
  t2.feed("\u{1b}[2@")
  assert_eq(t2.text(), "  ABC")
  let t3 = Terminal::new(cols=8, rows=1)
  t3.feed("ABCDEF\r")
  t3.feed("\u{1b}[2P")
  assert_eq(t3.text(), "CDEF")
}

///|
test "IL/DL：滚动区内插删行，区外不动作" {
  let t = Terminal::new(cols=6, rows=4)
  t.feed("r0\nr1\nr2\nr3")
  t.feed("\u{1b}[2;1H")
  t.feed("\u{1b}[1L")
  assert_eq(t.text(), "r0\n\nr1\nr2")
  t.feed("\u{1b}[1M")
  assert_eq(t.text(), "r0\nr1\nr2")
  // 区外（r0 行）不动作
  let t2 = Terminal::new(cols=6, rows=3)
  t2.feed("r0\nr1\nr2")
  t2.feed("\u{1b}[1;1H")
  t2.feed("\u{1b}[1L")
  assert_eq(t2.text(), "\nr0\nr1")
}

///|
test "DECSTBM：滚动区只滚区内、不进回看；SU 进回看" {
  let t = Terminal::new(cols=6, rows=4)
  t.feed("\u{1b}[2;3r")
  assert_eq(t.scroll_top, 1)
  assert_eq(t.scroll_bottom, 2)
  assert_eq(t.cursor(), (0, 0))
  t.feed("a\nb\nc\nd\ne\nf")
  assert_eq(t.ring.len(), 0)
  assert_eq(t.text(), "a\ne\nf")
  let t2 = Terminal::new(cols=6, rows=3)
  t2.feed("1\n2\n3")
  t2.feed("\u{1b}[1S")
  assert_eq(t2.ring.len(), 1)
  assert_eq(t2.text(), "1\n2\n3")
  let t3 = Terminal::new(cols=6, rows=3)
  t3.feed("1\n2\n3")
  t3.feed("\u{1b}[1T")
  assert_eq(t3.ring.len(), 0)
  assert_eq(t3.text(), "\n1\n2")
}

///|
test "OSC/DCS/PM 整段清洗：标题与剪贴板序列不消费、不外泄" {
  let t = Terminal::new(cols=20, rows=2)
  t.feed("\u{1b}]0;evil title\u{7}ok")
  assert_eq(t.text(), "ok")
  // OSC 52 写剪贴板载荷：同样整段丢弃
  t.feed("\u{1b}]52;c;YWJj\u{1b}\\x")
  assert_eq(t.text(), "okx")
  t.feed("\u{1b}P1.1qdata\u{1b}\\!")
  assert_eq(t.text(), "okx!")
  t.feed("\u{1b}^privatemsg\u{1b}\\?")
  assert_eq(t.text(), "okx!?")
}

///|
test "半截序列跨 feed 续上" {
  let t = Terminal::new(cols=10, rows=2)
  t.feed("\u{1b}[33;4")
  t.feed("4mXY")
  assert_eq(t.cell_fg(0, 0), Indexed(3))
  assert_eq(t.cell_bg(0, 0), Indexed(4))
  assert_eq(t.text(), "XY")
}

///|
test "私有模式：?25 光标显隐、?7 自动折行" {
  let t = Terminal::new(cols=5, rows=2)
  t.feed("\u{1b}[?25l")
  assert_false(t.cursor_visible)
  t.feed("\u{1b}[?7l")
  assert_false(t.autowrap)
  t.feed("abcdefgh")
  assert_eq(t.text(), "abcdh")
  t.feed("\u{1b}[?25h\u{1b}[?7h")
  assert_true(t.cursor_visible)
  assert_true(t.autowrap)
}

///|
test "存取光标：ESC 7/8 与 CSI s/u，越界钳制" {
  let t = Terminal::new(cols=10, rows=4)
  t.feed("\u{1b}[3;3H")
  t.feed("\u{1b}7")
  t.feed("\u{1b}[H")
  assert_eq(t.cursor(), (0, 0))
  t.feed("\u{1b}8")
  assert_eq(t.cursor(), (2, 2))
  t.feed("\u{1b}[2;2H\u{1b}[s\u{1b}[H\u{1b}[u")
  assert_eq(t.cursor(), (1, 1))
}

///|
test "IND/NEL/RI：ESC D 留列、ESC E 回行首、ESC M 反向下移（列都保留）" {
  let t = Terminal::new(cols=6, rows=3)
  t.feed("a\u{1b}Db")
  assert_eq(t.text(), "a\n b")
  t.feed("\u{1b}Mc")
  assert_eq(t.text(), "a c\n b")
  t.feed("\u{1b}[2;1H\u{1b}EX")
  assert_eq(t.text(), "a c\n b\nX")
}

///|
test "未知 CSI final 与超长参数：静默丢弃不外泄" {
  let t = Terminal::new(cols=20, rows=2)
  t.feed("\u{1b}[?9999npass")
  assert_eq(t.text(), "pass")
  let t2 = Terminal::new(cols=20, rows=2)
  let mut junk = ""
  for _ in 0..<200 {
    junk = junk + "1;"
  }
  t2.feed("\u{1b}[" + junk + "mX")
  assert_eq(t2.text(), "X")
  assert_eq(t2.cell_fg(0, 0), Default)
}

///|
test "DECSTBM 无效区间（top >= bottom）忽略" {
  let t = Terminal::new(cols=6, rows=4)
  t.feed("\u{1b}[3;2r")
  assert_eq(t.scroll_top, 0)
  assert_eq(t.scroll_bottom, 3)
}
