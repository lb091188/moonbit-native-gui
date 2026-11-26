# 内置组件速查（@ui）

返回 `Node` 的构造器即 `.mng` 标签（`<ui-button>` → `@ui.button`，`-`→`_`）；校验规则、轻提示等脚本侧工具在 `<script>` 段调用，不当标签。参数与事件以此表为索引、以 `.mooncakes/NoahLiu/native-gui/` 源码与 `pkg.generated.mbti` 为权威。

通用约定：

- 值控件（输入/复选/滑块…）当前值由 `Store[T]` 持有：外部 `set` 即刷新、交互改即回写。
- 展示类取值两入口：`x` 收静态值，`x_dyn` 收 `Signal[T]` 值变就地更新。
- 事件回调统一 `on_*`（`on_click` / `on_change` / `on_enter`…）。
- 尺寸为逻辑像素，给 `0` = 按内容或由父级定；外观覆盖走 `class`。

## 布局与容器

| 构造器 | 用途 | 要点 |
|---|---|---|
| `view` | 通用容器 | `direction?` 定主轴（缺省 Column）；`grow` 撑满剩余空间 |
| `col` / `row` | 纵 / 横排 | `row` 的 `align_items` 缺省 Stretch（子项撑满行高） |
| `panel` | 带标题面板 | `panel(title, children)`；圆角等外观走 `class` |
| `split` | 可拖分栏 | `direction` Horizontal/Vertical + `ratio` 0..1 + `min_first`/`min_second` |
| `scroll_view` | 滚动容器 | `state : ScrollState` 必传；`hscroll` 开横滚；`min_content_width` 下限档 |

## 文本与媒体

| 构造器 | 用途 | 要点 |
|---|---|---|
| `text` | 静态文本 | `wrap` 缺省 true，单行标签显式 `wrap=false`；排版档挂 `class` 字阶预设 |
| `text_dyn` | 信号文本 | 收 `Signal[String]`，值变就地改字 |
| `bind_label` / `bind` | 绑定文本 | Store/Signal + 转换函数 `f`，值变自动重渲染 |
| `divider` | 分隔线 | 给 `text` = 居中断线；`vertical` 定横竖 |
| `image` / `gif` / `icon` | 图 / 动图 / 矢量图标 | icon 的 `kind` 是 `IconKind` 枚举；gif 可拿 `GifHandle` 控播放 |
| `code_view` | 只读高亮代码 | 宽随容器自带横滚；`copyable` 出复制按钮；要编辑用 `code_editor` |
| `code_editor` | 代码编辑器 | `store : Store[String]` 双向投影；`on_change` 回全文；行级增量高亮 |
| `terminal` | 终端控件 | 模型 `Terminal::new()` + `feed(text)` 喂 ANSI；按键经 `on_input` 出口交应用 |
| `icon_button` | 图标按钮 | `kind` + `on_click`；`box_size` 是点击盒边长 |

## 表单（值全走 Store）

| 构造器 | Store 类型 | 要点与事件 |
|---|---|---|
| `button` | — | `variant` 五档 Solid/Soft/Border/Text/Danger |
| `input` | `Store[String]` | `on_enter` / `on_change`；`password` / `read_only` / `clearable` |
| `textarea` | `Store[String]` | `rows` 定高；贪心折行 + 纵滚 |
| `checkbox` / `switch` | `Store[Bool]` | 整行/胶囊点击；switch 有 `on_text`/`off_text` |
| `radio_group` | `Store[Int32]` | `options` 下标即值；方向键换选 |
| `slider` | `Store[Double]` | `min`/`max`/`step`；方向键步进 |
| `stepper` | `Store[Int32]` | `[-] 值 [+]` 三段；中格直输数字 |
| `select` | `Store[String]` | 下拉唯一入口；`on_change`；`editable=true` 可输入形态 |
| `color_picker` / `rate` | `Store[String]` / `Store[Int32]` | 色板网格 / 五角星评分 |
| `form` / `form_item` | — | 表单编排：`form_item(label, control, error?=Store[String])` 错误行常驻 |
| `validate` | `Store[String]` | `validate(store, rule)` 值变即重跑规则，返回的错误 Store 接 `form_item` |
| `required` / `min_len` / `email` / `int_range` | — | 四条现成校验规则 |
| `link` | — | 链接文字，`on_click` |

## 数据展示

| 构造器 | 用途 | 要点 |
|---|---|---|
| `tag` / `tag_of_type` | 标签 | 自定色实底 / 语义色浅底（`SemanticType`） |
| `badge_count` / `badge_dot` | 徽标 | 数字超 `max` 显示 max+ / 圆点 |
| `avatar` / `statistic` / `descriptions` | 头像 / 统计数字 / 描述列表 | descriptions 收 `(标签, 值)` 对 |
| `card` / `empty` / `result` | 卡片 / 空状态 / 结果页 | card 可选标题栏 |
| `progress` / `progress_line` | 进度条 | `state : Store[Double]` 纯展示 |
| `timeline` | 时间线 | 收 `(标题, 描述, 语义色)` |
| `carousel` | 轮播 | 程序化控制走 `CarouselHandle`；**卸载前必须 `carousel_stop`** |
| `alert` | 页内提示条 | 常驻不自动消失；轻提示用 `toast_layer` |

## 表格与列表

| 构造器 | 用途 | 要点 |
|---|---|---|
| `table` / `table_v` | 表格 / 万行虚拟表格 | 列 `TableColumn::make`、行 `TableRow::make(cells)`；行选择、表头排序 |
| `virt_list` | 虚拟列表 | **行高必须固定**；只挂可见区间 ±overscan；`rev` 递增触发整窗重挂 |
| `sticky_list` | 分组吸顶列表 | 组标题滚动吸顶 |

## 日期与时间

| 构造器 | 用途 |
|---|---|
| `calendar` | 内联月历；`on_pick` |
| `date_picker` / `date_range_picker` | 字段 + 月历浮层；值 `Store[DateYMD?]` / `Store[DateRange]` |
| `time_range_picker` / `datetime_range_picker` | 列式步进弹层；值 `Store[TimeRange]` / `Store[DateTimeRange]` |

值模型 `DateYMD` / `TimeHMS` / `DateRange` / `TimeRange` / `DateTimeRange` 配纯函数 `month_grid` / `month_shift` / `days_in_month` / `today_date` 等（`ui/datetime.mbt`）。

## 导航

| 构造器 | 用途 | 要点 |
|---|---|---|
| `menu` / `menu_sections` | 侧边菜单 / 分组菜单 | `selected : Store[String]` 可共享给主区联动；`foldable` 组可收起 |
| `segmented` | 分段控制器 | `selected : Store[String]` |
| `breadcrumb` / `pagination` / `steps` | 面包屑 / 分页 / 步骤条 | pagination 的 `current` 从 1 起；steps 的 `current` 0 起始 |
| `collapse` / `tree` / `tabs` / `transfer` | 折叠面板 / 树 / 页签 / 穿梭框 | tabs 内容区预建靠显隐切换 |

## 浮层与消息

浮层一律开在整窗浮层图层，按锚点与窗口边界自动收位，不会被裁切。

| 构造器 | 用途 | 要点 |
|---|---|---|
| `dialog` | 对话框 | `visible : Store[Bool]` 驱动；确认/取消/✕ 三个出口都先收起再回调 |
| `message_box` | 消息框 | `buttons=[(文案, 编号)]`，`on_response` 收编号；✕/Esc 走 `on_dismiss` |
| `popover` / `tooltip` / `dropdown` | 气泡 / 悬浮提示 / 菜单按钮 | tooltip 停留 `delay_ms` 弹出；dropdown `on_select` 收**下标**（与 select 的 Store 口径不同） |
| `context_menu_for` | 右键菜单 | `items` 文案 `"-"` 画分隔线 |
| `toast_layer` | 轻提示 | 建界面时调一次得推送函数，回调里 `toast("文案", @ui.Success)` |

## 响应式控制

| 构造器 | 用途 | 要点 |
|---|---|---|
| `when` / `when_else` | 信号显隐 | 真【挂载/显示】假隐藏，不销毁状态不丢；`_store` 形态接 `Store` |
| `for_list` | keyed 列表差分 | **`key` 必传**，同键复用行；变化字段做成 Store，别靠换元素重挂 |
| `for_list_indexed` | 按下标对齐 | 长度收缩才卸载多余行 |
| `follow_store` | 订阅重绘 | 自绘块接外部状态：值变即 `invalidate` |

## 拖放与悬停

| 构造器 | 用途 | 要点 |
|---|---|---|
| `drag_source` / `drop_target` | 拖源 / 落点 | 拖过 `threshold` 像素才取 payload；**拖源内容里别放按钮**（会截获按下） |
| `hover_group` / `cursor_group` | 悬停换底 / 光标形状 | 组级父链语义，无需轮询指针 |
