# 拖放、悬停与窗口事件

通用约定见[组件总览](index.md#约定)。

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

## 窗口显隐事件

### `WindowHost::on_hidden(f : () -> Unit)`

- 本窗被隐藏驻留（`window().hide()` 的真实转换）时回调；可注册多个，按注册顺序触发
- 回调在下一拍事件批内执行，此刻窗口已撤出屏幕

### `WindowHost::on_shown(f : () -> Unit)`

- 本窗从隐藏驻留唤回（`show()` 的真实转换）时回调；首次显示不触发，只有隐藏过的窗口才有「唤回」

两条保证：**隐藏清输入法会话**——隐藏不产生平台失焦事件，宿主在隐藏拍执行与「整窗失焦」相同的交接（在途 commit 归当前控件、清组合串显示、打断引擎侧组合），唤回后不残留组合串；**焦点栈不动**——唤回时控件焦点保持原状。演示见 showcase「窗口」页的驻留探针窗（显隐计数回显 + 「2 秒后自动隐藏」验证组合串清理）。
