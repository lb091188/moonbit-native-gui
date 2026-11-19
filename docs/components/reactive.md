# 响应式控制

`Store` / `Signal` / `ListStore` 的语义见[声明式与响应式](../guide/declarative.md)；以下是树内响应式控件的签名。

### `when(cond : Signal[T], then : Node, pred?)`

- 信号版显隐：真挂载 `then`、假隐藏，不销毁、状态不丢
- `pred`：值到布尔的判定，缺省按布尔真值（非布尔源需显式传）

### `when_else(cond, then, otherwise, pred?)`

- 双支常驻、按信号切换显隐，`swap_node` 实现、零重建
- `pred` 为真显示 `then`，为假显示 `otherwise`

### `when_store` / `when_store_bool` / `when_else_store` / `when_else_store_bool`

- 以上各条的 `Store[T]` 形态；`_bool` 结尾是布尔源的常用档（`Signal`/`Store` 各一组）

### `follow_store(s)`

- 订阅一个 `Store` 只为请求重绘（值变即 `invalidate`）；退订随本代回收袋——自绘块接外部状态用

### `for_list(ls : ListStore[T], build : (T, Int32) -> Node, key~ : (T) -> K, eq? : (T, T) -> Bool)`

- keyed 列表差分：`build(item, index)` 构建行
- `key`：键提取函数，键相同的元素视为同一行复用（必传）
- `eq`：同键元素的内容相等判据，缺省视为相等——会变化的字段各自做成 Store，不要靠换元素触发重挂

### `for_list_indexed(ls, build)`

- 按下标对齐（等价于无 `:key`）：长度收缩时才卸载多余行，改一格重挂那行

> 整棵替换内容走 `bind_node`；`ListStore` 的键控差分属 `@base` 响应式层（详见[声明式与响应式](../guide/declarative.md)）。
