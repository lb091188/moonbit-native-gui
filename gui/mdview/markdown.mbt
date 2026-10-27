// Markdown 展示视图（新栈）：@mdparse（NoahLiu/mdparse）解析 + 富文本行自绘
// 渲染，渲染层复用 `@ui` 组件面。
// 块级:标题 1-6(ATX/Setext)、围栏(```/~~~)与缩进代码块(复用
// @ui.code_view,语言取 info 串首词)、引用(子块递归)、GFM 提示块、
// 无序/有序(带 start)/任务列表(checkbox 复选框)、表格(等分列宽
// 网格,单元格富文本,列对齐随源标注)、定义列表、分隔线、脚注(正文
// 上标引用 + 文末定义)、块级图片(本地路径加载显示,失败降级 alt);
// 行内:**粗体**、*斜体*、~~删除线~~(横线自绘)、`行内代码`、
// [链接](url)(点击经 on_link 回调交调用方处理——open_url 属系统能力
// 线,接入后由调用方转接)、自动链接、引用式链接、图片(行内降级
// alt)、软换行→空格、硬换行→换行。行内 HTML / HTML 块默认不渲染。
// 富文本行自绘:逐段测宽得区间像素坐标,删除线横线、链接命中与悬浮
// 手型均按此换算;样式区间端点统一 UTF-8 字节下标(md_byte_len 换算,
// 与 AttributedText 契约同源),中英混排与 emoji 之后样式都不错位。

///|
/// 行内片段:一段带样式的文本。url 非空表示可点击链接(经 on_link
/// 回调交给调用方);sup 为脚注上标引用(小一号字体);strike 为删除线
/// (渲染层按区间像素坐标自画横线)。
priv struct MDSpan {
  mut text : String
  bold : Bool
  italic : Bool
  code : Bool
  link : Bool
  strike : Bool
  sup : Bool
  url : String
}

///|
/// 行内样式集:展平时随嵌套节点叠加(显式栈携带)。
priv struct MDStyle {
  bold : Bool
  italic : Bool
  code : Bool
  link : Bool
  strike : Bool
  sup : Bool
  url : String
}

///|
/// 无样式的片段(辅助构造)。
fn md_plain_span(text : String, link? : Bool = false) -> MDSpan {
  {
    text,
    bold: false,
    italic: false,
    code: false,
    link,
    strike: false,
    sup: false,
    url: "",
  }
}

///|
/// 全默认样式集。
fn md_style_default() -> MDStyle {
  {
    bold: false,
    italic: false,
    code: false,
    link: false,
    strike: false,
    sup: false,
    url: "",
  }
}

///|
/// 脚注扫描结果:no 为 label→正文序号(1 起),order 保存编号顺序。
priv struct MDFootScan {
  no : Map[String, Int]
  order : Array[String]
  counter : Ref[Int]
}

///|
/// 渲染上下文:脚注扫描结果、文档级链接定义(label→地址)、内容基准宽
/// (图片缩放上限)、链接点击回调(open_url 属系统能力线,由调用方接入)。
priv struct MDCtx {
  foot : MDFootScan
  defs : Map[String, String]
  width : Double
  on_link : (String) -> Unit
}

///|
/// 引用式链接/图片取地址:按 label 查文档级链接定义,查不到返回空串
/// (渲染为无点击的链接样式)。
fn md_def_url(label : String, ctx : MDCtx) -> String {
  match ctx.defs.get(label.trim(chars=" \t\n\r").to_owned()) {
    Some(u) => u
    None => ""
  }
}

///|
/// 一段文本的 UTF-8 字节数。`AttributedText` 的区间端点一律按**字节**计量
/// （C 侧 Pango 直接用字节索引，DWrite 侧再换算），禁止按码点或 UTF-16 code
/// unit 累计——中英混排时两者差 3 倍，样式会整体落到前面的字符上。
fn md_byte_len(text : String) -> Int {
  let mut n = 0
  for ch in text {
    let c = ch.to_int()
    n += if c < 0x80 {
      1
    } else if c < 0x800 {
      2
    } else if c < 0x10000 {
      3
    } else {
      4
    }
  }
  n
}

///|
/// 行内树展平:嵌套 mdast 行内节点递归展平为扁平 spans。显式栈遍历,
/// 子节点随样式集叠加压栈;相邻同样式片段合并,减少区间数。
/// 映射:Text 逐段收样;Code 加代码样式;Strong/Emphasis 子树加粗/斜;
/// Strikethrough 子树加删除线;Link 子树加链接样式并携地址;RefLink
/// 查链接定义取地址;Autolink 渲染地址;WikiLink 渲染标签(地址非
/// http 不挂点击);图片渲染 alt 并加链接样式(块级单图段落才显示图片);
/// FootnoteReference 渲染为上标 "[n]"(编号取脚注扫描);SoftBreak 渲染
/// 为空格;HardBreak 渲染为换行;行内 HTML/行内指令不渲染。
fn md_flatten_inline(inlines : Array[@mdast.Inline], ctx : MDCtx) -> Array[MDSpan] {
  let spans : Array[MDSpan] = []
  let nodes : Array[@mdast.Inline] = []
  let styles : Array[MDStyle] = []
  fn same_style(a : MDSpan, st : MDStyle) -> Bool {
    a.bold == st.bold && a.italic == st.italic && a.code == st.code && a.link == st.link && a.strike == st.strike && a.sup == st.sup && a.url == st.url
  }

  fn emit(text : String, st : MDStyle) -> Unit {
    if text.length() == 0 {
      return
    }
    let n = spans.length()
    if n > 0 && same_style(spans[n - 1], st) {
      spans[n - 1].text = spans[n - 1].text + text
    } else {
      spans.push({
        text,
        bold: st.bold,
        italic: st.italic,
        code: st.code,
        link: st.link,
        strike: st.strike,
        sup: st.sup,
        url: st.url,
      })
    }
  }

  // 逆序压栈保持文档顺序
  fn push_all(arr : Array[@mdast.Inline], st : MDStyle) -> Unit {
    for i = arr.length() - 1; i >= 0; i = i - 1 {
      nodes.push(arr[i])
      styles.push(st)
    }
  }

  push_all(inlines, md_style_default())
  while nodes.length() > 0 {
    let node = nodes.pop().unwrap()
    let st = styles.pop().unwrap()
    match node {
      Text(content~, ..) => emit(content, st)
      Code(content~, ..) => emit(content, { ..st, code: true })
      Strong(children~, ..) => push_all(children, { ..st, bold: true })
      Emphasis(children~, ..) => push_all(children, { ..st, italic: true })
      Strikethrough(children~, ..) => push_all(children, { ..st, strike: true })
      Link(children~, url~, ..) => push_all(children, { ..st, link: true, url })
      RefLink(children~, label~, ..) =>
        push_all(children, { ..st, link: true, url: md_def_url(label, ctx) })
      Autolink(url~, ..) => emit(url, { ..st, link: true, url })
      WikiLink(label~, ..) => emit(label, { ..st, link: true })
      Image(alt~, ..) | RefImage(alt~, ..) => emit(alt, { ..st, link: true })
      FootnoteReference(label~, ..) =>
        match ctx.foot.no.get(label) {
          Some(n) => emit("[\{n}]", { ..st, sup: true })
          None => ()
        }
      SoftBreak(..) => emit(" ", st)
      HardBreak(..) => emit("\n", st)
      HtmlInline(..) | Directive(..) => ()
    }
  }
  spans
}

///|
/// 展平片段 → 富文本区间表:[start, end) 为 **UTF-8 字节**端点
/// (AttributedText 区间语义),渲染与测试共用同一计量。
fn md_span_ranges(spans : Array[MDSpan]) -> Array[(Int, Int, MDSpan)] {
  let marks : Array[(Int, Int, MDSpan)] = []
  let pos = Ref(0)
  for span in spans {
    let start = pos.val
    pos.val += md_byte_len(span.text)
    marks.push((start, pos.val, span))
  }
  marks
}

///|
/// 围栏 info 串提取语言:取空白分隔的首词("rust title=x" → "rust")。
fn md_info_lang(info : String) -> String {
  let t = info.trim(chars=" \t\n\r").to_owned()
  let sb = StringBuilder()
  for ch in t {
    if ch == ' ' || ch == '\t' {
      break
    }
    sb.write_char(ch)
  }
  sb.to_string()
}

///|
/// 整块代码文本按 \n 切行(顺去 \r 与末尾空行),供 code_view 使用。
///|
fn md_split_code_lines(code : String) -> Array[String] {
  let lines : Array[String] = []
  let cur = Ref(StringBuilder())
  for ch in code {
    if ch == '\n' {
      lines.push(cur.val.to_string())
      cur.val = StringBuilder()
    } else if ch != '\r' {
      cur.val.write_char(ch)
    }
  }
  let tail = cur.val.to_string()
  if tail.length() > 0 || lines.length() == 0 {
    lines.push(tail)
  }
  lines
}

///|
/// 标题字号(级别 1-6)。
fn md_heading_size(level : Int) -> Double {
  match level {
    1 => 22.0
    2 => 18.0
    3 => 16.0
    4 => 14.0
    5 => 13.0
    _ => 12.5
  }
}

///|
/// 普通列表项标记(任务列表走 checkbox,不经此)。
fn md_list_marker(base : String) -> String {
  base
}

///|
/// GFM 提示块标题文字。
fn md_alert_title(kind : @mdast.AlertKind) -> String {
  match kind {
    Note => "NOTE"
    Tip => "TIP"
    Important => "IMPORTANT"
    Warning => "WARNING"
    Caution => "CAUTION"
  }
}

///|
/// 表格列对齐:mdast TableAlign → 容器对齐(None 归左)。
fn md_align_of(a : @mdast.TableAlign) -> @yoga.AlignItems {
  match a {
    @mdast.Center => @yoga.AlignItems::Center
    @mdast.Right => @yoga.AlignItems::FlexEnd
    _ => @yoga.AlignItems::FlexStart
  }
}

///|
/// 图片地址转本地路径:剥 file:// 前缀,其余原样(相对进程工作目录)。
fn md_image_path(url : String) -> String {
  if url.has_prefix("file://") {
    let sb = StringBuilder()
    let mut i = 0
    for ch in url {
      if i >= 7 {
        sb.write_char(ch)
      }
      i += 1
    }
    sb.to_string()
  } else {
    url
  }
}

///|
/// 脚注引用行内预扫描:行内树递归,遇 FootnoteReference 按出现顺序编号
/// (同一 label 只编号一次)。
fn md_scan_inline(inlines : Array[@mdast.Inline], s : MDFootScan) -> Unit {
  for node in inlines {
    match node {
      FootnoteReference(label~, ..) =>
        if s.no.get(label) is None {
          s.counter.val += 1
          s.no.set(label, s.counter.val)
          s.order.push(label)
        }
      Strong(children~, ..)
      | Emphasis(children~, ..)
      | Strikethrough(children~, ..)
      | Link(children~, ..)
      | RefLink(children~, ..) => md_scan_inline(children, s)
      Text(..)
      | SoftBreak(..)
      | HardBreak(..)
      | Code(..)
      | Directive(..)
      | WikiLink(..)
      | Autolink(..)
      | Image(..)
      | RefImage(..)
      | HtmlInline(..) => ()
    }
  }
}

///|
/// 脚注引用块级预扫描:遍历全部块(含嵌套列表/引用/表格单元格);
/// FootnoteDefinition 自身跳过(定义内的引用不参与编号)。
fn md_scan_blocks(blocks : Array[@mdast.Block], s : MDFootScan) -> Unit {
  for b in blocks {
    match b {
      Heading(children~, ..) | Paragraph(children~, ..) => md_scan_inline(children, s)
      Blockquote(children~, ..) | Alert(children~, ..) | Directive(children~, ..) =>
        md_scan_blocks(children, s)
      BulletList(items~, ..) | OrderedList(items~, ..) =>
        for it in items {
          md_scan_blocks(it.children, s)
        }
      Table(header~, rows~, ..) => {
        for c in header {
          md_scan_inline(c.children, s)
        }
        for row in rows {
          for c in row {
            md_scan_inline(c.children, s)
          }
        }
      }
      DefinitionList(items~, ..) =>
        for it in items {
          md_scan_inline(it.term, s)
          for d in it.definitions {
            md_scan_inline(d, s)
          }
        }
      Attributed(block~, ..) => md_scan_blocks([block], s)
      FencedCode(..)
      | IndentedCode(..)
      | MathBlock(..)
      | ThematicBreak(..)
      | HtmlBlock(..)
      | BlankLines(..)
      | FootnoteDefinition(..) => ()
    }
  }
}

///|
/// 列表项内容:段落直接展平(不套段落外距,行距一致),其余块递归。
fn md_item_content(children : Array[@mdast.Block], ctx : MDCtx) -> Array[@widget.Node] {
  let nodes : Array[@widget.Node] = []
  for b in children {
    match b {
      Paragraph(children=inl, ..) => nodes.push(md_rich_label(md_flatten_inline(inl, ctx), 13.0, ctx))
      _ =>
        for n in md_render_blocks([b], ctx) {
          nodes.push(n)
        }
    }
  }
  nodes
}

///|
/// 定宽标记列(列表圆点/序号/定义点)。
fn md_marker(text : String, w : Double) -> @widget.Node {
  @widget.node_of_new(fn(mk : @widget.Widget) -> @widget.Widget {
    mk.node.set_width(@yoga.fixed(w))
    // 行盒高度必须注册测量：这个格子只有绘制、没有子件，不注册就是**零高度**，
    // 而 hbox 默认 align_items=Center——0 高的格子被摆到行的中点，序号整个
    // 掉到文字基线上（实测 rect=(0,111,18,0) 而正文在 102..120，数字中心正好
    // 压在基线上）。测一次自己的文本，拿到与正文同源的行盒高。
    mk.node.set_measure(fn(_aw : Double?, _ah : Double?) -> (Double, Double) {
      match @text.measure(text, 13.0) {
        Some(m) => (m.width.to_double(), m.height.to_double())
        None => (w, 18.0)
      }
    })
    mk.on_draw = Some(fn(
      _self : @widget.Widget,
      p : @render.Painter,
      r : @base.Rect,
    ) -> Unit {
      let _ = @text.draw_box_at(
        p,
        0.0,
        0.0,
        r.w,
        r.h,
        text,
        @text.Font::new("", 13.0),
        @theme.theme_text_regular(),
        align=@text.Start,
        // 贴**首行**顶对齐（不是整盒居中）：列表项盒子常有一行多高，居中会把
        // 序号摆到中间——数字的中心正好压在首行基线上，看着像掉到基线下面
        valign=@text.Start,
        wrap=false,
      )
    })
    mk
  })
}

///|
/// 引用/提示块:主题色竖条 + 缩进内容。
fn md_quoted(content : Array[@widget.Node]) -> @widget.Node {
  let bar = @widget.node_of_new(fn(b : @widget.Widget) -> @widget.Widget {
    b.node.set_width(@yoga.fixed(3.0))
    b.node.set_min_height(@yoga.fixed(24.0))
    b.node.set_align_self(Some(@yoga.AlignItems::Stretch))
    b.on_draw = Some(fn(
      _self : @widget.Widget,
      p : @render.Painter,
      r : @base.Rect,
    ) -> Unit {
      p.set_fill_color(@theme.theme_primary())
      p.fill_rect(0.0, 0.0, r.w, r.h)
    })
    b
  })
  @ui.row([bar, @ui.col(content)], column_gap=10.0)
}

///|
/// 块级图片:本地路径加载显示(等比缩放,宽度上限取 ctx.width);加载
/// 失败或网络地址降级为 alt 富文本(链接样式)——富文本行不支持行内
/// 嵌图。
fn md_image(url : String, alt : String, ctx : MDCtx) -> @widget.Node {
  let img = @render.Image::new_from_file(md_image_path(url))
  if img.is_empty() {
    md_rich_label([md_plain_span(alt, link=true)], 13.0, ctx)
  } else {
    let iw = img.get_width()
    let ih = img.get_height()
    let w = if iw > 1.0 { iw.min(ctx.width) } else { 1.0 }
    let h = if iw > 1.0 { (w * ih / iw).max(1.0) } else { 1.0 }
    @widget.node_of_new(fn(c : @widget.Widget) -> @widget.Widget {
      c.node.set_width(@yoga.fixed(w))
      c.node.set_height(@yoga.fixed(h))
      c.node.set_margin_bottom(@yoga.fixed(10.0))
      c.on_draw = Some(fn(
        _self : @widget.Widget,
        p : @render.Painter,
        _r : @base.Rect,
      ) -> Unit {
        let _ = p.draw_image(img, 0.0, 0.0, w, h)
      })
      c
    })
  }
}

///|
/// 表格单元格 → 展平片段(表头加粗)。
fn md_table_cell_spans(cell : @mdast.TableCell, head : Bool, ctx : MDCtx) -> Array[MDSpan] {
  if head {
    let spans : Array[MDSpan] = []
    for s in md_flatten_inline(cell.children, ctx) {
      spans.push({ ..s, bold: true })
    }
    spans
  } else {
    md_flatten_inline(cell.children, ctx)
  }
}

///|
/// 表格:等分列宽网格(格子宽按列数均分百分比),表头加粗、表头下
/// 分隔线,列对齐随源标注(:--- / :---: / ---:)经格子容器 align_items
/// 落地;单元格为富文本(粗体/代码/链接可用)。
fn md_table(
  header : Array[@mdast.TableCell],
  alignments : Array[@mdast.TableAlign],
  rows : Array[Array[@mdast.TableCell]],
  ctx : MDCtx,
) -> @widget.Node {
  let n = header.length().max(1)
  let cells_of = fn(row : Array[@mdast.TableCell], head : Bool) -> Array[@widget.Node] {
    let cells : Array[@widget.Node] = []
    for i, cell in row {
      let al = match alignments.get(i) {
        Some(a) => md_align_of(a)
        None => @yoga.AlignItems::FlexStart
      }
      cells.push(
        @ui.view(
          [md_rich_label(md_table_cell_spans(cell, head, ctx), 13.0, ctx)],
          align_items=al,
          handle=fn(cw : @widget.Widget) -> Unit {
            cw.node.set_width(@yoga.percent(100.0 / n.to_double()))
          },
        ),
      )
    }
    cells
  }
  let nodes : Array[@widget.Node] = [@ui.row(cells_of(header, true))]
  nodes.push(@ui.divider())
  for row in rows {
    nodes.push(@ui.row(cells_of(row, false)))
  }
  // 列宽不可折(等分 percent,窄到极限也不折行):视口自带横向滚动,与代码块同口径
  @ui.scroll_view([@ui.col(nodes)], @ui.ScrollState::new(), hscroll=true)
}

///|
/// 块级渲染:mdast Block 17 变体 → 节点序列。不渲染的变体:HtmlBlock、
/// BlankLines、FootnoteDefinition(定义在 markdown_view 文末统一渲染)。
fn md_render_blocks(blocks : Array[@mdast.Block], ctx : MDCtx) -> Array[@widget.Node] {
  let nodes : Array[@widget.Node] = []
  for block in blocks {
    match block {
      Heading(level~, children~, ..) =>
        nodes.push(
          @ui.col([
          md_rich_label(
            md_flatten_inline(children, ctx),
            md_heading_size(level),
            ctx,
          ),
        ]),
        )
      Paragraph(children~, ..) => {
        // 块级图片:段落恰为一张图时显示图片(引用式图片查链接定义取地址)
        let mut img : (String, String) = ("", "")
        if children.length() == 1 {
          match children[0] {
            Image(alt~, url~, ..) => img = (url, alt)
            RefImage(alt~, label~, ..) => {
              let u = md_def_url(label, ctx)
              if u != "" {
                img = (u, alt)
              }
            }
            _ => ()
          }
        }
        if img.0 != "" {
          nodes.push(md_image(img.0, img.1, ctx))
        } else {
          nodes.push(
          @ui.col([md_rich_label(md_flatten_inline(children, ctx), 13.0, ctx)]),
        )
        }
      }
      FencedCode(info~, code~, ..) =>
        nodes.push(
          @ui.code_view(md_split_code_lines(code), lang=md_info_lang(info)),
        )
      IndentedCode(code~, ..) =>
        nodes.push(@ui.code_view(md_split_code_lines(code)))
      MathBlock(value~, ..) =>
        nodes.push(@ui.code_view(md_split_code_lines(value), lang="math"))
      Blockquote(children~, ..) =>
        // 引用收块:子块(段落/列表/嵌套引用)整体递归进竖条内容区
        nodes.push(md_quoted(md_render_blocks(children, ctx)))
      Alert(kind~, children~, ..) => {
        let content : Array[@widget.Node] = [
          @ui.text(md_alert_title(kind), weight=@text.SemiBold),
        ]
        for n in md_render_blocks(children, ctx) {
          content.push(n)
        }
        nodes.push(md_quoted(content))
      }
      BulletList(items~, ..) =>
        for item in items {
          match item.checked {
            // GFM 任务列表:真复选框(可勾选),内容并排
            Some(ck) =>
              nodes.push(
                @ui.row([
                  @ui.checkbox("", @base.Store::new(ck)),
                  @ui.col(md_item_content(item.children, ctx)),
                ]),
              )
            None =>
              nodes.push(
                @ui.row([
                  md_marker(md_list_marker("•"), 18.0),
                  @ui.col(md_item_content(item.children, ctx)),
                ]),
              )
          }
        }
      OrderedList(start~, items~, ..) => {
        let mut no = start
        for item in items {
          nodes.push(
            @ui.row([
              md_marker("\{no}.", 18.0),
              @ui.col(md_item_content(item.children, ctx)),
            ]),
          )
          no += 1
        }
      }
      Table(header~, alignments~, rows~, ..) =>
        nodes.push(md_table(header, alignments, rows, ctx))
      DefinitionList(items~, ..) =>
        for item in items {
          nodes.push(
            @ui.col([md_rich_label(md_flatten_inline(item.term, ctx), 13.0, ctx)]),
          )
          for def in item.definitions {
            nodes.push(
              @ui.row([
                md_marker("·", 18.0),
                md_rich_label(md_flatten_inline(def, ctx), 13.0, ctx),
              ]),
            )
          }
        }
      Directive(children~, ..) =>
        // 块级指令(:::note 等)渲染其内容
        for n in md_render_blocks(children, ctx) {
          nodes.push(n)
        }
      Attributed(block~, ..) =>
        for n in md_render_blocks([block], ctx) {
          nodes.push(n)
        }
      ThematicBreak(..) => nodes.push(@ui.divider())
      HtmlBlock(..) | BlankLines(..) | FootnoteDefinition(..) => ()
    }
  }
  nodes
}

///|
/// 是否「宽字符」(CJK 与全角标点):这类字符自成一个断行单元——中文没有空格,
/// 断点只能落在字与字之间;拉丁词整词为一个单元,不在词中间断开。
fn md_is_wide(ch : Char) -> Bool {
  let c = ch.to_int()
  if c < 0x1100 {
    false
  } else if c <= 0x115f {
    true
  } else if c >= 0x2e80 && c <= 0xa4cf {
    true
  } else if c >= 0xac00 && c <= 0xd7a3 {
    true
  } else if c >= 0xf900 && c <= 0xfaff {
    true
  } else if c >= 0xfe30 && c <= 0xfe6f {
    true
  } else if c >= 0xff00 && c <= 0xff60 {
    true
  } else {
    c >= 0xffe0 && c <= 0xffe6
  }
}

///|
/// 片段文本 → 断行单元:`\n` 出一个硬换行标记(单元文本就是 "\n"),宽字符
/// 逐字成单元,其余按「词 + 尾随空格」成单元(断行只发生在单元之前)。
fn md_units(text : String) -> Array[String] {
  let out : Array[String] = []
  let cur = Ref(StringBuilder())
  fn flush() -> Unit {
    let s = cur.val.to_string()
    if s.length() > 0 {
      out.push(s)
      cur.val = StringBuilder()
    }
  }

  for ch in text {
    if ch == '\n' {
      flush()
      out.push("\n")
    } else if md_is_wide(ch) {
      flush()
      out.push(ch.to_string())
    } else if ch == ' ' {
      // 空格挂在词尾:断行发生在下一单元之前
      cur.val.write_char(ch)
      flush()
    } else {
      if cur.val.to_string().has_suffix(" ") {
        flush()
      }
      cur.val.write_char(ch)
    }
  }
  flush()
  out
}

///|
/// 两片段样式是否相同(同一行内相邻同样式单元合并用)。
fn md_style_key(
  x : MDSpan,
) -> (Bool, Bool, Bool, Bool, Bool, Bool, String) {
  (x.bold, x.italic, x.code, x.link, x.strike, x.sup, x.url)
}

///|
fn md_same_style(a : MDSpan, b : MDSpan) -> Bool {
  md_style_key(a) == md_style_key(b)
}

///|
/// 一行富文本的几何:`at` 是该行的绘制对象,`xs`/`ws` 是行内各片段的像素起点
/// 与宽度(删除线横线与链接命中按它换算)。三者全部**惰性**建:一次 min-content
/// 探询能折出上百条行,全量建对象是这一页卡顿的主因,而其中绝大多数行永远不会
/// 被画。`sum` 是折行期逐单元宽的累加(免费拿到的估算宽,只在探询档用)。
priv struct MDLine {
  spans : Array[MDSpan]
  sum : Double
  mut w : Double
  xs : Array[Double]
  ws : Array[Double]
  mut at : @text.AttributedText
  mut at_ready : Bool
  mut geo_ready : Bool
}

///|
/// 富文本行(自绘):先按可用宽度贪心折行(中文逐字、拉丁逐词、`\n` 硬换行),
/// 每行按需拼一个 AttributedText(只有真要画、或要被父级当内在宽用的行才建);
/// 删除线段按该行像素区间补画横线;带地址的链接段
/// 可点击(按行号 + 行内像素区间命中,经 ctx.on_link 交调用方),悬浮手型光标;
/// sup 段用小一号字体;链接/代码段主题色,主题指纹变化时只重建绘制对象。
/// 区间端点由 [md_span_ranges] 按 UTF-8 字节计量。
fn md_rich_label(
  spans : Array[MDSpan],
  size : Double,
  ctx : MDCtx,
  max_w? : Double = 0.0,
) -> @widget.Node {
  // 折行产出走 Ref:显式定宽(max_w/ctx.width > 0,旧口径)构造期折一次、
  // 节点定宽定高;宽度 0(跟随容器)由 yoga measure 按可用宽重折——布局引擎
  // 的宽度约束就是响应式来源,不需要任何 resize 监听。limit 变化才重折。
  // `rows_ref` 只保存**要画的那一档**折叠:一次布局里 yoga 会交替问 max-content
  // (aw=None)、min-content(aw<1)、正式档三遍,若共用一份折叠状态,每遍都把上
  // 一遍的产出顶掉(重折 + 逐行建对象),而探询档的答案还可能是顶之前算的旧值。
  // 两个探询档各记一份备忘,不碰 rows_ref。
  let rows_ref : Ref[Array[MDLine]] = Ref([])
  let drawn_limit : Ref[Double] = Ref(-1.0)
  let min_ans = Ref((0.0, 0.0))
  let max_ans = Ref((0.0, 0.0))
  let static_limit : Double? = if max_w > 0.0 {
    Some(max_w)
  } else if ctx.width > 0.0 {
    Some(ctx.width)
  } else {
    None
  }
  let regular = @text.Font::new("", size)
  let bold = @text.Font::new("", size, weight=@text.Bold)
  let italic = @text.Font::new("", size, style=@text.Italic)
  let bold_italic = @text.Font::new("", size, weight=@text.Bold, style=@text.Italic)
  let mono = @text.Font::new("Monospace", size - 1.0)
  let sup_font = @text.Font::new("", (size - 4.0).max(8.0))
  fn font_of(span : MDSpan) -> @text.Font {
    if span.sup {
      sup_font
    } else if span.code {
      mono
    } else if span.bold && span.italic {
      bold_italic
    } else if span.bold {
      bold
    } else if span.italic {
      italic
    } else {
      regular
    }
  }

  fn font_tag(span : MDSpan) -> String {
    if span.sup {
      "s"
    } else if span.code {
      "m"
    } else if span.bold && span.italic {
      "bi"
    } else if span.bold {
      "b"
    } else if span.italic {
      "i"
    } else {
      "r"
    }
  }

  // 单元测宽:一次折行要测几十上百个单元,同名单元走本地缓存
  let wcache : Map[String, Double] = Map([])
  // 段宽要按「它在行中」量，不能按「它孤零零在行尾」量：CoreText 给行尾的全角
  // 标点一个压缩后的 advance（mac 实测「支持、」33、「支持、斜体」65——同一个
  // 「、」差 6px），而单独量一段正是行尾形态，于是逐段累加比整行联合窄：折行
  // 会超宽、删除线横线与链接命中会整体左偏。做法：段尾补一个中性汉字再减掉它
  // 自己的宽，把这一段还原成「后面还有字」的行中形态。
  let sent_cache : Map[String, Double] = Map([])
  fn sent_w(font : @text.Font, tag : String) -> Double {
    match sent_cache.get(tag) {
      Some(v) => v
      None => {
        let v = match @text.measure_font("中", font, wrap=false) {
          Some(m) => m.width.to_double()
          None => 0.0
        }
        sent_cache.set(tag, v)
        v
      }
    }
  }

  fn unit_w(unit : String, span : MDSpan) -> Double {
    let tag = font_tag(span)
    let key = tag + "@" + unit
    match wcache.get(key) {
      Some(v) => v
      None => {
        let f = font_of(span)
        let full = match @text.measure_font(
          unit + "中",
          f,
          max_width=0,
          ellipsize=false,
          wrap=false,
        ) {
          Some(m) => m.width.to_double()
          None => 0.0
        }
        let v = (full - sent_w(f, tag)).max(0.0)
        wcache.set(key, v)
        v
      }
    }
  }

  fn build_at(line : Array[MDSpan]) -> @text.AttributedText {
    let parts : Array[String] = []
    for sp in line {
      parts.push(sp.text)
    }
    let at = @text.AttributedText::new(
      parts.join(""),
      valign=@text.Center,
      wrap=false,
    )
    at.set_font(regular)
    at.set_color(@theme.theme_text_regular())
    for mark in md_span_ranges(line) {
      let (s, e, sp) = mark
      if sp.sup {
        at.set_font_for(sup_font, s, e)
      } else if sp.bold && sp.italic {
        at.set_font_for(bold_italic, s, e)
      } else if sp.bold {
        at.set_font_for(bold, s, e)
      } else if sp.italic {
        at.set_font_for(italic, s, e)
      } else if sp.code {
        at.set_font_for(mono, s, e)
      }
      if sp.link || sp.code {
        at.set_color_for(@theme.theme_primary(), s, e)
      }
    }
    at
  }

  /// 段起点与段宽按**整行联合排版**量（拿真正绘制用的那份 AttributedText 量
  /// 前缀），不按逐段宽度累加：换字体的边界上，一段单独量的宽与它在混排行里
  /// 占的宽不一致（mac 真机 13 号混排行实测累加比联合窄 11px），按累加值画的
  /// 删除线横线与按它命中的链接区间会整体错位、压在前一段字上。
  fn joint_w(line : Array[MDSpan], upto : Int) -> Double {
    if upto <= 0 {
      0.0
    } else {
      let head : Array[MDSpan] = []
      for i = 0; i < upto; i = i + 1 {
        head.push(line[i])
      }
      build_at(head).get_bounds_for(0.0, 0.0).width
    }
  }

  fn mk_line(line : Array[MDSpan], sum : Double) -> MDLine {
    {
      spans: line,
      sum,
      w: 0.0,
      xs: [],
      ws: [],
      at: @text.AttributedText::new("", valign=@text.Center, wrap=false),
      at_ready: false,
      geo_ready: false,
    }
  }

  /// 该行的绘制对象：首次真要画才建（建一次 = 一次 C 端排版会话）。
  fn line_at(line : MDLine) -> @text.AttributedText {
    if !line.at_ready {
      line.at = build_at(line.spans)
      line.at_ready = true
    }
    line.at
  }

  /// 整行联合排版宽：拿真正绘制用的那份对象量，首次用到才付测宽。
  fn line_w(line : MDLine) -> Double {
    if line.w <= 0.0 {
      let lw = line_at(line).get_bounds_for(0.0, 0.0).width
      line.w = if lw < 1.0 { 1.0 } else { lw }
    }
    line.w
  }

  /// 行内各段的像素起点与宽度：只有带删除线/链接的行需要，且只量一次。
  fn line_geo(line : MDLine) -> Unit {
    if !line.geo_ready {
      let n = line.spans.length()
      for i in 0..<n {
        let a = joint_w(line.spans, i)
        let b = joint_w(line.spans, i + 1)
        line.xs.push(a)
        line.ws.push((b - a).max(0.0))
      }
      line.geo_ready = true
    }
  }

  fn rows_w(rows : Array[MDLine]) -> Double {
    let mut w = 1.0
    for g in rows {
      w = w.max(line_w(g))
    }
    w
  }

  /// 探询档用的估算宽：逐单元宽累加，不逐行建对象。
  fn rows_sum_w(rows : Array[MDLine]) -> Double {
    let mut w = 1.0
    for g in rows {
      w = w.max(g.sum)
    }
    w
  }

  // 贪心折行:单元放不下就整单元换行(不做词内断开)。只产出段与逐单元累加宽,
  // 绘制几何留到真要画的那一行才建。
  fn fold_at(limit : Double) -> Array[MDLine] {
    let rows : Array[MDLine] = []
    let cur : Array[MDSpan] = []
    let cur_w = Ref(0.0)
    fn end_line() -> Unit {
      if cur.length() > 0 {
        rows.push(mk_line(cur.copy(), cur_w.val))
        cur.clear()
        cur_w.val = 0.0
      }
    }

    fn put(unit : String, span : MDSpan) -> Unit {
      let uw = unit_w(unit, span)
      if cur_w.val + uw > limit && cur.length() > 0 {
        end_line()
      }
      let n = cur.length()
      if n > 0 && md_same_style(cur[n - 1], span) {
        cur[n - 1].text = cur[n - 1].text + unit
      } else {
        cur.push({ ..span, text: unit })
      }
      cur_w.val += uw
    }

    for span in spans {
      for unit in md_units(span.text) {
        if unit == "\n" {
          end_line()
        } else if unit_w(unit, span) > limit {
          // 单个单元就比整行宽(长 URL / 长单词):按字符硬切,不然必然撑破容器
          for ch in unit {
            put(ch.to_string(), span)
          }
        } else {
          put(unit, span)
        }
      }
    }
    if cur.length() > 0 || rows.length() == 0 {
      rows.push(mk_line(cur.copy(), cur_w.val))
    }
    rows
  }

  let used_fonts : Array[@text.Font] = [regular]
  for sp in spans {
    used_fonts.push(font_of(sp))
  }
  let line_h_nat = match @text.line_height_multi(used_fonts) {
    Some(h) => h.to_double().max(1.0)
    None => size * 1.5
  }
  // 正文行距给足：字体天然行高只保证字形不相撞（13 号约 17），排出来每行贴脸。
  // 统一按字号 1.6 倍起排，标题这类大字号同样留得住呼吸。
  let line_h = line_h_nat.max(size * 1.6)
  @widget.node_of_new(fn(w : @widget.Widget) -> @widget.Widget {
    @ui.watch_theme()
    let fps = Ref("")
    match static_limit {
    Some(l) => {
      let rows = fold_at(l)
      rows_ref.val = rows
      drawn_limit.val = l
      w.node.set_width(@yoga.fixed(rows_w(rows)))
      w.node.set_height(@yoga.fixed(line_h * rows.length().to_double()))
    }
    None =>
      // 跟随容器:不设宽,yoga 才会把容器可用宽传进 measure 的 aw(设了宽
      // ——percent 也一样——aw 就不来了,折行只能落 fallback)。min-content
      // 探询已按「最窄可折」答,节点不会被探询宽撑大;宽随最长行,窄于容器
      // 时节点与容器同宽。
      // 不受约束(内在 max-content 探询)时答**自身最长行自然宽**,不落任何
      // 常量:常量会顺着「单元格自然宽 → 行自然宽 → percent 列的参照」把
      // 表格冻在该值上(真机 resize 后表格不重排、溢出滚不回来)。
      // 三档各自成答:宽和高都取**本档自己那次**折叠的产出。此前探询档拿的是
      // 顶之前算好的旧行数(1px 档折出「一字一行」的几十行高),整棵 md 列按这
      // 个被顶高的 max-content 排,真机表现就是列表项之间空出半屏。
      w.node.set_measure(fn(aw : Double?, _ah : Double?) -> (Double, Double) {
        match aw {
          // 正式档：按容器可用宽折，节点与可用宽同宽（块级跟随）
          Some(v) if v >= 1.0 => {
            if drawn_limit.val != v || rows_ref.val.length() == 0 {
              rows_ref.val = fold_at(v)
              drawn_limit.val = v
            }
            let rows = rows_ref.val
            (rows_w(rows).max(v), line_h * rows.length().to_double())
          }
          // min-content 探询（Some(0)）：1px 箱折，答最窄可折单元宽。
          // 这一档能折出「一单元一行」的上百条行，故只算宽不建绘制对象，
          // 且答案按档备忘——每次布局重折是这页滚动卡顿的来源。
          Some(_) => {
            if min_ans.val.0 <= 0.0 {
              let rows = fold_at(1.0)
              min_ans.val = (
                rows_sum_w(rows), line_h * rows.length().to_double(),
              )
            }
            min_ans.val
          }
          // max-content 探询（None）：单行不折，答自身最长行自然宽。
          None => {
            if max_ans.val.0 <= 0.0 {
              let rows = fold_at(1000000.0)
              max_ans.val = (rows_w(rows), line_h * rows.length().to_double())
            }
            max_ans.val
          }
        }
      })
    }
    w.on_draw = Some(fn(
      _self : @widget.Widget,
      p : @render.Painter,
      _r : @base.Rect,
    ) -> Unit {
      let cur_fp = @theme.theme_fingerprint_of(@theme.theme_current())
      if cur_fp != fps.val {
        fps.val = cur_fp
        for g in rows_ref.val {
          g.at_ready = false
        }
      }
      p.set_stroke_color(@theme.theme_text_regular())
      let mut y = 0.0
      for g in rows_ref.val {
        let _ = line_at(g).draw_at(p, 0.0, y, line_w(g), line_h)
        for i, sp in g.spans {
          if sp.strike {
            line_geo(g)
            p.begin_path()
            p.move_to(g.xs[i], y + line_h * 0.5)
            p.line_to(g.xs[i] + g.ws[i], y + line_h * 0.5)
            p.stroke()
          }
        }
        y += line_h
      }
    })
    // 链接交互:命中 = 先按 y 定行,再按该行像素区间定段 → on_link;悬浮手型
    let mut has_link = false
    for s in spans {
      if s.url != "" {
        has_link = true
      }
    }
    if has_link {
      fn hit_url(mx : Double, my : Double) -> String {
        let li = (my / line_h).floor().to_int()
        match rows_ref.val.get(li) {
          Some(g) => {
            if g.spans.any(fn(s : MDSpan) -> Bool { s.url != "" }) {
              line_geo(g)
              for j, s in g.spans {
                if s.url != "" && mx >= g.xs[j] && mx < g.xs[j] + g.ws[j] {
                  return s.url
                }
              }
            }
            ""
          }
          None => ""
        }
      }

      let hover = Ref(false)
      w.on_pointer = Some(fn(
        _self : @widget.Widget,
        ev : @widget.PointerEvent,
      ) -> Bool {
        match ev.kind {
          @widget.PointerKind::Down => {
            let u = hit_url(ev.x, ev.y)
            if u != "" {
              (ctx.on_link)(u)
              true
            } else {
              false
            }
          }
          @widget.PointerKind::Move => {
            let h = hit_url(ev.x, ev.y) != ""
            if h != hover.val {
              hover.val = h
              w.cursor = if h { @widget.CURSOR_HAND } else { 0 }
            }
            true
          }
          @widget.PointerKind::Leave => {
            if hover.val {
              hover.val = false
              w.cursor = 0
            }
            false
          }
          @widget.PointerKind::Up => false
        }
      })
    }
    w
  })
}

///|
/// Markdown 展示视图:@mdparse 解析 + 块级/行内渲染,
/// 代码块复用 @ui.code_view(语言取 fence info 首词,```rust、~~~py、
/// 缩进块通用);正文脚注引用按出现顺序编号,文末分隔线后逐条渲染被
/// 引用的脚注定义;链接点击经 on_link 回调交调用方(open_url 属系统
/// 能力线,接入后由调用方转接默认浏览器)。
/// width:0(缺省)= 跟随容器——段落按 yoga 布局的可用宽折行,窗口
/// resize 自动重排;>0 = 构造期定宽(旧口径,显式定宽的排版不再变)。
pub fn markdown_view(
  source : String,
  width? : Double = 0.0,
  on_link? : (String) -> Unit = fn(_u : String) -> Unit { () },
  handle? : (@widget.Widget) -> Unit = @ui.default_handle,
) -> @widget.Node {
  let res = @mdast.parse(source)
  let doc = res.document
  let foot : MDFootScan = { no: (Map([]) : Map[String, Int]), order: [], counter: Ref(0) }
  md_scan_blocks(doc.children, foot)
  let defs : Map[String, String] = (Map([]) : Map[String, String])
  for d in res.definitions {
    defs.set(d.label.trim(chars=" \t\n\r").to_owned(), d.url)
  }
  let ctx : MDCtx = { foot, defs, width, on_link }
  let nodes = md_render_blocks(doc.children, ctx)
  if foot.order.length() > 0 {
    let fd : Map[String, Array[@mdast.Block]] = (Map([]) : Map[String, Array[@mdast.Block]])
    for b in doc.children {
      match b {
        FootnoteDefinition(label~, children~, ..) => fd.set(label, children)
        _ => ()
      }
    }
    if fd.length() > 0 {
      nodes.push(@ui.divider())
      for lbl in foot.order {
        match fd.get(lbl) {
          Some(children) => {
            let num = match foot.no.get(lbl) {
              Some(n) => n
              None => 0
            }
            nodes.push(
              @ui.row([
                md_marker("\{num}.", 24.0),
                @ui.col(md_item_content(children, ctx)),
              ]),
            )
          }
          None => ()
        }
      }
    }
  }
  // 块间留 6：段与段、标题与正文之间不贴脸（行内行距见 md_rich_label）
  @ui.col(nodes, width=width, row_gap=6.0, handle~)
}
