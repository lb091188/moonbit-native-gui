# 组件配方

每个配方都是可编译的完整写法，取值只用 `baseline.md` 的刻度。主仓可运行版在 `examples/design-recipes/`（`moon check` 门禁覆盖）。

## 工具栏

主操作在左，次操作随后，搜索靠右（`grow=1.0` 撑开空隙），动作间 4。

```moonbit
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
```

## 表单

标签在上、控件在下（标签到控件 4）；行与行 8；整组包卡片，主操作贴右下。

```moonbit
fn field(label : String, control : @widget.Node) -> @widget.Node {
  @ui.col([@ui.text(label, role=@ui.Secondary), control], row_gap=4.0)
}

@ui.card(
  [
    field("名称", @ui.input(name, placeholder="项目名称")),
    field("邮箱", @ui.input(mail, placeholder="you@example.com")),
    @ui.row(
      [@ui.view([], grow=1.0),
       @ui.button("取消", variant=@ui.Text),
       @ui.button("保存", variant=@ui.Solid)],
      column_gap=8.0,
    ),
  ],
  title="编辑资料",
  padding=12.0,
  row_gap=16.0,
  class=[@style.style(border_radius=6.0)],
)
```

## 卡片网格

三张等宽卡片：外层 `row` + 每张包一层 `view(grow=1.0)`；卡片内 12、卡片间 12。

```moonbit
@ui.row(
  [
    @ui.view([@ui.card([
      @ui.text("运行时长", role=@ui.Secondary),
      @ui.text("128 h", font_size=20.0, weight=@text.SemiBold, color="text_primary"),
      @ui.button("查看", variant=@ui.Text),
    ], padding=12.0, row_gap=8.0, class=[@style.style(border_radius=6.0)])], grow=1.0),
    // …第二、三张同形
  ],
  column_gap=12.0,
)
```

## 列表

表头 12 + 内容；行内横向 8、行高交给控件高度；斑马纹用 `fill_zebra`，不加行间空隙。

```moonbit
fn list_row(name : String, owner : String, state : String, zebra : Bool) -> @widget.Node {
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

@ui.card(
  [
    @ui.row([/* 表头三格，同上宽度 */], padding=8.0, column_gap=8.0),
    @ui.divider(),
    list_row("数据导入", "林一", "运行中", false),
    list_row("报表导出", "周舟", "已完成", true),
  ],
  title="任务列表",
  padding=12.0,
  row_gap=0.0,
  class=[@style.style(border_radius=6.0)],
)
```

## 空状态

图标 + 一句说明 + 主操作，四周 24。

```moonbit
@ui.card(
  [
    @ui.empty(description="还没有项目，先新建一个"),
    @ui.button("新建项目", variant=@ui.Solid),
  ],
  padding=24.0,
  row_gap=12.0,
  class=[@style.style(border_radius=6.0)],
)
```

## 整页骨架

工具栏贴顶；左列内容、右列辅助区；外边距 16、区块间 16。

```moonbit
@ui.view(
  [
    toolbar(q),
    @ui.row(
      [
        @ui.col([cards(), list()], row_gap=16.0, grow=1.0),
        @ui.col([form(), empty_state()], row_gap=16.0, width=280.0),
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
```

## 两个全局开关

- 圆角全站关：`@style.set_square_corners(true)`，再 `@widget.host_repaint_all()` 触发重绘。
- 背景模糊：玻璃面板压在内容上方，绘制时把它下方的已画像素糊掉再回放。固定一档、半径固定 6，只给开关。

```moonbit
@ui.view(
  [
    background, // 任意内容节点（图片/图表/色块）
    @ui.glass(
      [@ui.text("背景模糊", role=@ui.Section), @ui.text("下方像素先糊再回放", role=@ui.Secondary)],
      padding=12.0,
      blur_on=fn() { on }, // 绘制期取值；切换后调用方触发重绘
      class=[@style.style(position=@yoga.Absolute, left=24.0, top=24.0, width=300.0, height=120.0)],
    ),
  ],
  width=420.0,
  height=180.0,
)
```

玻璃面板必须画在背景内容**之后**（同层兄弟里靠后，或用绝对定位），否则读不到背景像素。窗口背后（桌面壁纸）的毛玻璃不提供。
