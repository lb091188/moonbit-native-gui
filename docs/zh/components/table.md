# 表格与虚拟列表

通用约定见[组件总览](index.md#约定)。

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
