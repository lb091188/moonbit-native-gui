// 基础组件页：Store/Signal 驱动的主题组件演示。共享状态（counter 计数、
// picked_lang 最近操作）在 App；页内状态用页内 Store，展示端用
// `@ui.bind` 直连，无手动 subscribe 接线。勾选类在表单组件页，右键菜单
// 在导航组件页。
//
// 四处口径：
// ① 间距是布局容器的属性（段正文容器带 `row_gap`），控件不自己挂外边距；
// ② 文本框只有 Store 驱动的 `input`（Store 是文本状态的唯一权威），
//    「组内输入框」各配一个页内 Store；
// ③ `hover_group` / `cursor_group` 内建悬停父链语义与光标最深请求，
//    调用点不传 `on_change` / `radius`；
// ④ 声明式层与组件同住 `@ui`（`ui/declarative.mbt`）。

///|
pub fn page_basic(app : @shared.App) -> @widget.Node {
  // 两个悬停/光标组各配一个文本框状态
  let box_a : @base.Store[String] = @base.Store::new("组内输入框")
  let box_b : @base.Store[String] = @base.Store::new("组内输入框")
  // RTL：文本 run 基方向开关 + 布局镜像对比 + 从右起排的右侧文字样例
  let rtl = @base.Store::new(false)
  let rtl_toggle = @ui.button(
    "切换文本基方向 (LTR/RTL)",
    on_click=fn() {
      let v = !rtl.get()
      rtl.set(v)
      @text.set_base_dir(if v { @text.Rtl } else { @text.Ltr })
      @widget.invalidate()
      app.toast_push("文本基方向 → " + (if v { "RTL" } else { "LTR" }), @ui.Info)
    },
  )
  let rtl_mixed = @ui.text("Hello مرحبا World 123 — 混排 bidi", font_size=16.0)
  let mirror_items = ["一", "二", "三"].map(x => @ui.card([@ui.text(x)], padding=10.0))
  let ltr_row = @ui.col(
    [@ui.text("LTR 主轴", role=@ui.Secondary), @ui.row(mirror_items, column_gap=8.0)],
    row_gap=4.0,
  )
  let rtl_row = @ui.col(
    [
      @ui.text("RTL 布局镜像（Style.direction）", role=@ui.Secondary),
      @ui.row(
        mirror_items,
        column_gap=8.0,
        class=[@style.style().set_direction(Some(@style.Rtl))],
      ),
    ],
    row_gap=4.0,
  )
  @shared.page([
    @shared.section(
      "RTL 排版",
      "文本基方向与布局镜像",
      "两段机制各管一头：`@text.set_base_dir` 改文本 run 的基方向（bidi 混排里谁先谁后），`Style.direction=Rtl` 把布局主轴镜像（行列反向排）。开关只动前者，布局不受牵连。",
      [
        rtl_toggle,
        rtl_mixed,
        @ui.row([ltr_row, rtl_row], column_gap=24.0),
      ],
      code=[
        "@text.set_base_dir(@text.Rtl)",
        "@ui.row(items, class=[@style.style().set_direction(Some(@style.Rtl))])",
      ],
    ),
    @shared.section(
      "字体排版",
      "从右起排的右侧文字",
      "阿拉伯语、波斯语、希伯来语、乌尔都语这类文字整段从右往左落笔：容器方向给 `Rtl`、文本对齐给 `End`，行首就贴在右缘。数字段在 bidi 里仍按 LTR 走（"
      + "阿拉伯语里的拉丁数不反写），这是文本引擎的默认口径。字体按平台回退，"
      + "mac/Linux 缺相应字形时显示为方框属系统字体集问题，不是排版错位。",
      [
        @ui.col(
          [
            @ui.text("العربية — 阿拉伯语：مرحبا بالعالم", font_size=16.0),
            @ui.text("فارسی — 波斯语：سلام دنیا", font_size=16.0),
            @ui.text("עברית — 希伯来语：שלום עולם", font_size=16.0),
            @ui.text("اردو — 乌尔都语：دنیا کو سلام", font_size=16.0),
            @ui.text("RTL 段落里的 1234 / ABC 保持原序不反写", font_size=14.0),
          ],
          row_gap=8.0,
          class=[
            @style.style(
              direction=@yoga.RowReverse,
              align_items=@yoga.AlignItems::FlexEnd,
              text_align=@text.End,
            ),
          ],
          width=480.0,
        ),
        @ui.text("上面这块：容器镜像 + 贴右对齐（点击任意一行可复制到 LTR 段对照）", role=@ui.Secondary),
      ],
      code=[
        "@ui.col(lines,",
        "  class=[@style.style(",
        "    direction=@yoga.RowReverse,",
        "    align_items=@yoga.AlignItems::FlexEnd,",
        "    text_align=@text.End,",
        "  )])",
      ],
    ),
    @shared.section(
      "主题",
      "主题色板",
      "选一个主色，整套色板（hover/浅底/语义色）按 HSL 公式即时派生，切换深浅沿用当前主色；「跟随系统」读系统主色调，读不到回落内置。手动选色会先关掉跟随开关（否则下一次轮询就把它盖回去）。",
      [
        @ui.row(
          [
            @ui.button("跟随系统", variant=@ui.Solid, on_click=fn() {
              app.follow.set(true)
            }),
            @ui.button("默认蓝", on_click=fn() {
              app.follow.set(false)
              app.accent.set("")
            }),
            @ui.button("青", on_click=fn() {
              app.follow.set(false)
              app.accent.set("#009688")
            }),
            @ui.button("绿", on_click=fn() {
              app.follow.set(false)
              app.accent.set("#2E9E5B")
            }),
            @ui.button("紫", on_click=fn() {
              app.follow.set(false)
              app.accent.set("#9141AC")
            }),
            @ui.button("红", on_click=fn() {
              app.follow.set(false)
              app.accent.set("#D64550")
            }),
          ],
          column_gap=8.0,
        ),
        @ui.bind(app.accent.signal(), fn(s) {
          if s == "" {
            "当前主色：内置默认"
          } else {
            "当前主色：\{s}"
          }
        }),
      ],
      code=[
        "let dark = @win.sys_color_scheme() == \"dark\"",
        "let accent = @win.sys_accent()",
        "if accent != \"\" {",
        "  @theme.theme_apply(@theme.theme_from_accent(accent, dark=dark))",
        "} else {",
        "  @theme.theme_apply(if dark { @theme.dark_theme() } else { @theme.default_theme() })",
        "}",
      ],
    ),
    @shared.section(
      "按钮",
      "Button 按钮",
      "四变体；「主要操作」联动数据页访问量/进度条（信号）。",
      [
        @ui.row(
          [
            @ui.button("主要操作", variant=@ui.Solid, on_click=fn() {
              app.counter.update(fn(n) { n + 1 })
            }),
            @ui.button("次要操作", variant=@ui.Soft),
            @ui.button("文字按钮", variant=@ui.Text),
            @ui.button("危险操作", variant=@ui.Danger),
          ],
          column_gap=8.0,
        ),
      ],
      code=[
        "@ui.row([",
        "  @ui.button(\"主要操作\", variant=@ui.Solid, on_click=fn() { }),",
        "  @ui.button(\"次要操作\", variant=@ui.Soft),",
        "  @ui.button(\"文字按钮\", variant=@ui.Text),",
        "  @ui.button(\"危险操作\", variant=@ui.Danger),",
        "], column_gap=8.0)",
      ],
    ),
    @shared.section(
      "文字链接",
      "Label 与 Link",
      "五级排版角色，字号颜色随角色；Link 主题色文字悬停下划线，最近点击信号回显。",
      [
        @ui.text("标题文字（Title）", role=@ui.Title),
        @ui.text("小节标题（Section）", role=@ui.Section),
        @ui.text("正文文字（Body）", role=@ui.Body),
        @ui.text("辅助文字（Secondary）", role=@ui.Secondary),
        @ui.text("强调文字（Accent）", role=@ui.Accent),
        @ui.row(
          [
            @ui.link("打开文档", fn() { app.picked_lang.set("docs") }),
            @ui.link("帮助中心", fn() { app.picked_lang.set("help") }),
            @ui.text("最近点击：", role=@ui.Body),
            @ui.bind(app.picked_lang, fn(s) { s }),
          ],
          column_gap=10.0,
        ),
      ],
      code=[
        "@ui.text(\"标题文字\", role=@ui.Title)",
        "@ui.text(\"小节标题\", role=@ui.Section)",
        "@ui.text(\"正文文字\", role=@ui.Body)",
        "@ui.text(\"辅助文字\", role=@ui.Secondary)",
        "@ui.text(\"强调文字\", role=@ui.Accent)",
        "@ui.link(\"打开文档\", fn() { app.picked_lang.set(\"docs\") })",
      ],
    ),
    @shared.section(
      "分隔提示",
      "Divider 与 Tooltip",
      "水平（默认）/竖直 1px 主题边框色；tooltip 给任意节点包原生悬浮提示（系统样式，主题化气泡见反馈页 Popover）。",
      [
        @ui.text("上方内容", role=Body),
        @ui.divider(),
        @ui.text("下方内容", role=Body),
        @ui.row(
          [
            @ui.tooltip(@ui.button("悬停看提示"), "原生 tooltip：系统样式"),
            @ui.tooltip(@ui.button("再来一个", variant=@ui.Soft), "第二个提示"),
          ],
          column_gap=10.0,
        ),
      ],
      code=[
        "@ui.divider()",
        "@ui.divider(vertical=true)",
        "@ui.tooltip(@ui.button(\"悬停看提示\"), \"原生 tooltip：系统样式\")",
      ],
    ),
    @shared.section(
      "悬停光标",
      "HoverGroup 悬停组与 CursorGroup 光标组",
      "上：组内任意位置（含子控件）悬停即整组进入 hover 态——把指针移到卡片里的按钮或输入框上，整张卡片同样高亮。悬停态是父链语义，既不排定时器也不查指针。下：父设子随——指针落在组内任意位置（含输入框、按钮等子控件）都保持手型，移出恢复默认。光标是窗口级的一层，宿主按悬停路径取「最深的那个请求」，所以组只设自己一处即可。",
      [
        @ui.hover_group(
          [
            @ui.text("组标题：悬停我，或下面的子控件", role=@ui.Section),
            @ui.row(
              [@ui.input(box_a, width=200.0), @ui.button("组内按钮")],
              column_gap=10.0,
            ),
            @ui.text("子控件触发的事件同样改变组的样式", role=@ui.Secondary),
          ],
          padding=14.0,
          row_gap=8.0,
        ),
        @ui.cursor_group(
          [
            @ui.text("整组都是手型：移入试试，或移到子控件上", role=@ui.Section),
            @ui.row(
              [@ui.input(box_b, width=200.0), @ui.button("组内按钮")],
              column_gap=10.0,
            ),
          ],
          padding=14.0,
          row_gap=8.0,
        ),
      ],
      code=[
        "@ui.hover_group(",
        "  [",
        "    @ui.text(\"组标题\", role=@ui.Section),",
        "    @ui.row([@ui.input(box, width=200.0), @ui.button(\"组内按钮\")], column_gap=10.0),",
        "  ],",
        "  padding=14.0,",
        "  row_gap=8.0,",
        ")",
        "@ui.cursor_group(",
        "  [",
        "    @ui.text(\"整组都是手型\", role=@ui.Section),",
        "    @ui.input(box, width=200.0),",
        "    @ui.button(\"组内按钮\"),",
        "  ],",
        "  padding=14.0,",
        ")",
      ],
    ),
  ])
}
