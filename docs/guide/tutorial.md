# Getting started

Build a desktop app from scratch — one window, one button, and a counter that refreshes on every click — then walk through the project mechanics, single-file components, and debugging tools. The only prerequisite is the build environment: the MoonBit toolchain and per-platform dev packages, installed per [Build & run](build.md) §1–§3. If you would rather see results first without installing anything, take [Run the prebuilt packages](experience.md).

## 1. Create the project

```sh
moon new my_app
cd my_app
moon add NoahLiu/native-gui
```

The current `moon new` template: the root package is a library (`my_app.mbt` and an empty `moon.pkg`), and the executable entry lives in the `cmd/main/` sub-package (`main.mbt` + `moon.pkg`). Two hard rules:

- moon only recognizes a file named `main.mbt` as the program entry — keep that file name when creating your own entry files, or you get `Missing main function`.
- The root `moon.pkg` stays empty; dependencies are declared only in `cmd/main/moon.pkg`.

`moon add NoahLiu/native-gui` writes only the **module-level** dependency (the `import` in `moon.mod`), which makes the library's packages resolvable; the **package-level** `import` must be written separately in the `moon.pkg` of the package that uses it. Skip that and `@ui` in your code reports "package not found" — the number one first-time blocker, see §6. The `import` list decides which aliases your code can reference: `@ui` provides the widgets, components, and the declarative entry (`mount_window` and the node constructors); reactive state `@base`, style classes `@style`, the app host `@widget`, and system capabilities `@sys` are added as needed — the 17-alias table is in [Package layout](../reference/packages.md). Packages you don't import are neither compiled nor linked, costing no binary size; the standard library `moonbitlang/core` is injected by moon automatically and does not belong in the import list; transitive dependencies need no attention — the library declares them itself and `moon add` drops them into `.mooncakes/` automatically.

The project needs two manual adjustments:

- **`moon.mod`: change `preferred_target = "wasm"` to `"native"`** — this library uses native FFI and supports only the native backend (no wasm); without the change the build reports "package does not support the current target". Skip if the template already defaults to native.

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

  This lists every package the code on this page uses, all at once; in practice write only what you need — the minimum is the single `ui` line.

## 2. Your first window

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

A window appears: a title, a button, and a "Clicked 0 times" line. Click the button and the number ticks up by itself. That is **reactive state**: when `count` changes, `bind_label` refreshes on its own — no "update the text on click" glue code. The UI is declared as a tree of **node constructors** (`@ui.col([...])` / `@ui.text(...)` / `@ui.button(...)`) and mounted in one `mount_window` call; `mount_window` returns `None` when there is no window backend or no display service, and the example exits accordingly — expected behaviour, not a fault.

## 3. MoonBit syntax at a glance (only what the code above uses)

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

## 4. Single-file components (.mng)

Write the UI as a declarative template and the state/logic in MoonBit — both in one `.mng` file; the `mng` tool pre-compiles it to `.mbt` and the normal `moon build` takes over. `moon check` remains the only type gate. Full semantics live in `proposals/native-template.md`; a runnable minimal example is `examples/hello` (the page body is the single-file `hello.mng`).

### Install

From the repository root (the tool ships with this repo):

```sh
moon install ./tools/native-gui-tools/mng
mng --version   # prints mng 0.2.11 and mng-schema 1
```

CLI prompts and errors switch between Chinese and English via `LC_ALL` / `LC_MESSAGES` / `LANG` (a `zh` prefix selects Chinese); when these are absent the system UI language is consulted (Windows), defaulting to Chinese if still unknown; the `dev` watch log and compiler diagnostics stay in Chinese.

For editor support install the VS Code extension from `tools/vscode-mng` (coloring / completion / hover / jump / diagnostics; saving runs `moon check` and feeds type errors back into Problems — see its README).

### Start

- **New project**: `mng new my_app` generates a runnable minimal project (dependency versions are read live when generated inside the native-gui workspace; explicit form `mng new app my_app`) — `cd my_app && moon run .`.
- **Add a page to an existing project**: `mng new page pages/about` generates a single-page `.mng` sample (the parent directory is created if missing).
- **Wire templates into an existing project**: `mng init` writes `mng.toml`.

### What a page looks like

```html
<script>
let count : @base.Store[Int] = @base.Store::new(0)
let name : @base.Store[String] = @base.Store::new("")

fn reset() {
  count.set(0)
  name.set("")
}
</script>
<template>
  <ui-col class="page">
    <ui-input v-model="name" placeholder="Your name" width="220.0" />
    Hello, {{ name }}!
    <ui-stepper v-model="count" max="10" />
    Count: {{ count }}
    <ui-button text="Reset" @click="reset" />
  </ui-col>
</template>
<style>
  .page { padding: 24px; row-gap: 8px; align-items: center; }
</style>
```

Key points:

- Directives: interpolation `{{ }}`, `:attr` dynamic attributes, `@event` handlers, `v-model` (binds a Store directly), `v-if`/`v-else-if`/`v-else`, `v-show`, `v-for` (source must be a keyed `@base.ListStore`, `:key="it.id"` recommended); single-root template.
- Component tags: the built-in `ui-*` table; same-package components are plain `fn name`; cross-package `let name = @pkg.fn`.
- Parameterized components: the first `fn` in the script with a signature but no body is the props header (required as positional, optional as `name? : Type = default`).
- Styles go into the `<style>` block (class selectors + `var(--token)` + states/dark variants); style literals on template attributes are compile errors — put them in `<style>` or `class`.
- Expressions are pasted into MoonBit verbatim: concatenate with `{{ }}` or `"\{x}"` interpolation — MoonBit's `+` does not concatenate non-strings.

### dev / build

- `mng init` writes `mng.toml` at the module root (templates / build / run / app-id / theme); `mng dev` and `mng build` look it up upwards when run without arguments, falling back to `moon.mod`/`moon.work` defaults.
- `mng dev`: watches all project templates + project sources (`.mbt`/`moon.pkg`/`moon.mod`/`moon.work`) + theme files; the first run generates the dev-form `<stem>.gen.mbt` next to each template and starts the app. Change classes: structure/class/style values/restricted expressions apply hot in under a second; script, v-for row templates and new symbols fall back to a COLD restart which reopens the edited page; `.mng` files created while dev runs are generated and built automatically, deletions clean up (or warn about) generated code. The hot-reload facade lives in the library package `@mngdev` — one `import "NoahLiu/native-gui/mngdev" @mngdev` line in the template package's `moon.pkg` (already written by `mng new`); the app no longer copies any dev-facade `.mbt`.
- `mng build`: with no arguments generates **production-form** generated code for the whole project (zero dev traces); `mng build <input> -o <out>` compiles a single file. dev and production forms share the same `<stem>.gen.mbt` and overwrite each other — pick one before committing (CI compares both and accepts either).

### Wiring the generated code

Generated code lands next to the template: `<stem>.gen.mbt` provides `pub fn <stem>() -> @widget.Node`, wired like any function:

```moonbit
@ui.mount_window([hello()], title="Template Hello", width=420, height=360)
```

Commit the generated code (consumers need no toolchain); it carries a `// GENERATED … DO NOT EDIT` header — regenerate after editing the template instead of hand-editing.

### Common pitfalls

| Symptom | Cause and fix |
|---|---|
| `v-for 源须是 @base.ListStore` | Source was a Store/Signal or plain variable — declare `let rows : @base.ListStore[T] = @base.ListStore::new()` |
| `v-for 与 v-if 不写在同一元素` | Separate them with a container (outer v-if around v-for, or v-if inside the row) |
| `String + Int` type errors | Expressions are pasted verbatim — use `{{ }}` or `"\{x}"` interpolation; MoonBit's `+` does not concatenate non-strings |
| `moon check` says generated code is stale | Regenerate with `mng dev` (dev form) or `mng build` (production form) and commit |
| Conflicting generated functions in one package | Two `.mng` files share a stem — rename one |
| HOT fell back to COLD | v-for row templates / script / new symbols are COLD by design; the `[HOT→COLD]` log line says why |

## 5. Built-in Inspector (debugging your UI)

Library package `NoahLiu/native-gui/inspector` (import on demand); mount a read-only panel into any container:

```moonbit
// moon.pkg: "NoahLiu/native-gui/inspector"
@inspector.inspector_panel(refresh_ms=500, auto=false, table_h=240.0, width=640.0)
```

Three blocks:

- **Widget tree**: sourced from the `@widget.a11y_last_frame()` end-of-frame semantic snapshot — the same one screen readers see; invisible subtrees are entirely absent, and the panel itself appears in the tree (expected); indented by parent chain, click a row to select
- **Selected readouts**: id / parent / role / name / state / value / text / enabled / window rect
- **Frame cost**: `@base.paint_profile_summary()` (layout/paint/present totals and max frame); "Reset" zeroes the ledger

Refresh reads the "previous frame" snapshot — interact first, then refresh, or turn on auto refresh (500ms self-rearming timer).

**v2 write-back** (the "Style classes" tab): lists named classes from the `@style` registry (the same port mngdev style hot-reload writes); pick one and edit background/text/border colour/border width/radius (base and `:hover` each); "Apply" runs `@style.define_class` and widgets using the class pick up the new style next frame; "Restore" puts back the snapshot captured when the class list was first refreshed this session. Empty input = leave the field; both token names and `#hex` are accepted. The editor covers five common fields; everything else goes through template source or `mng dev` patches.

## 6. Common blockers

| Symptom | Cause and fix |
|---|---|
| `@ui` reports "package not found" | `cmd/main/moon.pkg` is missing the package-level import — `moon add` only changes `moon.mod` (module level), see §1 |
| Build reports "package does not support wasm / target unavailable" | `preferred_target` in `moon.mod` is still the template default wasm; change it to native, see §1 |
| `Missing main function` | moon only treats a file named `main.mbt` as the program entry, see §1 |
| `Parsing error: unexpected token {` (reading `moon.pkg`) | `moon.pkg` is moon's DSL format, not JSON — don't write `{ ... }`; keep the root `moon.pkg` empty |
| `Cannot inject the standard library moonbitlang/core: Cannot load the core file` | the toolchain installed incompletely (usually an interrupted `moon upgrade` with `~/.moon/lib` lost) — rerun the official install script; unrelated to your project |
| Red from the start on Linux: missing GTK headers / `pep-0263` | build dependencies incomplete, or `python` still points at 2.7 — the list is in [Build & run](build.md) §2, the fixes are its first two rows of §6 |
| The program exits immediately, no window | `mount_window` returned `None`: no window backend or no display service (e.g. an SSH session without X) — the structured exit is expected |
| Code changed but behaviour did not | a C stub change does not always trigger a relink, see [Build & run](build.md) §9 |

Deeper build-time failures (prebuild interpreters, workspace contamination, Windows link libraries, vendor downloads) are in [Build & run](build.md) §6, each with root cause and fix.

## 7. Next steps

Once your first app runs, pick a path by goal:

**Make it look good** — the first window probes the system light/dark mode and accent color once by default (skipped when you have applied a theme explicitly); for continuous following (live recolor when the system switches), connect it in one `follow_system_theme` line:

```moonbit
handle=fn(a : @widget.WindowHost) -> Unit {
  let _ = a.follow_system_theme(interval_ms=2000)
}
```

Themed forms for `@ui.text` / `@ui.button` (the four `button` `variant`s, `tag` / `alert` / `card`, …) are in [Components overview](../components/index.md); stylesheets (`Style` values plus `hover` / `active` / `focus` states and transitions) in [Layout & styling](layout.md).

**Copy from a working app** — the demo board is the material library: pick a page in the left menu and write against it on the right; each page's source is its own file (`examples/components/pages/*.mbt`), ready to copy and adapt. Downloads and how to run: [Run the prebuilt packages](experience.md) §2.

**Learn the layers** — pick by face:

- [How-to overview](../cookbook/index.md): how-to guides — for concrete goals like "center my content", "add and remove list items" or "refresh on a timer", each with paste-ready code and notes
- [Declarative & reactivity](declarative.md): describe the UI as a node tree (`Node` / `mount_window`) and bind state with `Store` / `Signal`
- [Layout & styling](layout.md): layout styling (the flex / padding / margin fields of `Style`, and the loose parameters plus the `class` channel of `@ui.col` / `@ui.row`)
- [Components overview](../components/index.md): a quick reference to every widget and component's parameters and events
- [System capabilities overview](../capability/sys.md): OS capabilities (`@sys`) — volume / app lookup / wallpaper / monitors / clipboard / power / printers…, with unified `Result` semantics

Project-level blockers (package not found, target unavailable, entry file name…) are back in §6 of this page; build-time failures (prebuild, linking, dependency packages) are in [Build & run](build.md) §6.

## 8. A note to contributors

This library aims at writing native desktop apps in MoonBit. It now covers self-drawn widgets, charts, Markdown, an embedded WebView, and system capabilities — and there is still a lot worth doing:

- **Platform compatibility**: Windows, Linux (Ubuntu XFCE/GNOME/KDE, Deepin) and macOS (Apple Silicon) are all verified on real devices against the same checklist (`测试文档/测试用例.md`); newly found platform differences are welcome as reports.
- **Widgets and capabilities**: un-wrapped items and per-platform adaptation pitfalls are all welcome as issues first.
- **Docs and examples**: the tutorial, component docs, and every component-gallery page are open for improvement.

No barrier to taking part: file an issue describing a problem or idea, or send a PR directly. Before you start, remember three things — `moon check` passes with zero errors and zero warnings and `moon test` is all green before committing; field-tested pitfalls go into [adaptation.md](https://github.com/lb091188/moonbit-native-gui/blob/master/experience/adaptation.md) together with their fixes; one cohesive change per batch. The full process (adding example modules, prebuild-hosted linking) is in [Build & run](build.md); the FFI rules are in the repo's `.agents/skills/moonbit-c-binding/`.
