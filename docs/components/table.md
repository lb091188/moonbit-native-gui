# Tables & virtual lists

General conventions: see [Components overview](index.md#conventions-read-this-first).

### `table(columns : Array[TableColumn], rows : Store[Array[TableRow]], width?=560.0, row_height?=36.0, selection?, sort?, on_row_click?, class?, handle?)`

- Table: header sorting — a click toggles a `TableSort` and the sort itself is the caller's job; zebra stripes, hover, row selection; column edges drag to resize

### `table_v(columns, rows : Store[Array[TableRow]], width?=560.0, height?=360.0, row_height?=32.0, selection?, sort?, on_row_click?, class?, handle?)`

- Virtual table at 10k+ rows: fixed header + only the visible range is mounted, sharing the header/row widgets with `table`

### `virt_list(items : Store[Array[T]], height : Double, row_height : Double, row_of : (Int, T) -> Node, width?, overscan?=2, rev?, class?, handle?)`

- Virtual list: `row_of(i, item)` builds row i; `i` is the source index, and sort/filter ordering stays the caller's choice

### `sticky_list(groups : Array[(String, Array[Node])], st : StickyList, width?, height?, head_h?=28.0, class?, handle?)`

- Sticky list: group headers pin to the top on scroll; the "current group" is inferred each frame from layout rectangles

> `TableColumn::make(...)` and `TableRow::make(cells : Array[String])` build columns and rows; `sort_rows(rows, sort)` (`ui/table.mbt`) gives a number-first, stable sort as a reference.
