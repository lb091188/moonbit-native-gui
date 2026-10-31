# App Developer Experience

The complete path from zero to your first window: on a fresh machine, a native desktop app written in MoonBit with native-gui within minutes. Written for app developers who have never used MoonBit. If you just want to see it run without writing code, the [experience guide](experience.md) has prebuilt packages.

## 1. Install the toolchain

One line for the MoonBit toolchain:

```sh
# Linux / macOS
curl -fsSL https://cli.moonbitlang.com/install/unix.sh | bash
# Windows (PowerShell)
irm https://cli.moonbitlang.com/install/powershell.ps1 | iex
```

The library goes through native FFI, so building also needs a C toolchain plus Python 3 (and the GTK3 dev packages on Linux): per-platform install lists and a self-check are in [Build & run](build.md) §2. On Windows, moon locates MSVC itself — a plain shell just works.

## 2. Create the project

```sh
moon new my_app
cd my_app
moon add NoahLiu/native-gui
```

The current `moon new` template: the root package is a library (`my_app.mbt` and an empty `moon.pkg`), and the executable entry lives in the `cmd/main/` sub-package (`main.mbt` + `moon.pkg`).

`moon add` writes only the **module-level** dependency (the import in `moon.mod`); its job is to make the library's packages resolvable. The **package-level** import must be declared separately, in the `moon.pkg` of the package that uses them. Skip it and every `@ui` in your code reports an unresolved package — the first blocker most newcomers hit, see §3 ①.

## 3. Two manual adjustments

**① `cmd/main/moon.pkg`** — declare the packages you use and the target (moon's DSL format, not JSON):

```
import {
  "NoahLiu/native-gui/ui" @ui,
}

pkgtype(kind: "executable")

supported_targets = "native"
```

The `import` list decides which aliases your code can reference: `@ui` provides the widgets, components, and the declarative entry (`mount_window` and the node constructors). Add more as needed — reactive state `@base`, style classes `@style`, the app host `@widget`, system capabilities `@sys`; the 15-alias table is in [Package layout](packages.md). Packages you don't import are neither compiled nor linked, costing no binary size.

**② `moon.mod`** — change `preferred_target = "wasm"` to `"native"`. Every package in this library supports only the native backend; leave it as wasm and the build reports an unsupported-target error.

Transitive dependencies are automatic: `yoga-mbt` and friends are declared by the library itself and land in `.mooncakes/` after `moon add` — nothing to add by hand.

## 4. First window

Replace `cmd/main/main.mbt` with:

```moonbit
fn main {
  let app = match @ui.mount_window(
    [@ui.text("Hello, MoonBit!", font_size=18.0)],
    title="Hello, MoonBit!",
    width=400,
    height=300,
  ) {
    None => {
      // no window backend or no display service on this host
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

A window appears — the path is through.

## Common blockers

| Symptom | Cause and fix |
|---|---|
| `@ui` reports an unresolved package | the package-level import is missing from `cmd/main/moon.pkg` — `moon add` only touches `moon.mod` (module level), see §3 ① |
| build reports package not available on wasm / unsupported target | `preferred_target` in `moon.mod` is still the template's wasm default — change it to native, see §3 ② |
| `Missing main function` | moon only recognizes a file literally named `main.mbt` as the program entry — the template already puts it in `cmd/main/`; keep that file name when creating your own entry files |
| Linux fails at the start: missing GTK headers / `pep-0263` error | build dependencies incomplete, or `python` still points to 2.7 — see [Build & run](build.md) §2 and §6 |
| the program exits with no window | `mount_window` returned `None`: no window backend or no display service (e.g. an SSH session without X) — the structured exit is expected behavior |

## Next steps

- [Five-minute tutorial](tutorial.md): a MoonBit syntax crash course plus a click counter (the minimal form of `Store` reactivity)
- [Components](components.md) · [Declarative & reactivity](declarative.md) · [Layout & styling](layout.md) · [System capabilities](system-capabilities.md)
- Clone the repository and run the examples: every showcase page is its own source file, ready to copy and adapt — entry points in the [experience guide](experience.md) §2
