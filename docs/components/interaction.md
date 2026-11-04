# Drag, hover & window events

General conventions: see [Components overview](index.md#conventions-read-this-first).

## Drag & drop (in-app, identical across the three platforms)

### `drag_source(content : Node, payload? : () -> DragData?, threshold?=4.0, external?=false, on_external?)`

- Drag source: after pressing on `content` and dragging `threshold` pixels, `payload()` is called to fetch the data and start the drag; `external=true` first tries a system-level drag-out (Windows/Linux wired), and falls back to an in-app session automatically if it fails

### `drop_target(content : Node, on_drop? : (DragData, Double, Double) -> Unit, accept? : (DragData) -> Bool)`

- Drop target: hover highlights with the theme accent; on release `accept` (defaults to accepting everything) decides, and an accepted drop calls `on_drop`

> Don't put a button inside a drag source: pointer events go deepest-first, so the interactive widget eats the press. `payload()` is lazy — under the threshold the gesture stays a normal click. `DragData` = `Text`/`Html`/`Paths`/`Img` (`@widget`). Cross-application system drag & drop is covered in the platform batches of [adaptation.md](https://github.com/lb091188/moonbit-native-gui/blob/master/experience/adaptation.md).

## Hover & cursor groups

### `hover_group(children, on_click?, …)`

- Hover group: hovering anywhere inside, including all children, puts the whole group into hover state and swaps its background; a click fires `on_click`; hover state in this stack is already parent-chain semantics, so no pointer polling is needed

### `cursor_group(children, direction?, row_gap?, column_gap?, padding?, width?, cursor?=CURSOR_HAND, handle?)`

- Cursor group: any position inside uses the `cursor` shape; a child that requests its own shape wins, the rest fall back to the group's shape

Built-in composite controls follow the same semantics: clickable blocks such as radio rows, calendar cells and month arrows, table rows and nav items all request the hand cursor at the block root; disabled or unpickable parts (a disabled radio group, out-of-month calendar cells) make no request and fall back to the default arrow.

### `text_sel_new(ed)` / `TextSel::sync(sel, text)`

- The low-level selection state for read-only text: prepare a read-only Editor (the full text is the selection range), copies go through the system slot; `sync` on text change (clears the selection, no offset migration). The ready-made `selectable` tiers already embed this chain — reach for it directly only when self-drawn text needs selection

## Window show/hide events

### `WindowHost::on_hidden(f : () -> Unit)`

- Fires when this window has just been hidden from the screen (a real transition of `window().hide()`); register several, they fire in registration order. Runs inside the next event batch, when the window is already off screen

### `WindowHost::on_shown(f : () -> Unit)`

- Fires when this window is woken back from its hidden residency (a real transition of `show()`); the first showing does not fire — only a window that has been hidden has a "wake-up"

Two guarantees: **hiding clears the IME session** — hiding produces no platform focus-loss event, so the host performs the same handover as for a whole-window focus loss on the hidden tick (in-flight commits go to the current widget, the composition string display is cleared, the engine-side composition is interrupted); after wake-up no half-typed pinyin lingers. **The focus stack is untouched** — widget focus survives the round trip, same tier as a whole-window focus loss. For a demo see the residency probe window on the showcase "Window" page (show/hide counter readout plus an "auto-hide after 2s" switch that verifies composition clearing).
