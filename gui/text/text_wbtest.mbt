// 文本层的口径回归：不断言具体像素宽（随字体配置变），只断言单调性与约束。

fn painted_count(bm : @render.Bitmap, w : Int, h : Int) -> Int {
  let mut n = 0
  for y = 0; y < h; y = y + 1 {
    for x = 0; x < w; x = x + 1 {
      if bm.pixel(x, y).a > 0 {
        n = n + 1
      }
    }
  }
  n
}

test "测量单调：文本更长更宽、字号更大更高" {
  let a = measure("Hello", 14.0)
  let b = measure("Hello World", 14.0)
  let big = measure("Hello", 28.0)
  match (a, b, big) {
    (Some(a), Some(b), Some(big)) => {
      assert_eq(b.width > a.width, true)
      assert_eq(big.width > a.width, true)
      assert_eq(big.height > a.height, true)
      assert_eq(a.baseline > 0 && a.baseline < a.height, true)
    }
    _ => assert_eq(false, true)
  }
}

test "测量含行尾空白：行尾空格要占宽（输入框光标位移靠它）" {
  match (measure("ab", 14.0), measure("ab ", 14.0), measure(" ", 14.0)) {
    (Some(base), Some(tail), Some(only)) => {
      assert_eq(tail.width > base.width, true, msg="行尾空格没有计入测量宽度")
      assert_eq(only.width > 0, true, msg="纯空格量出零宽")
    }
    _ => assert_eq(false, true)
  }
}

test "行高取字体口径：随字号增长、不绑样例文本" {
  match (line_height(14.0), line_height(28.0), line_ascent(14.0)) {
    (Some(h14), Some(h28), Some(a14)) => {
      assert_eq(h14 > 0, true)
      assert_eq(h28 > h14, true)
      assert_eq(a14 > 0, true)
      assert_eq(a14 < h14, true)
      // 字体行高（ascent+descent）不该小于任何单行盒高：探针量的「14px→17」
      // 是文本 "M" 的盒高（等于首行基线），属样例文本口径，两者在此分开
      match measure("M", 14.0) {
        Some(m) => assert_eq(h14 >= m.height, true)
        None => ()
      }
      match measure("Mg", 14.0) {
        Some(m) => assert_eq(h14 >= m.height, true)
        None => ()
      }
    }
    _ => assert_eq(false, true)
  }
}

test "max_width 约束换行：宽度受钳、高度增长" {
  let one = measure("the quick brown fox jumps over the lazy dog", 14.0)
  let wrapped = measure(
    "the quick brown fox jumps over the lazy dog",
    14.0,
    max_width=80,
    wrap=true,
  )
  match (one, wrapped) {
    (Some(one), Some(wrapped)) => {
      assert_eq(one.width > 80, true)
      assert_eq(wrapped.width <= 80, true)
      assert_eq(wrapped.height > one.height, true)
    }
    _ => assert_eq(false, true)
  }
}

test "折行测宽不超限：CJK 标点联排字距不得让行宽越过限宽" {
  // 真机 mac：showcase 段描述（60+ 个 CJK 字与全角标点混排）在 842 限宽下
  // 量出 879——mac 折行器按「断行单元孤测之和」贪心，而 CoreText 联排时才
  // 施加标点/混排字距调整（每单元约 +0.9px），孤测系统性低估整行宽，行尾
  // 三个字符被节点裁掉（「段描述吞字」）。英文句与纯 URL 孤测差不到 1px，
  // 上面两条老用例盖不住这条，必须用 CJK 标点混排串。
  let s =
    "选一个主色，整套色板（hover/浅底/语义色）按 HSL 公式即时派生，切换深浅沿用当前主色；「跟随系统」读系统主色调，读不到回落内置。手动选色会先关掉跟随开关（否则下一次轮询就把它盖回去）。"
  for w in [400, 600, 842, 900] {
    match measure(s, 12.0, max_width=w, wrap=true) {
      Some(m) => assert_eq(
        m.width <= w,
        true,
        msg="限宽 \{w} 折行测得 \{m.width}，越限",
      )
      None => assert_eq(false, true)
    }
  }
}

test "超长不可断单元按字符硬断：行数按宽度摊算，不是一行一个字" {
  // 真机 mac：浏览器示例「新窗请求」里那条长 URL（整串无空格）撑出两百行，
  // 把底部状态栏顶穿、整块布局错位。断行单元比整行还宽时只能逐字硬断，但
  // 硬断要**一直填到放不下为止**；每行只切一个字就回头重判的话，「整个剩余
  // 单元的宽」永远超限，于是退化成一行一个字。不断言具体行数（随字体变），
  // 只跟「总宽 ÷ 盒宽」的摊算值比。
  let url =
    "https://moonbitlang.github.io/moonbit-native-gui/examples/browser/a-very-long-path-without-any-breakable-space?query=1&x=2"
  match (measure(url, 13.0), line_height(13.0)) {
    (Some(one), Some(h)) if one.width > 200 && h > 0 => {
      let expect = (one.width + 200 - 1) / 200
      match measure(url, 13.0, max_width=200, wrap=true) {
        Some(w) => {
          assert_eq(w.width <= 200, true, msg="硬断后仍超出盒宽")
          // 容一行取整差；旧写法给的是「字符数」量级的行
          assert_eq(
            w.height <= (expect + 1) * h,
            true,
            msg="长 URL 折到 \{w.height}px，按 \{one.width}px 摊算只需 \{expect} 行（每行一个字就穿帮）",
          )
        }
        None => assert_eq(false, true)
      }
    }
    _ => assert_eq(false, true)
  }
}

test "测量宽自洽：按测量宽下发的盒不再折行" {
  // 布局用测量宽定盒，再把同一个宽交给断行算法；只要测量报得比真实浮点宽
  // 窄（四舍五入取整就会），单行标签会在自己的盒里凭空多出一行
  // （真机：mac「选中：」「最近确认：」错位重叠）。
  for s in [
    "选中：",
    "最近确认：",
    "全角标点：测试，一遍。",
    "Mixed 混排 label",
  ] {
    match measure(s, 13.0) {
      Some(free) => {
        assert_eq(free.width > 0, true, msg="'\{s}' 量出零宽")
        match measure(s, 13.0, max_width=free.width, wrap=true) {
          Some(at_box) => assert_eq(
            at_box.height,
            free.height,
            msg="'\{s}' 在自身测量宽 \{free.width}px 的盒里折成了多行",
          )
          None => assert_eq(false, true)
        }
      }
      None => assert_eq(false, true)
    }
  }
}

test "ellipsize 尾端省略不超约束" {
  match measure("the quick brown fox jumps over the lazy dog", 14.0,
    max_width=60,
    ellipsize=true,
  ) {
    Some(m) => {
      assert_eq(m.width <= 60, true)
      assert_eq(m.height > 0, true)
    }
    None => assert_eq(false, true)
  }
}

test "绘制真的往自有缓冲落像素" {
  let bm = @render.Bitmap::new(120, 30)
  let ok = draw_to(bm, 2.0, 2.0, "MoonBit", 16.0, "#ffffff")
  assert_eq(ok, true)
  assert_eq(painted_count(bm, 120, 30) > 20, true)
}

test "中文可测可画" {
  match measure("中文测试", 14.0) {
    Some(m) => assert_eq(m.width > 0 && m.height > 0, true)
    None => assert_eq(false, true)
  }
  let bm = @render.Bitmap::new(80, 24)
  assert_eq(draw_to(bm, 1.0, 1.0, "中文", 14.0, "#ff0000"), true)
  assert_eq(painted_count(bm, 80, 24) > 10, true)
}

test "空文本与空缓冲的安全边界" {
  let bm = @render.Bitmap::new(10, 10)
  assert_eq(draw_to(bm, 0.0, 0.0, "", 14.0, "#00ff00"), true)
  let empty = @render.Bitmap::new(0, 0)
  assert_eq(draw_to(empty, 0.0, 0.0, "x", 14.0, "#00ff00"), false)
  // 非法 hex 按黑色兜底，不应崩也不应空画
  let bm2 = @render.Bitmap::new(60, 20)
  assert_eq(draw_to(bm2, 1.0, 1.0, "abc", 14.0, "oops"), true)
}

///|
test "max_lines 行数钳制：超高截断出省略号、矮内容原样、单行限高即省略" {
  let long = "这是一段用来验证行数钳制的说明文字这一段足够长一定会超过两行这是一段用来验证行数钳制的说明文字这一段足够长一定会超过两行"
  let font = Font::new("", 13.0)
  // 整段高（不限行数）
  let full = match measure_font(long, font, max_width=300, wrap=true) {
    Some(m) => m
    None => {
      assert_eq(false, true)
      abort("unreachable")
    }
  }
  // 钳到 2 行：高不超过 2 行，且明显矮于整段
  let clamped = match measure_font(long, font, max_width=300, wrap=true, max_lines=2) {
    Some(m) => m
    None => {
      assert_eq(false, true)
      abort("unreachable")
    }
  }
  let one = match measure_font("中", font, wrap=false) {
    Some(m) => m.height
    None => 0
  }
  assert_eq(clamped.height <= one * 2, true)
  assert_eq(clamped.height < full.height, true)
  // 不超限的内容原样返回（高度一致）
  let short = "短句一行"
  match (
    measure_font(short, font, max_width=300, wrap=true),
    measure_font(short, font, max_width=300, wrap=true, max_lines=2),
  ) {
    (Some(a), Some(b)) => assert_eq(a.height, b.height)
    _ => assert_eq(false, true)
  }
  // max_lines=1 等价单行截断：高一行、宽不超可用宽
  let single = match measure_font(long, font, max_width=300, wrap=true, max_lines=1) {
    Some(m) => m
    None => {
      assert_eq(false, true)
      abort("unreachable")
    }
  }
  assert_eq(single.height <= one * 1 + 1, true)
  assert_eq(single.width <= 300, true)
}
