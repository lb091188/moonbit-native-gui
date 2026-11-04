// Markdown 展示视图（新栈）：@mdparse（NoahLiu/mdparse）解析 + 富文本行自绘
// 渲染，渲染层复用 `@ui` 组件面。
// 块级:标题 1-6(ATX/Setext)、围栏(```/~~~)与缩进代码块(复用
// @ui.code_view,语言取 info 串首词,selectable 随 markdown_view 的
// selectable 透传)、引用(子块递归)、GFM 提示块、
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
  // 段落可选中（markdown_view 的 selectable 透传，混排逐字几何见 md_rich_label）
  sel : Bool
  // 文档级跨段选中（sel 为真时可挂）：一份 Editor 拼全文档，块间补换行；
  // None = 独立档（每块各一份选区，直接挂 md_rich_label 的旧口径）
  doc : MDDocSel?
}

///|
/// 文档级跨段选中的块登记：矩形由本块 on_draw 每帧回填（闭包禁捕 Widget，
/// 命中要的落点几何走这份纯数据）；off/len 是本块在全文里的字节区间；
/// hit 是「本块局部坐标 → 块内字节偏移」（捕获行模型，纯数据）。
priv struct MDBlockEntry {
  uid : Int
  mut x : Double
  mut y : Double
  mut h : Double
  off : Int
  len : Int
  hit : (Double, Double) -> Int
}

///|
let md_block_uid : Ref[Int] = Ref(0)

///|
/// 一篇 markdown 的文档级选中态：全文 = 各可选块按**构造序（即视觉序）**
/// 拼接，块间补一个 \n（复制出来块与块换行分隔）。一份 Editor / TextSel
/// 共享：拖选跨块连续、Shift 扩选跨块、复制得跨块原文；块矩形挂载绘制后
/// 陆续回填，命中按绝对坐标找落点块。
priv struct MDDocSel {
  ed : @input.Editor
  st : @ui.TextSel
  // 构造期顺序拼全文（\n 分隔），拼完一次性装进 ed
  buf : Ref[StringBuilder]
  // 下一块的全文字节偏移（构造期顺序分配）
  mut acc : Int
  // 块登记（视觉序），矩形挂载绘制后回填
  list : Ref[Array[MDBlockEntry]]
  // 选区持有者登记的固定 id（全块同号）
  claim_id : Int
}

///|
/// 文档级选中态的认领号计数。
let md_doc_uid : Ref[Int] = Ref(0)

///|
/// 绝对坐标 → 全文字节：先找矩形罩住落点的块（用它的逐字行模型精确定位），
/// 落在块间空隙按中点归前/后块端点，压不进任何块时收两端。
fn MDDocSel::byte_at(
  self : MDDocSel,
  e : MDBlockEntry,
  lx : Double,
  ly : Double,
) -> Int {
  let ax = e.x + lx
  let ay = e.y + ly
  let bs = self.list.val
  for b in bs {
    if ay >= b.y - 0.5 && ay <= b.y + b.h + 0.5 {
      return (b.hit)(ax - b.x, ay - b.y) + b.off
    }
  }
  let n = bs.length()
  if n == 0 {
    return 0
  }
  if ay < bs[0].y {
    return bs[0].off
  }
  let last = bs[n - 1]
  if ay > last.y + last.h {
    return last.off + last.len
  }
  let mut prev = bs[0]
  for b in bs {
    if b.y > ay {
      let mid = (prev.y + prev.h + b.y) / 2.0
      return if ay < mid { prev.off + prev.len } else { b.off }
    }
    prev = b
  }
  last.off + last.len
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
/// 行内块内容列（列表/任务/定义/脚注/引用行的右半）：**吃掉行内剩余宽**。
/// 不给 grow 时它是 shrink-to-fit，盒宽=自身 max-content，而折行判据按逐单元
/// 累加宽算，两者差不到 1px 就整体折出第二行——第二行又被单行的行盒裁掉，
/// 真机看着就是「列表项尾巴丢了」。块级内容的折行宽应当是文档宽减去标记列。
fn md_content_col(nodes : Array[@widget.Node]) -> @widget.Node {
  @ui.col(nodes, grow=1.0)
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
  @ui.row([bar, md_content_col(content)], column_gap=10.0)
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
          @ui.code_view(
            md_split_code_lines(code),
            lang=md_info_lang(info),
            selectable=ctx.sel,
          ),
        )
      IndentedCode(code~, ..) =>
        nodes.push(@ui.code_view(md_split_code_lines(code), selectable=ctx.sel))
      MathBlock(value~, ..) =>
        nodes.push(
          @ui.code_view(
            md_split_code_lines(value),
            lang="math",
            selectable=ctx.sel,
          ),
        )
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
                  md_content_col(md_item_content(item.children, ctx)),
                ]),
              )
            None =>
              nodes.push(
                @ui.row([
                  md_marker(md_list_marker("•"), 18.0),
                  md_content_col(md_item_content(item.children, ctx)),
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
              md_content_col(md_item_content(item.children, ctx)),
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
                md_content_col([
                  md_rich_label(md_flatten_inline(def, ctx), 13.0, ctx),
                ]),
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
///|
/// 控件 id → 选中态（本包用例的读回口：断言选区/插入点用，不对外）。
let md_sel_states : Map[Int, @ui.TextSel] = Map([])

priv struct MDLine {
  spans : Array[MDSpan]
  sum : Double
  mut w : Double
  xs : Array[Double]
  ws : Array[Double]
  mut at : @text.AttributedText
  mut at_ready : Bool
  mut geo_ready : Bool
  // 选中档（首次用到才建）：lstart = 每个渲染段在原文里的字符起点；
  // cx / cidx 一一对应，长度 = 本行字符数 + 1（末尾那格是最后一个字的右缘）
  lstart : Array[Int]
  cx : Array[Double]
  cidx : Array[Int]
  mut cx_ready : Bool
}

///|
/// 富文本行(自绘):先按可用宽度贪心折行(中文逐字、拉丁逐词、`\n` 硬换行),
/// 每行按需拼一个 AttributedText(只有真要画、或要被父级当内在宽用的行才建);
/// 删除线段按该行像素区间补画横线;带地址的链接段
/// 可点击(按行号 + 行内像素区间命中,经 ctx.on_link 交调用方),悬浮手型光标;
/// sup 段用小一号字体;链接/代码段主题色,主题指纹变化时只重建绘制对象。
/// `ctx.sel` 开选中档：本段是一份可选中的连续文本——逐字 x 表按「段界取联合
/// 几何、段内按逐字宽线性分摊」建，选中交互链与 @ui 的 selectable 文本同一条
/// （`@ui.TextSel`），复制得到的是本段原文（软折行不插换行）。
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
  /// 段内前缀实测量：`bytes` 前 `bj` 字节在字体 `f` 下的 shaping 宽
  /// （逐字边缘的真值；与 entry/textarea 光标同口径的前缀量）。
  fn md_prefix_w(bytes : Bytes, bj : Int, f : @text.Font) -> Double {
    if bj <= 0 {
      0.0
    } else {
      match @text.measure_font(@utf8.decode_lossy(bytes[:bj]), f) {
        Some(m) => m.width.to_double()
        None => 0.0
      }
    }
  }

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

  fn mk_line(line : Array[MDSpan], sum : Double, starts : Array[Int]) -> MDLine {
    {
      spans: line,
      sum,
      w: 0.0,
      xs: [],
      ws: [],
      at: @text.AttributedText::new("", valign=@text.Center, wrap=false),
      at_ready: false,
      geo_ready: false,
      lstart: starts,
      cx: [],
      cidx: [],
      cx_ready: false,
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
    let cur_starts : Array[Int] = []
    let cur_w = Ref(0.0)
    fn end_line() -> Unit {
      if cur.length() > 0 {
        rows.push(mk_line(cur.copy(), cur_w.val, cur_starts.copy()))
        cur.clear()
        cur_starts.clear()
        cur_w.val = 0.0
      }
    }

    // at = 本单元第一个字符在原文里的字符下标（选中档的逐字命中要它定位）
    fn put(unit : String, span : MDSpan, at : Int) -> Unit {
      let uw = unit_w(unit, span)
      if cur_w.val + uw > limit && cur.length() > 0 {
        end_line()
      }
      let n = cur.length()
      if n > 0 && md_same_style(cur[n - 1], span) {
        cur[n - 1].text = cur[n - 1].text + unit
      } else {
        cur.push({ ..span, text: unit })
        cur_starts.push(at)
      }
      cur_w.val += uw
    }

    let mut log_i = 0
    for span in spans {
      let span_at = log_i
      let mut seen = 0
      for unit in md_units(span.text) {
        let ulen = unit.to_array().length()
        if unit == "\n" {
          end_line()
          seen += 1
        } else if unit_w(unit, span) > limit {
          // 单个单元就比整行宽(长 URL / 长单词):按字符硬切,不然必然撑破容器
          for ch in unit {
            put(ch.to_string(), span, span_at + seen)
            seen += 1
          }
        } else {
          put(unit, span, span_at + seen)
          seen += ulen
        }
        log_i += ulen
      }
    }
    if cur.length() > 0 || rows.length() == 0 {
      rows.push(mk_line(cur.copy(), cur_w.val, cur_starts.copy()))
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

  // ---- 选中档（`ctx.sel`）：本段是一份连续文本 ----
  // 原文按 spans 拼接（软折行不插换行，复制出来就是这段的原话）；字符下标→
  // 字节偏移表一次建好，Editor / AttributedText / 样式区间都按字节计量。
  // 独立档（ctx.doc None）：本块一份 Editor / TextSel，选区按块内字节；
  // 文档档（ctx.doc Some）：共享文档级 Editor / TextSel，本块登记全文偏移，
  // 命中/高亮在块内字节与全文字节之间换算（sel_off/sel_len）。
  let sel_buf = StringBuilder()
  for sp in spans {
    sel_buf.write_string(sp.text)
  }
  let ltext = sel_buf.to_string()
  let sel_len = @utf8.encode(ltext).length()
  let char2byte : Array[Int] = []
  {
    let mut b = 0
    for ch in ltext.to_array() {
      char2byte.push(b)
      b += md_byte_len(ch.to_string())
    }
    char2byte.push(b)
  }
  let sel_off : Int = match ctx.doc {
    Some(doc) => {
      // 构造序即视觉序：顺序分配全文偏移并拼全文
      let off = doc.acc
      doc.buf.val.write_string(ltext)
      doc.buf.val.write_string("\n")
      doc.acc = off + sel_len + 1
      off
    }
    None => 0
  }
  let st : @ui.TextSel? = if ctx.sel && ltext.length() > 0 {
    match ctx.doc {
      Some(doc) => Some(doc.st)
      None => {
        let sel_ed = @input.Editor::new()
        sel_ed.set_text(ltext)
        Some(@ui.text_sel_new(sel_ed))
      }
    }
  } else {
    None
  }

  /// 本行逐字几何：段界取**联合排版**（`line_geo` 的 xs/ws——整条前缀建成
  /// 一份多字体 AttributedText 实量，跨段 kerning 在这一层算对），段内按
  /// **前缀实测量**取逐字边缘：第 j 个字的左缘 = 该字之前在**本段字体**下
  /// 的 shaping 宽（与 entry/textarea 光标同一条口径——`measure_font` 前缀
  /// 量）。旧口径是「逐字单独量再按比例分摊到段宽」， shaping 误差全落在
  /// 分摊比例上（mac 实测累加比联合窄 11px，点击落点整体偏右、选不中字）；
  /// 前缀量在段内是精确值，段界仍归联合排版，两头都真。`cx`/`cidx` 平行，
  /// 长度 = 本行字符数 + 1，末格收到行右缘（下一段起点/行尾）。
  fn line_cx(g : MDLine) -> Unit {
    if g.cx_ready {
      return
    }
    line_geo(g)
    let n = g.spans.length()
    for i in 0..<n {
      let sp = g.spans[i]
      let cs = sp.text.to_array()
      let k = cs.length()
      if k == 0 {
        continue
      }
      let f = font_of(sp)
      // 逐字节边界的前缀实测量（段内第 j 个字的左缘）
      let bytes = @utf8.encode(sp.text)
      let mut bj = 0
      for j in 0..<k {
        g.cx.push(g.xs[i] + md_prefix_w(bytes, bj, f))
        g.cidx.push(g.lstart[i] + j)
        bj += md_byte_len(cs[j].to_string())
      }
      // 段末格：联合排版给的段界（与下一段起点严格连续；夹住下限防段宽为 0
      // 时末格回退）
      let end = g.xs[i] + g.ws[i].max(md_prefix_w(bytes, bj, f))
      g.cx.push(end)
      g.cidx.push(g.lstart[i] + k)
    }
    g.cx_ready = true
  }

  fn char_at(x : Double, y : Double) -> Int {
    let total = char2byte.length() - 1
    let rows = rows_ref.val
    let li = (y / line_h).floor().to_int()
    match rows.get(li) {
      Some(g) => {
        line_cx(g)
        let n = g.cx.length()
        if n == 0 {
          total
        } else if x <= g.cx[0] {
          g.cidx[0]
        } else if x >= g.cx[n - 1] {
          g.cidx[n - 1]
        } else {
          // 找到 x 所在的那一格，再按中线定边界：过半算这字之后、未过半算这字之前
          // （与 TextLayout::hit 同口径——给的是插入点，不是字符序号，
          // 不然永远选不到一行的最后一个字）
          let mut i = 0
          while i + 1 < n && g.cx[i + 1] <= x {
            i += 1
          }
          let mid = g.cx[i] + (g.cx[i + 1] - g.cx[i]) / 2.0
          if x > mid { g.cidx[i] + 1 } else { g.cidx[i] }
        }
      }
      None => total
    }
  }

  fn byte_at(x : Double, y : Double) -> Int {
    let c = char_at(x, y).max(0)
    match char2byte.get(c) {
      Some(b) => b
      None => char2byte[char2byte.length() - 1]
    }
  }

  // 文档档的块登记（id 在挂载期才知道，先建条目、挂载时补登记与矩形回填）
  let entry : MDBlockEntry? = if st is Some(_) {
    match ctx.doc {
      Some(_) => {
        md_block_uid.val += 1
        Some(
          {
            uid: md_block_uid.val,
            x: 0.0,
            y: 0.0,
            h: 0.0,
            off: sel_off,
            len: sel_len,
            hit: byte_at,
          },
        )
      }
      None => None
    }
  } else {
    None
  }
  // 本块的命中换算：独立档按块内字节，文档档换算成全文字节
  fn sel_hit(x : Double, y : Double) -> Int {
    match entry {
      Some(e) => match ctx.doc {
        Some(doc) => doc.byte_at(e, x, y)
        None => byte_at(x, y)
      }
      None => byte_at(x, y)
    }
  }

  /// 字节偏移换字符下标（画选区要把选区切到各行）。
  fn char_of_byte(b : Int) -> Int {
    let mut lo = 0
    let mut hi = char2byte.length() - 1
    while lo < hi {
      let mid = (lo + hi + 1) / 2
      if char2byte[mid] <= b {
        lo = mid
      } else {
        hi = mid - 1
      }
    }
    lo
  }

  /// 选区在本行的像素区间：没有交集给 None。
  fn line_sel_rect(g : MDLine, a : Int, b : Int) -> (Double, Double, Double)? {
    line_cx(g)
    if g.cidx.length() < 2 {
      return None
    }
    let lo = g.cidx[0]
    let hi = g.cidx[g.cidx.length() - 1]
    let ca = char_of_byte(a).max(lo)
    let cb = char_of_byte(b).min(hi)
    if cb <= ca {
      None
    } else {
      match
        (
          g.cx.get(ca - lo), g.cx.get(cb - lo),
        ) {
          (Some(x0), Some(x1)) => Some((x0, x1, x1 - x0))
          _ => None
        }
    }
  }

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
      r : @base.Rect,
    ) -> Unit {
      // 文档档：回填本块矩形（跨块命中按绝对坐标找落点块，纯数据登记表）
      match entry {
        Some(e) => {
          e.x = r.x
          e.y = r.y
          e.h = r.h
        }
        None => ()
      }
      let cur_fp = @theme.theme_fingerprint_of(@theme.theme_current())
      if cur_fp != fps.val {
        fps.val = cur_fp
        for g in rows_ref.val {
          g.at_ready = false
        }
      }
      // 本块可见的选区切片：独立档即全文（off=0）；文档档把全文选区裁到
      // [sel_off, sel_off+sel_len) 再换回块内字节
      let sel_slice : (Int, Int)? = match st {
        Some(state) =>
          match state.range() {
            Some((a, b)) => {
              let a2 = (a - sel_off).max(0).min(sel_len)
              let b2 = (b - sel_off).max(0).min(sel_len)
              if b2 > a2 {
                Some((a2, b2))
              } else {
                None
              }
            }
            None => None
          }
        None => None
      }
      p.set_stroke_color(@theme.theme_text_regular())
      let mut y = 0.0
      for g in rows_ref.val {
        // 选中档：先铺本行选区底色，再画字（高亮在字下，与 selectable 文本同层序）
        match sel_slice {
          Some((a2, b2)) =>
            match line_sel_rect(g, a2, b2) {
              Some((x0, _x1, w0)) => {
                p.set_fill_color(@theme.theme_primary_light())
                p.fill_rect(x0, y, w0.max(1.0), line_h)
              }
              None => ()
            }
          None => ()
        }
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
    // 选中档的指针链：与 @ui 的 selectable 文本同一条（单击/双击选词/拖选/
    // Shift 扩选/右键复制），几何由本段的逐字表给——文档档下超出本块的落点
    // 换算成全文字节，拖选跨块连续
    fn sel_via(self : @widget.Widget, ev : @widget.PointerEvent) -> Bool {
      match st {
        Some(state) =>
          state.pointer(self, ev, fn(x : Double, y : Double) -> Int {
            sel_hit(x, y)
          })
        None => false
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
              sel_via(_self, ev)
            }
          }
          @widget.PointerKind::Move => {
            let h = hit_url(ev.x, ev.y) != ""
            if h != hover.val {
              hover.val = h
              w.cursor = if h {
                @widget.CURSOR_HAND
              } else {
                @widget.CURSOR_TEXT
              }
            }
            if !h {
              let _ = sel_via(_self, ev)
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
          // Up 必须转发进选中链：sel_pointer 靠 Up 清 dragging——不转发的话
          // 拖选过一次后 dragging 永远为真，之后鼠标移动会一直从旧锚点改选区
          @widget.PointerKind::Up => sel_via(_self, ev)
        }
      })
    } else if st is Some(_) {
      w.cursor = @widget.CURSOR_TEXT
      w.on_pointer = Some(fn(
        self : @widget.Widget,
        ev : @widget.PointerEvent,
      ) -> Bool { sel_via(self, ev) })
    }
    match st {
      Some(state) => {
        let _ = md_sel_states.set(w.id, state)
        w.cursor = @widget.CURSOR_TEXT
        // 文档档：按 id 挂进块登记（矩形由 on_draw 回填）；摘除时同步移除，
        // 不在登记表里留死块
        match entry {
          Some(e) => match ctx.doc {
            Some(d) => {
              d.list.val.push(e)
              let dead_uid = e.uid
              let give = state
              w.on_discard = Some(fn(self : @widget.Widget) -> Unit {
                let _ = md_sel_states.remove(self.id)
                let keep : Array[MDBlockEntry] = []
                for b in d.list.val {
                  if b.uid != dead_uid {
                    keep.push(b)
                  }
                }
                d.list.val = keep
                give.give_up(self.id)
                @widget.text_sel_release(d.claim_id)
              })
            }
            None => {
              let give = state
              w.on_discard = Some(fn(self : @widget.Widget) -> Unit {
                let _ = md_sel_states.remove(self.id)
                give.give_up(self.id)
              })
            }
          }
          None => {
            let give = state
            w.on_discard = Some(fn(self : @widget.Widget) -> Unit {
              let _ = md_sel_states.remove(self.id)
              give.give_up(self.id)
            })
          }
        }
      }
      None => ()
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
  selectable? : Bool = false,
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
  // 文档级跨段选中（selectable 时启用）：一份 Editor 装全文档，可选块按
  // 构造序（= 视觉序）拼接、块间补 \n；块条目在各自挂载时登记、矩形绘制期
  // 回填（见 MDBlockEntry / MDDocSel::byte_at）。代码围栏/表格不进全文，
  // 是文档流里的独立选中岛。
  let doc_sel : MDDocSel? = if selectable {
    let ed = @input.Editor::new()
    let st = @ui.text_sel_new(ed)
    // 全块同号认领：块间换手不会把「前任」clear 掉（共享同一份 Editor，
    // 清前任等于清自己刚画的选区）
    md_doc_uid.val += 1
    st.claim.val = md_doc_uid.val
    Some({
      ed,
      st,
      buf: Ref(StringBuilder()),
      acc: 0,
      list: Ref([]),
      claim_id: md_doc_uid.val,
    })
  } else {
    None
  }
  let ctx : MDCtx = { foot, defs, width, on_link, sel: selectable, doc: doc_sel }
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
                md_content_col(md_item_content(children, ctx)),
              ]),
            )
          }
          None => ()
        }
      }
    }
  }
  // 全文档块拼装完毕（正文 + 文末脚注），一次性装进共享 Editor
  match doc_sel {
    Some(d) => d.ed.set_text(d.buf.val.to_string())
    None => ()
  }
  // 块间留 6：段与段、标题与正文之间不贴脸（行内行距见 md_rich_label）。
  // 跟随容器档（width=0）必须 percent(100)（块级铺满）：shrink-to-fit 的列
  // 会被父级按「未约束内在高」钉死高度，折行子项落地更高时容器矩形盖不住
  // 子项，命中链在容器底缘断掉（真机：折行段以下的块整块点不中，跨段选中
  // 用例钉住）；percent 让交叉轴确定，测量/落地两趟同走定宽档，两趟同答。
  let col_w = if width > 0.0 { width } else { 0.0 }
  @ui.col(
    nodes,
    width=col_w,
    row_gap=6.0,
    class=(if width > 0.0 { [] } else { [@style.style(width_percent=100.0)] }),
    handle~,
  )
}
