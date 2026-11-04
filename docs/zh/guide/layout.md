# 布局样式（@style + @yoga）

布局采用 CSS Flexbox（Level 1）规范，由 MoonBit 实现的布局引擎 yoga-mbt 驱动。样式是 `@style` 包中的 MoonBit 值，`Style` 结构体字段与 CSS 属性同名（连字符写作下划线）。组件既接受命名参数（`padding=` / `row_gap=` 等），也接受 `class? : Array[@style.Style]` 叠加样式块。

## 两种设置方式

- **命名参数**：`@ui.col` / `@ui.row` / `@ui.view` 直接接受 `padding` / `row_gap` / `column_gap` / `width` / `height` / `grow` / `align_items` / `background_color` / `border_color` 等常用字段。它们是 `Style` 对应字段的简便写法，最终折入匿名样式块。
- **`class` 通道**：接受一个或多个由 `@style.style(...)` 构造的 `Style` 块；同名属性以数组中靠后者为准。所有组件都接受 `class?`。

两种方式合并为一份 `Style`，作用于控件与布局节点。合并走一条固定全序：**继承 < 默认（组件内置观感）< 属性（构造散参数）< `class`（数组靠后者覆盖前者）< `style(...)`（组件收的显式规则块，如 `text_dyn` 的 `anon`）**，越靠后越赢。组件函数体里的内部布局（弹层轨道宽、固定行高这类）不进这条链，不对外样式化。

## 布局字段速查（`Style`）

`@style.style(...)` 的关键字参数即字段名，全部可选；`None` 表示不设置，使用引擎默认值。

### 尺寸

| 字段 | 含义 |
|---|---|
| `width` / `height` | 定尺寸，逻辑像素 |
| `width_percent` / `height_percent` | 百分比尺寸，相对父内框 |
| `min_width` / `min_height` | 最小尺寸，见下方 min:auto 行为 |
| `max_width` / `max_height` | 最大尺寸 |

### 盒内间距

| 字段 | 含义 |
|---|---|
| `padding` | 四边统一内边距，简写 |
| `padding_left` / `padding_right` / `padding_top` / `padding_bottom` | 单边内边距 |
| `margin` | 四边统一外边距，简写 |
| `margin_left` / `margin_right` / `margin_top` / `margin_bottom` | 单边外边距 |

### Flex

| 字段 | 取值 | 含义 |
|---|---|---|
| `flex_direction` | `Row` / `RowReverse` / `Column` / `ColumnReverse` | 主轴方向，默认 `Row`，web 语义 |
| `flex_wrap` | `NoWrap` / `Wrap` / `WrapReverse` | 是否换行，默认 `NoWrap` |
| `flex` | `Double` | 弹性增长因子，配合 `grow` |
| `justify_content` | `FlexStart` / `FlexEnd` / `Center` / `SpaceBetween` / `SpaceAround` / `SpaceEvenly` | 主轴对齐 |
| `align_items` | `Stretch` / `FlexStart` / `FlexEnd` / `Center` / `Baseline` | 交叉轴对齐，子项默认 |
| `align_self` | 同 `align_items` | 单项覆盖父的 `align_items` |
| `row_gap` / `column_gap` / `gap` | `Double` | 换行行间距 / 列间距 / 统一简写 |

### 定位与层序

| 字段 | 取值 | 含义 |
|---|---|---|
| `position` | `Relative` / `Absolute` | 定位模式 |
| `top` / `right` / `bottom` / `left` | `Double` | 相对或绝对偏移 |
| `z_index` | `Int` | 绘制层序键，值越大越后绘制 |
| `display` | — | 参与布局或隐藏；`Style` 字段，绘制与命中都跳过 |

枚举类型 `FlexDirection` / `AlignItems` / `JustifyContent` / `FlexWrap` / `PositionType` 与组件命名参数共用同一套定义，均来自 yoga-mbt，写作 `@yoga.Row` / `@yoga.Center` 形式，或直接传给 `view(direction=…)`。

## 关键行为

**min:auto 会使滚动与换行容器失效。** Flex 子项的默认最小尺寸是 `auto`（即内容尺寸）。滚动视口或换行容器若不显式设置 `min_width` / `min_height = 0.0`，会被内容撑到自然尺寸，导致无法滚动或整行溢出。库内容器 `scroll_view` / `virt_list` 及 showcase 侧栏已处理此项；自建滚动或换行结构时需自行设置 `min_width=0.0, min_height=0.0`。

**换行容器须为列方向。** `flex_wrap=Wrap` 只有在容器为**列**方向时才能正常折行：`row` 容器的交叉轴不拉伸，换行子项按内容定宽会堆叠为竖排。标签组这类「超宽自动换行」的场景应放入列容器，且每层显式设置 `min_* = 0`。

**gap 计入弹性分配。** 弹性分配（grow/shrink）计算自由空间时会先扣除 `gap × (n-1)`，因此「固定项 + grow 项 + gap」的组合不会溢出。引擎内置行为，无需额外处理。

**文本尺寸参与布局。** `@ui.text` / `bind_label` 的内容尺寸来自 Pango 测量，`measure` 与 `baseline` 均接入布局引擎，文本可参与基线对齐、按内容确定宽高；折行与截断由 `max_width` + `wrap` + `ellipsis` 三个参数控制。

## 增量重排

布局是增量的：属性与结构的变更只重算受影响的子树，`bind_label` 修改文本只重算该条链路，整帧布局开销接近常数。调用方无需干预；这也是推荐就地修改而非整棵重建的原因，见 [declarative.md](declarative.md)。

## 相关文档

- 组件与命名参数：[组件总览](../components/index.md)
- 布局场景怎么写（居中、三段式、分栏、滚动、换行）：[布局场景](../cookbook/layout.md)
- 响应式与原位替换：[declarative.md](declarative.md)
