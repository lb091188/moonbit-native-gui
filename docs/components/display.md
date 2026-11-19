# 数据展示

展示类另有 `*_dyn` 信号版：`text` 换 `Signal`、就地改字重算宽、退订随回收袋。通用约定见[组件总览](index.md#约定)。

### `tag_of_type(text, t : SemanticType, font_size?=12.0, class?)`

- 语义色标签，浅底 + 主色字；`t` 选语义色；`tag_of_type_dyn` 收信号

### `tag(text, color, font_size?=12.0, class?)`

- 自定色标签，实底 + 白字；`color` 给色值；`tag_dyn` 收信号

### `badge_count(value : Int32, max?=99, color?, class?)`

- 数字徽标：超过 `max` 显示「max+」；`badge_count_dyn` 收 `Signal[Int32]`

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

### `carousel_goto(handle, i)` / `carousel_pause(handle, v)` / `carousel_stop(handle)`

- 轮播程序化控制：跳到第 i 页、暂停/恢复自动轮播、停止（不可恢复；卸载前必须调，自排延时链不认识视图已移除）

### `alert(title, description?, t?=Info, closable?=false, on_close?, class?)`

- 页内提示条（常驻页面，不自动消失）：语义色图标 + 标题 + 描述；`closable` 出 ✕、关闭走 `on_close`。要自动消失的轻提示用 `toast_layer`

### `type_color(t)` / `type_light_color(t)`

- 语义色 `SemanticType` 对应的主题色值：实底档与浅底档；自绘或钉色时取，不写死十六进制

### `*_dyn` 信号版入口

- `tag_dyn` / `tag_of_type_dyn` / `badge_count_dyn` / `avatar_dyn` / `statistic_dyn`：静态版收值，`_dyn` 版收 `Signal`，值变就地改

