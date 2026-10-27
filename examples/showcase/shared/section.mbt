// 共享层：页面「段」装配。`page` 用 segmented 列出各段短名（如
// 主题|按钮|文字|…）；每段正文自带滚动区（切段各自保留滚动位置，
// 页级不再整体滚动），选中段填满剩余高度。切段只切容器可见性，
// 不重建视图树。代码区顶行常驻「复制」，点击写入剪贴板并经全局
// toast 回显（钩子由 main 注入）。
//
// 本栈口径：
// ① 组件返回 `@widget.Node`，间距/内边距走容器参数（`padding`/`row_gap`）；
// ② 显隐走 `Widget::set_visible`，挂载走 `Node::mount_into(Widget)`；
// ③ 「段滚动区撑满剩余高度」在 `handle` 里对滚动视口直接置 `flex_grow`
//    （滚动容器本身不接 grow 参数）。

///|
/// 全局 toast 推送钩子：main 创建 `toast_layer` 后注入，代码区「复制」回显用。
pub let code_toast : Ref[((String, @ui.SemanticType) -> Unit)?] = Ref(None)

///|
/// 一段演示：`name` 进页面顶部 segmented 标签列表（短名，页内唯一）；
/// title/desc/content/code 为该段正文四件套。
pub struct Section {
  name : String
  title : String
  desc : String
  content : Array[@widget.Node]
  code : Array[String]
}

///|
/// 声明一段演示：`name` 是段列表短名（页内唯一），`title`/`desc`/`content`/`code`
/// 为该段正文四件套；实际节点由 `page` 统一装配。
pub fn section(
  name : String,
  title : String,
  desc : String,
  content : Array[@widget.Node],
  code? : Array[String] = [],
) -> Section {
  // 段标题/描述是纯显示串：在出口统一取译（英文目录命中则英文，否则原中文）。
  // 段名 name 作 segmented 的选中值不译，显示由 `page` 的 label_of 走 `seg.` 键。
  {
    name,
    title: @i18n.t_or(title, title),
    desc: @i18n.t_or("desc§" + title, desc),
    content,
    code,
  }
}

///|
/// 一页 = 顶部 segmented 段列表（超宽自动换行）+ 段正文栈；选中段填满剩余
/// 高度并自带滚动，其余段隐藏（不重建，滚动位置各自保留）。
pub fn page(secs : Array[Section]) -> @widget.Node {
  let selected : @base.Store[String] = @base.Store::new(secs[0].name)
  let names : Array[String] = []
  for s in secs {
    names.push(s.name)
  }
  // 段条超宽真换行（flex_wrap 走样式槽；行距给 4，不然两行贴在一起）。
  // 段条是页列的**直接子项**，四周 16 走 `margin`，不再包一层 padding 列：
  // 包裹列自身没有宽度（纯靠 stretch 定宽）时，它的 min-content 高仍按
  // 「无定宽全堆叠」算，段条会把整块正文高度顶起来（实测 236 vs 真值 66）。
  let flat = @style.style(min_height=0.0, min_width=0.0)
  // 段名是 key（选中值不译），显示走 `seg.` 前缀取译——前缀是为了和正文里
  // 「原文当 key」的条目划开：短名如「文字」撞正文的概率太高。
  let strip = @ui.segmented(
    names,
    selected,
    label_of=fn(n : String) -> String { @i18n.t_or("seg." + n, n) },
    class=[
      @style.style(flex_wrap=@yoga.Wrap, row_gap=4.0, min_width=0.0, margin=16.0),
    ],
    // 段条是不可压缩的定高头部：正文够高时（Markdown 段整篇文档）压缩量
    // 会全落到「min=0 且没设 flex_shrink=0」的层上，实测 44px → 23.3px，
    // 标签戳出条外。收缩的活儿交给下面的正文列（min=0 + grow）。
    handle=fn(w : @widget.Widget) -> Unit { w.node.set_flex_shrink(0.0) },
  )
  let bodies : Array[@widget.Node] = []
  for s in secs {
    bodies.push(section_body(s, selected))
  }
  // 页列自带 percent(100) 宽：折行容器的内在下限以「自身 style 定住的宽」为
  // 参照，纯 stretch 的列不做这个参照（实测同一条段条两种写法差 170px）。
  @ui.col(
    [strip, @ui.col(bodies, grow=1.0, class=[flat])],
    grow=1.0,
    class=[@style.style(width_percent=100.0)],
  )
}

///|
/// 选中段的正文：标题 + 演示 + 说明 + 代码（带复制行），内容超高段内滚动；
/// 容器随页面 `selected` 切换显隐。演示内容**惰性挂载**：未选中过的段只有
/// 标题/说明/代码骨架，首次选中才把 content 挂进占位容器；挂过之后保形，
/// 显隐/滚动位置语义不变。页级的构造推迟由 `@router` 管（见 `main.mbt` 的路由表）。
fn section_body(s : Section, selected : @base.Store[String]) -> @widget.Node {
  let mounted : Ref[Bool] = Ref(false)
  let holder = @ui.col([], row_gap=8.0, handle=fn(h) {
    fn ensure(name : String) -> Unit {
      if !mounted.val && name == s.name {
        mounted.val = true
        for c in s.content {
          let _ = c.mount_into(h)
        }
      }
    }

    ensure(selected.get())
    selected.subscribe(ensure)
  })
  let inner : Array[@widget.Node] = [
    @ui.text(s.title, class=[@style.text_title]),
  ]
  if s.desc.length() > 0 {
    // 说明折行跟随容器宽（`text` 缺省即折行，flex 0 1 auto 按可用宽排）：
    // 不设上限，段标题/描述/正文/代码同一条右缘，窗口多宽排多宽
    inner.push(@ui.text(s.desc, class=[@style.text_secondary], wrap=true))
  }
  inner.push(holder)
  if s.code.length() > 0 {
    inner.push(code_copy_row(s.code))
    inner.push(@ui.code_view(s.code, lang="moonbit", line_numbers=true))
  }
  // 本容器是显隐切换对象；滚动视口在 handle 里撑满剩余高度
  @ui.col(
    [
      @ui.scroll_view(
        [@ui.col(inner, row_gap=6.0, padding=16.0)],
        @ui.ScrollState::new(),
        handle=fn(v) { v.node.set_flex_grow(1.0) },
      ),
    ],
    grow=1.0,
    handle=fn(c) {
      fn apply(name : String) -> Unit {
        c.set_visible(name == s.name)
      }

      apply(selected.get())
      selected.subscribe(apply)
    },
  )
}

///|
/// 代码区顶行：左「代码」小标，右「复制」按钮（toast 回显）。
fn code_copy_row(lines : Array[String]) -> @widget.Node {
  @ui.row(
    [
      @ui.text(tx("代码"), class=[@style.text_secondary]),
      @ui.text("", class=[@style.text_secondary], handle=fn(w) {
        w.node.set_flex_grow(1.0)
      }),
      @ui.button(tx("复制"), variant=@ui.Text, on_click=fn() {
        // 提示必须跟真实结果：`clipboard_set_text` 的 Bool 就是「有没有写进去」，
        // 原先 `let _ =` 把它丢了，失败也照样弹「已复制」
        let ok = @sys.clipboard_set_text(lines.join("\n"))
        match code_toast.val {
          Some(push) =>
            if ok {
              push(tx("代码已复制 ✓"), @ui.Success)
            } else {
              push(tx("复制失败：剪贴板不可用"), @ui.Danger)
            }
          None => ()
        }
      }),
    ],
    column_gap=8.0,
  )
}
