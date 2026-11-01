# How-to guides

A scenario manual indexed by "I want to do X": 19 recipes across four areas — layout, interaction, styling & theme, and system capabilities. Each recipe gives a description, paste-ready code, and notes. Snippets are checked against the current API and the sources in `examples/showcase`. Starting from zero: the [five-minute start](tutorial.md).

## Prerequisites

Use this `moon.pkg` import list (each recipe references what it needs):

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

- Layout recipes show a node tree that replaces the first argument of `mount_window`; interaction recipes are complete programs.
- Two write paths: constructor loose parameters (`padding=` / `width=` …) and `class=[@style.style(...)]` style blocks; `class` arrays are last-wins. See [Layout & styling](layout.md).
- A flex container has two axes: the main axis of `col` is vertical, of `row` horizontal; `justify_content` aligns along the main axis, `align_items` along the cross axis.

---

## 1. Layout

### 1.1 Centering content (horizontal / vertical / both)

| Container | Main axis | Center horizontally | Center vertically |
|---|---|---|---|
| `col` (main axis vertical) | vertical | `align_items` (parameter) | `justify_content` (via `class` or `view`) |
| `row` / `view(direction=Row)` (main axis horizontal) | horizontal | `justify_content` (via `class` or `view`) | `align_items` (parameter) |

Both axes, `view` form (same as `examples/hello`):

```moonbit
@ui.view(
  [@ui.text("Hello, MoonBit!", class=[@style.text_heading])],
  grow=1.0,                                     // fill the parent's remaining space
  align_items=@yoga.AlignItems::Center,         // cross axis (horizontal): center
  justify_content=@yoga.JustifyContent::Center, // main axis (vertical): center
)
```

`col` form — loose parameters only take `align_items`, so the vertical main axis goes through `class`:

```moonbit
@ui.col(
  [@ui.text("Hello, MoonBit!", class=[@style.text_heading])],
  grow=1.0,
  align_items=@yoga.AlignItems::Center,
  class=[@style.style(justify_content=@yoga.JustifyContent::Center)],
)
```

Horizontal only: drop `justify_content`. Vertical only: keep only `justify_content`; children stretch to full width on the cross axis by default.

Notes:

- The container must fill its parent (`grow=1.0` or an explicit `height`), otherwise there is no free space to distribute.
- The axis follows the container's direction: `align_items=Center` centers horizontally in a `view` (default direction Column) and vertically in a `row`.
- `@ui.text(align=...)` controls alignment inside a wrapped text block; centering the block in its container uses the table above.
- Enums are written in full form `@yoga.AlignItems::Center`; short forms like `@yoga.Center` are equivalent.

### 1.2 Header + flexible body + footer

Header and footer size to content; the body consumes all remaining height and scrolls internally. Outer `col` with three children; the body is wrapped in `col(grow=1.0)` with the scroll viewport at `height=0.0`.

```moonbit
let body = @ui.ScrollState::new()
@ui.col(
  [
    @ui.row(
      [@ui.text("Settings", class=[@style.text_title])],
      padding=12.0,
    ),
    @ui.col(
      [
        @ui.scroll_view(
          [
            @ui.text("A long first paragraph…"),
            @ui.text("A long second paragraph…"),
            // …
          ],
          body,
          height=0.0,  // viewport height delegated to the parent
        ),
      ],
      grow=1.0,
      min_height=0.0,
    ),
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

Notes:

- Without `grow=1.0` on the body, all three sections size to content and the footer does not sit at the window bottom.
- Without `min_height=0.0` on the wrapping layer, long content pushes it back to its natural height (min:auto) and the scroll viewport never gets a fixed viewport. The scroll view handles this itself; a layer you wrap around it must state it. See [Layout & styling](layout.md).

### 1.3 Sidebar + flexible main area (splitting)

Fixed width via `width=`, flexibility via `grow=1.0`, equal halves via `width_percent=50.0`, draggable divider via `split`.

```moonbit
@ui.row(
  [
    @ui.col([@ui.text("Nav"), @ui.text("Settings")], width=180.0),
    @ui.col([@ui.text("Main area")], grow=1.0),
  ],
  align_items=@yoga.AlignItems::Stretch,
)
```

```moonbit
@ui.row(
  [
    @ui.col([@ui.text("Left")], width_percent=50.0),
    @ui.col([@ui.text("Right")], width_percent=50.0),
  ],
)
```

```moonbit
@ui.split(
  @ui.col([@ui.text("File tree")]),
  @ui.col([@ui.text("Editor")]),
  ratio=0.3,
  min_first=160.0,
)
```

Note: `row`'s `align_items` defaults to Center (`col` defaults to Stretch); write `Stretch` explicitly for full-height panes.

### 1.4 Scrolling overflowing content

`scroll_view` is the scrolling container; `ScrollState` holds the offset state (required); `height` is the viewport height. Vertical scrolling is the default; horizontal needs `hscroll=true`.

```moonbit
let st = @ui.ScrollState::new()
@ui.scroll_view(
  [
    @ui.text("Line 1"),
    @ui.text("Line 2"),
    // …many lines…
  ],
  st,
  height=300.0,
)
```

```moonbit
@ui.scroll_view(
  [@ui.text("A very long line that must not wrap")],
  @ui.ScrollState::new(),
  height=40.0,
  hscroll=true,
)
```

Notes:

- The viewport height needs a source: an explicit `height=`, or `height=0.0` inside a `grow=1.0` layer.
- `code_view` scrolls horizontally on its own; no `scroll_view` wrapper needed.
- The scrollbar colors in on hover and takes no layout width; `st.at_bottom()` reads whether the bottom is reached.

### 1.5 Wrapping a row of tags

A `row` container plus `flex_wrap`; spacing between wrapped lines uses `row_gap`, between items `column_gap`.

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

Note: if wrapping does not kick in, check two things — the container is a `row`, and no enclosing layer pins its minimum size to content size (if needed write `min_width=0.0, min_height=0.0` on it). See the min:auto rules in [Layout & styling](layout.md).

### 1.6 Right-aligning a button row

A `row`'s main axis is horizontal; main-axis alignment is `justify_content`, and `FlexEnd` means right. `row` takes no such loose parameter — use the `class` channel.

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

Other modes: `FlexStart` (default), `Center`, `SpaceBetween`, `SpaceAround`, `SpaceEvenly`. A `col` applies the same set vertically (see §1.1).

---

## 2. Interaction

### 2.1 Reading input and submitting on Enter

The field's value lives in a `Store[String]`; `on_change` fires on every change, `on_enter` on Enter. The multi-line `textarea` works the same way.

```moonbit
fn main {
  let name : @base.Store[String] = @base.Store::new("")
  let greeting = @base.Signal::computed(fn() {
    let n = name.get()
    if n == "" { "Type your name" } else { "Hello, \{n}!" }
  })
  let app = match @ui.mount_window(
    [
      @ui.input(name, placeholder="Your name", clearable=true,
        on_enter=fn() {
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

Notes:

- Don't `set` a received value back to the same store inside `on_change`.
- Echo with `text_dyn` (takes a `Signal`) or `bind_label` (takes a `Store`).
- Ctrl/Cmd+C/X/V are wired to the system clipboard by default, with a right-click edit menu.

### 2.2 Adding and removing list items

List data lives in a `ListStore`; rendering goes through `for_list`, whose keyed diffing touches only changed rows.

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

Notes:

- Same `key~` means same row; to support duplicate entries give each a unique id, or use positional `for_list_indexed`.
- Fields that change per row should each be their own `Store`; see [Declarative & reactivity](declarative.md) §5.
- Wrap long lists in §1.4's `scroll_view`; for ten-thousand-row tables use `virt_list` / `table_v`.

### 2.3 A confirmation dialog

`dialog` visibility is driven by a `Store[Bool]`; all four exits (confirm, cancel, ✕, Esc) close first and then call back. The dialog sits anywhere in the tree and renders on the overlay layer.

```moonbit
fn main {
  let ask_clear : @base.Store[Bool] = @base.Store::new(false)
  let items : @base.ListStore[String] = @base.ListStore::new(["a", "b"])
  let app = match @ui.mount_window(
    [
      @ui.button("Clear list", variant=@ui.Danger, on_click=fn() {
        ask_clear.set(true)
      }),
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

Notes: don't repeat `ask_clear.set(false)` inside `on_confirm`; whether clicking the mask closes is up to `close_on_mask` (default false).

### 2.4 A toast

Call `toast_layer` once while building the UI to get a push function; then push from any callback. Strips disappear after 2.6 s and stack automatically.

```moonbit
fn main {
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

Semantic colors: `@ui.Primary` / `@ui.Success` / `@ui.Warning` / `@ui.Danger` / `@ui.Info`. For flows the user must actively confirm, use §2.3's dialog.

### 2.5 Refreshing on a timer

`@shell.set_timeout(ms, callback)` is a one-shot timer; a loop is a callback that re-arms itself at the tail. Start the loop from `mount_window`'s `handle` callback.

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
        let _ = @shell.set_timeout(500, pump)
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

Notes:

- `set_timeout` called before mounting has no effect; start it from `handle` / `Node::on_mount` / an event callback. See [Declarative & reactivity](declarative.md) §2.
- To stop the loop, keep a `Store[Bool]` switch, check it at the top of `pump`, and skip the re-arm.

### 2.6 Showing and hiding on a condition

`when_store_bool` toggles visibility from a boolean store; the node is not destroyed and its state survives. For two resident branches use `when_else_store`.

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

```moonbit
@ui.when_else_store(is_login, @ui.text("Welcome back"), @ui.text("Please sign in"))
```

Note: toggling does not reinitialize the node, so input content survives; clear the store yourself or switch to `bind_node` for a fresh state. `Signal` and generic forms: [Components](components.md), "Reactive control".

### 2.7 Form items with error messages

`form_item` bundles "label + control + always-present error row"; the error row's height is reserved up front. The message lives in a `Store[String]`; empty string means no error.

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

Note: you choose when to validate — the submit callback or `input`'s `on_change`.

### 2.8 Opening a second window

`App::open_window(width, height, title)` returns the child window's `App`; mount content with its `mount`. The `app` value only exists after `mount_window` returns — hand it in through a `Ref`.

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

Notes: `open_window` takes `Int32` sizes; without a window backend it returns `None`. The multi-window facade: [Components](components.md), "Declarative mounting".

---

## 3. Styling & theme

### 3.1 Changing the accent / following the system

Controls read theme tokens, so a theme change takes effect immediately. Set an accent with `theme_apply`; follow system dark/light and accent with `follow_system_theme`.

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

```moonbit
@ui.mount_window(
  [/* … */],
  title="Theme",
  handle=fn(a : @widget.App) {
    let _ = a.follow_system_theme(interval_ms=2000)  // returns an unsubscribe function
  },
)
```

Note: hard-coded hex colors do not track the theme; prefer the semantic routes (`SemanticType`, class presets like `text_secondary`) and hard-code only truly fixed colors.

### 3.2 Per-widget styling (hover / active / focus)

Add a `@style.style(...)` block through the `class` channel; the `hover` / `active` / `focus` slots each take a nested `Style` that merges in while the state is active; `transition_ms` smooths colors, border width, radius, font size, and line height.

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

Notes:

- `class` arrays are last-wins: to override a widget's built-in style, put your block later in the array.
- Global corner and font changes use the theme layer's switches (`@theme.corners_round_set` etc.).

---

## 4. System capabilities

The capability family uses a uniform `Result` semantics and returns error values in unsupported environments; the three-platform matrix is in [System capabilities](system-capabilities.md).

### 4.1 Opening links / revealing files

`@sys.open_url` opens a URL; `@sys.open_file` hands a file to the system's default program; `@shell.reveal_in_file_manager` locates and selects it in the file manager.

```moonbit
@ui.col(
  [
    @ui.link("Open the docs", fn() {
      let _ = @sys.open_url("https://moonbit-native-gui.pages.dev")
    }),
    @ui.button("Open image", on_click=fn() {
      let _ = @sys.open_file("/home/me/photo.png")
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

`clipboard_set_text` writes the system clipboard directly and returns a `Bool`.

```moonbit
@ui.button("Copy install command", on_click=fn() {
  if @sys.clipboard_set_text("moon add NoahLiu/native-gui") {
    toast("Copied", @ui.Success)   // toast, see §2.4
  }
})
```

Read with `clipboard_get_text() -> String?`. Input fields already talk to the system clipboard themselves.

### 4.3 Desktop notifications

`@shell.notify_send(title, body, app_name)`; probe with `notify_supported()` first. Linux goes over D-Bus, Windows uses the tray balloon, macOS uses the UN center.

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

Notes: send from event callbacks. On macOS the desktop banner requires running as an `.app` bundle, and first use asks for system authorization; see the [experience guide](experience.md).

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

- Widget signatures: [Components](components.md); state binding: [Declarative & reactivity](declarative.md); every layout field: [Layout & styling](layout.md).
- Full programs combining these recipes: `cd examples/showcase && moon run .`; each page's source is under `examples/showcase/pages/*.mbt`.
- Starting from zero: the [five-minute start](tutorial.md).
