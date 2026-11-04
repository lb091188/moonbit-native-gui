# Reactive controls

`Store` / `Signal` / `ListStore` semantics are in [Declarative & reactivity](../guide/declarative.md); this page is the signature quick-reference for in-tree reactive controls.

### `when(cond : Signal[T], then : Node, pred?)`

- Signal show/hide: true mounts `then`, false hides it — nothing is destroyed, state survives; `when_bool` is the common boolean-source form

### `when_else(cond, then, otherwise, pred?)`

- Both branches stay resident and the signal switches visibility; `swap_node` lands the change with zero rebuilds; `when_else_bool` is the boolean-source form

### `when_store` / `when_store_bool` / `when_else_store` / `when_else_store_bool`

- The `Store[T]` forms of the above

### `for_list(ls : @base.ListStore[T], build : (T, Int) -> Node, key~, eq?)`

- Keyed list diff: `build(item, index)` builds each row; the default criterion is "same key, same value", so mutable fields become their own Store

### `for_list_indexed(ls, build)`

- Index-aligned, equivalent to no `:key`: extra rows unload only when the length shrinks

> Replacing the whole tree goes through `bind_node`; `ListStore` keyed diffing belongs to the `@base` reactive layer (details in [Declarative & reactivity](../guide/declarative.md)).
