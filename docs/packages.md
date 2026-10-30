# Package layout

`moon add NoahLiu/native-gui` brings in the whole module. MoonBit compiles and links only the packages you import, so unused packages add nothing to your binary:

| Alias | Contents |
|---|---|
| `@base` | Platform-free primitives: the `Store` / `Signal` / `ListStore` reactive core, the focus stack, key-code constants, end-of-frame batching and the frame ledger |
| `@shell` | System-capability shell: menu bars / context menus, the global-hotkey facade, tray, notifications, open-externally, plus the loop scheduler and read-only platform probes |
| `@widget` | Self-drawn widget host: layout-tree mapping, hit-testing and event routing, paint walk, declarative `Node`, overlays (layer and native tiers), drag & drop, input mapping, the `App` pump |
| `@ui` | Self-drawn controls and the component library: window mounting, labels / buttons, forms, display, navigation, date, tables and virtual lists, entries, scrolling, overlays, code view, declarative layer |
| `@render` | Rasterizer: pure-MoonBit software raster plus a Cairo backend; bitmaps, canvas, images, PNG |
| `@text` | Text layer: font families, fonts, rich text and range attributes (Pango / DirectWrite) |
| `@theme` | Theme system: palette derivation and change subscription |
| `@icons` | Vector icon system |
| `@sys` | System capabilities: autostart, idle, subprocess, environment, files, JSON, dialogs, browser history / bookmarks, recent files, wallpaper, volume, power, printers, monitors, window control, app lookup |
| `@input` | Editing core and key codes |
| `@win` | Platform window backends (Win32 / GTK3 C stubs): hotkeys, icons, input methods, message boxes, notifications, tray, surfaces |
| `@dbus` | Linux D-Bus bridge: tray SNI, notifications, logind / upower, media, network, screensaver |
| `@chart` | Charts and the cross-cutting interaction layer |
| `@mdview` | Markdown rendering view |
| `@style` | Style layer: stylesheets as MoonBit values, with state classes and transitions |

Heavier capabilities live in **separate modules** and are optional:

| Module | Contents |
|---|---|
| `NoahLiu/gui-media` | Audio/video engine and player components |
| `NoahLiu/gui-webview` | Embedded WebView (WebKitGTK / WebView2 / WKWebKit) |
