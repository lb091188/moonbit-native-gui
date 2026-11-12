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

### `dropdown(trigger, items : Array[String], on_select? : (Int32) -> Unit, width?=150.0, focus_id?, class?)`

- Menu button: trigger text + item list; the selection callback receives the index (`-1` when nothing is selected). `on_select` is an `(Int32) -> Unit`, unlike `select`'s Store-based contract

### `toast_layer(duration_ms? = 2600) -> (String, SemanticType) -> Unit`

- Call once while building the UI to get a push function; then from any callback `toast("Saved", @ui.Success)` — auto-dismisses and stacks

### `msgbox_icon_of(kind)` / `msgbox_icon_color_of(kind)` / `msgbox_default_code(buttons)`

- Message-box companions: the icon and icon colour for a `MsgBoxKind`, and the primary button's code in a `buttons` list — for self-drawn title bars or message-box clones

### `update_dialog(visible : Store[Bool], flow : UpdateFlow, actions : UpdateActions, current_version?, title?, width?=400, …)`

- App self-update dialog: walks the "checking → available → downloading → ready → install & restart" state machine from `flow.state`; `visible` drives open / close
- The component owns only the state machine and the view: buttons mark state first, then fire the closures injected in `actions`; results feed back through `flow.report_check / report_download / report_install` (how network and disk actually run is the wiring's business, the component does not hardcode it)
- `make_update_flow()` builds the ledger (state Store + found manifest + carrier path); `sys_update_actions(flow, manifest_url, current_version, quit)` is the shortest wiring straight into `@sys.update_*` (each action is deferred one tick so the loading state paints first; sys runs subprocesses synchronously, so the UI stalls during large downloads — a known v1 trade-off)
- The failure state offers Retry per retryable step (re-check / re-download); install failures offer no retry; Installing has no exit (the success path is relaunch + quit)
- Manifest format and the release pipeline: see [Packaging & auto-update](/guide/publish.md)
