# native-gui

A **cross-platform desktop GUI framework for MoonBit** — one codebase ships native windows on Windows / Linux / macOS, desktop capabilities ready to use. Windows, pixels, the event loop, layout and every widget belong to the library itself and are written in pure MoonBit.

> Formerly `moonbit-libyue` (renamed 2026-10). The mooncakes package is **`NoahLiu/native-gui`** and all existing import paths are unchanged.

![Component showcase on Windows](https://cdn.jsdelivr.net/gh/lb091188/moonbit-native-gui@master/docs/public/images/os-windows.png)

## Highlights

- **🖥 Full system surfaces** — tray, notifications, global shortcuts, clipboard, native menus, file dialogs, drag & drop, autostart and other everyday desktop capabilities work out of the box, plus system queries for volume / power / wallpaper / monitors / printers.
- **🎨 Consistent look, lightweight** — no heavyweight graphics engine; the same widget appearance on all three platforms, with small artifacts and fast startup. Follows the system light/dark mode and accent colour by default, theme fully customizable; built-in control text is localizable (English and Chinese ship with the package).
- **📊 A complete widget set** — layout primitives, form controls, interactive charts and Markdown rendering; the separate `gui-media` adds audio/video playback and display, and `gui-webview` adds web rendering on the system webview.
- **🧩 Capability modules** — the desktop surfaces are separate mooncakes modules you can also consume standalone: `gui-sys` (pure read/write system tools), `gui-window` (windows, tray/notify/hotkey, dialogs), `gui-dbus` (D-Bus/SNI for Linux), `gui-shell` (the six-channel integration facade + i18n).
- **📝 Declarative UI with reactive state** — the interface is described as a tree, mounted in one `mount_window` call; state lives in `Store` / `Signal`, and bound spots refresh with the data.

## Usage

```sh
moon add NoahLiu/native-gui
```

The library builds only for the **native target**: set `preferred_target = "native"` in `moon.mod` and `supported_targets = "native"` in the executable package's `moon.pkg`. Import the packages you need in `moon.pkg` (e.g. `NoahLiu/native-gui/ui` as `@ui`) and mount a window:

```moonbit
fn main {
  let app = match @ui.mount_window(
    [@ui.text("Hello, MoonBit!", font_size=18.0)],
    title="Hello, MoonBit!",
    width=400,
    height=300,
  ) {
    None => return // no window backend or no display service on this host
    Some(a) => a
  }
  app.run()
}
```

Runnable examples in this repository, from shallow to deep — every directory under `examples/` is a standalone module, so `cd` in and `moon run .`:

```sh
cd examples/hello && MOON_WORK=off moon run .
```

`MOON_WORK=off` resolves the example against the published library from the registry, so no other workspace member's prebuild runs; drop it to build against your own working-tree changes.

- `examples/hello` — a minimal window
- `examples/showcase` — full demo board: components + system probes + extended charts, 15 pages
- `examples/browser` — embedded WebView browser (demo menu + status bar)
- `examples/sysmonitor` — system monitor: overview, processes, disks, network and sensors

Each showcase page is its own source file under `examples/showcase/pages/` — the best copy-paste material library.

## Packages

| Import | Alias | Contents |
|---|---|---|
| `NoahLiu/native-gui/base` | `@base` | Platform-free primitives: `Store` / `Signal` / `ListStore`, focus stack, key codes, tick/prof |
| `NoahLiu/native-gui/shell` | `@shell` | System-capability shell: menus, global hotkeys, tray, notifications, reveal, the loop scheduler and read-only platform probes |
| `NoahLiu/native-gui/widget` | `@widget` | Self-drawn widget host: layout mapping, hit-testing, event routing, paint walk, declarative `Node`, overlays, drag & drop, input mapping, the `App` pump |
| `NoahLiu/native-gui/ui` | `@ui` | Self-drawn widgets and the component library: forms, display, navigation, date, tables & virtual lists, entries, scroll, overlays, code view, declarative layer |
| `NoahLiu/native-gui/render` | `@render` | Rasterizer — a pure-MoonBit software raster (path / fill / blend / gradient) plus a Cairo backend; bitmaps, canvas, images, PNG |
| `NoahLiu/native-gui/text` | `@text` | Text layer: font families, fonts, attributed text and range attributes (Pango / DirectWrite) |
| `NoahLiu/native-gui/theme` | `@theme` | Theme system: palette derivation + change subscription |
| `NoahLiu/native-gui/icons` | `@icons` | Vector icon system (800+ icons) |
| `NoahLiu/native-gui/sys` | `@sys` | OS capabilities: autostart, idle, subprocesses, environment, files, JSON, dialogs, browser history / bookmarks, recent files, wallpaper, volume, power plans, printers, monitors, window controls, app lookup |
| `NoahLiu/native-gui/input` | `@input` | Editing core and key codes |
| `NoahLiu/native-gui/win` | `@win` | Platform window backend (Win32 / GTK3 C stubs) |
| `NoahLiu/native-gui/dbus` | `@dbus` | Linux D-Bus bridge (tray SNI, notifications, logind / upower, media, network…) |
| `NoahLiu/native-gui/chart` | `@chart` | Charts plus the interactive layer |
| `NoahLiu/native-gui/mdview` | `@mdview` | Markdown rendering view |
| `NoahLiu/native-gui/style` | `@style` | Style layer: stylesheets as MoonBit values — `Style` rule blocks, hover / active / focus states, transitions |
| `NoahLiu/native-gui/i18n` | `@i18n` | UI text i18n: TOML catalog lookup with interpolation and plurals, subscribable language switching; built-in control text ships in English and Chinese |
| `NoahLiu/native-gui/router` | `@router` | Single-window page routing: route tree, per-level selected keys and link bindings — any component can navigate via `on_link` |

Optional capabilities in **separate modules** (a plain `moon add` of this module never drags them in):

| Module | Contents |
|---|---|
| `NoahLiu/gui-media` | Audio/video engine (ffmpeg decode + miniaudio output) and the player component |
| `NoahLiu/gui-webview` | Embedded WebView (WebKitGTK / WebView2), extracted from this module's `web` subpackage on 2026-10-16 |

## Platform support

| | Windows | Linux | macOS |
|---|---|---|---|
| Status | ✅ 10 / 11 | ✅ X11 mainline | ✅ Apple Silicon, verified on device |
| Notes | GUI-subsystem exe: double-click opens no console window | Ubuntu 24.04 and Deepin 23 / 25 verified; Deepin 20 is not a support target until MoonBit fixes it. Wayland sessions run, X11-dependent capabilities degrade per session | Cocoa / CoreText / ImageIO / WKWebView; verified on Apple Silicon with the same checklist as Windows / Linux |

## Roadmap

Where this library is heading (see the public roadmap for the full picture):

1. **Rendering performance** — an optional GPU-composited backend (WebGPU), per-widget GPU drawing, per-frame redraw scoping, layout caching and incremental chart redraws.
2. **Windows** — key-routing fallback after in-window page switches, so keystrokes reach the page after navigation.
3. **Input & overlays** — selection and copy for static text (read-only editor with hit-testing, selection highlight and Ctrl+C / context-menu copy).
4. **Further content** — an embeddable terminal widget, a WebGL canvas host, macOS GIF frame-disposal composition.

Explicit non-goals: accessibility APIs, GTK4 / Qt backends, and platform-native widget skins — the self-drawn stack is the product.

**Versioning**: at `0.x` the interfaces still evolve per batch; breaking changes are recorded in commit messages and the docs ship in the same batch.

## Documentation

- Repository root [README](https://github.com/lb091188/moonbit-native-gui) — architecture, package map, contributing and gates
- [Documentation site](https://moonbit-native-gui.pages.dev/) — usage docs, Chinese version under [`/zh/`](https://moonbit-native-gui.pages.dev/zh/)
- [Public roadmap](https://github.com/lb091188/moonbit-native-gui/blob/master/docs/zh/roadmap.md) (Chinese) — positioning, support matrix, commitments, non-goals

MIT License.
