// 代码高亮白盒测试：分词着色（关键字/类型/调用/数字/字符串/注释/断词）、
// 代码配色派生（深浅基底各一套、角色映射语义 token）与 code_view 组件
// （出像素、多色 token、行号列、高度按行数、显式钉死配色）。

///|
fn mounted_bm(w : @widget.Widget) -> @render.Bitmap {
  let bm = @render.Bitmap::new(
    w.rect.w.round().to_int() + 2,
    w.rect.h.round().to_int() + 2,
  )
  let p = @render.Painter::new(bm)
  w.paint_at(p, w.rect.x, w.rect.y)
  p.end()
  bm
}

///|
/// 近似色计数（容差 16/通道）。
fn count_color(bm : @render.Bitmap, r : Int32, g : Int32, b : Int32) -> Int32 {
  let mut n = 0
  for y in 0..<bm.height {
    for x in 0..<bm.width {
      let px = bm.pixel(x, y)
      if (px.r - r).abs() <= 16 &&
        (px.g - g).abs() <= 16 &&
        (px.b - b).abs() <= 16 {
        n = n + 1
      }
    }
  }
  n
}

///|
/// 角色比较（TokenRole 不 derive Eq——本工具链给公开类型 derive 会把 impl
/// 方法隐式升普通方法并告警，见 datetime_wbtest 记档；白盒测试手写比较）。
fn role_is(actual : TokenRole, want : TokenRole) -> Bool {
  match (actual, want) {
    (Fg, Fg)
    | (Keyword, Keyword)
    | (Ty, Ty)
    | (Call, Call)
    | (StrLit, StrLit)
    | (NumLit, NumLit)
    | (Comment, Comment)
    | (LineNo, LineNo) => true
    _ => false
  }
}

///|
fn role_name(r : TokenRole) -> String {
  match r {
    Fg => "Fg"
    Keyword => "Keyword"
    Ty => "Ty"
    Call => "Call"
    StrLit => "StrLit"
    NumLit => "NumLit"
    Comment => "Comment"
    LineNo => "LineNo"
  }
}

///|
test "tokenize_lang / tokenize_moonbit：分词与角色规则" {
  fn role_of(line : String, word : String, lang : String) -> TokenRole {
    let mut found = Fg
    for t in tokenize_lang(line, lang) {
      if t.text == word {
        found = t.role
      }
    }
    found
  }
  fn expect_role(
    line : String,
    word : String,
    lang : String,
    want : TokenRole,
  ) -> Unit {
    let got = role_of(line, word, lang)
    if !role_is(got, want) {
      abort(
        "\{line} 的 \{word}：期望 \{role_name(want)} 实得 \{role_name(got)}",
      )
    }
  }
  // 关键字(含补全的 in/loop/typealias 等)、大写开头类型
  expect_role("for row in rows", "for", "moonbit", Keyword)
  expect_role("for row in rows", "in", "moonbit", Keyword)
  expect_role("loop { break }", "loop", "moonbit", Keyword)
  expect_role("typealias T = Int", "typealias", "moonbit", Keyword)
  expect_role("typealias T = Int", "T", "moonbit", Ty)
  expect_role("let n : Array[Int] = []", "Array", "moonbit", Ty)
  // @ 限定名:最后段小写为调用、大写为类型
  expect_role("@yue.tooltip_t(x, y)", "@yue.tooltip_t", "moonbit", Call)
  expect_role("@yue.IconKind", "@yue.IconKind", "moonbit", Ty)
  // 词后紧跟 '(' 为函数调用;无括号的限定名保持普通色
  expect_role("items.push(v)", "items.push", "moonbit", Call)
  expect_role("let v = items.copy", "items.copy", "moonbit", Fg)
  // 区间:前导数字独立、..< 归运算符
  expect_role("for i in 0..<n", "0", "moonbit", NumLit)
  expect_role("for i in 0..<n", "..<", "moonbit", Fg)
  // 字符串、行注释(按语言前缀)
  expect_role("let s = \"abc\"", "\"abc\"", "moonbit", StrLit)
  expect_role("// note", "// note", "moonbit", Comment)
  expect_role("# python", "# python", "python", Comment)
  // tokenize_moonbit 收敛为 moonbit 特化;其余语言关键字表不回归
  assert_true(role_is(tokenize_moonbit("in")[0].role, Keyword))
  expect_role("fn main() {}", "fn", "rust", Keyword)
}

///|
test "code_theme_of：深浅基底两套映射，角色全走语义 token" {
  let light = code_theme_of(@theme.default_theme())
  assert_eq(light.bg, @theme.default_theme().fill_zebra)
  assert_eq(light.keyword, @theme.default_theme().primary)
  assert_eq(light.ty, @theme.default_theme().warning)
  assert_eq(light.str_lit, @theme.default_theme().success)
  assert_eq(light.comment, @theme.default_theme().text_secondary)
  let dark = code_theme_of(@theme.dark_theme())
  assert_eq(dark.bg, @theme.dark_theme().bg_panel)
  assert_eq(dark.text, @theme.dark_theme().text_primary)
  assert_eq(dark.call, @theme.dark_theme().primary_hover)
  assert_eq(dark.num_lit, @theme.dark_theme().danger)
  // 当前主题缺省源跟 theme_current
  assert_eq(code_theme_current().bg, code_theme_of(@theme.theme_current()).bg)
}

///|
test "code_view 组件：出像素、多色 token、行号列、高度按行数（钉死配色）" {
  if !ui_text_guard() {
    return
  }
  let code = ["fn main {", "  let s = \"你好\"", "  // 注释行", "}"]
  // 钉死 One Dark 配色（像素断言要确定值；刻意场景即此参数的用途）
  let one_dark : CodeTheme = {
    bg: "#282C34",
    text: "#ABB2BF",
    keyword: "#C678DD",
    ty: "#E5C07B",
    call: "#61AFEF",
    str_lit: "#98C379",
    num_lit: "#D19A66",
    comment: "#5C6370",
    line_no: "#6B7280",
  }
  let (_root, w) = mounted(
    code_view(code, line_numbers=true, font_size=13.0, code_theme=one_dark),
    640.0,
    400.0,
  )
  // 尺寸按内容：4 行 > 0 高、宽 > 0（内容宽自适应）
  assert_true(w.rect.h > 60.0)
  assert_true(w.rect.w > 100.0)
  let bm = mounted_bm(w)
  // 深底（One Dark #282C34 = 40,44,52）铺满
  let dark = count_color(bm, 40, 44, 52)
  assert_true(dark > bm.width * bm.height / 2)
  // token 墨迹：非深底且非透明的像素（逐纯色计数对抗锯齿敏感，
  // 小字形的字芯也会被次像素渲染稀释，故按「有墨」计）
  let mut inked = 0
  for y in 0..<bm.height {
    for x in 0..<bm.width {
      let px = bm.pixel(x, y)
      if !((px.r - 40).abs() <= 16 &&
        (px.g - 44).abs() <= 16 &&
        (px.b - 52).abs() <= 16) &&
        px.a > 0 {
        inked = inked + 1
      }
    }
  }
  assert_true(inked > 150)
}

///|
test "code_view 缺省跟主题：当前主题的代码底色出像素" {
  if !ui_text_guard() {
    return
  }
  // 进程当前主题（浅色基准）→ 底 = fill_zebra
  @theme.theme_apply(@theme.default_theme())
  let ct = code_theme_current()
  let (lr, lg, lb) = match @theme.parse_hex(ct.bg) {
    Some((r, g, b)) => (r, g, b)
    None => abort("代码底色解析失败")
  }
  let (_root, w) = mounted(code_view(["let a = 1"]), 400.0, 200.0)
  let bm = mounted_bm(w)
  assert_true(count_color(bm, lr, lg, lb) > bm.width * bm.height / 2)
}

///|
test "code_view 组件：行数翻倍高度近似翻倍（行高恒定）" {
  let two = ["let a = 1", "let b = 2"]
  let four = ["let a = 1", "let b = 2", "let c = 3", "let d = 4"]
  let (_r1, w1) = mounted(code_view(two), 640.0, 400.0)
  let (_r2, w2) = mounted(code_view(four), 640.0, 400.0)
  let grew = w2.rect.h - w1.rect.h
  let per_line = w1.rect.h / 2.0
  // 新增两行 ≈ 两倍单行高（容差一行的一半）
  assert_true((grew - per_line * 2.0).abs() < per_line)
}

///|
test "code_view 宽跟随容器，代码比容器宽时才溢出横滚" {
  // flex 1 口径：窄代码的底色条铺满整行（不断在最长行处），长行撑出视口交
  // 自带横滚。视口 → 内容包裹层 → 画布，画布才是那块底。
  let (root_s, vp_s) = mounted(code_view(["fn main {}"]), 640.0, 200.0)
  let _ = paint(root_s, 640, 200)
  let canvas_s = vp_s.children()[0].children()[0]
  assert_eq(canvas_s.rect.w, vp_s.rect.w)
  let long_line = "let x = \"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\""
  let (root_l, vp_l) = mounted(code_view([long_line]), 400.0, 200.0)
  let _ = paint(root_l, 400, 200)
  let canvas_l = vp_l.children()[0].children()[0]
  assert_true(
    canvas_l.rect.w > vp_l.rect.w,
    msg="长行没撑出视口，canvas=\{canvas_l.rect.w} vp=\{vp_l.rect.w}",
  )
}

///|
/// 挂一件 code_view 并用 handle 抓住画布控件（它住在自带横滚视口里面）。
fn mount_code(
  lines : Array[String],
  selectable~ : Bool,
  line_numbers~ : Bool = true,
) -> (@widget.Widget, @widget.Widget) {
  let held = Ref(None)
  let n = code_view(lines, lang="moonbit", line_numbers~, selectable~, handle=fn(
    w : @widget.Widget,
  ) -> Unit {
    held.val = Some(w)
  })
  let root = mount_root([n], 360.0, 160.0)
  (root, held.val.unwrap_or(@widget.Widget::new()))
}

///|
/// 第 row 行的中线（画布纵排：内容高 = 行数 × 行高 + 14 上下内缩）。
fn row_y(w : @widget.Widget, rows : Int32, row : Int32) -> Double {
  let line_h = (w.rect.h - 28.0) / rows.to_double()
  w.rect.y + 14.0 + (row.to_double() + 0.5) * line_h
}

///|
test "code_view selectable：单击定位、双击选词、行号列不进选区" {
  if !ui_text_guard() {
    return
  }
  use_system_clipboard(false)
  let (root, w) = mount_code(
    ["fn main() {", "  let x = 1", "}"],
    selectable=true,
  )
  let st = match sel_states.val.get(w.id) {
    Some(s) => s
    None => abort("code_view 没装起来")
  }
  assert_eq(st.ed.get_text(), "fn main() {\n  let x = 1\n}")
  // 点在文本左缘之外（行号列那一侧）：列归 0——行号列压根不在选区参照系里
  sel_click(root, w.rect.x + 1.0, row_y(w, 3, 0))
  assert_eq(st.ed.caret_pos(), 0)
  assert_true(st.ed.selection() is None)
  // 换到别处单击（离上次 >4px，不算双击）：caret 落进第一行首词「fn」
  // 文本左缘 = 16 + 行号两位宽 + 8（与组件同一式），点第二个字符中央
  let mono = @text.Font::new("Monospace", 13.0)
  let in_word = 24.0 + text_width("88", mono) + text_width("f", mono) * 1.5
  sel_click(root, w.rect.x + in_word, row_y(w, 3, 0))
  assert_true(st.ed.caret_pos() > 0)
  assert_true(st.ed.selection() is None)
  // 原地再来一次（400ms + 4px 内）= 双击：整词选中，边界落码点起点
  sel_click(root, w.rect.x + in_word, row_y(w, 3, 0))
  match st.ed.selection() {
    Some((a, b)) => {
      assert_true(b > a)
      assert_eq(a, st.ed.floor_boundary(a))
      assert_eq(st.ed.get_text_in_range(a, b), "fn")
    }
    None => abort("双击没选成词")
  }
  assert_eq(@widget.text_sel_owner(), w.id)
  use_system_clipboard(true)
}

///|
test "code_view selectable：拖选跨行、复制按行拼换行" {
  if !ui_text_guard() {
    return
  }
  use_system_clipboard(false)
  let (root, w) = mount_code(
    ["fn main() {", "  let x = 1", "}"],
    selectable=true,
  )
  let st = match sel_states.val.get(w.id) {
    Some(s) => s
    None => abort("code_view 没装起来")
  }
  // 第一行行首起拖 → 第二行 → 第三行行尾
  sel_down(root, w.rect.x + 1.0, row_y(w, 3, 0))
  sel_move(root, w.rect.x + 60.0, row_y(w, 3, 1))
  match st.ed.selection() {
    Some((a, b)) => {
      assert_eq(a, 0)
      assert_true(b > 12 && b < 24)
    }
    None => abort("跨行拖选第一段没成选区")
  }
  sel_move(root, w.rect.x + 240.0, row_y(w, 3, 2))
  sel_up(root, w.rect.x + 240.0, row_y(w, 3, 2))
  match st.ed.selection() {
    Some((a, b)) => {
      assert_eq(a, 0)
      assert_eq(b, st.ed.byte_len())
      assert_true(@widget.text_sel_copy())
      assert_eq(st.ed.clip_text(), "fn main() {\n  let x = 1\n}")
    }
    None => abort("拖到末行没成整段选区")
  }
  use_system_clipboard(true)
}

///|
test "code_view 缺省档零变化：没开 selectable 不挂指针、没有选中态" {
  let (_root, w) = mount_code(["let a = 1"], selectable=false)
  assert_true(w.on_pointer is None)
  assert_true(sel_states.val.get(w.id) is None)
}

///|
test "scan_line：跨行块注释按行传播状态（rust 嵌套各自算）" {
  let (t1, s1) = scan_line("let a = 1 /* 起", "moonbit", SNormal)
  assert_true(s1 is SBlockComment(1))
  assert_true(
    t1.any(fn(t : Token) -> Bool { t.role is Comment && t.text == "/* 起" }),
    msg="块注释没从开记号起成段",
  )
  let (t2, s2) = scan_line("还在注释里", "moonbit", s1)
  assert_true(s2 is SBlockComment(1))
  assert_eq(t2.length(), 1)
  assert_eq(t2[0].text, "还在注释里")
  assert_true(t2[0].role is Comment)
  let (t3, s3) = scan_line("*/ let b = 2", "moonbit", s2)
  assert_true(s3 is SNormal)
  assert_eq(t3[0].text, "*/")
  assert_true(t3[0].role is Comment)
  // rust 允许嵌套：内层闭合后仍挂一层；C 系同文则已闭合
  let (r1, rs) = scan_line("/* /* */ 还差一层", "rust", SNormal)
  assert_true(rs is SBlockComment(1))
  assert_eq(r1.length(), 1)
  let (_r2, rs2) = scan_line("*/ done", "rust", rs)
  assert_true(rs2 is SNormal)
  // C 系不嵌套：第一个 */ 就闭合，行内余下的字回正常着色
  let (c1, cs1) = scan_line("/* /* */ 到这儿已闭", "c", SNormal)
  assert_true(cs1 is SNormal)
  assert_eq(c1.length(), 3)
  assert_true(c1[0].role is Comment)
  assert_eq(c1[0].text, "/* /* */")
  assert_true(c1[2].role is Fg)
}

///|
test "scan_line：python 三引号串与 bash heredoc 跨行" {
  let (p1, st1) = scan_line("x = \"\"\"开始", "python", SNormal)
  match st1 {
    STriple(d) => assert_eq(d, "\"\"\"")
    _ => abort("三引号没挂上跨行状态")
  }
  assert_true(
    p1.any(fn(t : Token) -> Bool {
      t.role is StrLit && t.text == "\"\"\"开始"
    }),
    msg="三引号串没从定界符起成段",
  )
  let (p2, st2) = scan_line("结束\"\"\" y = 1", "python", st1)
  assert_true(st2 is SNormal)
  assert_true(p2[0].role is StrLit)
  assert_eq(p2[0].text, "结束\"\"\"")
  // bash：<<TAG 记下结束标记，正文整段按字符串着色，标记行吃完回正常
  let (h1, hs1) = scan_line("cat <<EOF", "bash", SNormal)
  match hs1 {
    SHeredoc(tag) => assert_eq(tag, "EOF")
    _ => abort("heredoc 没挂上跨行状态")
  }
  assert_false(h1.any(fn(t : Token) -> Bool { t.role is Comment }))
  let (h2, hs2) = scan_line("正文 任意 内容", "bash", hs1)
  match hs2 {
    SHeredoc(tag) => assert_eq(tag, "EOF")
    _ => abort("heredoc 正文没继续挂着")
  }
  assert_eq(h2.length(), 1)
  assert_true(h2[0].role is StrLit)
  let (_h3, hs3) = scan_line("EOF", "bash", hs2)
  assert_true(hs3 is SNormal)
}

///|
test "scan_line：token 连续覆盖整行的 UTF-8 字节区间" {
  let line = "让 a = 1 // 中文注释"
  let (ts, _st) = scan_line(line, "moonbit", SNormal)
  let mut acc = 0
  for t in ts {
    assert_eq(t.byte_start, acc)
    let bl = @utf8.encode(t.text).length()
    assert_eq(t.byte_len, bl)
    acc += bl
  }
  assert_eq(acc, @utf8.encode(line).length())
  // 注释段的字节区间就是它自己那几个字
  let mut ctext = ""
  let mut clen = 0
  for t in ts {
    if t.role is Comment {
      ctext = t.text
      clen = t.byte_len
    }
  }
  assert_eq(ctext, "// 中文注释")
  assert_eq(clen, @utf8.encode("// 中文注释").length())
}

///|
test "code_view 描边：边缘出 border 墨，与底色分层" {
  let store = @base.Store::new("")
  let _ = store
  let v = code_view(["let a = 1", "let b = 2"], lang="moonbit")
  let root = @widget.Widget::new()
  root.set_size(220.0, 90.0)
  root.set_column()
  let w = v.mount_into(root)
  root.relayout(220.0, 90.0)
  let bm = @render.Bitmap::new(220, 90)
  let p = @render.Painter::new(bm)
  root.paint(p)
  p.end()
  // 左缘中点应是描边色，内部应是代码底色——两者必须不同（没描边时同色）
  let edge = bm.pixel(0, (w.rect.h / 2.0).to_int())
  let inner = bm.pixel((w.rect.w / 2.0).to_int(), (w.rect.h / 2.0).to_int())
  assert_true(
    (edge.r, edge.g, edge.b, edge.a) != (inner.r, inner.g, inner.b, inner.a),
    msg="code_view 边缘没有描边（与底色同色）",
  )
}

///|
test "copyable：头部区加高、悬浮出复制按钮墨" {
  let plain = code_view(["let a = 1"], lang="moonbit")
  let root = @widget.Widget::new()
  root.set_size(220.0, 90.0)
  root.set_column()
  let wp = plain.mount_into(root)
  root.relayout(220.0, 90.0)
  // copyable=true：内容高 + 20（顶部头部区），现有布局缺省关不受影响
  let copied : Ref[Bool] = Ref(false)
  let rich = code_view(["let a = 1"], lang="moonbit", copyable=true, on_copied=fn(
    _ok : Bool,
  ) -> Unit {
    copied.val = true
  })
  let root2 = @widget.Widget::new()
  root2.set_size(220.0, 110.0)
  root2.set_column()
  let wc = rich.mount_into(root2)
  root2.relayout(220.0, 110.0)
  assert_eq(wc.rect.h - wp.rect.h, 20.0)
  // 指针悬浮视口：右上头部区出按钮墨（与底色异色像素）
  let bm = @render.Bitmap::new(220, 110)
  let p = @render.Painter::new(bm)
  root2.paint(p)
  p.end()
  let idle_ink = 0
  let _ = idle_ink
  // hovered 由宿主 route 维护，无头直注只能手动置（entry 的 clearable 用例同款）
  wc.hovered = true
  let bm2 = @render.Bitmap::new(220, 110)
  let p2 = @render.Painter::new(bm2)
  root2.paint(p2)
  p2.end()
  let bg = bm2.pixel(60, 40)
  let mut ink = 0
  // 头部区右上（按钮位）：视口宽约 220，按钮贴右缘 8
  for x = 150; x < 214; x = x + 1 {
    for y = 6; y < 24; y = y + 1 {
      let c = bm2.pixel(x, y)
      if (c.r, c.g, c.b, c.a) != (bg.r, bg.g, bg.b, bg.a) {
        ink = ink + 1
      }
    }
  }
  assert_true(ink > 6, msg="悬浮后复制按钮没有显形")
  let _ = copied
}
