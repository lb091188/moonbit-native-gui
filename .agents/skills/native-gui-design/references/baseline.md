# 公约数基准：取值表

三端共用一张表。标「库默认」的是从 `gui` 源码量出来的既有值，改动它等于跟框架对着干；标「档」的是本基准定的取值范围，可以自由调，但调了要整套一起调。

## 间距刻度

`2 / 4 / 6 / 8 / 12 / 16 / 24`，只用这七个数。

| 档 | 用在哪 | 依据 |
|---|---|---|
| 2 | 图标与紧邻文字的微调、徽章内边距 | 档 |
| 4 | 同一语义小组内的间隔（两个单选项、文字按钮组） | 档 |
| 6 | 图标到标签的间距；面板标题与正文之间 | 库默认：`button` 图标槽 `icon_size + 6.0`；`panel` 的 `row_gap=6.0` |
| 8 | 控件与控件之间、表单行与行之间 | 档 |
| 12 | 卡片内边距；卡片与卡片之间 | 库默认：`card` 的 `padding=12.0` |
| 16 | 页面内边距；分组与分组之间 | 档 |
| 24 | 大区块之间、空状态与主视觉四周 | 档 |

配套的定值：**1px 描边**（`border_width=1.0`）是唯一描边宽度，不用 2px 以上的框线画卡片。

## 字阶

正文锚在 13（`@ui.text` 与 `@ui.button` 的 `font_size` 默认值都是 13.0），这是桌面字号，别再往上加。

| 角色 | 字号 | 字重 | 颜色 token | 用途 |
|---|---|---|---|---|
| `@ui.Title` | 18 | SemiBold | `text_primary` | 窗口/页主标题，一屏最多一个 |
| `@ui.Section` | 14 | SemiBold | `text_primary` | 分区标题、卡片标题 |
| `@ui.Body` | 13 | Normal | `text_regular` | 正文、表单标签、列表项 |
| `@ui.Secondary` | 12 | Normal | `text_secondary` | 说明、时间戳、次要信息 |
| `@ui.Accent` | 13 | SemiBold | `primary` | 强调词、链接式操作 |
| `@ui.Plain` | 13 | Normal | `text_regular` | 无角色，此时才由调用方给 `font_size` / `color` |

写法：`@ui.text("保存成功", role=@ui.Secondary)`。上表的字号、字重、颜色由 `role_font` / `role_color` 给出，换主题自动跟随——这就是不要手写 `font_size=` 的原因。

数字型强调（统计数、金额）用 20 或 26 + `SemiBold` + `text_primary`，配一行 `@ui.Secondary` 说明；这是唯一允许脱离字阶的地方。

## 密度：紧凑怎么个紧凑法

控件高度是全局契约 `@theme.control_height = 32.0`，不要试图压到 24——那会跟输入框、下拉、按钮的内部测量打架。紧凑感来自上面这几档取小：

- 表单：行距 8，标签到控件 4，分组间 16。
- 工具栏：`@ui.row(column_gap=4, padding=6)`，两端 `padding=6`。
- 列表/表格行：行高交给 `control_height`，单元格横向内边距 8，斑马纹用 `fill_zebra`，不加行间距。
- 卡片网格：卡片内 12，卡片间 12，页面外框 16。
- 页面：外边距 16，区块间 24。

一句话：**默认按上表偏小的一档起步，觉得挤了再往上升一档，不要一开始就用 16/24。**

## 圆角

| 层 | 值 | 怎么给 |
|---|---|---|
| 控件（按钮、输入框、下拉、标签） | 4 | 库内默认值就是 4，占绝大多数，通常不用写 |
| 卡片、面板 | 6 | **必须显式给**：`@ui.card(..., class=[@style.style(border_radius=6.0)])`，`@ui.panel(..., class=[...])` 同理。两者默认都没有圆角 |
| 对话框、浮层窗口级容器 | 8 | `@ui.dialog` 收 `class`，同样显式给 |

`border_radius` 大于 8 不出现。圆形元素（头像、状态点）用 `@ui.avatar` 之类自带形态的组件，不要靠 `border_radius=999` 造。

## 配色比例

一个界面里：**60% 中性底**（`bg_page` 打底，`bg_panel` 铺面板与卡片）、**30% 结构与文字**（`text_primary` / `text_regular` / `text_secondary` / `border` / `fill_hover` / `fill_zebra`）、**10% 强调**（`primary` 及其派生）。

主色的用法是穷举的，只允许这三处：主操作按钮、选中项、焦点环。危险操作用 `danger`，成功/警告状态用 `success` / `warning`，都只出现在文本与图标上，不拿来铺底（要浅底用 `*_light`）。

图表系列色走 `@theme.chart_palette` 按序取，不散配。

## 状态与层次

投影、模糊都没有。层次按这个顺序叠：

1. 页面底 `bg_page`
2. 面板/卡片底 `bg_panel` + `border` 1px 描边
3. 交互反馈：`fill_hover` 铺底（悬停）、按下时更深一档
4. 压暗用现成的：对话框走 `@ui.dialog`（自带遮罩）；其他浮层需要压暗时用整层 `opacity` 或垫一层深色底。要玻璃观感用 `@ui.glass`（只糊面板下方的内容），不要做窗口背后毛玻璃

状态桶用现成的：`Style::hover(...)` / `Style::active(...)` / `Style::focus(...)`，或 `@style.style(hover=..., active=..., focus=...)`。过渡时长用 `transition_ms=`（毫秒）。
