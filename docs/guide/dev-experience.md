# App Developer Experience

Shortest runnable path: the [five-minute tutorial](tutorial.md). See it run without writing code: [Try the demos](experience.md).

## 1. What a project looks like

`moon new my_app` gives you a template whose root package is a library (`my_app.mbt` and an empty `moon.pkg`), with the executable entry in the `cmd/main/` sub-package (`main.mbt` + `moon.pkg`). Two hard rules:

- moon only recognizes a file named `main.mbt` as the program entry — keep that file name when creating your own entry files, or you get `Missing main function`.
- The root `moon.pkg` stays empty; dependencies are declared only in `cmd/main/moon.pkg`.

## 2. moon add and import are two different things

`moon add NoahLiu/native-gui` writes only the **module-level** dependency (the `import` in `moon.mod`), which makes the library's packages resolvable; the **package-level** `import` must be written separately in the `moon.pkg` of the package that uses it. Skip that and `@ui` in your code reports "package not found" — the number one first-time blocker, see item 1 below.

The `import` list decides which aliases your code can reference: `@ui` provides the widgets, components, and the declarative entry (`mount_window` and the node constructors). Add more as needed — reactive state `@base`, style classes `@style`, the app host `@widget`, system capabilities `@sys`; the 17-alias table is in [Package layout](../reference/packages.md). Packages you don't import are neither compiled nor linked, costing no binary size. The standard library `moonbitlang/core` is injected by moon automatically — it does not belong in the import list. Transitive dependencies need no attention: the library declares them itself and `moon add` drops them into `.mooncakes/` automatically.

## 3. The two manual adjustments

**① `cmd/main/moon.pkg`** — add the packages you use and declare the target platform (moon's DSL format, not JSON):

```
import {
  "NoahLiu/native-gui/ui" @ui,
}

pkgtype(kind: "executable")

supported_targets = "native"
```

**② `moon.mod`** — change `preferred_target = "wasm"` to `"native"`. Every package of this library supports only the native backend (native FFI, no wasm); without the change the build reports "package does not support the current target".

## 4. Your first window

Follow the [five-minute tutorial](tutorial.md) §3: replace `cmd/main/main.mbt` and run `moon run cmd/main`. `mount_window` returns `None` when there is no window backend or no display service, and the example exits accordingly — expected behaviour, not a fault.

## 5. Single-file components (.mng)

Write the UI as a declarative template and the state/logic in MoonBit — both in one `.mng` file; the `mng` tool pre-compiles it to `.mbt` and the normal `moon build` takes over. `moon check` remains the only type gate. Full semantics live in `proposals/native-template.md`; a runnable minimal example is `examples/template-hello`.

### Install

From the repository root:

```sh
moon install ./tools/native-gui-tools/mng
mng --version   # prints mng 0.2.10 and mng-schema 1
```

CLI prompts and errors switch between Chinese and English via `LC_ALL` / `LC_MESSAGES` / `LANG` (a `zh` prefix selects Chinese); when these are absent the system UI language is consulted (Windows), defaulting to Chinese if still unknown; the `dev` watch log and compiler diagnostics stay in Chinese.

For editor support install the VS Code extension from `tools/vscode-mng` (coloring / completion / hover / jump / diagnostics; **saving runs `moon check` and feeds type errors back into Problems** — see its README).

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

## Common blockers

| Symptom | Cause and fix |
|---|---|
| `@ui` reports "package not found" | `cmd/main/moon.pkg` is missing the package-level import — `moon add` only changes `moon.mod` (module level), see §2 |
| Build reports "package does not support wasm / target unavailable" | `preferred_target` in `moon.mod` is still the template default wasm; change it to native, see §3 ② |
| `Missing main function` | moon only treats a file named `main.mbt` as the program entry, see §1 |
| `Parsing error: unexpected token {` (reading `moon.pkg`) | `moon.pkg` is moon's DSL format, not JSON — don't write `{ ... }`; keep the root `moon.pkg` empty |
| `Cannot inject the standard library moonbitlang/core: Cannot load the core file` | the toolchain installed incompletely (usually an interrupted `moon upgrade` with `~/.moon/lib` lost) — rerun the official install script; unrelated to your project |
| Red from the start on Linux: missing GTK headers / `pep-0263` | build dependencies incomplete, or `python` still points at 2.7 — the list is in [Build & run](build.md) §2, the fixes are its first two rows of §6 |
| The program exits immediately, no window | `mount_window` returned `None`: no window backend or no display service (e.g. an SSH session without X) — the structured exit is expected |
| Code changed but behaviour did not | a C stub change does not always trigger a relink, see [Build & run](build.md) §9 |

Deeper build-time failures (prebuild interpreters, workspace contamination, Windows link libraries, vendor downloads) are in [Build & run](build.md) §6, each with root cause and fix.

## Next steps

- [Five-minute tutorial](tutorial.md): MoonBit syntax at a glance + the click counter (the minimal form of `Store` reactivity)
- [Components overview](../components/index.md) · [Declarative & reactivity](declarative.md) · [Layout & styling](layout.md) · [System capabilities overview](../capability/sys.md)
- Clone the repo and run the examples: each showcase page's source is its own file, ready to copy and adapt — entry point in [Try the demos](experience.md) §2
