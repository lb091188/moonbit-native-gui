# 组件总览（@ui）

控件与组件库住在 `NoahLiu/native-gui/ui`（别名 `@ui`），每个组件是返回 `@widget.Node` 的构造器，参数以代码为准（`gui/ui/*.mbt`）。

> 各组件的可运行示例集中在 `examples/components`（每页一个源文件）。

## 家族一览

| 分页 | 内容 |
|---|---|
| [布局与容器](containers.md) | `view` / `col` / `row` / `panel` / `split` / `scroll_view` |
| [文本与基础控件](basics.md) | `text` / `image` / `icon` / `code_view` / `code_editor` / `terminal` / `gif` / 分隔线 |
| [表单控件](form.md) | `button` / `input` / `checkbox` / `select` / `slider` / `form` 等 |
| [日期与时间](date.md) | `calendar` / `date_picker` / 区间选择器 |
| [数据展示](display.md) | 标签 / 徽标 / 卡片 / 进度 / 时间线 / 轮播 |
| [表格与虚拟列表](table.md) | `table` / `table_v` / `virt_list` / `sticky_list` |
| [导航](navigation.md) | `menu` / `tabs` / `breadcrumb` / `pagination` / `tree` 等 |
| [浮层与消息](overlay.md) | `dialog` / `message_box` / `popover` / `tooltip` / 右键菜单 |
| [拖放、悬停与窗口事件](interaction.md) | 拖源与落点 / 悬停组与光标组 / 窗口显隐 |
| [响应式控制](reactive.md) | `when` / `for_list` / 显隐与列表差分 |

## 约定

- 组件参数均为类型化参数（尺寸、颜色、值），不接受 CSS 字符串；外观覆盖用命名参数或 `class? : Array[@style.Style]`，同名属性按一条全序覆盖：命名参数（属性）< `class`（数组靠后者为准）< 组件收的显式规则块（`style(...)`/`anon`）；样式字段清单与全序见[布局样式](../guide/layout.md)
- 尺寸单位为逻辑像素；`width` / `height` 给 `0` 通常表示按内容或由父级决定
- 值类控件（复选 / 单选 / 开关 / 滑块 / 输入框 / 进度）的当前值由 `@base.Store[T]` 持有：组件读写它，外部修改即刷新
- 展示类控件另有两条取值入口：`x` 收静态值，`x_dyn` 收 `Signal[T]`
- 事件回调统一命名为 `on_*`（`on_click` / `on_change` / `on_drop` …）
- `handle?` 返回内部 `@widget.Widget` 句柄，用于框架未暴露的操作，不是事件回调
- `disabled?` / `enabled?` 控制禁用态；`focus_id?` 指定 Tab 焦点序（缺省自动分配）
- 表单族控件默认进入 Tab 焦点链，聚焦描边转主题色；空格 / 回车激活，方向键按控件语义调值或换选
- 文本排版预设挂 `class`：`text_heading`（18 SemiBold）、`text_title`（14 SemiBold）、`text_secondary`（12 次要色）、`text_accent`（13 SemiBold 主色）；正文 13 为 `text` 缺省档，不必挂；字号读 `@theme` 字阶令牌
- 语义色 `SemanticType`：`Primary` / `Success` / `Warning` / `Danger` / `Info`；存储 theme token 名，随主题取值

## 声明式挂载

### `mount_window(children : Array[Node], title?="", width?=800, height?=600, handle? : (WindowHost) -> Unit)`

- 声明一棵树并装入窗口：创建宿主（窗口 + 事件循环 + 浮层图层 + 输入法通道）→ 挂载 → 交回调用方 `run`
- `handle`：挂载后收到 `WindowHost` 句柄，用于 `follow_system_theme` 等宿主操作
- 无显示服务时返回 `None`
- 不提供 `center` / `on_close` 参数：居中交系统窗口管理器，关闭即停宿主循环，收尾代码写在 `run()` 之后

### `mount_window_render(render : () -> Array[Node], title?, width?, height?, handle?)`

- render 槽形态，与静态数组二选一：`render` 在挂载时调用一次构建首帧，此后的响应全靠树内 `for_list` / `when` / `*_dyn` 自订阅自差分

## 相关文档

- 教程与第一扇窗：[上手体验](../guide/tutorial.md)
- 声明式树 / `Store` / `Signal`：[声明式与响应式](../guide/declarative.md)
- 布局样式（`Style` 字段与 `class` 通道）：[布局样式](../guide/layout.md)
- 系统能力（`@sys`）：[系统能力总览](../capability/sys.md)
