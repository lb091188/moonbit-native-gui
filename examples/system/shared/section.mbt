// 共享层：页面「段」装配。`menu_page` 用左侧分组菜单列出各段短名（如
// 文件|消息框|通知|…）；每段正文自带滚动区（切段各自保留滚动位置，
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
  code~ : Array[String] = [],
) -> Section {
  // 段标题/描述是纯显示串：在出口统一取译（目录命中则译文，否则原中文）。
  // 段名 name 作菜单选中值不译，显示即短名本身（本示例不做语言切换）。
  {
    name,
    title: @i18n.t_or(title, title),
    desc: @i18n.t_or("desc§" + title, desc),
    content,
    code,
  }
}

///|
/// 一页 = 左侧分组菜单（`@ui.menu_sections`，组可折叠、项可键盘换选）+ 右侧
/// 段正文栈；选中段填满剩余高度并自带滚动，其余段隐藏（不重建，滚动位置各自
/// 保留）。菜单项与选中值都是段短名 `name`，与右侧显隐用同一份 Store。
/// 分组是 (组名, 组内段列)；组名显示走 `nav.g.` 前缀取译（缺失回落原文，由
/// 菜单组件内部处理）。
pub fn menu_page(cats : Array[(String, Array[Section])]) -> @widget.Node {
  let selected : @base.Store[String] = @base.Store::new(cats[0].1[0].name)
  let secs : Array[(String, Array[String])] = []
  for cat in cats {
    let names : Array[String] = []
    for s in cat.1 {
      names.push(s.name)
    }
    secs.push((cat.0, names))
  }
  let bodies : Array[@widget.Node] = []
  for cat in cats {
    for s in cat.1 {
      bodies.push(section_body(s, selected))
    }
  }
  @ui.row(
    [
      // 左栏定宽不可压缩：正文列再宽也挤不到菜单（收缩量全落 min=0 的右栏）
      @ui.scroll_view(
        [@ui.menu_sections(secs, selected, width=200.0)],
        @ui.ScrollState::new(),
        width=200.0,
        handle=fn(v) {
          v.node.set_flex_grow(1.0)
          v.node.set_flex_shrink(0.0)
        },
      ),
      @ui.col(bodies, grow=1.0, class=[
        @style.style(min_height=0.0, min_width=0.0),
      ]),
    ],
    grow=1.0,
    // 拉伸对齐：左栏视口高度才确定，菜单超高时栏内才真滚得动
    align_items=@yoga.AlignItems::Stretch,
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
    // 复制按钮内建在 code_view 头部（悬浮右上显形），toast 回显经 on_copied 接
    inner.push(
      @ui.code_view(s.code, lang="moonbit", line_numbers=true, copyable=true, on_copied=fn(
        ok : Bool,
      ) -> Unit {
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
    )
  }
  // 本容器是显隐切换对象；滚动视口在 handle 里撑满剩余高度。
  // 段名进读屏：VO 进段念「<标题>, group」而不是无名 group
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
      c.name = s.title
    },
  )
}
