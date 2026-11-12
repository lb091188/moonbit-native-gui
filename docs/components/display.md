# Data display

The display family also has `*_dyn` signal forms: `text` becomes a `Signal`, the label is edited in place and the width recomputed, and unsubscribing rides the unsubscribe bundle. General conventions: see [Components overview](index.md#conventions-read-this-first).

### `tag_of_type(text, t : SemanticType, font_size?=12.0, class?)`

- Semantic-colour tag: light background + accent text; `tag_of_type_dyn` takes a signal

### `tag(text, color, font_size?=12.0, class?)`

- Custom-colour tag: solid background + white text; `tag_dyn` takes a signal

### `badge_count(value : Int32, max?=99, color?, class?)`

- Number badge: over `max` it shows "max+"; `badge_count_dyn` takes a `Signal[Int32]`

### `badge_dot(size?=8.0, color?, class?)`

- Dot badge: no number, it just signals "something new"

### `avatar(text, size?=32.0, background_color?, class?)`

- Avatar: centers the first character of the text; `avatar_dyn` takes a signal

### `statistic(title, value, precision_color?, prefix?, class?)`

- Statistic: small title + value, with optional prefix/suffix; `statistic_dyn` takes a `Signal[String]`

### `card(children, title?, padding?=12.0, row_gap?=6.0, class?)`

- Card: optional title bar + content area, panel background + border

### `descriptions(items : Array[(String, String)], title?, label_width?=96.0, class?)`

- Description list: `(label, value)` pairs, one row each

### `empty(description?="暂无数据", class?)`

- Empty state: icon + description, centered

### `result(title, subtitle?, t?=Success, class?)`

- Result page: semantic icon + title + subtitle

### `progress(state : Store[Double], max?=1.0, width?=200.0, height?=6.0, color?, class?, handle?)`

- Progress bar: `state` runs 0..max, display-only

### `progress_line(state, max?=1.0, width?=200.0, label_side?=true, class?)`

- Progress with a percentage label

### `timeline(items : Array[(String, String, SemanticType)], item_height?=56.0, gap?=12.0, class?)`

- Timeline: `(title, description, semantic colour)` rows of equal height; the connector line spans row gaps without breaking

### `carousel(pages : Array[Node], width?=360.0, height?=180.0, interval_ms?=3000, rotation?=CarouselHandle::make(), class?, handle?)`

- Carousel: panel sequence + arrows + indicator dots; auto-advances when `interval_ms>0` and pages > 1, pauses on hover; `rotation` holds an external `CarouselHandle` driven by `carousel_goto` / `carousel_pause` / `carousel_stop` (must call `carousel_stop` before unmounting)

### `carousel_goto(handle, i)` / `carousel_pause(handle, v)` / `carousel_stop(handle)`

- Programmatic carousel control: jump to page i, pause/resume auto-advance, stop (not recoverable; required before unmounting — the self-arming delay chain does not know the view is gone)

### `alert(title, description?, t?=Info, closable?=false, on_close?, class?)`

- In-page banner (stays on the page, does not auto-dismiss): semantic icon + title + description; `closable` shows a ✕ and closes via `on_close`. For self-dismissing strips use `toast_layer`

### `type_color(t)` / `type_light_color(t)`

- Theme colour values for a `SemanticType`: the solid tier and the light tier — read them instead of hard-coding hex in custom drawing or pinned colours

### `*_dyn` signal entries

- `tag_dyn` / `tag_of_type_dyn` / `badge_count_dyn` / `avatar_dyn` / `statistic_dyn`: the static forms take a value, the `_dyn` forms take a `Signal` and update in place
