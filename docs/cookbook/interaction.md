# Interaction recipes

Import list and ground rules: see [How-to overview](index.md#prerequisites); the recipes here are complete programs.

## Reading input and submitting on Enter

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

## Adding and removing list items

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
- Fields that change per row should each be their own `Store`; see [Declarative & reactivity](../guide/declarative.md).
- Wrap long lists in the [scrolling](layout.md#scrolling-overflowing-content) recipe's `scroll_view`; for ten-thousand-row tables use `virt_list` / `table_v`.

## A confirmation dialog

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

## A toast

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

Semantic colors: `@ui.Primary` / `@ui.Success` / `@ui.Warning` / `@ui.Danger` / `@ui.Info`. For flows the user must actively confirm, use the [confirmation dialog](#a-confirmation-dialog).

## Refreshing on a timer

`@shell.set_timeout(ms, callback)` is a one-shot timer; a loop is a callback that re-arms itself at the tail. Start the loop from `mount_window`'s `handle` callback.

```moonbit
fn main {
  let ticks : @base.Store[Int] = @base.Store::new(0)
  let app = match @ui.mount_window(
    [@ui.bind_label(ticks, fn(n : Int) { "\{n} ticks" })],
    title="Timer",
    width=320, height=140,
    handle=fn(_app : @widget.WindowHost) {
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

- `set_timeout` called before mounting has no effect; start it from `handle` / `Node::on_mount` / an event callback. See [Declarative & reactivity](../guide/declarative.md).
- To stop the loop, keep a `Store[Bool]` switch, check it at the top of `pump`, and skip the re-arm.

## Showing and hiding on a condition

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

Note: toggling does not reinitialize the node, so input content survives; clear the store yourself or switch to `bind_node` for a fresh state. `Signal` and generic forms: [Reactive controls](../components/reactive.md).


## Form items with error messages

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
          toast("Submitted", @ui.Success)   // toast, see [A toast](#a-toast)
        }
      })],
      class=[@style.style(justify_content=@yoga.JustifyContent::FlexEnd)],
    ),
  ],
  row_gap=12.0,
)
```

Note: you choose when to validate — the submit callback or `input`'s `on_change`.

## Opening a second window

`WindowHost::open_window(width, height, title)` returns the child window's `App`; mount content with its `mount`. The `app` value only exists after `mount_window` returns — hand it in through a `Ref`.

```moonbit
fn main {
  let host : Ref[@widget.WindowHost?] = Ref(None)
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

Notes: `open_window` takes `Int32` sizes; without a window backend it returns `None`. The multi-window facade: [Components overview](../components/index.md#declarative-mounting).

## Remember window geometry

`WindowHost::remember_geometry(app_id)` is a one-liner: after opening, the window first restores its previous position/size/maximized state (if the file does not exist nothing happens — a first run keeps defaults), and close or quit writes the current geometry back automatically. Call `save_geometry()` to flush at another moment; clear `remember_id` to stop remembering.

```moonbit
let app = match @ui.mount_window(page(), title="MyApp", width=1280, height=800) {
  None => return
  Some(a) => a
}
app.remember_geometry("com.example.myapp")   // same source as the package id
app.mount(page())
app.run()
```

The state file lives in the app-owned directory per platform (macOS `~/Library/Application Support/<id>/`, Linux `$XDG_STATE_HOME` or `~/.local/state`/`<id>/`, Windows `%APPDATA%\<id>\`), always named `window-state.json`; a window stuck offscreen is fixed by deleting the file. Boundaries: no screen clamping on restore; one geometry per app id — suffix the id per window to split them.

