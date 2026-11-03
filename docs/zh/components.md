# 组件速查（@ui）

控件与组件库全部住在 `NoahLiu/native-gui/ui`（别名 `@ui`）。每个组件是一个**返回 `@widget.Node` 的构造器**——把界面描述成一棵节点树，交给 `@ui.mount_window([...])` 一次挂载。本文按家族列每个组件的完整签名、参数与行为，作速查用；参数一律以代码为准（`gui/ui/*.mbt`）。

> 各组件的可运行示例集中在 `examples/showcase`（每页一个源文件），是最快的上手参照。

## 约定

- 组件参数均为类型化参数（尺寸、颜色、值），不接受 CSS 字符串；外观覆盖用命名参数或 `class? : Array[@style.Style]`，同名属性以数组靠后者为准；样式字段清单见 [layout.md](layout.md)
- 尺寸单位为逻辑像素；`width` / `height` 给 `0` 通常表示按内容或由父级决定
- 值类控件（复选 / 单选 / 开关 / 滑块 / 输入框 / 进度）的当前值由 `@base.Store[T]` 持有：组件读写它，外部修改即刷新
- 展示类控件另有两条取值入口：`x` 收静态值，`x_dyn` 收 `Signal[T]`
- 事件回调统一命名为 `on_*`（`on_click` / `on_change` / `on_drop` …）
- `handle?` 返回内部 `@widget.Widget` 句柄，用于框架未暴露的操作，不是事件回调
- `disabled?` / `enabled?` 控制禁用态；`focus_id?` 指定 Tab 焦点序（缺省自动分配）
- 表单族控件默认进入 Tab 焦点链，聚焦描边转主题色；空格 / 回车激活，方向键按控件语义调值或换选
- 文本排版预设挂 `class`：`text_heading`（18 SemiBold）、`text_title`（14 SemiBold）、`text_secondary`（12 次要色）、`text_accent`（13 SemiBold 主色）；正文 13 为 `text` 缺省档，不必挂；字号读 `@theme` 字阶令牌
- 语义色 `SemanticType`：`Primary` / `Success` / `Warning` / `Danger` / `Info`；存储 theme token 名，随主题取值

## 布局与容器

### `view(children, direction?=Column, row_gap?, column_gap?, padding?, width?, height?, grow?, background_color?, border_color?, align_items?, justify_content?, class?, handle?)`

- 通用容器：方向、两轴间距、内边距、尺寸、底色与描边
- `direction`：主轴方向，默认 `Column`
- `grow`：弹性增长，撑满父级剩余空间
- 尺寸给 `0` 表示按内容定

### `col(children, row_gap?, padding?, width?, height?, grow?, background_color?, border_color?, align_items?, class?, handle?)`

- 垂直布局容器（`view` 的 Column 形态）

### `row(children, column_gap?, padding?, width?, height?, grow?, background_color?, border_color?, align_items?=Center, class?, handle?)`

- 水平布局容器（`view` 的 Row 形态）；`align_items` 默认 `Center`

### `panel(title, children, padding?=10.0, row_gap?=6.0, width?, class?)`

- 带标题面板：标题在上、内容在下，面板底 + 描边；圆角等外观经 `class` 传入

### `split(first, second, direction?=Horizontal, ratio?=0.5, min_first?, min_second?, class?, handle?)`

- 可拖分栏，`hsplit` / `vsplit` 合并、方向参数化
- `direction`：`Horizontal`（左右分）或 `Vertical`（上下分）
- `ratio`：初始分割比例，0..1
- `min_first` / `min_second`：两侧最小尺寸

### `scroll_view(children, state : ScrollState, width?, height?, hscroll?=false, min_content_width?=0.0, class?, handle?)`

- 滚动容器；滚动条为浮在右缘的拇指：不绘制轨道、不占宽度，悬停满色、平时淡色
- `state`：`ScrollState` 持有滚动偏移，外部可读写
- `height`：视口高度，`0` 表示由父级决定
- `hscroll`：开启横向滚动
- `min_content_width`：内容宽两档——缺省 `0.0` 为自然宽档 `max(子项自然宽, 视口宽)`（长代码行 / 表格适用）；给定正值 `N` 为下限档 `max(N, 视口宽)`，不读子项自然宽，更宽的内容由它自己的视口滚动

> 滚动偏移在绘制期平移、不进布局；`ScrollState` 由 `ui/scroll.mbt` 提供。

## 文本与基础

### `text(content, font_size?=13.0, color?, weight?, family?, align?, max_width?, wrap?=true, ellipsis?, max_lines?=0, selectable?=false, class?, handle?)`

- 文本，`label` 与 `label_t` 合并：尺寸来自 Pango 测量并进布局引擎，可参与基线对齐
- `wrap`：缺省 `true`（块级段落）；单行标签显式 `wrap=false`——行内挤不过兄弟件时收缩、末端出 …
- `max_width`：折行宽度上限
- `ellipsis`：溢出补省略号
- `max_lines`：`wrap` 时限制行数，超过第 N 行截断、行末补 …（`0` = 不限）
- 排版档走 `class`（`@style.text_heading` 等字阶预设）
- `selectable`：打开后这段静态文本**可用鼠标选中并复制**——单击定位、双击选词、拖选、Shift+点击扩选，`Ctrl/Cmd+C` 或右键菜单复制。它是只读的：不可聚焦、不进 Tab 链（可选中文本海量，全进 Tab 环绕键盘就废了），所以按键由宿主在「当前谁持有选区」上兜住。已知边界：折行块内不逐行对齐（整块随 `align` 偏移）；选中期间文本或盒宽变了就清选区；行数钳制与省略与缺省档同源，选中范围=可见范围

### `text_dyn(sig : Signal[String], font_size?, color?, …, wrap?=true, selectable?=false, class?, handle?)`

- 随信号更新的文本：值变化就地改字、只重算该条链路
- `sig`：字符串信号源；其余参数同 `text`
- `bind_label` 的信号版对应物，展示类 `*_dyn` 的原型

### `bind_label(store : Store[A], f : (A) -> String, font_size?, color?, handle?)`

- 声明式文本绑定：初值 `f(store.get())`，之后每次 `set` 就地更新文本并重测
- `f`：值到文本的转换函数；恒单行

### `bind(sig : Signal[A], f : (A) -> String, font_size?, color?, handle?)`

- 信号版文本绑定：`sig` 接源信号或 `computed` 派生信号，`f` 同 `bind_label`

### `divider(text?, vertical?=false, color?, class?)`

- 分隔线：`text` 空 = 直线，`vertical` 定横 / 竖；给字 = 居中断线

### `image(path, width?, height?, handle?)`

- 图像：按文件解码（PNG / JPEG / GIF 首帧）；尺寸给 `0` 用原始尺寸

### `icon(kind : @icons.IconKind, size?=16.0, color?, class?, handle?)`

- 矢量图标：`kind` 为图标枚举；`size` 是盒子边长
- `color` 空 = 主题正文色，随主题取值

### `code_view(lines : Array[String], lang?="moonbit", font_size?=13.0, line_numbers?=false, handle?)`

- 代码高亮视图：One Dark 深底、不随主题；词分类着色
- `lang`：语言选择，支持 `js` / `ts` / `python` / `rust` / `c` / `go` / `bash` / `sql`，缺省 `moonbit`
- `line_numbers`：显示行号列
- 宽度跟随容器（flex 1）：窄代码深底条铺满整行，代码比容器宽时自带横向滚动（调用方不必再包 `scroll_view`），高按行数

### `gif(path, width?, height?, looping?=true, running?=true, state?, handle?)`

- 动图：非 GIF 静图只绘制第一帧
- `looping`：`false` 播完一轮即停
- `running`：初始播放状态
- `state`：`GifHandle` 外部句柄，程序化控制播放

## 表单控件

值类控件的当前值都由 `Store[T]` 持有，外部改值即刷新，交互改值即回写。

### `button(text, on_click?, variant?=Soft, color?, background_color?, font_size?, min_width?, focus_id?, disabled?, enabled?, class?, handle?)`

- 按钮：`variant : ButtonVariant` = `Solid` / `Soft` / `Border` / `Text` / `Danger`；键盘空格 / 回车激活
- `min_width`：最小宽度

### `input(store : Store[String], placeholder?, password?=false, read_only?=false, font_size?=13.0, family?, width?=0.0, focus_id?, caret_on?, on_enter?, on_change?, clearable?=false, editor?, class?, …)`

- 单行输入框：选区 / 双击选词 / 撤销重做 / Ctrl+A-C-V / IME 内联全语义
- `placeholder`：空值占位文案；`password` 密码遮罩；`read_only` 只读
- `on_enter`：回车回调；`on_change`：内容变化回调
- `clearable`：悬停 / 聚焦出 ✕、点击清空
- `editor`：挂载时交出 `@input.Editor` 编辑内核句柄，组件外改选区 / 读文本等操作用它
- 右键出编辑菜单（剪切 / 复制 / 粘贴 / 全选，密码框无复制 / 剪切）；Ctrl/Cmd+C/X/V 默认接系统剪贴板（`use_system_clipboard(false)` 可关闭）

### `textarea(store : Store[String], placeholder?, rows?=3, width?=260.0, height?=0.0, font_size?=13.0, family?, read_only?, focus_id?, caret_on?, on_change?, class?, handle?)`

- 多行输入：贪心折行（空格 / 拉丁词 / 中日韩逐字）+ 垂直滚动，上下键跨显示行
- `rows`：初始行数；`height` 给正值时以 `height` 为准
- `on_change`：内容变化回调
- 右键出编辑菜单；Ctrl/Cmd+C/X/V 默认接系统剪贴板

### `checkbox(content, state : Store[Bool], disabled?, enabled?, focus_id?, font_size?, class?, handle?)`

- 复选框 + 文本标签，整行点击区；空格 / 回车切换

### `radio_group(options : Array[String], state : Store[Int], disabled?, direction?=Row, gap?=12.0, class?)`

- 单选组：`options` 依次对应值 `0..n-1`；空格 / 回车选中本项、方向键换选、到头环绕
- `direction`：排布方向，默认横向

### `switch(state : Store[Bool], on_text?, off_text?, disabled?, focus_id?, on_change?, class?)`

- 开关：40×20 胶囊 + 16 圆滑珠；空格 / 回车切换
- `on_text` / `off_text`：开 / 关侧文案，可空
- `on_change`：用户拨动后回调 `on_change(Bool)`（外部写值不回调）

### `slider(state : Store[Double], min?=0.0, max?=100.0, step?=0.0, width?=160.0, disabled?, focus_id?, class?, handle?)`

- 滑块：按下即取值、拖动跟随；方向键步进、Home / End 到端点
- `min` / `max`：取值范围；`step`：吸附步长（`>0` 生效）

### `stepper(state : Store[Int], min?=0, max?=999, step?=1, focus_id?, class?)`

- 数值步进器 `[-] 值 [+]`，共框三段；↑ / ↓ 增减，← / → 移光标
- 中间格可直接输入：只收数字，回车或失焦回写并夹取
- 触界侧自动禁用（灰底次级字、光标回箭头）；聚焦（点击 / Tab / 点加减 / ↑↓）即全选，输入整体替换

### `select(options : Array[String], value : Store[String], on_change?, clearable?=false, placeholder?="", width?=200.0, …)`

- 下拉选择，唯一入口；弹层在浮层图层，↑↓ 高亮 + 回车取值 + Esc 收起
- `on_change`：选中回调
- `clearable`：可清空已选
- `placeholder`：空值占位文案
- 可输入形态用 `editable=true`

### `color_picker(value : Store[String], colors?=[内置 15 色], on_change?, width?=200.0, focus_id?, class?, handle?)`

- 取色器：字段 + 色板网格；回车开板、← / → 移一格、↑ / ↓ 移行、回车取色
- `colors`：色板颜色清单
- `on_change`：取色回调

### `rate(value : Store[Int], max?=5, on_change?, size?=22.0, gap?=4.0, focus_id?, …)`

- 评分：矢量五角星 + 悬停预亮；方向键加减星、Home / End 清零 / 打满
- `max`：星级上限；`size` / `gap`：星形尺寸与间距
- `on_change`：评分变化回调

### `form_item(label_text, control : Node, label_width?=90.0, error?=Store[String], handle?)`

- 表单项：左定宽右对齐标签 + 右控件，下方常驻错误行；行高固定预留、不跳动布局
- `error`：错误文案 Store，非空显示错误行

### `form(title, items : Array[Node], row_gap?=8.0, handle?)`

- 表单：分组标题 + 一组纵排表单项

### `link(text, on_click : () -> Unit, font_size?, class?, handle?)`

- 链接文字：主题色、悬停下划线、抬起触发；`on_click` 点击回调

## 数据展示

展示类另有 `*_dyn` 信号版：`text` 换 `Signal`、就地改字重算宽、退订随回收袋。

### `tag_of_type(text, t : SemanticType, font_size?=12.0, class?)`

- 语义色标签，浅底 + 主色字；`t` 选语义色；`tag_of_type_dyn` 收信号

### `tag(text, color, font_size?=12.0, class?)`

- 自定色标签，实底 + 白字；`color` 给色值；`tag_dyn` 收信号

### `badge_count(value : Int, max?=99, color?, class?)`

- 数字徽标：超过 `max` 显示「max+」；`badge_count_dyn` 收 `Signal[Int]`

### `badge_dot(size?=8.0, color?, class?)`

- 圆点徽标，无数字、仅提示「有新内容」；`size` 为圆点直径

### `avatar(text, size?=32.0, background_color?, class?)`

- 头像：取文本首字符居中；`avatar_dyn` 收信号

### `statistic(title, value, precision_color?, prefix?, class?)`

- 统计数字：小标题 + 数值、可带前后缀；`statistic_dyn` 收 `Signal[String]`

### `card(children, title?, padding?=12.0, row_gap?=6.0, class?)`

- 卡片：可选标题栏 + 内容区，面板底 + 描边

### `descriptions(items : Array[(String, String)], title?, label_width?=96.0, class?)`

- 描述列表：`items` 为 `(标签, 值)` 对，逐行显示；`label_width` 定标签列宽

### `empty(description?="暂无数据", class?)`

- 空状态：图标 + 描述，居中

### `result(title, subtitle?, t?=Success, class?)`

- 结果页：语义图标 + 标题 + 副标题；`t` 选语义色

### `progress(state : Store[Double], max?=1.0, width?=200.0, height?=6.0, color?, class?, handle?)`

- 进度条，纯展示：`state` 取 `0..max`

### `progress_line(state, max?=1.0, width?=200.0, label_side?=true, class?)`

- 带百分比文字的进度条；`label_side` 定文字侧

### `timeline(items : Array[(String, String, SemanticType)], item_height?=56.0, gap?=12.0, class?)`

- 时间线：`items` 为 `(标题, 描述, 语义色)` 逐行等高；连接线含行间隙、不中断

### `carousel(pages : Array[Node], width?=360.0, height?=180.0, interval_ms?=3000, rotation?=CarouselHandle::make(), class?, handle?)`

- 轮播：面板序列 + 箭头 + 指示点；`interval_ms>0` 且页数 >1 时自动轮播、悬停暂停
- `rotation`：外部持有的 `CarouselHandle`，配 `carousel_goto` / `carousel_pause` / `carousel_stop` 程序化控制（卸载轮播前必须调 `carousel_stop`）

## 导航

### `menu(items : Array[String], selected : Store[String], icons? : Array[(String, IconKind)], width?=180.0, class?, handle?)`

- 侧边导航菜单：选中项主题浅底 + 左缘强调条
- `icons`：`(项名, 图标)` 对清单，按名匹配
- `selected`：选中项 Store，可共享给主区联动

### `menu_sections(sections : Array[(String, Array[String])], selected, icons?, foldable?=true, width?=180.0, class?, handle?)`

- 分组侧边菜单：组标题行 + 组内项
- `foldable=true` 点击标题收起 / 展开

### `segmented(options : Array[String], selected : Store[String], class?, handle?)`

- 分段控制器：选中段面板底 + 主题色文字；每段进 Tab 链、空格 / 回车选中、方向键换段

### `breadcrumb(items : Array[String], selected : Store[String], class?, handle?)`

- 面包屑：层级间插 `/`；当前项按 `selected` 判定、不按位置

### `pagination(current : Store[Int], pages : Int, class?, handle?)`

- 分页 `‹ 1 2 … ›`：`current` 从 1 起，箭头越界夹到首 / 末页

### `steps(items : Array[String], current : Store[Int], class?, handle?)`

- 步骤条：数字方块（已完成 / 当前 / 待办）+ 文字 + 连线；`current` 为 0 起始下标

### `collapse(panels : Array[(String, Array[Node])], class?, handle?)`

- 折叠面板：点击标题切换内容显隐，各面板独立，默认只展开第一个

### `tree(root : Array[TreeNode], class?, handle?)`

- 树：逐层缩进，点击有子节点的行展开 / 收起

### `tabs(pages : Array[(String, Node)], selected? : Store[Int], class?, handle?)`

- 页签：头行选中主题色 + 底部指示条，内容区预建、靠显隐切换；`selected` 0 起始，不传时内部创建

### `transfer(left_items : Store[Array[String]], right_items : Store[Array[String]], width?=200.0, height?=160.0, item_height?=24.0, class?, handle?)`

- 穿梭框：左右两列 + 中间 `›` / `‹`；两列各由一个 `Store` 驱动
- `item_height`：单行高，配合 `height` 定可视行数

## 表格与虚拟列表

### `table(columns : Array[TableColumn], rows : Store[Array[TableRow]], width?=560.0, row_height?=36.0, selection?, sort?, on_row_click?, class?, handle?)`

- 表格：斑马纹、悬停、行选择；列边界可拖调宽
- `sort`：表头排序配置，点击切换 `TableSort`、排序口径由调用方实现
- `on_row_click`：行点击回调

### `table_v(columns, rows : Store[Array[TableRow]], width?=560.0, height?=360.0, row_height?=32.0, selection?, sort?, on_row_click?, class?, handle?)`

- 万行级虚拟表格：固定表头 + 只挂可见区间，与 `table` 共用表头 / 行控件

### `virt_list(items : Store[Array[T]], height : Double, row_height : Double, row_of : (Int, T) -> Node, width?=0.0, overscan?=2, rev?, class?, handle?)`

- 虚拟列表：只挂可见区间（±overscan）的行，万行级数据只挂十来个控件
- `height` / `row_height`：视口高与行高，行高必须固定（等距窗口才能从偏移算下标；非等距行用 `scroll_view` + 重建式列表）
- `row_of(i, item)`：构建第 i 行，`i` 是源下标，排序 / 过滤顺序由调用方定
- `overscan`：视口外预挂行数
- `rev`：外部修订号 `Store[Int]`——列宽等需要行内容重建的变更递增它，触发整窗重挂

### `sticky_list(groups : Array[(String, Array[Node])], st : StickyList, width?, height?, head_h?=28.0, class?, handle?)`

- 粘性列表：分组标题滚动时吸顶；「当前组」每帧读布局矩形反推

> `TableColumn::make(...)`、`TableRow::make(cells : Array[String])` 构建列与行；`sort_rows(rows, sort)`（`ui/table.mbt`）提供数值优先 + 稳定排序的参考实现。

## 浮层与消息

对话框 / 气泡 / 菜单 / 提示等浮层一律开在整窗的**浮层图层**上，天然压过内容与其它浮层，不需要常驻隐藏树。锚点类浮层（下拉、气泡、日期时间弹层、悬浮提示）按图层边界收位：贴窗口底边放不下翻到锚点上方、贴右边放不下与锚点右缘对齐，翻完仍越界则钳回窗口内——弹层不会被窗口裁切。

### `dialog(visible : Store[Bool], title, children, confirm_text?="确定", cancel_text?="取消", on_confirm?, on_cancel?, close_on_mask?=false, …)`

- 对话框：`visible` 驱动弹出 / 收起；标题栏 + ✕ + 内容 + 底部按钮
- `confirm_text` / `cancel_text`：按钮文案，空串隐藏对应按钮
- `close_on_mask`：点击遮罩关闭
- 三个出口（确认 / 取消 / ✕ 与遮罩）都先收起再回调

### `message_box(visible : Store[Bool], title, content, kind?=Information, informative?, buttons?=[("确定",1)], on_response?, on_dismiss?, close_on_mask?=false, width?)`

- 消息框：`kind` 选图标语义，`informative` 为补充说明文字
- `buttons`：`(文案, 编号)` 清单，第一个是主色默认按钮；响应编号由调用方定
- `on_response` 收按钮编号；Enter 触发第一钮；✕ / Esc / 点遮罩走 `on_dismiss`、不给编号

### `popover(trigger : Node, content : Node, width?, height?, class?, handle?)`

- 气泡弹层：点击 trigger 在其下方弹出任意内容，再次点击收起
- `width` / `height` 传 `0` 按内容定尺寸

### `tooltip(content : Node, tip : String, delay_ms?=500, class?, handle?)`

- 悬浮提示：停留 `delay_ms` 后在下方弹出 `tip` 气泡，离开即收；走宿主 `on_hover_change` 父链语义

### `context_menu_for(content : Node, items : Array[(String, () -> Unit)], width?=150.0, handle?)`

- 右键上下文菜单：`items` 文案为 `"-"` 时绘制分隔线；右键按「祖先优先」派发

## 日期与时间

值模型（`ui/datetime.mbt`）：`DateYMD{y,m,d}`、`TimeHMS{h,m,s}`（秒默认 0，`format(show_seconds=true)` 输出 `HH:MM:SS`）、`DateRange`、`TimeRange`、`DateTimeRange`，配纯函数 `month_grid` / `month_shift` / `days_in_month` / `date_weekday` / `range_state_of`。

### `calendar(on_pick? : (DateYMD) -> Unit, value? : Store[DateYMD?], today? : DateYMD, class?, handle?)`

- 内联月历：‹ / › 切月，点击选中一天
- `on_pick`：选中回调
- `value`：传入时以 Store 为唯一权威（外部 `set` 立即反映），不传则组件自持
- `today`：基准日，默认系统今天

### `date_picker(value : Store[DateYMD?], on_change?, placeholder?="请选择日期", clearable?=true, today? : DateYMD, width?=180.0, focus_id?, class?, handle?)`

- 日期选择：字段 + 月历浮层，选中回显 `YYYY-MM-DD`
- `clearable`：可清空已选；`today`：基准日

### `date_range_picker(value : Store[DateRange], on_change?, placeholder?="请选择日期区间", clearable?=true, today? : DateYMD, width?=220.0, handle?)`

- 日期区间选择器

### `time_range_picker(value : Store[TimeRange], on_change?, width?=110.0, show_seconds?=false, handle?)`

- 时间区间选择器：列式步进弹层（每列 + / 数值 / − / 单位，`:` 分隔，到界回绕），非 `input`
- `show_seconds`：增加秒列

### `datetime_range_picker(value : Store[DateTimeRange], on_change?, today? : DateYMD, date_width?=130.0, time_width?=86.0, show_seconds?=false, handle?)`

- 日期时间区间选择器

> 「今天」经 `wm_local_date` → `@shell.local_ymd()` 取系统日历时间；单调钟 `now_ms` 不能用于推算日期。

## 响应式控制

### `when(cond : Signal[T], then : Node, pred?)`

- 信号版显隐：真挂载 `then`、假隐藏，不销毁、状态不丢
- `pred`：值到布尔的判定，缺省按布尔真值（非布尔源需显式传）

### `when_else(cond, then, otherwise, pred?)`

- 双支常驻、按信号切换显隐，`swap_node` 实现、零重建
- `pred` 为真显示 `then`，为假显示 `otherwise`

### `when_store` / `when_store_bool` / `when_else_store` / `when_else_store_bool`

- 以上各条的 `Store[T]` 形态

### `for_list(ls : ListStore[T], build : (T, Int) -> Node, key~ : (T) -> K, eq? : (T, T) -> Bool)`

- keyed 列表差分：`build(item, index)` 构建行
- `key`：键提取函数，键相同的元素视为同一行复用（必传）
- `eq`：同键元素的内容相等判据，缺省视为相等——会变化的字段各自做成 Store，不要靠换元素触发重挂

### `for_list_indexed(ls, build)`

- 按下标对齐（等价于无 `:key`）：长度收缩时才卸载多余行，改一格重挂那行

> 整棵替换内容走 `bind_node`；`ListStore` 的键控差分属 `@base` 响应式层（详见 [declarative.md](declarative.md)）。

## 拖放（应用内，三平台同构）

### `drag_source(content : Node, payload? : () -> DragData?, threshold?=4.0, external?=false, on_external?, handle?)`

- 拖源：`content` 上按下并拖出 `threshold` 像素后调用 `payload()` 取数据开拖
- `external=true` 先尝试系统级拖出（三平台已接），失败自动回落应用内会话
- `on_external`：系统级拖出结果回调，收 `Result[DragEffect, DragError]`
- `payload()` 惰性求值，未过阈值按普通点击处理

### `drop_target(content : Node, on_drop? : (DragData, Double, Double) -> Unit, accept? : (DragData) -> Bool)`

- 落点：悬停描主题主色高亮；松手按 `accept`（默认全收）判定是否接收，接收则调用 `on_drop`（坐标为落点位置）

> 拖源内容中不要放置按钮：指针事件按最深优先派发，交互控件会截获按下事件。`DragData` = `Text` / `Html` / `Paths` / `Img`（`@widget`）。

## 悬停与光标

### `hover_group(children, on_click?, padding?=8.0, row_gap?=4.0, width?=0.0, background_color?="", hover_bg?="", class?, handle?)`

- 悬停组：组内任意位置（含全部子控件）悬停即整组进入悬停态换底色，点击（按下后松开仍在组内）触发 `on_click`；悬停态是父链语义、无需轮询指针
- `background_color` / `hover_bg`：常态底色与悬停底色，空串走主题推导

### `cursor_group(children, direction?, row_gap?, column_gap?, padding?, width?, cursor?=CURSOR_HAND, handle?)`

- 光标组：组内任意位置使用 `cursor` 形状；子控件自行指定形状时以子控件为准，其余回落组形状

内置组合控件走同一套语义：radio 行、月历格与翻月箭头、表格行、导航项等整块可点击的组合件在块根设手型光标；禁用或不可选的部位（禁用的 radio 组、跨月日历格）不发请求，回默认箭头。

## 声明式挂载

### `mount_window(children : Array[Node], title?="", width?=800, height?=600, handle? : (App) -> Unit)`

- 声明一棵树并装入窗口：创建宿主（窗口 + 事件循环 + 浮层图层 + 输入法通道）→ 挂载 → 交回调用方 `run`
- `handle`：挂载后收到 `App` 句柄，用于 `follow_system_theme` 等宿主操作
- 无显示服务时返回 `None`
- 不提供 `center` / `on_close` 参数：居中交系统窗口管理器，关闭即停宿主循环，收尾代码写在 `run()` 之后

### `mount_window_render(render : () -> Array[Node], title?, width?, height?, handle?)`

- render 槽形态，与静态数组二选一：`render` 在挂载时调用一次构建首帧，此后的响应全靠树内 `for_list` / `when` / `*_dyn` 自订阅自差分

## 窗口显隐事件

### `App::on_hidden(f : () -> Unit)`

- 本窗被隐藏驻留（`window().hide()` 的真实转换）时回调；可注册多个，按注册顺序触发
- 回调在下一拍事件批内执行，此刻窗口已撤出屏幕

### `App::on_shown(f : () -> Unit)`

- 本窗从隐藏驻留唤回（`show()` 的真实转换）时回调；首次显示不触发，只有隐藏过的窗口才有「唤回」

两条保证：**隐藏清输入法会话**——隐藏不产生平台失焦事件，宿主在隐藏拍执行与「整窗失焦」相同的交接（在途 commit 归当前控件、清组合串显示、打断引擎侧组合），唤回后不残留组合串；**焦点栈不动**——唤回时控件焦点保持原状。演示见 showcase「窗口」页的驻留探针窗（显隐计数回显 + 「2 秒后自动隐藏」验证组合串清理）。

## 组件库文档索引

- 教程与第一扇窗：[tutorial.md](tutorial.md)
- 声明式树 / `Store` / `Signal`：[declarative.md](declarative.md)
- 布局样式（`Style` 字段与 `class` 通道）：[layout.md](layout.md)
- 系统能力（`@sys`）：[system-capabilities.md](system-capabilities.md)
