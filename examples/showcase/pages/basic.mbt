// 基础组件页：Store/Signal 驱动的主题组件演示。共享状态（counter 计数、
// picked_lang 最近操作）在 App；页内状态用页内 Store，展示端用
// `@ui.bind` 直连，无手动 subscribe 接线。勾选类在表单组件页，右键菜单
// 在导航组件页。
//

///|
pub fn page_basic(app : @shared.App) -> @widget.Node {
  // 两个悬停/光标组各配一个文本框状态
  let box_a : @base.Store[String] = @base.Store::new(@shared.tx("组内输入框"))
  let box_b : @base.Store[String] = @base.Store::new(@shared.tx("组内输入框"))
  @shared.page([
    @shared.section(
      "主题",
      "主题色板",
      "选一个主色，整套色板（hover/浅底/语义色）按 HSL 公式即时派生，切换深浅沿用当前主色；「跟随系统」读系统主色调，读不到回落内置。手动选色会先关掉跟随开关（否则下一次轮询就把它盖回去）。",
      [
        @ui.row(
          [
            @ui.button(@shared.tx("跟随系统"), variant=@ui.Solid, on_click=fn() {
              app.follow.set(true)
            }),
            @ui.button(@shared.tx("默认蓝"), on_click=fn() {
              app.follow.set(false)
              app.accent.set("")
            }),
            @ui.button(@shared.tx("青"), on_click=fn() {
              app.follow.set(false)
              app.accent.set("#009688")
            }),
            @ui.button(@shared.tx("绿"), on_click=fn() {
              app.follow.set(false)
              app.accent.set("#2E9E5B")
            }),
            @ui.button(@shared.tx("紫"), on_click=fn() {
              app.follow.set(false)
              app.accent.set("#9141AC")
            }),
            @ui.button(@shared.tx("红"), on_click=fn() {
              app.follow.set(false)
              app.accent.set("#D64550")
            }),
          ],
          column_gap=8.0,
        ),
        @ui.bind(app.accent.signal(), fn(s) {
          if s == "" {
            @shared.tx("当前主色：内置默认")
          } else {
            @shared.tr_with("dyn.accent_now", [("c", s)], "当前主色：\{s}")
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
      "字体排版",
      "各语言的行首方向",
      "每一行都占满整行宽度，所以中文、英文从左缘起笔，阿拉伯语、波斯语、希伯来语、乌尔都语这类从右往左落笔的文字右端贴右缘——对齐只给文本自身的 `align=End`，方向另给 `direction=Rtl`。行内数字与拉丁段在 bidi 里仍按 LTR 走，不反写。字体按平台回退，缺相应字形时显示方框属系统字体集问题，不是排版错位。",
      [
        @ui.col(
          [
            @ui.text(@shared.tx("简体中文 — 你好，世界"), font_size=16.0),
            @ui.text("English — Hello, world", font_size=16.0),
            @ui.text(
              @shared.tx("العربية — 阿拉伯语：مرحبا بالعالم"),
              font_size=16.0,
              align=@text.End,
              class=[@style.style().set_direction(Some(@style.Rtl))],
            ),
            @ui.text(
              @shared.tx("فارسی — 波斯语：سلام دنیا"),
              font_size=16.0,
              align=@text.End,
              class=[@style.style().set_direction(Some(@style.Rtl))],
            ),
            @ui.text(
              @shared.tx("עברית — 希伯来语：שלום עולם"),
              font_size=16.0,
              align=@text.End,
              class=[@style.style().set_direction(Some(@style.Rtl))],
            ),
            @ui.text(
              @shared.tx("اردو — 乌尔都语：دنیا کو سلام"),
              font_size=16.0,
              align=@text.End,
              class=[@style.style().set_direction(Some(@style.Rtl))],
            ),
            @ui.text(
              @shared.tx("RTL 行里的 1234 / ABC 保持原序不反写"),
              font_size=14.0,
              align=@text.End,
              class=[@style.style().set_direction(Some(@style.Rtl))],
            ),
          ],
          row_gap=8.0,
        ),
      ],
      code=[
        "@ui.col([",
        "  @ui.text(\"English — Hello, world\", font_size=16.0),",
        "  @ui.text(\"العربية — مرحبا بالعالم\",",
        "    font_size=16.0, align=@text.End,",
        "    class=[@style.style().set_direction(Some(@style.Rtl))]),",
        "], row_gap=8.0)",
      ],
    ),
    @shared.section(
      "按钮",
      "Button 按钮",
      "四变体；「主要操作」联动数据页访问量/进度条（信号）。",
      [
        @ui.row(
          [
            @ui.button(@shared.tx("主要操作"), variant=@ui.Solid),
            @ui.button(@shared.tx("次要操作"), variant=@ui.Soft),
            @ui.button(@shared.tx("文字按钮"), variant=@ui.Text),
            @ui.button(@shared.tx("危险操作"), variant=@ui.Danger),
          ],
          column_gap=8.0,
        ),
        @ui.row(
          [
            @ui.button(@shared.tx("主要操作"), disabled=true, variant=@ui.Solid),
            @ui.button(@shared.tx("次要操作"), disabled=true, variant=@ui.Soft),
            @ui.button(@shared.tx("文字按钮"), disabled=true, variant=@ui.Text),
            @ui.button(@shared.tx("危险操作"), disabled=true, variant=@ui.Danger),
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
        @ui.text(@shared.tx("标题文字（Title）"), role=@ui.Title),
        @ui.text(@shared.tx("小节标题（Section）"), role=@ui.Section),
        @ui.text(@shared.tx("正文文字（Body）"), role=@ui.Body),
        @ui.text(@shared.tx("辅助文字（Secondary）"), role=@ui.Secondary),
        @ui.text(@shared.tx("强调文字（Accent）"), role=@ui.Accent),
        @ui.row(
          [
            @ui.link(@shared.tx("打开文档"), fn() { app.picked_lang.set("docs") }),
            @ui.link(@shared.tx("帮助中心"), fn() { app.picked_lang.set("help") }),
            @ui.text(@shared.tx("最近点击："), role=@ui.Body),
            @ui.bind(app.picked_lang, fn(s) { s }),
          ],
          column_gap=8.0,
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
      "水平（默认）/竖直 1px 主题边框色；tooltip 给任意节点包原生悬浮提示（系统样式，主题化气泡见反馈页 Popover）。容器描边的线形走样式槽 `border_style`：solid/dashed/dotted 三档，虚线周期由 `border_width` 派生（与 CSS 同口径），卡片、面板、滚动视口这类读描边槽的容器都吃这条。",
      [
        @ui.text(@shared.tx("上方内容"), role=Body),
        @ui.divider(),
        @ui.text(@shared.tx("下方内容"), role=Body),
        @ui.row(
          [
            @ui.tooltip(@ui.button(@shared.tx("悬停看提示")), @shared.tx("原生 tooltip：系统样式")),
            @ui.tooltip(@ui.button(@shared.tx("再来一个"), variant=@ui.Soft), @shared.tx("第二个提示")),
          ],
          column_gap=8.0,
        ),
        @ui.row(
          [
            @ui.card(
              [@ui.text(@shared.tx("dashed：实 3 空 2"), role=@ui.Secondary)],
              padding=12.0,
              class=[@style.style(border_style=@style.Dashed)],
            ),
            @ui.card(
              [@ui.text(@shared.tx("dotted：圆头点"), role=@ui.Secondary)],
              padding=12.0,
              class=[@style.style(border_style=@style.Dotted, border_width=2.0)],
            ),
          ],
          column_gap=8.0,
        ),
      ],
      code=[
        "@ui.divider()",
        "@ui.divider(vertical=true)",
        "@ui.tooltip(@ui.button(\"悬停看提示\"), \"原生 tooltip：系统样式\")",
        "@ui.card([..], class=[@style.style(border_style=@style.Dashed)])",
        "@ui.card([..], class=[@style.style(border_style=@style.Dotted, border_width=2.0)])",
      ],
    ),
    @shared.section(
      "悬停光标",
      "HoverGroup 悬停组与 CursorGroup 光标组",
      "上：组内任意位置（含子控件）悬停即整组进入 hover 态——把指针移到卡片里的按钮或输入框上，整张卡片同样高亮。悬停态是父链语义，既不排定时器也不查指针。下：父设子随——指针落在组内任意位置（含输入框、按钮等子控件）都保持手型，移出恢复默认。光标是窗口级的一层，宿主按悬停路径取「最深的那个请求」，所以组只设自己一处即可。",
      [
        @ui.hover_group(
          [
            @ui.text(@shared.tx("组标题：悬停我，或下面的子控件"), role=@ui.Section),
            @ui.row(
              [@ui.input(box_a, width=200.0), @ui.button(@shared.tx("组内按钮"))],
              column_gap=8.0,
            ),
            @ui.text(@shared.tx("子控件触发的事件同样改变组的样式"), role=@ui.Secondary),
          ],
          padding=12.0,
          row_gap=8.0,
        ),
        @ui.cursor_group(
          [
            @ui.text(@shared.tx("整组都是手型：移入试试，或移到子控件上"), role=@ui.Section),
            @ui.row(
              [@ui.input(box_b, width=200.0), @ui.button(@shared.tx("组内按钮"))],
              column_gap=8.0,
            ),
          ],
          padding=12.0,
          row_gap=8.0,
        ),
      ],
      code=[
        "@ui.hover_group(",
        "  [",
        "    @ui.text(\"组标题\", role=@ui.Section),",
        "    @ui.row([@ui.input(box, width=200.0), @ui.button(\"组内按钮\")], column_gap=8.0),",
        "  ],",
        "  padding=12.0,",
        "  row_gap=8.0,",
        ")",
        "@ui.cursor_group(",
        "  [",
        "    @ui.text(\"整组都是手型\", role=@ui.Section),",
        "    @ui.input(box, width=200.0),",
        "    @ui.button(\"组内按钮\"),",
        "  ],",
        "  padding=12.0,",
        ")",
      ],
    ),
  ])
}
