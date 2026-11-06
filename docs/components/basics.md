# Text & basic controls

General conventions (typed parameters, the `class` override order, `Store`-held values): see [Components overview](index.md#conventions-read-this-first).

### `text(content, font_size?=13.0, color?, weight?, family?, align?, max_width?, wrap?=true, ellipsis?, max_lines?=0, selectable?=false, class?, handle?)`

- Text, unifying `label` + `label_t`: size comes from Pango measurement and feeds the layout engine, so text participates in baseline alignment; `wrap` defaults to true (block-level paragraph semantics), single-line labels pass `wrap=false` explicitly (shrinks against row siblings and ends with …); typography tiers go through `class` (`@style.text_heading` etc.); when `wrap` is on, `max_lines`>0 clamps the line count — extra lines are cut and the last kept line ends with … (0 = unlimited); `selectable=true` makes this static text **selectable and copyable** — click to place, double-click for a word, drag to extend, Shift+click to extend further, `Ctrl/Cmd+C` or the right-click menu to copy; it stays read-only (not focusable, off the Tab chain) and the host routes the copy key to whoever holds the selection. Known edges: wrapped blocks align as a whole (not per line); a text or width change clears the selection; line clamping and the ellipsis share the default path, so the selectable range equals the visible range

### `text_dyn(sig : Signal[String], font_size?, color?, …, wrap?=true, selectable?=false, class?, handle?)`

- Signal-driven text: on change it edits the text in place and recomputes only this chain; the counterpart of the old `bind_label` and the prototype of the display `*_dyn` family

### `bind_label(store : Store[A], f : (A) -> String, font_size?, color?, handle?)`

- Declarative text binding: initial value `f(store.get())`, then every `set` updates the text in place and re-measures; always single-line

### `bind(sig : Signal[A], f : (A) -> String, font_size?, color?, handle?)`

- Text binding in signal form: takes a source signal or a `computed` derived signal directly

### `divider(text?, vertical?=false, color?, class?)`

- Divider, unifying `separator` + the labelled `divider`: empty `text` draws a plain line (`vertical` picks horizontal/vertical), with text it draws a centered breaking line

### `image(path, width?, height?, handle?)`

- Image: decodes a file (PNG/JPEG/GIF first frame); size 0 uses the original dimensions

### `icon(kind : @icons.IconKind, size?=16.0, color?, class?, handle?)`

- Vector icon: `size` is the box edge; empty colour means the theme body text colour, resolved live with the theme

### `code_view(lines : Array[String], lang?="moonbit", font_size?=13.0, line_numbers?=false, selectable?=false, handle?)`

- `copyable`: reserves a header strip on top; hovering the block reveals a small "Copy" button at the top-right that writes the whole text (joined with `\n`) to the system clipboard; `on_copied(ok)` reports the result (hook your toast here). Off by default — the strip takes no height
- Division of labour: **use `code_view` for read-only display** (stateless, light, height follows content) and **`code_editor` for editing** — both share one geometry (top 14, line numbers at x 16, code left edge = 16 + digits width + 8, right pad 8)
- Code highlight view, colours derived from the theme (a light and a dark role mapping, redrawn on theme/accent change; passing `code_theme` pins one palette on purpose): 8-language keyword tables + token coloring, optional line-number column; **width follows the container (flex 1)** — the dark panel fills the row, and when a line is wider than the container the component **ships its own horizontal scrollbar** (callers do not wrap it in `scroll_view`); height follows the line count; `selectable=true` makes the block mouse-selectable and copyable (drag across lines, double-click for a word, Shift+click to extend, `Ctrl/Cmd+C` or the right-click menu) — the line-number column never enters the selection, and a multi-line copy joins lines with `\n`; read-only and off the Tab chain

### `code_editor(store : @base.Store[String], lang?="moonbit", font_size?=13.0, line_numbers?=true, read_only?=false, rows?=12, height?=0.0, focus_id?=0, caret_on?, on_change?, class?, handle?)`

- Code editor: monospace + highlighting + line numbers + editing in one control — two-way bound via `store` (external `set` feeds the kernel back), `on_change` reports the full text on every edit
- Editing semantics shared with the input fields: click / drag / double-click word select, Shift extend, arrow keys / Home / End / PageUp-Down (pages by visible rows), Tab inserts two spaces, `Ctrl/Cmd+Z` undo-redo, `Ctrl/Cmd+A/C/X/V` interoperates with the system clipboard, IME preedit inline; `read_only` allows selection but no edits
- Highlighting is **line-incremental** (`scan_line` state machine + prefix/suffix row-aligned rescan): editing rescans only the affected lines, and a 10k-line file lays out just the visible rows on first paint (progressive scanning — jumping to an unscanned region scans on that jump)
- P2 extras: `Ctrl/Cmd+F` find (overlay bar + full-text match highlight + ▲▼ jump + Esc to close, ASCII case-insensitive); Enter **auto-indent** (inherits leading whitespace, one more level after an open bracket); **bracket matching** highlight (brackets inside strings/comments are skipped); **current-line highlight** while focused
- Width follows the container (percent 100); `height` pins the height (0 = by `rows`); long lines scroll horizontally, many lines scroll vertically with the line-number column in sync, and the caret auto-scrolls into view

### `gif(path, width?, height?, looping?=true, running?=true, state?, handle?)`

- Animated image: `looping=false` stops after one pass; a non-GIF still image draws a single frame

### `icon_button(kind, on_click?, icon_size?=16.0, box_size?=28.0, color?, disabled?)`

- Icon button: vector icon box + click callback; `box_size` is the click-box edge, `disabled` is the disabled state

### `bg_block(hex)` / `fg_block(hex)` / `border_block(hex)`

- Three colour shortcut `Style`s: in `class`, `@style.bg_block("#2A303C")` sets the background colour (the other two set text colour / border colour) — equivalent to a full `@style.style(...)`

### `watch_theme()`

- Requests a repaint when the theme changes (a single process-level subscription); custom blocks that follow the theme use it
