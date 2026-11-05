// code_editor 首屏口径回证（proposals/code-stack.md 未核项）：万行级文件
// 构造期预排版（`scan_line` + 逐 token 测宽，与 `code_view` 构造同一条路）
// 的耗时，对照「单行编辑 → 行级增量重扫」的重扫行数——首屏走预排版还是
// 只排可视行，按这组读数定。跑法：moon run experiment/code_editor_bench

///|
/// 生成 n 行仿真 MoonBit 源码：平均约 80 列，混关键字/字符串/注释/中文注释/
/// 长行，给测量一点真实形状。
fn gen_lines(n : Int32) -> Array[String] {
  let seeds : Array[String] = [
    "pub fn handle_event(self : Editor, ev : KeyEvent) -> Bool {", "  let shift = (ev.mods & @base.MOD_SHIFT) != 0",
    "  let rect = compute_layout(self.node, width=640.0, height=480.0)", "  // 逐 token 测宽后按 CodeTheme 现取色，深浅基底各一套映射",
    "  // 中文注释行：增量重扫按「行首状态与缓存一致」收敛停，不许死循环",
    "  let toks = scan_line(line, lang, state) match { Some(t) => t, None => [] }",
    "  if depth > 0 && starts_at(cs, i, shape.close) { return (true, i + 2, 0) }",
    "  let metrics = @text.measure_font(prefix, font) match { Some(m) => m.width, None => 0.0 }",
    "  for k in 0..<tokens.length() { total = total + tokens[k].byte_len }", "  } else if ev.keysym == @base.KS_UP || ev.keysym == @base.KS_DOWN {",
    "  let msg = \"字符串字面量 \\{value} 与转义 \\n 都要占宽\"", "  undo.push((copy_of(self.chars), self.caret, self.anchor)) // 撤销栈快照",
    "  let very_long_line_for_horizontal_scroll_testing = some_function(argument_one, argument_two, argument_three, argument_four)",
    "  assert_eq(toks.length(), expect) // 字节区间累加等于行长", "}",
    "",
  ]
  let out : Array[String] = []
  for i in 0..<n {
    out.push(seeds[i % seeds.length()])
  }
  out
}

///|
/// 与 code_view 构造同一条路：逐行 scan_line（状态顺行走）+ 逐 token 测宽。
/// 返回 (总毫秒, 纯扫描毫秒, 各行行首状态, 最长行宽)。
fn prelayout(
  lines : Array[String],
  lang : String,
) -> (UInt64, UInt64, Array[@ui.ScanState], Double) {
  let font = @text.Font::new("Monospace", 13.0)
  let t0 = @env.now()
  let states : Array[@ui.ScanState] = []
  let mut state : @ui.ScanState = @ui.SNormal
  let mut max_w = 0.0
  for line in lines {
    let (toks, next) = @ui.scan_line(line, lang, state)
    states.push(state)
    state = next
    let mut x = 0.0
    for t in toks {
      x = x + @ui.text_width(t.text, font)
    }
    if x > max_w {
      max_w = x
    }
  }
  let t_all = @env.now() - t0
  // 复跑一遍只扫描不测宽：拆出分词本身的成本
  let t1 = @env.now()
  let mut st2 : @ui.ScanState = @ui.SNormal
  for line in lines {
    let (_, next) = @ui.scan_line(line, lang, st2)
    st2 = next
  }
  let t_scan = @env.now() - t1
  (t_all, t_scan, states, max_w)
}

///|
fn state_eq(a : @ui.ScanState, b : @ui.ScanState) -> Bool {
  match (a, b) {
    (@ui.SNormal, @ui.SNormal) => true
    (@ui.SBlockComment(x), @ui.SBlockComment(y)) => x == y
    (@ui.STriple(x), @ui.STriple(y)) => x == y
    (@ui.SHeredoc(x), @ui.SHeredoc(y)) => x == y
    _ => false
  }
}

///|
/// 行级增量重扫（收敛判据与 code_editor 缓存层同口径）：从变更行起向下重扫，
/// 某行「新行首状态 == 缓存行首状态 且 行文本未变」即停，返回重扫行数。
fn rescan_count(
  lines : Array[String],
  cached_states : Array[@ui.ScanState],
  lang : String,
  first : Int32,
) -> Int32 {
  let mut state : @ui.ScanState = if first == 0 {
    @ui.SNormal
  } else {
    cached_states[first]
  }
  let mut i = first
  let mut count = 0
  while i < lines.length() {
    if i > first &&
      i < cached_states.length() &&
      state_eq(state, cached_states[i]) {
      // 内容未变且行首状态与缓存一致：后面整段与缓存相同，收敛停
      // （探针只数重扫行数，不重建 token）
      break
    }
    let (_, next) = @ui.scan_line(lines[i], lang, state)
    state = next
    count = count + 1
    i = i + 1
  }
  count
}

///|
fn main {
  let font = @text.Font::new("Monospace", 13.0)
  let lh = @text.line_height_font(font)
  let lh_s = match lh {
    Some(h) => h.to_string()
    None => "None"
  }
  println("LINE-HEIGHT Monospace 13 = \{lh_s}")
  let lines = gen_lines(10000)
  let (ms_all, ms_scan64, states, max_w) = prelayout(lines, "moonbit")
  let ms = ms_all.to_int()
  let ms_scan = ms_scan64.to_int()
  println(
    "PRELAYOUT 10000x~80col scan+measure = \{ms} ms (scan only = \{ms_scan} ms) max_line_w=\{max_w.round()}px",
  )
  // 单行编辑（第 5000 行加一个词）：变更行 + 收敛探查
  lines[5000] = lines[5000] + " // edited"
  let c1 = rescan_count(lines, states, "moonbit", 5000)
  println("RESPLAIN single-line edit rescan lines = \{c1}")
  // 未闭合块注释（第 5000 行开 /* 不闭）：退化到文末
  lines[5000] = "  /* 未闭合块注释"
  let c2 = rescan_count(lines, states, "moonbit", 5000)
  println("RESPLAIN unclosed block rescan lines = \{c2}")
}
