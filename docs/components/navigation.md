# Navigation

General conventions: see [Components overview](index.md#conventions-read-this-first).

### `menu(items : Array[String], selected : Store[String], icons?, width?=180.0, class?, handle?)`

- Side navigation menu: the selection gets a light theme background + a left accent bar; `selected` can be shared with the main area for page linking

### `menu_sections(sections : Array[(String, Array[String])], selected, icons?, foldable?=true, width?=180.0, class?, handle?)`

- Grouped side menu: group header row + items in the group; with `foldable=true` a header click collapses/expands the group

### `segmented(options : Array[String], selected : Store[String], class?, handle?)`

- Segmented control: the selected segment gets a panel background + accent text; every segment joins the Tab chain, Space/Enter select, arrow keys move segments

### `breadcrumb(items : Array[String], selected : Store[String], class?, handle?)`

- Breadcrumb: `/` between levels; **the current item is decided by `selected`**, not by position — otherwise the last item would never be clickable

### `pagination(current : Store[Int32], pages : Int32, class?, handle?)`

- Pagination `‹ 1 2 … ›`: `current` starts at 1; out-of-range arrows clamp to the first/last page

### `steps(items : Array[String], current : Store[Int32], on_select? : (Int32) -> Unit, class?, handle?)`

- Steps: number squares (done/current/todo) + text + connector; `current` is a 0-based index
- The number squares are clickable and focusable: without `on_select`, click / Space / Enter jumps to that step and ← / → moves between steps (out-of-range clamps); with `on_select(i)`, clicks and arrow keys go to the caller instead (e.g. a read-only preview in a wizard — the highlight still follows `current` only)

### `collapse(panels : Array[(String, Array[Node])], class?, handle?)`

- Collapse: clicking a header toggles its content; panels are independent, only the first is expanded by default

### `tree(root : Array[TreeNode], class?, handle?)`

- Tree: per-level indent; clicking a row with children expands/collapses it

### `tabs(pages : Array[(String, Node)], selected? : Store[Int32], class?, handle?)`

- Tabs: the selected header gets accent text + a bottom indicator; content pages are prebuilt and switched by visibility; `selected` is 0-based and created internally when omitted

### `transfer(left_items : Store[Array[String]], right_items : Store[Array[String]], width?=200.0, height?=160.0, item_height?=24.0, class?, handle?)`

- Transfer: two columns + a middle `›`/`‹`; each column is driven by its own `Store`
