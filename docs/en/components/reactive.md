# Reactive controls

`Store` / `Signal` / `ListStore` semantics are in [Declarative & reactivity](../guide/declarative.md); below are the signatures of the in-tree reactive controls.

### `when(cond : Signal[T], then : Node, pred?)`

- Signal show/hide: true mounts `then`, false hides it — nothing is destroyed, state survives; `when_bool` is the common boolean-source form

### `when_else(cond, then, otherwise, pred?)`

- Both branches stay resident and the signal switches visibility; `swap_node` lands the change with zero rebuilds; `when_else_bool` is the boolean-source form

### `when_store` / `when_store_bool` / `when_else_store` / `when_else_store_bool`

- The `Store[T]` forms of the above; the `_bool` suffix marks the common boolean-source tier (one set each for `Signal` / `Store`)

### `follow_store(s)`

- Subscribes to a `Store` purely to request a repaint (value change → `invalidate`); unsubscribes with the current recycle bundle — for custom blocks wired to external state

### `for_list(ls : @base.ListStore[T], build : (T, Int32) -> Node, key~, eq?)`

- Keyed list diff: `build(item, index)` builds each row; the default criterion is "same key, same value", so mutable fields become their own Store

### `for_list_indexed(ls, build)`

- Index-aligned, equivalent to no `:key`: extra rows unload only when the length shrinks

> Replacing the whole tree goes through `bind_node`; `ListStore` keyed diffing belongs to the `@base` reactive layer (details in [Declarative & reactivity](../guide/declarative.md)).
