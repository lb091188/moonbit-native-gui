# Form controls

Value controls hold their current value in a `Store[T]`: an external change refreshes the control, an interaction writes back. General conventions: see [Components overview](index.md#conventions-read-this-first).

### `button(text, on_click?, variant?=Soft, color?, background_color?, font_size?, min_width?, focus_id?, disabled?, enabled?, class?, handle?)`

- Button, `variant : ButtonVariant` = `Solid`/`Soft`/`Border`/`Text`/`Danger`; Space/Enter activate from the keyboard

### `input(store : Store[String], placeholder?, password?=false, read_only?=false, font_size?, family?, width?, focus_id?, caret_on?, …)`

- Single-line input: selection / double-click word select / undo-redo / Ctrl+A-C-V / placeholder / read-only / password mask / inline IME, all with full semantics; `clearable` shows a ✕ on hover/focus and clicking it clears; right-click opens an edit menu (cut / copy / paste / select all; no copy or cut on password fields); Ctrl/Cmd+C/X/V talk to the system clipboard by default (`use_system_clipboard(false)` to opt out)

### `textarea(store : Store[String], placeholder?, rows?=3, width?=260.0, height?, font_size?, family?, read_only?, focus_id?, caret_on?, …)`

- Multi-line input: greedy wrapping (spaces / Latin words / CJK per character) + vertical scroll; up/down keys move across display lines; right-click opens the same edit menu; Ctrl/Cmd+C/X/V talk to the system clipboard by default

### `checkbox(content, state : Store[Bool], disabled?, enabled?, focus_id?, font_size?, class?, handle?)`

- Checkbox + text label; the whole row is the click area; Space/Enter toggle

### `radio_group(options : Array[String], state : Store[Int], disabled?, direction?=Row, gap?=12.0, class?)`

- Radio group: `options` map to values 0..n-1 in order; Space/Enter select the current item, arrow keys move the selection and wrap around

### `switch(state : Store[Bool], on_text?, off_text?, disabled?, focus_id?, on_change?, class?)`

- Switch: a 40×20 pill + 16 round knob, with optional on/off labels; Space/Enter toggle; `on_change(Bool)` fires on user toggles (external writes do not)

### `slider(state : Store[Double], min?=0.0, max?=100.0, step?=0.0, width?=160.0, disabled?, focus_id?, class?, handle?)`

- Slider: a press takes the value, dragging follows the pointer, `step>0` snaps; arrow keys step, Home/End jump to the ends

### `stepper(state : Store[Int], min?=0, max?=999, step?=1, focus_id?, class?)`

- Number stepper `[-] value [+]`: one boxed three-segment control whose middle segment is a real number field (digits only; written back and clamped on Enter or on blur); the button at a reached bound renders disabled (gray fill + secondary text, arrow cursor); gaining focus (click / Tab / buttons / Up-Down) selects the whole number so typing replaces it; Up/Down increment/decrement, Left/Right move the caret

### `select(options : Array[String], value : Store[String], on_change?, …)`

- Dropdown, the single entry — the editable form goes through `editable=true`: the popup opens on the overlay layer, ↑↓ highlight + Enter picks + Esc closes

### `color_picker(value : Store[String], colors?=[内置 15 色], on_change?, …)`

- Color picker: field + swatch grid; Enter opens, ←/→ move a cell, ↑/↓ move a row, Enter picks

### `rate(value : Store[Int], max?=5, on_change?, …)`

- Rating: vector five-point stars + hover pre-lighting; arrow keys change stars, Home/End clear or max out

### `form_item(label_text, control : Node, label_width?=90.0, error?=Store[String], handle?)`

- Form item: fixed-width right-aligned label + control; a permanent error row below, its line height always reserved so errors never jump the layout

### `form(title, items : Array[Node], row_gap?=8.0, handle?)`

- Form: group title + a column of form items

### `link(text, on_click : () -> Unit, font_size?, class?, handle?)`

- Link text: theme colour, underline on hover, fires on release
