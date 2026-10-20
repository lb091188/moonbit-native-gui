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
/// 演示用底图：三段色带 + 两块高对比方块，模糊前后差异一眼可辨。
fn appearance_art() -> @render.Bitmap {
  let bm = @render.Bitmap::new(360, 140)
  bm.fill_area(0, 0, 120, 140, { r: 45, g: 104, b: 196, a: 255 })
  bm.fill_area(120, 0, 240, 140, { r: 46, g: 158, b: 91, a: 255 })
  bm.fill_area(240, 0, 360, 140, { r: 214, g: 69, b: 80, a: 255 })
  bm.fill_area(40, 40, 120, 100, { r: 255, g: 255, b: 255, a: 255 })
  bm.fill_area(220, 30, 300, 110, { r: 42, g: 47, b: 54, a: 255 })
  bm
}

///|
/// 圆角样例：卡片 6、按钮与输入框 4 —— 拨开关时这一排整体变直角。
fn appearance_radius_samples(q : @base.Store[String]) -> @widget.Node {
  @ui.row(
    [
      @ui.card(
        [@ui.text("卡片圆角 6", role=@ui.Secondary)],
        padding=12.0,
        class=[@style.style(border_radius=6.0)],
      ),
      @ui.button("按钮 4", variant=@ui.Solid),
      @ui.input(q, placeholder="输入框 4", width=160.0),
    ],
    column_gap=12.0,
  )
}

///|
/// 背景模糊演示：底图 + 一张压在它上方的玻璃面板；开关切换面板下方像素是否先糊。
fn appearance_stage(app : @shared.App) -> @widget.Node {
  let art = @render.Image::from_bitmap(appearance_art())
  let bg = @widget.node_of_new(fn(w : @widget.Widget) -> @widget.Widget {
    w.node.set_width(@yoga.fixed(420.0))
    w.node.set_height(@yoga.fixed(180.0))
    w.on_draw = Some(fn(
      _self : @widget.Widget,
      p : @render.Painter,
      r : @base.Rect,
    ) -> Unit {
      p.flush()
      p.draw_image(art, 0.0, 0.0, r.w, r.h)
    })
    w
  })
  let glass = @ui.glass(
    [
      @ui.text("背景模糊", role=@ui.Section),
      @ui.text("面板下方的像素先糊再回放", role=@ui.Secondary),
      @ui.button("操作", variant=@ui.Border),
    ],
    padding=12.0,
    blur_on=fn() { app.soft.get() },
    class=[
      @style.style(
        position=@yoga.Absolute,
        left=24.0,
        top=24.0,
        width=300.0,
        height=120.0,
      ),
    ],
  )
  @ui.view([bg, glass], width=420.0, height=180.0)
}

///|
pub fn page_basic(app : @shared.App) -> @widget.Node {
  // 两个悬停/光标组各配一个文本框状态
  let box_a : @base.Store[String] = @base.Store::new("组内输入框")
  let box_b : @base.Store[String] = @base.Store::new("组内输入框")
  let radius_demo : @base.Store[String] = @base.Store::new("")
  @shared.page([
    @shared.section(
      "外观",
      "圆角与柔焦",
      "两个总开关：圆角关掉后全站经样式槽的圆角按 0 绘制；背景模糊把玻璃面板下方**已经画好的像素**读出来糊掉再回放（Painter::backdrop_blur，固定一档）。",
      [
        @ui.row(
          [
            @ui.text("圆角", role=@ui.Body),
            @ui.switch(app.flat, on_change=fn(v) {
              @style.set_square_corners(v)
              @widget.host_repaint_all()
            }),
            @ui.text("背景模糊", role=@ui.Body),
            @ui.switch(app.soft, on_change=fn(_v) {
              @widget.host_repaint_all()
            }),
          ],
          column_gap=12.0,
        ),
        appearance_radius_samples(radius_demo),
        appearance_stage(app),
      ],
      code=[
        "@style.set_square_corners(true)",
        "@widget.host_repaint_all()",
        "@ui.glass(children, blur_on=fn() { on })",
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
