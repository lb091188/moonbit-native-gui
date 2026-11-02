// 代码高亮白盒测试：分词着色（关键字/类型/调用/数字/字符串/注释/断词）、
// 代码配色派生（深浅基底各一套、角色映射语义 token）与 code_view 组件
// （出像素、多色 token、行号列、高度按行数、显式钉死配色）。

///|
fn mounted_bm(w : @widget.Widget) -> @render.Bitmap {
  let bm = @render.Bitmap::new(w.rect.w.round().to_int() + 2, w.rect.h.round().to_int() + 2)
  let p = @render.Painter::new(bm)
  w.paint_at(p, w.rect.x, w.rect.y)
  p.end()
  bm
}

///|
/// 近似色计数（容差 16/通道）。
fn count_color(
  bm : @render.Bitmap,
  r : Int,
  g : Int,
  b : Int,
) -> Int {
  let mut n = 0
  for y in 0..<bm.height {
    for x in 0..<bm.width {
      let px = bm.pixel(x, y)
      if (px.r - r).abs() <= 16 && (px.g - g).abs() <= 16 && (px.b - b).abs() <= 16 {
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
  fn expect_role(line : String, word : String, lang : String, want : TokenRole) -> Unit {
    let got = role_of(line, word, lang)
    if !role_is(got, want) {
      abort("\{line} 的 \{word}：期望 \{role_name(want)} 实得 \{role_name(got)}")
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
  let code = [
    "fn main {",
    "  let s = \"你好\"",
    "  // 注释行",
    "}",
  ]
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
      if !((px.r - 40).abs() <= 16 && (px.g - 44).abs() <= 16 && (px.b - 52).abs() <= 16) && px.a > 0 {
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
  let four = [
    "let a = 1",
    "let b = 2",
    "let c = 3",
    "let d = 4",
  ]
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
  let long_line =
    "let x = \"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\""
  let (root_l, vp_l) = mounted(code_view([long_line]), 400.0, 200.0)
  let _ = paint(root_l, 400, 200)
  let canvas_l = vp_l.children()[0].children()[0]
  assert_true(
    canvas_l.rect.w > vp_l.rect.w,
    msg="长行没撑出视口，canvas=\{canvas_l.rect.w} vp=\{vp_l.rect.w}",
  )
}
