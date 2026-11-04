# App Developer Experience

What a project looks like, the two levels of `moon add` vs `import`, why the two manual adjustments are needed, and the most common first-time blockers. Shortest runnable path: the [five-minute tutorial](tutorial.md). See it run without writing code: [Try the demos](experience.md).

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
