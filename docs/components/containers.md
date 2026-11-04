# Layout & containers

General conventions (typed parameters, the `class` override order, `Store`-held values): see [Components overview](index.md#conventions-read-this-first).

### `view(children, direction?=Column, row_gap?, column_gap?, padding?, width?, height?, grow?, background_color?, border_color?, align_items?, justify_content?, class?, handle?)`

- Generic container: direction, gaps on both axes, padding, size, background and border. Size 0 fits the content; `grow=1.0` fills the remaining space

### `col(children, row_gap?, padding?, width?, height?, grow?, background_color?, border_color?, align_items?, class?, handle?)`

- Vertical layout container (the Column form of `view`)

### `row(children, column_gap?, padding?, width?, height?, grow?, background_color?, border_color?, align_items?=Center, class?, handle?)`

- Horizontal layout container (the Row form of `view`)

### `panel(title, children, padding?=10.0, row_gap?=6.0, width?, class?)`

- Titled panel: title on top, content below, panel background + border; pass skin such as corner radius through `class`

### `split(first, second, direction?=Horizontal, ratio?=0.5, min_first?, min_second?, class?, handle?)`

- Draggable split pane; unifies `hsplit`/`vsplit` with the direction parameterized

### `scroll_view(children, state : ScrollState, width?, height?, hscroll?=false, min_content_width?=0.0, class?, handle?)`

- Scroll container; `height` is the viewport height, 0 means the parent supplies it; overflow is clipped, and the scrollbar is a thumb floating on the right edge (no track, no reserved width — opaque on hover, faded otherwise). `hscroll=true` enables horizontal scrolling with two content-width modes: the default natural mode `max(children's natural width, viewport)` (for code lines / tables that cannot wrap), or — when `min_content_width` is given — the floor mode `max(that value, viewport)`, which **ignores the children's natural width**: wider content scrolls inside its own viewport, so this min-width is the only number that binds

> Scroll offset shifts at paint time and stays out of layout; `ScrollState` is provided by `ui/scroll.mbt`.
