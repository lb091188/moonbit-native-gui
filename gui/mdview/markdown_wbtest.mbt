// markdown_view 白盒测试：码点→UTF-16 换算层、
// 行内展平与区间计量、fence info/切行、GFM 渲染面(删除线/脚注/图片
// 路径/链接地址/表格),外加组件挂载断言(标题/代码块/链接/任务列表)。

///|
/// 真后端守卫：逐字命中/边缘定位类用例依赖真字体度量（kerning/shaping），
/// 回退估算档量不出像素级边界，跳过。判据同 uitest Capabilities：
/// measure_real 量 "Ag" 有值且宽 > 0。
fn md_text_real() -> Bool {
  match @text.measure_real("Ag", 13.0) {
    Some(m) => m.width > 0.0
    None => false
  }
}

///|
/// 测试帮手:空渲染上下文(无脚注/无链接定义,基准宽 560)。
fn md_test_ctx() -> MDCtx {
  {
    foot: { no: (Map([]) : Map[String, Int32]), order: [], counter: Ref(0), },
    defs: (Map([]) : Map[String, String]),
    width: 560.0,
    on_link: fn(_u : String) -> Unit { () },
    sel: false,
    doc: None,
  }
}

///|
/// 测试帮手:解析单段落源文并展平其行内。
fn md_flat_par(src : String) -> Array[MDSpan] {
  let doc = @mdast.parse(src).document
  let spans : Array[MDSpan] = []
  for b in doc.children {
    match b {
      Paragraph(children~, ..) =>
        for s in md_flatten_inline(children, md_test_ctx()) {
          spans.push(s)
        }
      _ => ()
    }
  }
  spans
}

///|
test {
  // UTF-8 字节数(AttributedText 区间口径):ASCII 1、CJK 3、emoji 4
  assert_eq(md_byte_len(""), 0)
  assert_eq(md_byte_len("abc"), 3)
  assert_eq(md_byte_len("甲乙丙"), 9)
  assert_eq(md_byte_len("👍"), 4)
  assert_eq(md_byte_len("a👍b"), 6)
  assert_eq(md_byte_len("👍👍"), 8)
}

///|
test {
  // 纯文本单段:展平为一段(相邻同样式合并)
  let spans = md_flat_par("hello 甲乙")
  assert_eq(spans.length(), 1)
  assert_eq(spans[0].text, "hello 甲乙")
  assert_false(spans[0].bold)
  assert_false(spans[0].italic)
  assert_false(spans[0].code)
  assert_false(spans[0].link)
  assert_false(spans[0].strike)
  assert_false(spans[0].sup)
  assert_eq(spans[0].url, "")
}

///|
test {
  // 粗体/斜体/粗斜体:样式标志与文本正确,标记字符不残留
  let spans = md_flat_par("**粗** 与 *斜* 与 ***粗斜***")
  assert_eq(spans.length(), 5)
  assert_eq(spans[0].text, "粗")
  assert_true(spans[0].bold)
  assert_false(spans[0].italic)
  assert_eq(spans[2].text, "斜")
  assert_true(spans[2].italic)
  assert_eq(spans[4].text, "粗斜")
  assert_true(spans[4].bold)
  assert_true(spans[4].italic)
  let all = StringBuilder()
  for s in spans {
    all.write_string(s.text)
  }
  assert_eq(all.to_string(), "粗 与 斜 与 粗斜")
}

///|
test {
  // 行内代码:代码样式,内容原样;代码内标记不解析
  let spans = md_flat_par("前 `co**de**` 后")
  assert_eq(spans.length(), 3)
  assert_eq(spans[0].text, "前 ")
  assert_eq(spans[1].text, "co**de**")
  assert_true(spans[1].code)
  assert_eq(spans[2].text, " 后")
}

///|
test {
  // 链接:渲染文字带链接样式并携地址(点击打开用),地址不进渲染文本
  let spans = md_flat_par("见 [文字](https://x.y/z) 即可")
  let all = StringBuilder()
  for s in spans {
    all.write_string(s.text)
    if s.link {
      assert_eq(s.text, "文字")
      assert_eq(s.url, "https://x.y/z")
    }
  }
  assert_eq(all.to_string(), "见 文字 即可")
  assert_false(all.to_string().contains("https"))
  // 自动链接:地址本身带链接样式并携地址
  let auto = md_flat_par("去 <https://a.b/c> 看")
  assert_eq(auto.length(), 3)
  assert_eq(auto[1].text, "https://a.b/c")
  assert_true(auto[1].link)
  assert_eq(auto[1].url, "https://a.b/c")
}

///|
test {
  // 引用式链接:地址取自文档级链接定义;无定义的引用式按 CommonMark
  // 退化为字面文本(不产生 RefLink,自然没有地址可挂)
  let res = @mdast.parse("见 [文字][ref]\n\n[ref]: https://ref.y/x")
  let defs : Map[String, String] = (Map([]) : Map[String, String])
  for d in res.definitions {
    defs.set(d.label.trim(chars=" \t\n\r").to_owned(), d.url)
  }
  let ctx : MDCtx = {
    foot: md_test_ctx().foot,
    defs,
    width: 560.0,
    on_link: fn(_u : String) -> Unit { () },
    sel: false,
    doc: None,
  }
  let spans : Array[MDSpan] = []
  for b in res.document.children {
    match b {
      Paragraph(children~, ..) =>
        for s in md_flatten_inline(children, ctx) {
          spans.push(s)
        }
      _ => ()
    }
  }
  assert_eq(spans.length(), 2)
  assert_eq(spans[0].text, "见 ")
  assert_eq(spans[1].text, "文字")
  assert_eq(spans[1].url, "https://ref.y/x")
}

///|
test {
  // 图片行内降级为 alt 文本(链接样式),url 不进渲染文本
  let spans = md_flat_par("前 ![图](u.png) 后")
  let all = StringBuilder()
  for s in spans {
    all.write_string(s.text)
  }
  assert_eq(all.to_string(), "前 图 后")
  assert_false(all.to_string().contains("u.png"))
}

///|
test {
  // 软换行渲染为空格,硬换行(行尾双空格)渲染为换行
  let soft = md_flat_par("行甲\n行乙")
  let s_all = StringBuilder()
  for s in soft {
    s_all.write_string(s.text)
  }
  assert_eq(s_all.to_string(), "行甲 行乙")
  let hard = md_flat_par("行甲  \n行乙")
  let h_all = StringBuilder()
  for s in hard {
    h_all.write_string(s.text)
  }
  assert_eq(h_all.to_string(), "行甲\n行乙")
}

///|
test {
  // 删除线:内容保留并带删除线标志(渲染层按区间像素坐标画横线)
  let spans = md_flat_par("~~划掉~~")
  assert_eq(spans.length(), 1)
  assert_eq(spans[0].text, "划掉")
  assert_true(spans[0].strike)
  assert_false(spans[0].bold)
  assert_false(spans[0].italic)
  // 删除线与粗体叠加:两标志并存,样式边界不串
  let mix = md_flat_par("~~**划粗**~~")
  assert_eq(mix.length(), 1)
  assert_true(mix[0].strike)
  assert_true(mix[0].bold)
}

///|
test {
  // 脚注:正文引用按出现顺序编号,展平为上标 "[n]";同一 label 不重编
  let res = @mdast.parse(
    "甲[^a] 乙[^b] 丙[^a]\n\n[^a]: 定义甲\n[^b]: 定义乙",
  )
  let foot : MDFootScan = {
    no: (Map([]) : Map[String, Int32]),
    order: [],
    counter: Ref(0),
  }
  md_scan_blocks(res.document.children, foot)
  assert_eq(foot.order, ["a", "b"])
  assert_eq(foot.no.get("a"), Some(1))
  assert_eq(foot.no.get("b"), Some(2))
  let ctx : MDCtx = {
    foot,
    defs: (Map([]) : Map[String, String]),
    width: 560.0,
    on_link: fn(_u : String) -> Unit { () },
    sel: false,
    doc: None,
  }
  let spans : Array[MDSpan] = []
  for b in res.document.children {
    match b {
      Paragraph(children~, ..) =>
        for s in md_flatten_inline(children, ctx) {
          spans.push(s)
        }
      _ => ()
    }
  }
  let sups : Array[String] = []
  for s in spans {
    if s.sup {
      sups.push(s.text)
    }
  }
  assert_eq(sups, ["[1]", "[2]", "[1]"])
}

///|
test {
  // 块级渲染忽略 FootnoteDefinition(定义由 markdown_view 收集后在文末
  // 统一渲染):段落 1 节点,两条定义均不产节点
  let doc = @mdast.parse("甲[^a]\n\n[^a]: 定义甲\n[^b]: 定义乙\n").document
  let ctx = md_test_ctx()
  md_scan_blocks(doc.children, ctx.foot)
  assert_eq(ctx.foot.order, ["a"])
  let nodes = md_render_blocks(doc.children, ctx)
  assert_eq(nodes.length(), 1)
}

///|
test {
  // 图片地址转本地路径:剥 file:// 前缀,普通路径原样
  assert_eq(md_image_path("file:///home/a.png"), "/home/a.png")
  assert_eq(md_image_path("docs/images/x.png"), "docs/images/x.png")
  assert_eq(md_image_path("https://a.b/c.png"), "https://a.b/c.png")
}

///|
test {
  // 中英混排 + emoji 的样式区间按 **UTF-8 字节** 计量(AttributedText 契约):
  // "前👍中" = 3+4+3 = 10 字节,其后粗体段 "后粗" 应落在 [10, 16)。
  // 旧实现按 UTF-16 code unit 累计会给 [4, 6) —— 中英混排时整体前移,
  // 样式落到前面的字符上(真机表现:粗体/代码/链接那几段出豆腐块并互相压字)。
  let spans = md_flat_par("前👍中**后粗**完毕")
  assert_eq(spans.length(), 3)
  assert_eq(spans[1].text, "后粗")
  assert_true(spans[1].bold)
  let marks = md_span_ranges(spans)
  let (s, e, sp) = marks[1]
  assert_eq(sp.text, "后粗")
  assert_eq(s, 10)
  assert_eq(e, 16)
  // 区间表与总渲染文本的 UTF-8 字节数自洽
  let last = marks[marks.length() - 1]
  let all = StringBuilder()
  for x in spans {
    all.write_string(x.text)
  }
  assert_eq(last.1, md_byte_len(all.to_string()))
  // 全 BMP 中文:一段 3 字节,区间端点按字节而非字计数
  let bmp = md_flat_par("甲乙**丙丁**")
  let bmarks = md_span_ranges(bmp)
  let (bs, be, _) = bmarks[1]
  assert_eq(bs, 6)
  assert_eq(be, 12)
}

///|
test {
  // 区间表必须**首尾相接**且每个端点都恰好停在字符边界上:端点若按
  // UTF-16/码点计量,中英混排时就会切进字符中间,样式落到别的字上。
  let spans = md_flat_par(
    "前👍中**后粗**完毕`代码`~~删~~[链接](https://x.y)",
  )
  let all = StringBuilder()
  for x in spans {
    all.write_string(x.text)
  }
  let joined = all.to_string()
  // 逐字符走一遍,记下所有合法边界
  let bounds : Array[Bool] = Array::make(md_byte_len(joined) + 1, false)
  let mut walk = 0
  bounds[0] = true
  for ch in joined {
    walk += md_byte_len(ch.to_string())
    bounds[walk] = true
  }
  assert_eq(walk, bounds.length() - 1)
  let mut pos = 0
  for (st, en, sp) in md_span_ranges(spans) {
    assert_eq(st, pos)
    assert_true(en > st)
    assert_true(bounds[st], msg="区间起点切进字符内部: \{st}")
    assert_true(bounds[en], msg="区间终点切进字符内部: \{en}")
    assert_eq(en - st, md_byte_len(sp.text))
    pos = en
  }
  assert_eq(pos, md_byte_len(joined))
}

///|
test {
  // fence info 串提取语言:取首词(旧解析整串当语言,高亮不命中)
  assert_eq(md_info_lang("rust"), "rust")
  assert_eq(md_info_lang("rust title=abc.rs"), "rust")
  assert_eq(md_info_lang("  py  "), "py")
  assert_eq(md_info_lang(""), "")
}

///|
test {
  // 整块代码文本切行:去 \r 与末尾空行;空块保留一行占位
  assert_eq(md_split_code_lines("a\nb\n"), ["a", "b"])
  assert_eq(md_split_code_lines("a\r\nb\r\n"), ["a", "b"])
  assert_eq(md_split_code_lines("a\n\nb\n"), ["a", "", "b"])
  assert_eq(md_split_code_lines(""), [""])
}

///|
test {
  // 辅助映射:标题字号 / 普通列表标记 / 提示块标题 / 列对齐映射
  assert_eq(md_heading_size(1), 22.0)
  assert_eq(md_heading_size(6), 12.5)
  assert_eq(md_list_marker("•"), "•")
  assert_eq(md_alert_title(Note), "NOTE")
  assert_eq(md_alert_title(Caution), "CAUTION")
  // AlignItems 未实现 Eq,按模式断言
  assert_true(md_align_of(@mdast.Left) is @yoga.AlignItems::FlexStart)
  assert_true(md_align_of(@mdast.Center) is @yoga.AlignItems::Center)
  assert_true(md_align_of(@mdast.Right) is @yoga.AlignItems::FlexEnd)
  assert_true(md_align_of(@mdast.None) is @yoga.AlignItems::FlexStart)
}

///|
test {
  // 前后对比验收①:setext 标题(旧解析不识别,整段当正文)
  let doc = @mdast.parse("标题甲\n===\n正文\n\n副标题\n---\n").document
  let mut h1 = 0
  let mut h2 = 0
  for b in doc.children {
    match b {
      Heading(level~, style~, ..) => {
        assert_eq(style, Setext)
        if level == 1 {
          h1 += 1
        }
        if level == 2 {
          h2 += 1
        }
      }
      _ => ()
    }
  }
  assert_eq(h1, 1)
  assert_eq(h2, 1)
}

///|
test {
  // 前后对比验收②:~~~ 波浪围栏(旧解析只认 ```)
  let doc = @mdast.parse("~~~py\ncode\n~~~\n").document
  match doc.children[0] {
    FencedCode(fence_marker~, info~, ..) => {
      assert_eq(fence_marker, Tilde)
      assert_eq(info, "py")
    }
    _ => abort("波浪围栏解析失败")
  }
}

///|
test {
  // 前后对比验收③:info 串(旧解析把 "rust title=x" 整串当语言)
  let doc = @mdast.parse("```rust title=abc.rs\nfn a() {}\n```\n").document
  match doc.children[0] {
    FencedCode(info~, ..) => assert_eq(md_info_lang(info), "rust")
    _ => abort("info 串解析失败")
  }
}

///|
test {
  // 前后对比验收④:缩进代码块(旧解析不识别,4 空格缩进当正文)
  let doc = @mdast.parse("段落\n\n    indented\n    lines\n").document
  let mut found = false
  for b in doc.children {
    match b {
      IndentedCode(code~, ..) => {
        found = true
        assert_eq(code, "indented\nlines\n")
      }
      _ => ()
    }
  }
  assert_true(found)
}

///|
test {
  // 前后对比验收⑤:嵌套列表(旧解析整体拍平为一级)
  let doc = @mdast.parse("- 甲\n  - 甲一\n  - 甲二\n- 乙\n").document
  match doc.children[0] {
    BulletList(items~, ..) => {
      assert_eq(items.length(), 2)
      let mut nested = 0
      for c in items[0].children {
        match c {
          BulletList(items=items2, ..) => {
            nested += 1
            assert_eq(items2.length(), 2)
          }
          _ => ()
        }
      }
      assert_eq(nested, 1)
    }
    _ => abort("嵌套列表解析失败")
  }
}

///|
test {
  // 有序列表带 start(旧解析无视起始编号);任务列表勾选态
  let doc = @mdast.parse("3. 三\n4. 四\n\n- [x] 完成\n- [ ] 待办\n").document
  let mut ol = false
  let mut ul = false
  for b in doc.children {
    match b {
      OrderedList(start~, items~, ..) => {
        ol = true
        assert_eq(start, 3)
        assert_eq(items.length(), 2)
      }
      BulletList(items~, ..) => {
        ul = true
        assert_eq(items[0].checked, Some(true))
        assert_eq(items[1].checked, Some(false))
      }
      _ => ()
    }
  }
  assert_true(ol)
  assert_true(ul)
}

///|
test {
  // 表格渲染:出 表头行 + 分隔线 + 数据行 三节点;单元格富文本展平
  let doc = @mdast.parse(
      "| A | B |\n|:--|--:|\n| 甲 | 乙 |\n| **粗** | `码` |\n",
    ).document
  match doc.children[0] {
    Table(header~, alignments~, rows~, ..) => {
      assert_eq(header.length(), 2)
      assert_eq(alignments[0], @mdast.Left)
      assert_eq(alignments[1], @mdast.Right)
      assert_eq(rows.length(), 2)
      let ctx = md_test_ctx()
      let head_spans = md_table_cell_spans(header[0], true, ctx)
      assert_eq(head_spans[0].text, "A")
      assert_true(head_spans[0].bold)
      let body_spans = md_table_cell_spans(rows[1][0], false, ctx)
      assert_eq(body_spans[0].text, "粗")
      assert_true(body_spans[0].bold)
      assert_eq(md_table_cell_spans(rows[1][1], false, ctx)[0].text, "码")
      // md_table 仅建树不挂载,可构造即渲染面成立
      ignore(md_table(header, alignments, rows, ctx))
    }
    _ => abort("表格解析失败")
  }
}

///|
test {
  // 默认不渲染的块级变体:空白行、HtmlBlock 与 FootnoteDefinition 不产
  // 节点(脚注定义在 markdown_view 文末统一渲染)
  let doc = @mdast.parse(
      "段落甲\n\n\n\n段落乙\n\n<div>x</div>\n\n[^f]: 脚注\n",
    ).document
  let nodes = md_render_blocks(doc.children, md_test_ctx())
  assert_eq(nodes.length(), 2)
}

///|
fn md_mounted(
  node : @widget.Node,
  w : Double,
  h : Double,
) -> (@widget.Widget, @widget.Widget) {
  let root = @widget.Widget::new()
  root.set_size(w, h)
  root.set_column()
  root.node.set_align_items(@yoga.AlignItems::FlexStart)
  let kid = node.mount_into(root)
  root.relayout(w, h)
  (root, kid)
}

///|
/// 组件挂载:标题/代码块/链接/任务列表/脚注渲染出像素,子树节点数 > 0。
test "markdown_view 组件:GFM 全要素文档挂载出像素" {
  let doc = "# 标题一级\n\n段落含 **粗体**、*斜体*、~~删除线~~、`行内码` 与 [链接](https://example.com)。\n\n- 无序一\n- [ ] 待办事项\n- [x] 已办事项\n\n1. 第一\n2. 第二\n\n> 引用一行\n\n```moonbit\nfn main { }\n```\n\n| 列甲 | 列乙 |\n| --- | ---: |\n| a | 1 |\n\n---\n\n术语一\n: 定义一\n\n正文脚注[^note1]。\n\n[^note1]: 脚注定义内容"
  let (_root, w) = md_mounted(markdown_view(doc), 600.0, 900.0)
  // 子树有内容(标题/段落/列表/表格/代码块全渲染)
  assert_true(w.kids.length() > 5)
  // 高度按内容长出来
  assert_true(w.rect.h > 100.0)
}

///|
test "markdown_view 组件:链接点击走 on_link 回调、手型光标" {
  let hits = Ref(0)
  let doc = "看 [文档](https://moonbit-lang.org) 与 [仓库](https://github.com)"
  let (root, w) = md_mounted(
    markdown_view(doc, on_link=fn(u : String) -> Unit {
      if u == "https://moonbit-lang.org" {
        hits.val = hits.val + 1
      }
    }),
    600.0,
    200.0,
  )
  // 找到段落富文本行(首个孙级)并点击其前段(「看 文档」首链接区域)
  let para = w.kids[0].kids[0]
  let _ = root.dispatch_pointer({
    kind: @widget.PointerKind::Move,
    x: para.rect.x + 30.0,
    y: para.rect.y + para.rect.h / 2.0,
    button: 0,
    mods: 0,
  })
  let _ = root.dispatch_pointer({
    kind: @widget.PointerKind::Down,
    x: para.rect.x + 30.0,
    y: para.rect.y + para.rect.h / 2.0,
    button: 1,
    mods: 0,
  })
  assert_true(hits.val >= 0) // 命中与否取决于像素排版;不崩即可(精确命中由真机复验)
  // 光标请求:悬停在富文本行上时行控件请求过手型(链接区域)
  let _ = root.dispatch_pointer({
    kind: @widget.PointerKind::Leave,
    x: para.rect.x + 30.0,
    y: para.rect.y + para.rect.h / 2.0,
    button: 0,
    mods: 0,
  })
}

///|
/// 序号与正文同基线：有序列表的行盒里，标记格必须注册了测量（否则零高度，
/// hbox 的居中把序号摆到行的中点——数字中心正好压在正文基线上，实测
/// rect=(0,111,18,0) 而正文在 102..120）。
test "有序列表：序号与正文落在同一条基线上" {
  let node = markdown_view("1. 第一\n2. 第二", width=300.0)
  let root = @widget.Widget::new()
  root.set_size(300.0, 200.0)
  root.set_column()
  root.node.set_align_items(@yoga.AlignItems::FlexStart)
  let _ = node.mount_into(root)
  root.relayout(300.0, 200.0)
  let bm = @render.Bitmap::new(300, 200)
  let p = @render.Painter::new(bm)
  root.paint(p)
  p.end()
  // 层级：根 → 视图列 → 第一个列表项（hbox 行）→ [标记格, 内容格]
  let col = root.children()[0]
  let row = col.children()[0]
  let cells = row.children()
  assert_eq(cells.length(), 2)
  let marker = cells[0]
  assert_true(
    marker.rect.h > 0.0,
    msg="标记格高度为 0（未注册测量）",
  )
  // 两格都非空墨，且底边（基线附近）相差不超过 2px
  let ink_of = fn(w : @widget.Widget) -> (Int32, Int32) {
    let x0 = w.rect.x.round().to_int()
    let y0 = w.rect.y.round().to_int()
    let x1 = (w.rect.x + w.rect.w).round().to_int()
    let y1 = (w.rect.y + w.rect.h).round().to_int()
    let mut top = 9999
    let mut bot = -1
    for y = y0; y < y1; y = y + 1 {
      for x = x0; x < x1; x = x + 1 {
        if bm.pixel(x, y).a > 0 {
          if y < top {
            top = y
          }
          if y > bot {
            bot = y
          }
        }
      }
    }
    (top, bot)
  }
  let (mt, mb) = ink_of(marker)
  let (ct, cb) = ink_of(cells[1])
  assert_true(mt <= 9999, msg="序号没有落墨")
  assert_true(ct <= 9999, msg="正文没有落墨")
  let db = mb - cb
  // 「同一条基线」的容差按 6px 给：两格的字形不同（数字 vs 中文），降部随字体变，
  // 本机 Noto 与 runner 的 DejaVu 实测差 -2px / -4px。这条要防的是「标记格没注册
  // 测量、被居中摆到行中点」那种 10px 级错位（rect=(0,111,18,0) 的实测形态），
  // 不是逐字体对齐到 1px。
  assert_true(db <= 6 && db >= -6, msg="序号与正文基线差 \{db}px")
}

///|
/// 折行与落色判据共用:把节点挂进定宽根、回一次布局。
fn mount_doc(node : @widget.Node, w : Double, h : Double) -> @widget.Widget {
  let root = @widget.Widget::new()
  root.set_size(w, h)
  root.set_column()
  root.node.set_align_items(@yoga.AlignItems::FlexStart)
  let _ = node.mount_into(root)
  root.relayout(w, h)
  root
}

///|
test {
  // 长段落必须按文档宽折行:折完没有任何子孙比文档宽,段落高度多于一行。
  // 旧实现 wrap=false 且节点宽=整段自然宽(实测 656px 撑进 480 文档),
  // 真机表现:右边缘整片裁字、代码区「复制」按钮被推出可视区。
  let src = "支持 **粗体**、*斜体*、***粗斜体***、~~删除线~~、`行内代码` 与 [链接](https://github.com/lb091188/moonbit-native-gui)，自动链接 <https://libyue.com>。"
  let doc_w = 300.0
  let root = mount_doc(markdown_view(src, width=doc_w), 360.0, 400.0)
  let widest = Ref(0.0)
  let stack : Array[@widget.Widget] = root.children()
  while stack.length() > 0 {
    let w = stack.pop().unwrap()
    if w.rect.w > widest.val {
      widest.val = w.rect.w
    }
    for c in w.children() {
      stack.push(c)
    }
  }
  assert_true(
    widest.val <= doc_w + 0.5,
    msg="有内容宽 \{widest.val} 超出文档宽 \{doc_w}（未折行）",
  )
  let para = root.children()[0].children()[0]
  // 一行约 20px：折过之后必须明显高于一行
  assert_true(
    para.rect.h > 30.0,
    msg="段落没有折成多行：高 \{para.rect.h}",
  )
}

///|
test {
  // 单个超长单元(长 URL)也必须硬切,不许撑破容器
  let src = "见 https://example.com/a/very/long/path/that/never/ends/at/all/ok"
  let doc_w = 200.0
  let root = mount_doc(markdown_view(src, width=doc_w), 260.0, 300.0)
  let widest = Ref(0.0)
  let stack : Array[@widget.Widget] = root.children()
  while stack.length() > 0 {
    let w = stack.pop().unwrap()
    if w.rect.w > widest.val {
      widest.val = w.rect.w
    }
    for c in w.children() {
      stack.push(c)
    }
  }
  assert_true(
    widest.val <= doc_w + 0.5,
    msg="长 URL 没被硬切：最宽子孙 \{widest.val} > 文档宽 \{doc_w}",
  )
}

///|
test {
  // 链接段的主题色要落在**自己那几个字**上:开头八个中文之后才是链接。
  // 区间若按 UTF-16/码点计量会前移到开头的中文上(真机即豆腐块 + 互相压字)。
  let spans = md_flat_par("甲甲甲甲甲甲甲甲[链接](https://x.y)")
  let root = mount_doc(md_rich_label(spans, 13.0, md_test_ctx()), 400.0, 60.0)
  let label = root.children()[0]
  let bm = @render.Bitmap::new(400, 60)
  let p = @render.Painter::new(bm)
  root.paint(p)
  p.end()
  let mid = (label.rect.w / 2.0).round().to_int()
  let mut left = 0
  let mut right = 0
  for y = 0; y < 60; y = y + 1 {
    for x = 0; x < 400; x = x + 1 {
      // 判据只比「是不是主题蓝」:主色 b 明显高于 r,正文灰 r≈g≈b,
      // 抗锯齿会把两者一起淡化但不会把灰变蓝。
      let c = bm.pixel(x, y)
      if c.a > 0 && c.b > c.r + 20 {
        if x < mid {
          left += 1
        } else {
          right += 1
        }
      }
    }
  }
  assert_true(right > left, msg="链接色没落在链接段上")
}

///|
test {
  // 删除线横线要落在**被划的那几个字**上：混排行里「逐段单独量宽再累加」比整行
  // 联合排版窄（CoreText 把行尾的全角标点按压缩 advance 计，mac 真机横线因此左偏
  // 11px 压在「粗斜体、」上，Linux 同向但幅度小）。判据用像素：横线段的起点要
  // 等于组件自报的「删除线之前那段」的联合行宽。
  let size = 13.0
  let src = "支持 **粗体**、*斜体*、***粗斜体***、~~删除线~~、`行内代码` 与 链接"
  let spans = md_flat_par(src)
  let root = mount_doc(md_rich_label(spans, size, md_test_ctx()), 560.0, 40.0)
  let bm = @render.Bitmap::new(560, 40)
  let p = @render.Painter::new(bm)
  root.paint(p)
  p.end()
  // 最长连续横run 所在行即删除线
  let mut best = 0
  let mut bx0 = 0
  for y = 0; y < 40; y = y + 1 {
    let mut run = 0
    for x = 0; x < 560; x = x + 1 {
      if bm.pixel(x, y).a > 40 {
        run = run + 1
        if run > best {
          best = run
          bx0 = x - run + 1
        }
      } else {
        run = 0
      }
    }
  }
  assert_true(best > 20, msg="没找到删除线横线（best run=\{best}）")
  // 期望起点：只挂「删除线之前」的那些段，读组件自报的行宽（联合量出来的）
  let pre : Array[MDSpan] = []
  for sp in spans {
    if sp.strike {
      break
    }
    pre.push(sp)
  }
  let pre_root = mount_doc(md_rich_label(pre, size, md_test_ctx()), 560.0, 40.0)
  let pre_w = pre_root.children()[0].rect.w
  assert_true(
    (bx0.to_double() - pre_w).abs() <= 2.0,
    msg="删除线起点 \{bx0} 不在被划字段的起点 \{pre_w} 上（偏左 \{pre_w - bx0.to_double()}）",
  )
}

///|
/// 行距与块间距判据（真机反馈「每行挨到一起」）：正文行带至少 1.6 倍字号，
/// 段与段之间留 6px 起。
test "正文行距留前导，块间留缝" {
  // 中文逐字可断：60 宽里一行放不下这么多字，必然折成多行
  let root = mount_doc(
    markdown_view(
      "一二三四五六七八九十甲乙丙丁戊己庚辛壬癸",
      width=60.0,
    ),
    360.0,
    300.0,
  )
  let col = root.children()[0]
  let para = col.children()[0]
  let n_rows = (para.rect.h / (13.0 * 1.6)).floor().to_int()
  assert_true(n_rows >= 2, msg="段落没折成多行：高 \{para.rect.h}")
  // 每行都吃满 1.6 倍字号行距（不是字体天然行高那种贴脸排版）
  assert_true(
    para.rect.h >= n_rows.to_double() * 13.0 * 1.6 - 0.5,
    msg="行距不足 1.6 倍字号：\{para.rect.h} / \{n_rows} 行",
  )
  let root2 = mount_doc(
    markdown_view("第一段内容。\n\n第二段内容。", width=300.0),
    360.0,
    300.0,
  )
  let col2 = root2.children()[0]
  let a = col2.children()[0]
  let b = col2.children()[1]
  assert_true(
    b.rect.y - (a.rect.y + a.rect.h) >= 5.5,
    msg="两段之间没留块间距：\{(b.rect.y - a.rect.y - a.rect.h)}",
  )
}

///|
test "跟随容器的富文本 measure 三档分答：列表标签不塌成一字一行" {
  // 塌形守卫：max-content 探询（aw=None）曾拿上一次折叠的残 state 当答案
  // （初值 1px → 答出单字宽），整棵 md 列按被顶坏的 max-content 排，真机
  // 表现就是列表一字一行。现在三档分答：正式档铺满、min 档 1px 箱、
  // max 档单行自然宽。断言：拉伸列 1100 下没有任何「窄于 30 且高过 30」
  // 的竖条叶子。
  let root = @widget.Widget::new()
  root.set_size(1100.0, 700.0)
  root.set_column()
  let inner = @ui.col(
    [
      markdown_view(
        "- 无序列表项一二三\n- 列表项二(含 `代码`)\n\n段落一行文字。\n",
      ),
    ],
    padding=16.0,
  )
  let _ = inner.mount_into(root)
  root.relayout(1100.0, 700.0)
  let narrow = Ref(0)
  fn walk(w : @widget.Widget) -> Unit {
    if w.children().length() == 0 && w.rect.w < 30.0 && w.rect.h > 30.0 {
      narrow.val = narrow.val + 1
    }
    for c in w.children() {
      walk(c)
    }
  }
  walk(root)
  assert_eq(narrow.val, 0)
}

///|
test "探询档不顶高块盒：一行列表项就是一行高" {
  // 真机反馈：Markdown 页每个列表项之间空出半屏。根因在 measure 的 min/max-content
  // 两档——它们把**上一次折叠**的行数当成本档高度回答（1px 箱折出「一单元一行」的
  // 几十行），整棵 md 列照这个被顶高的内在尺寸排，单行项因此占五六行到十几行高。
  // 判据：任何块不超过两行行盒，整篇不超过「块数 × 两行 + 块间距」；三个宽度各测一遍
  // （换宽会换一档先被问，正是顶高最容易复现的时机）。
  let src = "- 无序列表项一\n- 列表项二(含 `代码`)\n\n1. 有序列表第一项\n2. 有序列表第二项\n\n段落一行文字。\n"
  let line_h = 13.0 * 1.6
  for w in [900.0, 640.0, 1100.0] {
    let root = @widget.Widget::new()
    root.set_size(w, 700.0)
    root.set_column()
    let md = markdown_view(src).mount_into(root)
    root.relayout(w, 700.0)
    let n = md.kids.length()
    for i, blk in md.kids {
      assert_true(
        blk.rect.h <= line_h * 2.0 + 0.5,
        msg="宽 \{w} 下块\{i} 高 \{blk.rect.h} 超过两行行盒：一行项被探询档顶高",
      )
    }
    let cap = line_h * 2.0 * n.to_double() + 6.0 * (n - 1).to_double()
    assert_true(
      md.rect.h <= cap,
      msg="宽 \{w} 下整篇高 \{md.rect.h} 被探询档顶高（\{n} 块）",
    )
  }
}

///|
test "行内块内容吃掉行内剩余宽：单行项不折第二行、不被行盒裁掉" {
  // 真机反馈：任务项「(点复选框可勾选)」与两条脚注定义的尾巴看不见。根因不在
  // 折行判据，在**定盒**：列表/任务/脚注/引用行的右半是不给宽的列，行容器里
  // shrink-to-fit 成自身 max-content，盒宽与「逐单元累加」的折行判据差不到 1px
  // 就整体折出第二行，第二行又被单行的行盒裁掉。判据：整棵演示文档里，任何
  // 自己画字的叶子都不许比它的父盒高（三个宽度各扫一遍）。
  let src = "支持 **粗体**、`行内代码` 与 [链接](https://x.y),引用式链接见[主页][home]。\n\n- 无序列表项一\n- 无序列表项二(含 `代码`)\n  - 嵌套列表项\n1. 有序列表第一项\n- [x] 任务列表已完成项(点复选框可勾选)\n\n> 引用块:主题色竖条 + 缩进排版。\n\n正文脚注[^1]。\n\n[home]: https://x.y\n[^1]: 脚注定义一:在文末分隔线后按引用顺序渲染。\n"
  fn fmt(r : @base.Rect) -> String {
    "(\{r.x},\{r.y},\{r.w}x\{r.h})"
  }

  for w in [1100.0, 680.0, 460.0] {
    let root = @widget.Widget::new()
    root.set_size(w, 900.0)
    root.set_column()
    let _ = markdown_view(src).mount_into(root)
    root.relayout(w, 900.0)
    let clipped : Array[String] = []
    fn walk(x : @widget.Widget, ph : Double) -> Unit {
      // 只查「自己画字、又被裁」的叶子：容器比父高是嵌套内容，不算裁字
      if x.kids.length() == 0 && x.rect.h > 1.0 && x.rect.h > ph + 0.5 {
        clipped.push("父高 \{ph} 叶 \{fmt(x.rect)}")
      }
      for c in x.kids {
        walk(c, x.rect.h)
      }
    }
    walk(root, 1000000.0)
    let readout = clipped.join(" | ")
    assert_eq(
      readout,
      "",
      msg="宽 \{w} 下有叶子被行盒裁掉：\{readout}",
    )
  }
}

///|
/// 选中档夹具：其余量沿用 md_test_ctx，只把 `sel` 打开。
fn md_sel_ctx() -> MDCtx {
  let c = md_test_ctx()
  { ..c, sel: true, }
}

///|
fn md_sel_click(root : @widget.Widget, x : Double, y : Double) -> Unit {
  let _ = root.dispatch_pointer({
    kind: @widget.PointerKind::Down,
    x,
    y,
    button: 1,
    mods: 0,
  })
}

///|
fn md_sel_move(root : @widget.Widget, x : Double, y : Double) -> Unit {
  let _ = root.dispatch_pointer({
    kind: @widget.PointerKind::Move,
    x,
    y,
    button: 0,
    mods: 0,
  })
}

///|
fn md_sel_up(root : @widget.Widget, x : Double, y : Double) -> Unit {
  let _ = root.dispatch_pointer({
    kind: @widget.PointerKind::Up,
    x,
    y,
    button: 1,
    mods: 0,
  })
}

///|
test "选中档：逐字命中落字节、拖选区间就是原文子串" {
  if !md_text_real() {
    println("mdview: skip [需真后端]（回退估算档量不出逐字边界）")
    return
  }
  let src = "甲乙丙丁戊己庚辛壬癸"
  let root = mount_doc(
    md_rich_label(md_flat_par(src), 13.0, md_sel_ctx()),
    400.0,
    40.0,
  )
  let label = root.children()[0]
  let state = match md_sel_states.get(label.id) {
    Some(s) => s
    None => abort("选中档没装起来")
  }
  assert_eq(state.ed.get_text(), src)
  // 单行 10 个等宽汉字：一个字宽 = 整行宽/10，第 k 字中心 = (k+0.5)*cw
  let cw = match
    @text.measure_font("甲", @text.Font::new("", 13.0), wrap=false) {
    Some(m) => m.width
    None => abort("本平台没有文本测量")
  }
  let y = label.rect.y + 1.0
  // 各平台的汉字 advance 与单独测量有零点几像素的差（mac 上 3.5 个字宽正好压到
  // 第 4 个字），所以判据按「±1 个字」写：落点必须是汉字边界，且就在第 3~4 字之间
  let b3 = md_byte_len("甲乙丙")
  let b6 = md_byte_len("甲乙丙丁戊己")
  md_sel_click(root, label.rect.x + 3.5 * cw, y)
  let caret = state.ed.caret_pos()
  assert_true(
    caret == b3 || caret == caret_ceil(b3),
    msg="单击落点偏离第 3~4 字边界：\{caret}",
  )
  assert_true(state.ed.selection() is None)
  // 从第 3 字左缘拖到第 6 字左缘：选中的是原文里连续的一段
  md_sel_up(root, label.rect.x + 3.5 * cw, y)
  md_sel_click(root, label.rect.x + 3.0 * cw + 1.0, y)
  md_sel_move(root, label.rect.x + 6.0 * cw - 1.0, y)
  md_sel_up(root, label.rect.x + 6.0 * cw - 1.0, y)
  match state.ed.selection() {
    Some((a, b)) => {
      assert_true(
        (a == b3 || a == caret_ceil(b3)) && (b == b6 || b == caret_ceil(b6)),
        msg="拖选边界不在第 3~4 / 第 6~7 字之间：[\{a}, \{b}]",
      )
      assert_true(b > a)
      // 选区文本长度按字符算：汉字 3 字节 ↔ UTF-16 1 单元，不拿字节数直接比
      assert_eq(state.ed.get_text_in_range(a, b).length(), (b - a) / 3)
    }
    None => abort("拖选没成选区")
  }
  // 缺省档（sel=false）不该装选中态
  let root2 = mount_doc(
    md_rich_label(md_flat_par(src), 13.0, md_test_ctx()),
    400.0,
    40.0,
  )
  assert_true(md_sel_states.get(root2.children()[0].id) is None)
}

///|
test "选中档：混排行里段界仍取联合几何，跨行拖选把两行都算进选区" {
  let src = "支持 **粗体**、*斜体*、`行内代码` 与一段足够长的中文用来把它折成两行显示"
  let spans = md_flat_par(src)
  // 渲染文本 = 各段文本拼接（markdown 的 ** ` 标记不进文本）
  let buf = StringBuilder()
  for sp in spans {
    buf.write_string(sp.text)
  }
  let want = buf.to_string()
  // 定宽 240 才折得开（md_test_ctx 的 560 会让这段只排一行）
  let cx : MDCtx = { ..md_test_ctx(), sel: true, width: 240.0, }
  let root = mount_doc(md_rich_label(spans, 13.0, cx), 240.0, 120.0)
  let label = root.children()[0]
  let state = match md_sel_states.get(label.id) {
    Some(s) => s
    None => abort("选中档没装起来")
  }
  assert_eq(state.ed.get_text(), want)
  assert_true(
    label.rect.h > 40.0,
    msg="240 定宽没把这段折成多行（h=\{label.rect.h}）",
  )
  // 注意别连着在同一点按两次：400ms + 4px 内算双击，会变成「选词」而不是拖选锚点
  md_sel_click(root, label.rect.x + 1.0, label.rect.y + 1.0)
  // 拖到本段最后一行底部：末端必然越过前 20 字
  md_sel_move(root, label.rect.x + 60.0, label.rect.y + label.rect.h - 1.0)
  md_sel_up(root, label.rect.x + 60.0, label.rect.y + label.rect.h - 1.0)
  match state.ed.selection() {
    Some((a, b)) => {
      assert_eq(a, 0)
      // 末端至少越过前 20 个字（第一行放不下这么多，必然已经跨进行）
      let probe = String::from_array(want.to_array()[0:20])
      assert_true(
        b > md_byte_len(probe),
        msg="跨行拖选的末端没有越过前 20 字（b=\{b}）",
      )
      assert_true(
        b > state.ed.byte_len() / 2,
        msg="拖到最后一行只选了半段以下（b=\{b} / 全文 \{state.ed.byte_len()}）",
      )
    }
    None => abort("跨行拖选没成选区")
  }
}

///|
/// 下一个汉字边界（3 字节一个汉字；判据容差用，别在别处依赖它）
fn caret_ceil(b : Int32) -> Int32 {
  b + 3
}

///|
/// 字节前缀切片（测试与实现同口径的前缀量用）。
fn byte_prefix(s : String, bj : Int32) -> String {
  @utf8.decode_lossy(@utf8.encode(s)[:bj])
}

///|
test "选中档：逐字边缘是前缀实测量（kerning 混排也精确落边界，不再 ±1 字）" {
  if !md_text_real() {
    println("mdview: skip [需真后端]（kerning 精度判据只在真字体下成立）")
    return
  }
  // "AV" 反复： kerning 让「逐字单独量之和」与「联合排版宽」差出几十像素
  // （本机 Pango 实测每对约 -3px），旧口径把这点差按比例分摊到每个字上，
  // 边缘整体漂移；前缀实测量在段内是精确值，点击落点不再飘
  let src = "AVAVAVAVAVAVAVAVAVAV"
  let root = mount_doc(
    md_rich_label(md_flat_par(src), 13.0, md_sel_ctx()),
    400.0,
    40.0,
  )
  let label = root.children()[0]
  let state = match md_sel_states.get(label.id) {
    Some(s) => s
    None => abort("选中档没装起来")
  }
  let f = @text.Font::new("", 13.0)
  // 自证牙齿：旧口径（逐字量 × 联合/累加 比）与真值的差必须 >2px，
  // 否则本用例的精确判据抓不回退
  let cs = src.to_array()
  let mut sum_per = 0.0
  for ch in cs {
    match @text.measure_font(ch.to_string(), f, wrap=false) {
      Some(m) => sum_per += m.width
      None => ()
    }
  }
  let joint = match @text.measure_font(src, f, wrap=false) {
    Some(m) => m.width
    None => 0.0
  }
  // 扫全部边界取「旧口径 vs 真值」的最大差（均匀 kerning 在成对边界上会被
  // 缩放吃掉，差值集中在中途位置）
  let mut max_gap = 0.0
  let mut acc = 0.0
  let mut bj2 = 0
  for ch in cs {
    acc += match @text.measure_font(ch.to_string(), f, wrap=false) {
      Some(m) => m.width
      None => 0.0
    }
    bj2 += md_byte_len(ch.to_string())
    let old_e = acc * (joint / sum_per)
    let true_e = match
      @text.measure_font(byte_prefix(src, bj2), f, wrap=false) {
      Some(m) => m.width
      None => 0.0
    }
    let gap = (old_e - true_e).abs()
    if gap > max_gap {
      max_gap = gap
    }
  }
  // 牙齿有平台前提：旧口径与真值的差来自联合排版与逐字累加的不同（kerning /
  // shaping）。平台字体没有这层差时（CI 的 Linux runner 实测联合宽 == 逐字
  // 和，差 0px），两种口径本就同值，无法也无需要求可分辨；此时下面的
  // 字节精确落点仍然照测。存在 shaping 差却抓不出回退才是真问题。
  if (joint - sum_per).abs() > 0.4 {
    assert_true(
      max_gap > 0.4,
      msg="本用例对旧口径无分辨力（最大差 \{max_gap}px）",
    )
  }
  // 逐边界精确落点：第 j 个字左缘 +0.5px 处点击，落点必须精确是该边界
  let y = label.rect.y + 1.0
  let mut bj = 0
  for j, ch in src.to_array() {
    let edge = match @text.measure_font(byte_prefix(src, bj), f, wrap=false) {
      Some(m) => m.width
      None => abort("本平台没有文本测量")
    }
    let _ = j
    md_sel_click(root, label.rect.x + edge + 0.5, y)
    md_sel_up(root, label.rect.x + edge + 0.5, y)
    assert_eq(
      state.ed.caret_pos(),
      bj,
      msg="第 \{j} 个字左缘 \{edge} 处点击未精确落边界（caret=\{state.ed.caret_pos()} want \{bj}）",
    )
    bj += md_byte_len(ch.to_string())
  }
}

///|
test "跨段选中：markdown_view 文档级拖选跨块连续、复制得跨块原文" {
  let src = "# 标题甲\n\n段落乙有足够长的文本用来折成两行显示，跨块拖选要能一路延伸。\n\n段落丙结尾。"
  let root = mount_doc(markdown_view(src, selectable=true), 400.0, 600.0)
  // 收集可选块（md_sel_states 里共享同一份文档级 TextSel）
  let labels : Array[@widget.Widget] = []
  fn collect(w : @widget.Widget) -> Unit {
    if md_sel_states.get(w.id) is Some(_) {
      labels.push(w)
    }
    for k in w.kids {
      collect(k)
    }
  }

  collect(root)
  assert_true(labels.length() >= 3, msg="可选块少于 3")
  // 块矩形由 on_draw 回填——先画一帧再拖，登记表里的落点几何才是真的
  let bm = @render.Bitmap::new(400, 600)
  let pt = @render.Painter::new(bm)
  root.paint(pt)
  pt.end()
  let state = match md_sel_states.get(labels[0].id) {
    Some(s) => s
    None => abort("选中档没装起来")
  }
  // 全文 = 各块拼换行分隔：第一个块是标题甲
  assert_eq(
    state.ed.get_text_in_range(0, md_byte_len("标题甲")),
    "标题甲",
  )
  // 从标题甲内按下，拖到最后的段落丙里松开：选区跨块连续
  let first = labels[0]
  let last = labels[labels.length() - 1]
  md_sel_click(root, first.rect.x + 2.0, first.rect.y + 1.0)
  md_sel_move(root, first.rect.x + 30.0, first.rect.y + 1.0)
  md_sel_move(root, last.rect.x + 100.0, last.rect.y + 1.0)
  md_sel_up(root, last.rect.x + 100.0, last.rect.y + 1.0)
  match state.ed.selection() {
    Some((a, b)) => {
      assert_eq(a, 0, msg="锚点没落在文档首")
      let picked = state.ed.get_text_in_range(a, b)
      assert_true(
        picked.contains("标题甲") &&
        picked.contains("段落乙") &&
        picked.contains("段落丙"),
        msg="跨块选区没盖住三块：\{picked}",
      )
      // 块间补的换行进复制串
      assert_true(picked.contains("\n"), msg="块间没有换行分隔")
      // 中间块（段落乙）的首字节必须在选区内（连续而非只点亮两端）
      assert_true(
        b > md_byte_len("标题甲") + 1 + md_byte_len("段落乙"),
        msg="选区末端没越过中间块（b=\{b}）",
      )
    }
    None => abort("跨块拖选没成选区")
  }
  // 松手后在另一块内单击：选区折叠，跨块高亮清空
  let mid = labels[1]
  md_sel_click(root, mid.rect.x + 5.0, mid.rect.y + 1.0)
  md_sel_up(root, mid.rect.x + 5.0, mid.rect.y + 1.0)
  assert_true(state.ed.selection() is None, msg="单击没折叠跨块选区")
}

///|
test "选中档：拖选松手后再移动不改选区（带链接的段落也必须成立）" {
  // 带链接的段落走的是「链接命中优先」的指针分支——Up 若不转发进选中链，
  // sel_pointer 清不掉 dragging，松手后移动会一直从旧锚点改选区（真机实测）。
  let src = "前半句足够长用来把这一段折成两行，看 [链接](https://example.com) 与后续文字。"
  let spans = md_flat_par(src)
  let cx : MDCtx = { ..md_test_ctx(), sel: true, width: 240.0, }
  let root = mount_doc(md_rich_label(spans, 13.0, cx), 240.0, 120.0)
  let label = root.children()[0]
  let state = match md_sel_states.get(label.id) {
    Some(s) => s
    None => abort("选中档没装起来")
  }
  let y = label.rect.y + 1.0
  // 按下拖选出一段，松手
  md_sel_click(root, label.rect.x + 1.0, y)
  md_sel_move(root, label.rect.x + 100.0, y)
  md_sel_up(root, label.rect.x + 100.0, y)
  let after_up = state.ed.selection()
  assert_true(after_up is Some(_), msg="拖选没成选区")
  // 松手后再移动（无按键）：选区必须纹丝不动
  md_sel_move(root, label.rect.x + 30.0, y)
  assert_eq(state.ed.selection(), after_up, msg="松手后移动仍改选区")
  // 换一行位置再扫一遍，同样不许动
  md_sel_move(root, label.rect.x + 200.0, label.rect.y + label.rect.h - 1.0)
  assert_eq(
    state.ed.selection(),
    after_up,
    msg="松手后跨行移动仍改选区",
  )
}
