# Data display

The display family also has `*_dyn` signal forms: `text` becomes a `Signal`, the label is edited in place and the width recomputed, and unsubscribing rides the unsubscribe bundle. General conventions: see [Components overview](index.md#conventions-read-this-first).

### `tag_of_type(text, t : SemanticType, font_size?=12.0, class?)`

- Semantic-colour tag: light background + accent text; `tag_of_type_dyn` takes a signal

### `tag(text, color, font_size?=12.0, class?)`

- Custom-colour tag: solid background + white text; `tag_dyn` takes a signal

### `badge_count(value : Int, max?=99, color?, class?)`

- Number badge: over `max` it shows "max+"; `badge_count_dyn` takes a `Signal[Int]`

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

- Carousel: panel sequence + arrows + indicator dots; auto-advances when `interval_ms>0` and pages > 1, pauses on hover
