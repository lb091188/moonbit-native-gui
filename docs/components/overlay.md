# Overlays & messages

Overlays — dialog / popover / menu / tooltip — all open on the window-wide **overlay layer**, so they naturally sit above content and other overlays; no permanently hidden tree is needed. Anchored popups (select, popover, date/time panels, tooltips) are then fitted to that layer's box: if a list does not fit below its trigger it opens above it, if it overflows the right edge it aligns to the trigger's right, and anything still larger than the window is clamped inside — popups never get cut off by the window edge.

### `dialog(visible : Store[Bool], title, children, confirm_text?="确定", cancel_text?="取消", on_confirm?, on_cancel?, close_on_mask?=false, …)`

- Dialog: `visible` drives open/close; title bar with +✕ + content + footer buttons, and an empty label hides that button; all three exits close first, then call back

### `message_box(visible : Store[Bool], title, content, kind?=Information, informative?, buttons?=[("确定",1)], on_response?, on_dismiss?, close_on_mask?=false, width?)`

- Self-drawn message box, coexisting with the native form: `buttons` are `(label, code)` and the first is the primary default button; Enter = first button, while ✕/Esc/mask click go through `on_dismiss` without a code; response codes are chosen by the caller

### `popover(trigger : Node, content : Node, width?, height?, class?, handle?)`

- Popover: clicking the trigger drops arbitrary content below it, clicking again closes; `width/height` of 0 size to the content

### `tooltip(content : Node, tip : String, delay_ms?=500, class?, handle?)`

- Tooltip: after a `delay_ms` hover it opens a bubble below and closes on leave; it rides the host's `on_hover_change`, a parent-chain semantics

### `context_menu_for(content : Node, items : Array[(String, () -> Unit)], width?=150.0, handle?)`

- Right-click context menu: in `items` the label `"-"` draws a separator; right-click dispatch is "ancestor-first"
