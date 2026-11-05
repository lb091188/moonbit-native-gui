# 布局与容器

通用约定（尺寸口径、`class` 覆盖全序、值控件与 `Store`）见[组件总览](index.md#约定)。

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
- `state`：`ScrollState` 持有滚动偏移，外部可读写；`set_follow_bottom(true)` 开启「跟随底部」——内容变高时自动贴底（首帧布局完成后即生效），用户手动滚离底部暂停、回到底部恢复，宿主追加内容后不必重复调 `scroll_to_bottom`（首帧前几何未知，直接调它是空操作）
- `height`：视口高度，`0` 表示由父级决定
- `hscroll`：开启横向滚动
- `min_content_width`：内容宽两档——缺省 `0.0` 为自然宽档 `max(子项自然宽, 视口宽)`（长代码行 / 表格适用）；给定正值 `N` 为下限档 `max(N, 视口宽)`，不读子项自然宽，更宽的内容由它自己的视口滚动

> 滚动偏移在绘制期平移、不进布局；`ScrollState` 由 `ui/scroll.mbt` 提供。自绘里画 4px 圆角矩形可直接用门面 `@render.Painter::fill_round_rect`（组件层惯用名 `fill_round_rect` 是同一实现的上收入口）。
