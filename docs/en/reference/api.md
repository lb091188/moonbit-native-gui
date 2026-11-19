# Package layout & API reference

`moon add NoahLiu/native-gui` brings in the whole module. MoonBit compiles and links only the packages you import, so unused packages add nothing to your binary.

The complete API reference is generated on mooncakes.io from the source doc comments: types and function signatures per package, documentation, and links to source lines, with a version switcher for past releases. Each alias below links straight to its package:

**[Open the native-gui API reference ↗](https://mooncakes.io/docs/NoahLiu/native-gui)**

| Alias | Contents |
|---|---|
| [@base](https://mooncakes.io/docs/NoahLiu/native-gui/base) | Platform-free primitives: the `Store` / `Signal` / `ListStore` reactive core, the focus stack, key-code constants, end-of-frame batching and the frame ledger |
| [@shell](https://mooncakes.io/docs/NoahLiu/native-gui/shell) | System-capability shell: menu bars / context menus, the global-hotkey facade, tray, notifications, open-externally, plus the loop scheduler and read-only platform probes |
| [@widget](https://mooncakes.io/docs/NoahLiu/native-gui/widget) | Widget host: layout-tree mapping, hit-testing and event routing, paint walk, declarative `Node`, overlays (layer and native tiers), drag & drop, input mapping, the `WindowHost` pump |
| [@ui](https://mooncakes.io/docs/NoahLiu/native-gui/ui) | Controls and the component library: window mounting, labels / buttons, forms, display, navigation, date, tables and virtual lists, entries, scrolling, overlays, code view, declarative layer (see [Components overview](../components/index.md)) |
| [@render](https://mooncakes.io/docs/NoahLiu/native-gui/render) | Canvas and images: canvas, bitmaps, images & PNG (see [Canvas](../components/canvas.md)) |
| [@text](https://mooncakes.io/docs/NoahLiu/native-gui/text) | Text layer: font families, fonts, rich text and range attributes (Pango / DirectWrite) |
| [@theme](https://mooncakes.io/docs/NoahLiu/native-gui/theme) | Theme system: palette derivation and change subscription |
| [@icons](https://mooncakes.io/docs/NoahLiu/native-gui/icons) | Vector icon system |
| [@sys](https://mooncakes.io/docs/NoahLiu/native-gui/sys) | System capabilities: autostart, idle, subprocess, environment, files, JSON, dialogs, browser history / bookmarks, recent files, wallpaper, volume, power, printers, monitors, window control, app lookup (see [Overview](../capability/sys.md)) |
| [@input](https://mooncakes.io/docs/NoahLiu/native-gui/input) | Editing core and key codes |
| [@win](https://mooncakes.io/docs/NoahLiu/native-gui/win) | Platform window layer: windows, shortcuts, icons, IME, message boxes, notifications, tray |
| [@dbus](https://mooncakes.io/docs/NoahLiu/native-gui/dbus) | Linux D-Bus bridge: tray SNI, notifications, logind / upower, media, network, screensaver |
| [@chart](https://mooncakes.io/docs/NoahLiu/native-gui/chart) | Charts and the cross-cutting interaction layer |
| [@mdview](https://mooncakes.io/docs/NoahLiu/native-gui/mdview) | Markdown rendering view |
| [@style](https://mooncakes.io/docs/NoahLiu/native-gui/style) | Style layer: stylesheets as MoonBit values, with state classes and transitions (see [Layout & styling](../guide/layout.md)) |
| [@i18n](https://mooncakes.io/docs/NoahLiu/native-gui/i18n) | UI copy localization: TOML catalog lookup / interpolation / plurals, with locale-change subscription; built-in control copy ships in English and Chinese |
| [@router](https://mooncakes.io/docs/NoahLiu/native-gui/router) | Single-window page routing: route tree + per-level selected key + link binding; any component can navigate via `on_link` |

Heavier capabilities live in **separate modules** and are optional:

| Module | Contents |
|---|---|
| [NoahLiu/gui-media](https://mooncakes.io/docs/NoahLiu/gui-media) | Audio/video engine and player components |
| [NoahLiu/gui-webview](https://mooncakes.io/docs/NoahLiu/gui-webview) | Embedded WebView (WebKitGTK / WebView2 / WKWebKit) |

Usage and recipes live in the guide on the left; the API reference is authoritative for signatures.
