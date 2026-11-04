# Five-minute tutorial

Build a desktop app from scratch: one window, one button, and a counter that refreshes on every click.

## 1. Prepare the tools

**MoonBit toolchain** (one line):

```sh
# Linux / macOS
curl -fsSL https://cli.moonbitlang.com/install/unix.sh | bash
# Windows (PowerShell)
irm https://cli.moonbitlang.com/install/powershell.ps1 | iex
```

This library uses native FFI, so building also needs a C toolchain and some dev packages (Linux additionally needs the GTK3 family) — **the full three-platform install list and environment self-check are in [Build & run](build.md) §2**. If you would rather see results first without installing anything, take [Try the demos](experience.md).

## 2. Create the project

```sh
moon new my_app
cd my_app
moon add NoahLiu/native-gui
```

The current `moon new` template: the root package is a library (`my_app.mbt` and an empty `moon.pkg`), and the executable entry lives in the `cmd/main/` sub-package (`main.mbt` + `moon.pkg`). The project needs two manual adjustments:

- **`moon.mod`: change `preferred_target = "wasm"` to `"native"`** — this library uses native FFI and supports only the native backend; skip if the template already defaults to native.

- **Replace the whole `cmd/main/moon.pkg` with** — moon's DSL format, not JSON:

  ```
  import {
    "NoahLiu/native-gui/base",
    "NoahLiu/native-gui/widget" @widget,
    "NoahLiu/native-gui/ui",
    "NoahLiu/native-gui/style" @style,
  }

  pkgtype(kind: "executable")

  supported_targets = "native"
  ```

  The entry file is `cmd/main/main.mbt` — moon only recognizes a file named `main.mbt` as the program entry; keep that file name when creating your own entry files.

  Why each adjustment, and the module-level / package-level `import` split of `moon add`, are in the [App developer experience](dev-experience.md).

## 3. Your first window

Replace `cmd/main/main.mbt` entirely with:

```moonbit
fn main {
  let count : @base.Store[Int] = @base.Store::new(0)
  let app = match @ui.mount_window(
    [
      @ui.col(
        [
          @ui.text("Hello, MoonBit!", class=[@style.text_heading]),
          @ui.button("Click me", variant=@ui.Solid, on_click=fn() {
            count.update(fn(n) { n + 1 })
          }),
          @ui.bind_label(count, fn(n : Int) -> String { "Clicked \{n} times" }),
        ],
        padding=24.0,
        row_gap=12.0,
      ),
    ],
    title="Tutorial demo",
    width=360,
    height=220,
  ) {
    None => {
      println("No window backend or no display service on this platform")
      return
    }
    Some(a) => a
  }
  app.run()
}
```

```sh
moon run cmd/main
```

A window appears: a title, a button, and a "Clicked 0 times" line. Click the button and the number ticks up by itself. That is **reactive state**: when `count` changes, `bind_label` refreshes on its own — no "update the text on click" glue code. The UI is declared as a tree of **node constructors** (`@ui.col([...])` / `@ui.text(...)` / `@ui.button(...)`) and mounted in one `mount_window` call; `mount_window` returns `None` when there is no window backend or no display service, and the example exits accordingly.

## 4. MoonBit syntax at a glance (only what the code above uses)

| Syntax | Meaning |
|---|---|
| `fn main { ... }` | program entry |
| `let count : @base.Store[Int] = ...` | type annotation: `Store[Int]` is a box of integer state |
| `match expr { ... }` | pattern matching, take a value per branch (here, unwrapping an `Option`) |
| `None => ... / Some(a) => a` | the two states of an optional value: `None` absent, `Some(x)` present |
| `fn(n) { n + 1 }` | anonymous function (lambda), passed in as a callback |
| `on_click=fn() { ... }` | labelled argument: parameters with defaults are passed by name |
| `"Clicked \{n} times"` | string interpolation, `\{expression}` embeds any value |

**Learn MoonBit properly**: the official [Chinese tutorial](https://docs.moonbitlang.com/zh-cn/latest/tutorial/index.html) ([English tutorial](https://docs.moonbitlang.com/en/latest/tutorial/index.html)); if you prefer learning hands-on, the official [Tour of MoonBit](https://tour.moonbitlang.com) walks you through lessons in the browser.

## 5. Next steps

Once your first app runs, pick a path by goal:

**Make it look good** — the first window probes the system light/dark mode and accent color once by default (skipped when you have applied a theme explicitly); for continuous following (live recolor when the system switches), connect it in one `follow_system_theme` line:

```moonbit
handle=fn(a : @widget.WindowHost) -> Unit {
  let _ = a.follow_system_theme(interval_ms=2000)
}
```

Themed forms for `@ui.text` / `@ui.button` (the four `button` `variant`s, `tag` / `alert` / `card`, …) are in [Components overview](../components/index.md); stylesheets (`Style` values plus `hover` / `active` / `focus` states and transitions) in [Layout & styling](layout.md).

**Copy from a working app** — the demo board is the material library: pick a page in the left menu and write against it on the right; each page's source is its own file (`examples/showcase/pages/*.mbt`), ready to copy and adapt. Downloads and how to run: [Try the demos](experience.md).

**Learn the layers** — pick by face:

- [How-to overview](../cookbook/index.md): how-to guides — for concrete goals like "center my content", "add and remove list items" or "refresh on a timer", each with paste-ready code and notes
- [Declarative & reactivity](declarative.md): describe the UI as a node tree (`Node` / `mount_window`) and bind state with `Store` / `Signal`
- [Layout & styling](layout.md): layout styling (the flex / padding / margin fields of `Style`, and the loose parameters plus the `class` channel of `@ui.col` / `@ui.row`)
- [Components overview](../components/index.md): a quick reference to every widget and component's parameters and events
- [System capabilities overview](../capability/sys.md): OS capabilities (`@sys`) — volume / app lookup / wallpaper / monitors / clipboard / power / printers…, with unified `Result` semantics

**Hit a problem** — project-level blockers (package not found, target unavailable, entry file name…) are in the [App developer experience](dev-experience.md); build-time failures (prebuild, linking, dependency packages) are in [Build & run](build.md) §6.

## 6. A note to contributors

This library aims at writing native desktop apps in MoonBit. It now covers self-drawn widgets, charts, Markdown, an embedded WebView, and system capabilities — and there is still a lot worth doing:

- **Platform compatibility**: Windows, Linux (Ubuntu XFCE/GNOME/KDE, Deepin) and macOS (Apple Silicon) are all verified on real devices against the same checklist (`测试文档/测试用例.md`); newly found platform differences are welcome as reports.
- **Widgets and capabilities**: un-wrapped items and per-platform adaptation pitfalls are all welcome as issues first.
- **Docs and examples**: the tutorial, component docs, and every showcase page are open for improvement.

No barrier to taking part: file an issue describing a problem or idea, or send a PR directly. Before you start, remember three things — `moon check` passes with zero errors and zero warnings and `moon test` is all green before committing; field-tested pitfalls go into [adaptation.md](https://github.com/lb091188/moonbit-native-gui/blob/master/experience/adaptation.md) together with their fixes; one cohesive change per batch. The full process (adding example modules, prebuild-hosted linking) is in [Build & run](build.md); the FFI rules are in the repo's `.agents/skills/moonbit-c-binding/`.
