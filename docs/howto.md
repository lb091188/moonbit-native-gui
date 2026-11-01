# How-to guides

A scenario-driven manual indexed by "I want to do X": 19 recipes across four areas — layout, interaction, styling & theme, and system capabilities. Each one follows **goal → approach → code → pitfalls**. It complements the [five-minute start](tutorial.md): that page walks you linearly from zero to a first window, this one answers "how do I write this particular step" afterwards. Every snippet is checked against the current API and the real sources in `examples/showcase`, so you can paste them straight into your entry file (`cmd/main/main.mbt`).

## Prerequisites

**Project and imports**. The recipes assume you have followed [the five-minute start](tutorial.md) §2–§3 and have a first window running. Use this `moon.pkg` import list (a few more lines than the tutorial's; carrying them all up front saves you from revisiting per recipe — only the ones actually referenced get compiled in):

```
import {
  "NoahLiu/yoga-mbt/src" @yoga,
  "NoahLiu/native-gui/base" @base,
  "NoahLiu/native-gui/shell" @shell,
  "NoahLiu/native-gui/widget" @widget,
  "NoahLiu/native-gui/ui",
  "NoahLiu/native-gui/style" @style,
  "NoahLiu/native-gui/sys" @sys,
  "NoahLiu/native-gui/theme" @theme,
}
```

**How to use the snippets**. Layout recipes show a node tree that replaces the first argument of `mount_window`; interaction recipes show complete runnable programs. Every constructor returns a `@widget.Node`, so trees nest freely.

**Two conventions** used throughout:

- **Two write paths**: the constructor's loose parameters (`padding=` / `width=` …) and the `class=[@style.style(...)]` style blocks. The loose parameters are sugar with a single destination (they fold into the style slot); `class` arrays are **last-wins** — a later block's same-named property overrides an earlier one. See [Layout & styling](layout.md).
- **Two axes**: a flex container has a main axis and a cross axis, set by `flex_direction` — the main axis of `col` is vertical, of `row` horizontal. `justify_content` aligns along the **main axis**, `align_items` along the **cross axis**. Mixing up the axes is the single most common layout mistake; see §1.1.

---

## 1. Layout

### 1.1 Centering content (horizontal / vertical / both)

**Goal**: put a piece of text in the middle of the window — or center it on one axis only.

**Approach**: first ask whether the container is a row or a column, then which axis you are centering on. Each axis has its own property; writing the wrong one is the most frequent layout bug.

| Container | Main axis | Center horizontally | Center vertically |
|---|---|---|---|
| `col` (main axis vertical) | vertical | `align_items` (parameter) | `justify_content` (via `class` or `view`) |
| `row` / `view(direction=Row)` (main axis horizontal) | horizontal | `justify_content` (via `class` or `view`) | `align_items` (parameter) |

**Code**. Centering on both axes with `view` — both axes as plain parameters, the most direct form (same as `examples/hello`):

```moonbit
@ui.view(
  [@ui.text("Hello, MoonBit!", class=[@style.text_heading])],
  grow=1.0,                                     // fill the window's remaining space
  align_items=@yoga.AlignItems::Center,         // cross axis (horizontal): center
  justify_content=@yoga.JustifyContent::Center, // main axis (vertical): center
)
```

The same effect with `col` — its parameters only take `align_items` (horizontal), so the vertical main axis goes through the `class` channel:

```moonbit
@ui.col(
  [@ui.text("Hello, MoonBit!", class=[@style.text_heading])],
  grow=1.0,
  align_items=@yoga.AlignItems::Center,
  class=[@style.style(justify_content=@yoga.JustifyContent::Center)],
)
```

**Horizontal only**: drop the `justify_content` line (in the `view` form) or the `class` block (in the `col` form).
**Vertical only**: keep only `justify_content` and drop `align_items` — children stretch to full width on the cross axis by default, so the text is vertically centered while spanning left to right; the classic header look.

**Pitfalls**:

- **Centering has no effect** — nine times out of ten the container doesn't fill its parent. A container the size of its content has no free space on the main axis, so there is nothing to center within. Give it `grow=1.0` (consume the parent's free space) or an explicit `height`.
- **Code copied from `examples/hello` behaves differently inside a `row`** — hello's root container is a `view` (default direction Column), where `align_items=Center` centers horizontally; inside a `row` the same attribute centers vertically. The axis follows the container's direction, not the property name.
- **`@ui.text(align=...)` is not this recipe** — it controls alignment *inside* a wrapped text block; centering the text block within its container is the container's job, done with `align_items` / `justify_content`.
- The full enum form `@yoga.AlignItems::Center` is the safest to write; shorter forms like `@yoga.Center` also work (see `@yoga.Wrap` in §1.5).

### 1.2 Header + flexible body + footer

**Goal**: a fixed-height header, a fixed-height button bar at the bottom, and a body that consumes all remaining height and scrolls internally when content overflows.

**Approach**: an outer `col` with three children; wrap the body in a `col(grow=1.0)` that takes all the remaining height, and put the scroll viewport inside with `height=0.0` — viewport height delegated to the parent.

**Code**:

```moonbit
let body = @ui.ScrollState::new()
@ui.col(
  [
    // header: sized by content
    @ui.row(
      [@ui.text("Settings", class=[@style.text_title])],
      padding=12.0,
    ),
    // body: grow takes all remaining height, scrolls internally
    @ui.col(
      [
        @ui.scroll_view(
          [
            @ui.text("A long first paragraph…"),
            @ui.text("A long second paragraph…"),
            // …
          ],
          body,
          height=0.0,  // viewport height decided by the parent
        ),
      ],
      grow=1.0,
      min_height=0.0,  // without it, long content pushes this layer back to its natural height and the footer leaves the window
    ),
    // footer: right-aligned buttons, see §1.6
    @ui.row(
      [
        @ui.button("Cancel"),
        @ui.button("Save", variant=@ui.Solid),
      ],
      column_gap=8.0,
      padding=12.0,
      class=[@style.style(justify_content=@yoga.JustifyContent::FlexEnd)],
    ),
  ],
)
```

**Pitfalls**:

- **Forgetting `grow=1.0` on the body** — all three sections size to content, the footer sits right below the content instead of at the window bottom.
- **Forgetting `min_height=0.0` on the wrapping layer** — a flex child's default minimum size is its content size (min:auto); long content pushes the layer back to natural height, the scroll viewport never gets a fixed viewport, and the window overflows. The scroll view itself already handles this; the layer you wrap around it must state it explicitly. See [Layout & styling](layout.md), "the sizes you must know".

### 1.3 Sidebar + flexible main area (splitting)

**Goal**: a fixed-width sidebar on the left and a main area that consumes the rest — or two equal halves, or a draggable divider between them.

**Approach**: fixed width via `width=`, flexibility via `grow=1.0`, equal halves via `width_percent=50.0`, and a draggable divider via `split`.

**Code**. Fixed sidebar + flexible main:

```moonbit
@ui.row(
  [
    @ui.col([@ui.text("Nav"), @ui.text("Settings")], width=180.0),
    @ui.col([@ui.text("Main area")], grow=1.0),
  ],
  align_items=@yoga.AlignItems::Stretch,  // row's align_items defaults to Center; use Stretch for full-height panes
)
```

Equal halves (tracking window width):

```moonbit
@ui.row(
  [
    @ui.col([@ui.text("Left")], width_percent=50.0),
    @ui.col([@ui.text("Right")], width_percent=50.0),
  ],
)
```

Draggable divider (`ratio` is the first pane's share; minimum widths optional):

```moonbit
@ui.split(
  @ui.col([@ui.text("File tree")]),
  @ui.col([@ui.text("Editor")]),
  ratio=0.3,
  min_first=160.0,
)
```

**Pitfalls**: `row`'s `align_items` **defaults to Center** (`col` defaults to Stretch) — with panes of unequal content height you'll see each pane vertically centered and bottom edges misaligned. For equal-height panes write `align_items=@yoga.AlignItems::Stretch` explicitly.

### 1.4 Scrolling overflowing content

**Goal**: content taller than the visible area gets a vertical scrollbar; content wider than it (code, tables) gets a horizontal one.

**Approach**: `scroll_view` is the scrolling container; `ScrollState` holds the offset state and is required; `height` is the viewport height. Vertical scrolling is the default; horizontal needs `hscroll=true`.

**Code**:

```moonbit
let st = @ui.ScrollState::new()
@ui.scroll_view(
  [
    @ui.text("Line 1"),
    @ui.text("Line 2"),
    // …many lines…
  ],
  st,
  height=300.0,  // viewport height; pass 0.0 when wrapped in a grow layer, see §1.2
)
```

Horizontal scrolling (the standard route for non-wrappable content):

```moonbit
@ui.scroll_view(
  [@ui.text("A very long line that must not wrap")],
  @ui.ScrollState::new(),
  height=40.0,
  hscroll=true,
)
```

**Pitfalls**:

- **Viewport height with no source** — if neither `height` nor the parent provides it, the viewport collapses and nothing scrolls. Either set `height=` explicitly, or wrap it in a `grow=1.0` layer with `height=0.0`.
- **Code blocks need no wrapper** — `code_view` scrolls horizontally on its own (width follows the container); wrapping it in another `scroll_view` yields double scrollbars.
- The scrollbar is a floating thumb that colors in on hover and takes no layout width; all offset state lives in `ScrollState` — use it to read "did I reach the bottom" (`st.at_bottom()`).

### 1.5 Wrapping a row of tags

**Goal**: a row of tags (or icons, buttons) laid out horizontally that wraps to the next line when the container narrows, reflowing as the window resizes.

**Approach**: a `row` container plus `flex_wrap`. Spacing between wrapped lines uses `row_gap`, between items `column_gap`.

**Code** (same recipe as the showcase icon grid):

```moonbit
@ui.row(
  [
    @ui.tag_of_type("MoonBit", @ui.Primary),
    @ui.tag_of_type("Cross-platform", @ui.Success),
    @ui.tag_of_type("Native windows", @ui.Info),
    @ui.tag_of_type("Self-drawn", @ui.Warning),
    @ui.tag_of_type("Theming", @ui.Danger),
    // …more tags wrap naturally
  ],
  column_gap=8.0,
  class=[@style.style(flex_wrap=@yoga.FlexWrap::Wrap, row_gap=8.0)],
)
```

**Pitfalls**: if wrapping doesn't kick in, check two things — the container is a `row` (`flex_wrap` wraps along the row direction), and no enclosing layer pins its minimum size to content size (a pinned layer never shrinks; if needed write `min_width=0.0, min_height=0.0` on it). The min:auto rules are in [Layout & styling](layout.md).

### 1.6 Right-aligning a button row

**Goal**: the "Cancel / OK" pair at the bottom of a dialog or form sits on the right.

**Approach**: a `row`'s main axis is horizontal, so main-axis alignment is `justify_content`; `FlexEnd` means right. `row` takes no `justify_content` parameter — use the `class` channel.

**Code**:

```moonbit
@ui.row(
  [
    @ui.button("Cancel"),
    @ui.button("OK", variant=@ui.Solid),
  ],
  column_gap=8.0,
  class=[@style.style(justify_content=@yoga.JustifyContent::FlexEnd)],
)
```

The remaining main-axis modes: `FlexStart` (left, default), `Center`, `SpaceBetween` (edges pinned, even middle), `SpaceAround` / `SpaceEvenly` (even spacing with margins; the latter fully uniform). A `col` applies the same set vertically (see the axis table in §1.1).

---

## 2. Interaction

### 2.1 Reading input and submitting on Enter

**Goal**: a single-line field that echoes as you type and submits on Enter.

**Approach**: the field's value lives in a `Store[String]`; the widget and your code read and write the same box. `on_change` fires on every change, `on_enter` on Enter. The multi-line `textarea` works the same way.

**Code** (complete and runnable):

```moonbit
fn main {
  let name : @base.Store[String] = @base.Store::new("")
  // derived signal: the echo updates itself as the input changes
  let greeting = @base.Signal::computed(fn() {
    let n = name.get()
    if n == "" { "Type your name" } else { "Hello, \{n}!" }
  })
  let app = match @ui.mount_window(
    [
      @ui.input(name, placeholder="Your name", clearable=true,
        on_enter=fn() {
          // submit on Enter: just read the store
          println("submitted: \{name.get()}")
        }),
      @ui.text_dyn(greeting),
    ],
    title="Input",
    width=360, height=160,
  ) {
    None => return
    Some(a) => a
  }
  app.run()
}
```

**Pitfalls**:

- **Setting the same store back inside `on_change`** triggers yourself in a loop; avoid writing back what you just received.
- Echo with `text_dyn` (takes a `Signal`) or `bind_label` (takes a `Store`); don't poke another widget's text from `on_change` — that's the imperative path the framework already covers.
- Ctrl/Cmd+C/X/V are wired to the system clipboard by default, with a right-click edit menu; no extra plumbing needed.

### 2.2 Adding and removing list items

**Goal**: a todo list — type an entry, press "Add"; each row carries a delete button.

**Approach**: the data lives in a `ListStore`, rendering goes through `for_list` — keyed diffing touches only the rows that changed, never rebuilds the whole list.

**Code**:

```moonbit
fn main {
  let todos : @base.ListStore[String] = @base.ListStore::new(["Buy milk", "Weekly report"])
  let draft : @base.Store[String] = @base.Store::new("")
  let app = match @ui.mount_window(
    [
      @ui.row(
        [
          @ui.input(draft, placeholder="New item", width=200.0),
          @ui.button("Add", variant=@ui.Solid, on_click=fn() {
            let s = draft.get()
            if s != "" {
              todos.push(s)
              draft.set("")
            }
          }),
        ],
        column_gap=8.0,
      ),
      @ui.for_list(
        todos,
        build=fn(item, _i) {
          @ui.row(
            [
              @ui.text(item),
              @ui.button("Delete", variant=@ui.Text, on_click=fn() {
                todos.remove(fn(x) { x == item })
              }),
            ],
            column_gap=8.0,
          )
        },
        key~=fn(item) { item },
      ),
    ],
    title="Todos",
    width=360, height=320,
  ) {
    None => return
    Some(a) => a
  }
  app.run()
}
```

**Pitfalls**:

- **`key~` drives the diff** — same key means same row. Using text as the key makes duplicate entries interfere with each other; to support duplicates give each entry a unique id (store records with ids), or switch to positional `for_list_indexed`.
- Fields that change per row (checked state etc.) should each be their own `Store`; don't refresh by re-mounting whole rows. More rules in [Declarative & reactivity](declarative.md) §5.
- Long lists want §1.4's `scroll_view` around the `for_list`; for ten-thousand-row tables use `virt_list` / `table_v`.

### 2.3 A confirmation dialog

**Goal**: clicking "Clear" first shows a confirmation; the action runs only on confirm.

**Approach**: `dialog` visibility is driven by a `Store[Bool]` — the button only sets the store, the dialog pops itself. All four exits (confirm, cancel, ✕, Esc) close it first and then call back.

**Code**:

```moonbit
fn main {
  let ask_clear : @base.Store[Bool] = @base.Store::new(false)
  let items : @base.ListStore[String] = @base.ListStore::new(["a", "b"])
  let app = match @ui.mount_window(
    [
      @ui.button("Clear list", variant=@ui.Danger, on_click=fn() {
        ask_clear.set(true)
      }),
      // the dialog sits anywhere in the tree; it renders on the overlay layer
      @ui.dialog(
        ask_clear,
        "Clear the list?",
        [@ui.text("This cannot be undone.")],
        confirm_text="Clear",
        on_confirm=fn() {
          items.splice(0, items.length(), [])
        },
      ),
    ],
    title="Confirm",
    width=360, height=160,
  ) {
    None => return
    Some(a) => a
  }
  app.run()
}
```

**Pitfalls**: don't `ask_clear.set(false)` again inside `on_confirm` — every exit already closes before calling back; a redundant set is harmless but noise. Whether clicking the mask closes the dialog is up to `close_on_mask` (default false; keep it off for modal confirmations).

### 2.4 A toast

**Goal**: after an action succeeds, a "Saved" strip appears at the top and disappears by itself after ~2 seconds, without interrupting anything.

**Approach**: call `toast_layer` **once** while building the UI to get a push function; then push a toast from any callback.

**Code**:

```moonbit
fn main {
  // build this layer before mount_window
  let toast = @ui.toast_layer(duration_ms=2600)
  let app = match @ui.mount_window(
    [
      @ui.button("Save", variant=@ui.Solid, on_click=fn() {
        toast("Saved", @ui.Success)
      }),
    ],
    title="Toast",
    width=320, height=140,
  ) {
    None => return
    Some(a) => a
  }
  app.run()
}
```

The second argument is the semantic color: `@ui.Primary` / `@ui.Success` / `@ui.Warning` / `@ui.Danger` / `@ui.Info`. Multiple toasts stack automatically. When the user must actively confirm, that's §2.3's dialog; toast is one-way notification only.

### 2.5 Refreshing on a timer

**Goal**: refresh the UI every 500 ms — clocks, progress, polled data all follow this recipe.

**Approach**: `@shell.set_timeout(ms, callback)` is a one-shot timer; a loop is a callback that **re-arms itself at the tail**. The timer channel is only installed once the host exists, so the loop must be started after mounting — the natural spot is `mount_window`'s `handle` callback.

**Code**:

```moonbit
fn main {
  let ticks : @base.Store[Int] = @base.Store::new(0)
  let app = match @ui.mount_window(
    [@ui.bind_label(ticks, fn(n : Int) { "\{n} ticks" })],
    title="Timer",
    width=320, height=140,
    handle=fn(_app : @widget.App) {
      fn pump() {
        ticks.update(fn(n) { n + 1 })
        let _ = @shell.set_timeout(500, pump)  // tail self-rearm = the loop
      }
      pump()
    },
  ) {
    None => return
    Some(a) => a
  }
  app.run()
}
```

**Pitfalls**:

- **`set_timeout` called during construction is a no-op** — before `mount_window` in `main`, the timer channel isn't installed and the first beat lands on an empty channel. Start it from `handle` / `Node::on_mount`, or from an event callback. This is the library's most common "why doesn't my timer run"; see the warning in [Declarative & reactivity](declarative.md) §2.
- Loops need a way to stop: keep a `Store[Bool]` switch, check it at the top of `pump`, and skip the re-arm when it flips.

### 2.6 Showing and hiding on a condition

**Goal**: a details section that appears only when "Show details" is checked — or two blocks that alternate.

**Approach**: `when_store_bool` toggles visibility from a boolean store — the node is not destroyed and its state survives. For two resident branches use `when_else_store`.

**Code**:

```moonbit
let show : @base.Store[Bool] = @base.Store::new(false)
@ui.col(
  [
    @ui.checkbox("Show details", show),
    @ui.when_store_bool(show, @ui.text("Details live here…")),
  ],
  row_gap=8.0,
)
```

Alternating blocks:

```moonbit
@ui.when_else_store(is_login, @ui.text("Welcome back"), @ui.text("Please sign in"))
```

**Pitfalls**: toggling does **not** reinitialize the node — text typed into an input inside survives the toggle. That's a feature (state is kept); if you want a fresh state on every appearance, clear the store yourself or switch to `bind_node` whole-subtree replacement. The `when` family also has `Signal` and generic forms; see [Components](components.md), "Reactive control".

### 2.7 Form items with error messages

**Goal**: label-left / control-right form rows, validated on submit, with the error message under the offending item.

**Approach**: `form_item` bundles "label + control + always-present error row"; the error row's height is reserved from the start, so nothing jumps when an error appears. The message lives in a `Store[String]`; empty string means no error.

**Code**:

```moonbit
let email : @base.Store[String] = @base.Store::new("")
let nick : @base.Store[String] = @base.Store::new("")
let email_err : @base.Store[String] = @base.Store::new("")
@ui.col(
  [
    @ui.form(
      "Sign up",
      [
        @ui.form_item("Email", @ui.input(email, placeholder="you@example.com"),
          error=email_err),
        @ui.form_item("Nickname", @ui.input(nick, placeholder="Display name")),
      ],
    ),
    @ui.row(
      [@ui.button("Submit", variant=@ui.Solid, on_click=fn() {
        let v = email.get()
        if v == "" {
          email_err.set("Email is required")
        } else if !v.contains("@") {
          email_err.set("Not a valid email")
        } else {
          email_err.set("")
          toast("Submitted", @ui.Success)   // toast, see §2.4
        }
      })],
      class=[@style.style(justify_content=@yoga.JustifyContent::FlexEnd)],
    ),
  ],
  row_gap=12.0,
)
```

**Pitfalls**: you choose when to validate — the sample validates in the submit callback; to validate as the user types, hang the same logic off `input`'s `on_change`. The error row's space is reserved up front, so content below never shifts.

### 2.8 Opening a second window

**Goal**: a button in the main window opens an independent child window.

**Approach**: `App::open_window(width, height, title)` returns the child window's `App`; mount content with its `mount`. The `app` value only exists after `mount_window` returns, while the button tree is built before it — hand it in through a `Ref`.

**Code**:

```moonbit
fn main {
  let host : Ref[@widget.App?] = Ref(None)
  let app = match @ui.mount_window(
    [
      @ui.button("Open child window", on_click=fn() {
        match host.val {
          Some(a) =>
            match a.open_window(320, 220, "Child") {
              Some(child) =>
                child.mount(
                  [
                    @ui.col(
                      [@ui.text("I am the child window", class=[@style.text_title])],
                      padding=16.0,
                    ),
                  ],
                )
              None => ()
            }
          None => ()
        }
      }),
    ],
    title="Main",
    width=360, height=200,
  ) {
    None => return
    Some(a) => a
  }
  host.val = Some(app)
  app.run()
}
```

**Pitfalls**: `open_window` takes `Int32` sizes; without a window backend it returns `None`, matched away above. The multi-window facade (count, activate, close) is in [Components](components.md) under "Declarative mounting" and in `examples/showcase`'s Window page.

---

## 3. Styling & theme

### 3.1 Changing the accent / following the system

**Goal**: apps follow the system dark/light and accent color by default; sometimes you want to set the accent yourself, or take over the following loop explicitly.

**Approach**: every control reads theme tokens, so a theme change takes effect immediately — no tree rebuild. Setting an accent is one `theme_apply` call; taking over the follow loop is `App::follow_system_theme`.

**Code**. Switching the accent from buttons at runtime:

```moonbit
@ui.row(
  [
    @ui.button("Purple", on_click=fn() {
      @theme.theme_apply(@theme.theme_from_accent("#7c4dff"))
    }),
    @ui.button("Green", on_click=fn() {
      @theme.theme_apply(@theme.theme_from_accent("#2e7d32"))
    }),
  ],
  column_gap=8.0,
)
```

Following system dark/light and accent (skip if the default following is enough; polls system state at an interval):

```moonbit
@ui.mount_window(
  [/* … */],
  title="Theme",
  handle=fn(a : @widget.App) {
    let _ = a.follow_system_theme(interval_ms=2000)  // returns an unsubscribe function
  },
)
```

**Pitfalls**: don't **bake color snapshots** into your own code — `@style.style(background_color="...")` with a hard-coded hex works but stops tracking the theme after a switch. Prefer the semantic routes first (`SemanticType` on `tag_of_type`, class presets like `text_secondary`); hard-code a color only when you truly mean a fixed color.

### 3.2 Per-widget styling (hover / active / focus)

**Goal**: one card that gets a different border and larger radius on hover, with a transition — affecting only that widget.

**Approach**: add a `@style.style(...)` block through the `class` channel; the `hover` / `active` / `focus` slots each take a nested `Style` that merges in while the state is active; `transition_ms` smooths the interpolatable properties (colors, border width, radius, font size, line height).

**Code**:

```moonbit
@ui.card(
  [@ui.text("Hover me")],
  class=[
    @style.style(
      border_radius=8.0,
      transition_ms=150.0,
      hover=@style.style(
        border_color="#7c4dff",
        background_color="#f5f0ff",
        border_radius=12.0,
      ),
    ),
  ],
)
```

**Pitfalls**:

- `class` is an array and **last wins** — to override a widget's built-in style put your block later in the array; putting it first gets overridden.
- `transition_ms` only applies to interpolatable properties; everything else switches instantly.
- To change corners or fonts globally you don't need per-widget classes — the theme layer has global switches (`@theme.corners_round_set` etc.); see [Components](components.md) and the [design document](https://github.com/lb091188/moonbit-native-gui/blob/master/proposals/design.md).

---

## 4. System capabilities

The system capability family uses a uniform `Result` semantics: unsupported environments return an error value instead of crashing. The three-platform support matrix is in [System capabilities](system-capabilities.md).

### 4.1 Opening links / revealing files

**Goal**: open a web page on click; or locate a file in the system file manager.

**Approach**: `@sys.open_url` opens a URL (browser or protocol handler); `@sys.open_file` hands a file to the system's default program; `@shell.reveal_in_file_manager` locates and selects it in the file manager.

**Code**:

```moonbit
@ui.col(
  [
    @ui.link("Open the docs", fn() {
      let _ = @sys.open_url("https://moonbit-native-gui.pages.dev")
    }),
    @ui.button("Open image", on_click=fn() {
      let _ = @sys.open_file("/home/me/photo.png")   // handed to the system's default viewer
    }),
    @ui.button("Reveal in file manager", on_click=fn() {
      match @shell.reveal_in_file_manager("/home/me/photo.png") {
        Ok(_) => ()
        Err(e) => println("reveal failed: \{e}")
      }
    }),
  ],
  row_gap=8.0,
)
```

### 4.2 Copying to the clipboard

**Goal**: a "Copy" button that puts text on the system clipboard, with a toast on success.

**Approach**: `clipboard_set_text` writes the system clipboard directly and returns a `Bool`.

**Code**:

```moonbit
@ui.button("Copy install command", on_click=fn() {
  if @sys.clipboard_set_text("moon add NoahLiu/native-gui") {
    toast("Copied", @ui.Success)   // toast, see §2.4
  }
})
```

Read with `clipboard_get_text() -> String?` (`None` when empty or unavailable). Input fields already talk to the system clipboard themselves (Ctrl/Cmd+C/X/V), so no extra code is needed for them.

### 4.3 Desktop notifications

**Goal**: background events — a finished build, a finished download — surface as a system notification.

**Approach**: `@shell.notify_send(title, body, app_name)`; probe with `notify_supported()` first. Linux goes over D-Bus, Windows uses the tray balloon, macOS uses the UN center.

**Code**:

```moonbit
@ui.button("Send notification", on_click=fn() {
  if @shell.notify_supported() {
    match @shell.notify_send("Build finished", "3 targets produced", "My App") {
      Ok(_id) => toast("Sent", @ui.Info)
      Err(e) => println("notify failed: \{e}")
    }
  } else {
    println("notifications not supported here")
  }
})
```

**Pitfalls**:

- Send notifications from event callbacks (a button click, a task completing), not during construction.
- On macOS the desktop banner requires running as an `.app` bundle, and the first use asks for system authorization; an unbundled raw binary may deliver to the notification center without showing a banner. Details in the [experience guide](experience.md) and `proposals/adaptation.md`.

---

## Cheat sheet

| I want to… | Key API | Section |
|---|---|---|
| Center content (h/v/both) | `align_items` / `justify_content` | §1.1 |
| Header + body + footer | `col` + `grow` + `scroll_view` | §1.2 |
| Sidebar + main / halves / draggable split | `grow` / `width_percent` / `split` | §1.3 |
| Scroll content (v/h) | `scroll_view` + `ScrollState` | §1.4 |
| Wrap a row of tags | `flex_wrap=@yoga.FlexWrap::Wrap` | §1.5 |
| Right-align buttons | `justify_content=FlexEnd` (class) | §1.6 |
| Read input / submit on Enter | `input` + `Store[String]` + `on_enter` | §2.1 |
| Add/remove list items | `ListStore` + `for_list` | §2.2 |
| Confirmation dialog | `dialog` + `Store[Bool]` | §2.3 |
| Action feedback toast | `toast_layer` | §2.4 |
| Refresh on a timer | `@shell.set_timeout` with tail self-rearm | §2.5 |
| Show/hide on a condition | `when_store_bool` / `when_else_store` | §2.6 |
| Form validation | `form` + `form_item(error=)` | §2.7 |
| Open a second window | `App::open_window` + `mount` | §2.8 |
| Change accent / follow system | `theme_apply` / `follow_system_theme` | §3.1 |
| Per-widget hover styling | `class` + `hover=` + `transition_ms` | §3.2 |
| Open links / reveal files | `@sys.open_url` / `@shell.reveal_in_file_manager` | §4.1 |
| Copy to clipboard | `@sys.clipboard_set_text` | §4.2 |
| Desktop notification | `@shell.notify_send` | §4.3 |

## Next steps

- A recipe touches a widget this page didn't cover — look up its signature in [Components](components.md); the full state-binding contract is in [Declarative & reactivity](declarative.md); every layout field is in [Layout & styling](layout.md).
- To see these recipes combined in a real program: `cd examples/showcase && moon run .` — every page in the left menu is a standalone source file under `examples/showcase/pages/*.mbt`, ready to copy.
- Starting from zero: the [five-minute start](tutorial.md).
