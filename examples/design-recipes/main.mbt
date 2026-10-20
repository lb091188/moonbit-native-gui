// 设计配方：基准取值落在真实控件上的样子。一个卡片 = 一个常见界面模式，
// 取值只用七档间距（2/4/6/8/12/16/24）与 4/6/8 圆角，颜色一律走 token。

///|
/// 工具栏：主操作在前、次操作随后，搜索靠右，动作之间用 4 的档分隔。
fn recipe_toolbar(q : @base.Store[String]) -> @widget.Node {
  @ui.row(
    [
      @ui.button("新建", variant=@ui.Solid),
      @ui.button("导入", variant=@ui.Border),
      @ui.button("导出", variant=@ui.Text),
      @ui.divider(vertical=true),
      @ui.view([], grow=1.0),
      @ui.input(q, placeholder="搜索…", width=200.0),
    ],
    padding=8.0,
    column_gap=4.0,
    background_color="bg_panel",
    border_color="border",
  )
}

///|
/// 表单一行：标签在上、控件在下，标签到控件 4。
fn recipe_field(label : String, control : @widget.Node) -> @widget.Node {
  @ui.col([@ui.text(label, role=@ui.Secondary), control], row_gap=4.0)
}

///|
/// 表单：行与行之间 8，整组用卡片包；主操作贴右下。
fn recipe_form(name : @base.Store[String], mail : @base.Store[String]) -> @widget.Node {
  @ui.card(
    [
      recipe_field("名称", @ui.input(name, placeholder="项目名称")),
      recipe_field("邮箱", @ui.input(mail, placeholder="you@example.com")),
      @ui.row(
        [@ui.view([], grow=1.0), @ui.button("取消", variant=@ui.Text), @ui.button("保存", variant=@ui.Solid)],
        column_gap=8.0,
      ),
    ],
    title="编辑资料",
    padding=12.0,
    row_gap=16.0,
    class=[style_card()],
  )
}

///|
/// 卡片圆角 6：card 默认直角，圆角要显式给。
fn style_card() -> @style.Style {
  @style.style(border_radius=6.0)
}

///|
/// 卡片网格：三张等宽卡片，卡片间 12；卡片内边距 12、行距 8。
fn recipe_cards() -> @widget.Node {
  let one : @widget.Node = @ui.card(
    [
      @ui.text("运行时长", role=@ui.Secondary),
      @ui.text("128 h", font_size=20.0, weight=@text.SemiBold, color="text_primary"),
      @ui.button("查看", variant=@ui.Text),
    ],
    padding=12.0,
    row_gap=8.0,
    class=[style_card()],
  )
  let two : @widget.Node = @ui.card(
    [
      @ui.text("本周新增", role=@ui.Secondary),
      @ui.text("36", font_size=20.0, weight=@text.SemiBold, color="text_primary"),
      @ui.button("详情", variant=@ui.Text),
    ],
    padding=12.0,
    row_gap=8.0,
    class=[style_card()],
  )
  let three : @widget.Node = @ui.card(
    [
      @ui.text("失败率", role=@ui.Secondary),
      @ui.text("0.4%", font_size=20.0, weight=@text.SemiBold, color="text_primary"),
      @ui.button("排查", variant=@ui.Text),
    ],
    padding=12.0,
    row_gap=8.0,
    class=[style_card()],
  )
  @ui.row(
    [
      @ui.view([one], grow=1.0),
      @ui.view([two], grow=1.0),
      @ui.view([three], grow=1.0),
    ],
    column_gap=12.0,
  )
}

///|
/// 列表一行：斑马纹用 fill_zebra，单元格横向 8、行高交给控件高度。
fn recipe_list_row(name : String, owner : String, state : String, zebra : Bool) -> @widget.Node {
  @ui.row(
    [
      @ui.view([@ui.text(name, role=@ui.Body)], grow=1.0),
      @ui.view([@ui.text(owner, role=@ui.Secondary)], width=120.0),
      @ui.view([@ui.text(state, role=@ui.Secondary)], width=72.0),
    ],
    padding=8.0,
    column_gap=8.0,
    background_color=if zebra { "fill_zebra" } else { "bg_panel" },
  )
}

///|
/// 列表：表头 12 + 内容，斑马纹隔行，不加行间空隙。
fn recipe_list() -> @widget.Node {
  @ui.card(
    [
      @ui.row(
        [
          @ui.view([@ui.text("名称", role=@ui.Secondary)], grow=1.0),
          @ui.view([@ui.text("负责人", role=@ui.Secondary)], width=120.0),
          @ui.view([@ui.text("状态", role=@ui.Secondary)], width=72.0),
        ],
        padding=8.0,
        column_gap=8.0,
      ),
      @ui.divider(),
      recipe_list_row("数据导入", "林一", "运行中", false),
      recipe_list_row("报表导出", "周舟", "已完成", true),
      recipe_list_row("权限审查", "陈默", "待处理", false),
    ],
    title="任务列表",
    padding=12.0,
    row_gap=0.0,
    class=[style_card()],
  )
}

///|
/// 空状态：图标 + 一句说明 + 主操作，四周留 24。
fn recipe_empty() -> @widget.Node {
  @ui.card(
    [
      @ui.empty(description="还没有项目，先新建一个"),
      @ui.button("新建项目", variant=@ui.Solid),
    ],
    padding=24.0,
    row_gap=12.0,
    class=[style_card()],
  )
}

///|
/// 整页：工具栏贴顶，下面左列内容、右列空状态；外边距 16，区块间 16。
fn recipe_page() -> @widget.Node {
  let q : @base.Store[String] = @base.Store::new("")
  let name : @base.Store[String] = @base.Store::new("")
  let mail : @base.Store[String] = @base.Store::new("")
  @ui.view(
    [
      recipe_toolbar(q),
      @ui.row(
        [
          @ui.col([recipe_cards(), recipe_list()], row_gap=16.0, grow=1.0),
          @ui.col([recipe_form(name, mail), recipe_empty()], row_gap=16.0, width=280.0),
        ],
        column_gap=16.0,
        grow=1.0,
        align_items=@yoga.AlignItems::FlexStart,
      ),
    ],
    padding=16.0,
    row_gap=16.0,
    grow=1.0,
    background_color="bg_page",
  )
}

///|
fn main {
  let app = match @ui.mount_window(
    [recipe_page()],
    title="设计配方",
    width=960,
    height=720,
  ) {
    None => return
    Some(a) => a
  }
  app.run()
}
