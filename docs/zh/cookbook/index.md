# 场景总览

按「我想做 X」检索，分四页：[布局](layout.md)、[交互](interaction.md)、[样式与主题](theme.md)、[系统能力](system.md)。工程从零起步见[上手体验](../guide/tutorial.md)。

## 公共前提

`moon.pkg` 的 import 用这一份（各场景按需引用）：

```
import {
  "NoahLiu/yoga-mbt/src" @yoga,
  "NoahLiu/native-gui/base" @base,
  "NoahLiu/native-gui/shell" @shell,
  "NoahLiu/native-gui/widget" @widget,
  "NoahLiu/native-gui/ui",
  "NoahLiu/native-gui/style" @style,
  "NoahLiu/native-gui/sys" @sys,
  "NoahLiu/native-gui/theme" @theme,
}
```

- 布局类场景给出节点树，替换 `mount_window` 的第一个参数；交互类场景是完整程序。
- 两条写入路径：构造器命名参数（`padding=` / `width=` …）与 `class=[@style.style(...)]` 样式块；`class` 数组尾赢，同名属性后者生效。见[布局样式](../guide/layout.md)。
- flex 容器两根轴：`col` 主轴纵向、`row` 主轴横向；`justify_content` 管主轴、`align_items` 管交叉轴。

## 场景检索表

| 我想… | 关键 API | 场景 |
|---|---|---|
| 内容居中（横/纵/双向） | `align_items` / `justify_content` | [布局 · 内容对齐](layout.md#内容对齐) |
| 顶栏 + 内容 + 底栏 | `col` + `grow` + `scroll_view` | [布局 · 三段式](layout.md#顶栏-自适应内容-底栏-三段式) |
| 侧栏 + 主区 / 等分 / 可拖分栏 | `grow` / `width_percent` / `split` | [布局 · 侧栏与分栏](layout.md#侧栏与分栏-固定宽-弹性-等分-可拖) |
| 内容滚动（纵/横） | `scroll_view` + `ScrollState` | [布局 · 内容超高滚动](layout.md#内容超高滚动) |
| 标签超宽换行 | `flex_wrap=@yoga.FlexWrap::Wrap` | [布局 · 标签换行](layout.md#一排标签超宽自动换行) |
| 按钮靠右 | `justify_content=FlexEnd`（class） | [布局 · 按钮右对齐](layout.md#底部按钮右对齐) |
| 输入框取值 / 回车提交 | `input` + `Store[String]` + `on_enter` | [交互 · 输入框](interaction.md#输入框取值与回车提交) |
| 列表增删 | `ListStore` + `for_list` | [交互 · 列表增删](interaction.md#列表增删项) |
| 确认弹窗 | `dialog` + `Store[Bool]` | [交互 · 确认弹窗](interaction.md#确认弹窗) |
| 操作反馈轻提示 | `toast_layer` | [交互 · 轻提示](interaction.md#轻提示) |
| 定时刷新 | `@shell.set_timeout` 回调尾自排 | [交互 · 定时刷新](interaction.md#定时刷新) |
| 按条件显隐 | `when_store_bool` / `when_else_store` | [交互 · 条件显隐](interaction.md#按条件显隐) |
| 表单校验 | `form` + `form_item(error=)` | [交互 · 表单校验](interaction.md#表单项与错误提示) |
| 开第二个窗口 | `WindowHost::open_window` + `mount` | [交互 · 多窗口](interaction.md#打开第二个窗口) |
| 换主色 / 跟随深浅 | `theme_apply` / `follow_system_theme` | [样式主题 · 换主色](theme.md#换主色与跟随系统深浅) |
| 控件 hover 定制 | `class` + `hover=` + `transition_ms` | [样式主题 · 交互样式](theme.md#给控件交互样式) |
| 打开链接 / 定位文件 | `@sys.open_url` / `@shell.reveal_in_file_manager` | [系统能力 · 打开与定位](system.md#打开链接与定位文件) |
| 复制到剪贴板 | `@sys.clipboard_set_text` | [系统能力 · 剪贴板](system.md#复制到剪贴板) |
| 桌面通知 | `@shell.notify_send` | [系统能力 · 桌面通知](system.md#桌面通知) |
| 画控件拼不出的内容 / 自绘区接键鼠（画板、节点编辑器） | `node_of_new` + `on_draw` / `on_pointer` / `on_key` | [自绘与键鼠](../components/custom-draw.md) |

## 下一步

- 控件签名：[组件总览](../components/index.md)；状态绑定：[声明式与响应式](../guide/declarative.md)；布局字段全集：[布局样式](../guide/layout.md)。
- 场景组合的完整程序：`cd examples/showcase && moon run .`，每页源码在 `examples/showcase/pages/*.mbt`。
