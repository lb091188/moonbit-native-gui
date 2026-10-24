# native-gui [![CI](https://github.com/lb091188/moonbit-native-gui/actions/workflows/ci.yml/badge.svg)](https://github.com/lb091188/moonbit-native-gui/actions/workflows/ci.yml)

> **Where it came from**: this library started as a MoonBit binding of [Cheng Zhao (zcbenz)](https://github.com/zcbenz)'s [Yue / libyue](https://github.com/yue/yue), with layout following [Yoga](https://github.com/facebook/yoga)'s flexbox. Neither is a runtime dependency any more — both stay as references for behaviour and as sources of material. Thanks also to [MoonBit](https://github.com/moonbitlang).

A **cross-platform desktop GUI framework** for [MoonBit](https://github.com/moonbitlang) — one MoonBit codebase ships native windows on Windows 🟩 / Linux 🟩 / macOS 🟩, with tray, notifications, shortcuts, file dialogs and other desktop capabilities ready to use and zero configuration after `moon add`. All three platforms (Windows / Linux / macOS) share one codebase and one synchronised real-machine checklist.

English | [简体中文](README_ZH.md)

📚 **Documentation**: <https://moonbit-native-gui.pages.dev/>

![Component showcase](./docs/public/images/showcase-main.png)
![Live demo on Linux (XFCE)](./docs/public/images/showcase-anim-linux.webp)
![Live demo on Windows](./docs/public/images/showcase-anim-windows.webp)

## Highlights

**🖥 Full system surfaces** — tray, notifications, global shortcuts, clipboard, native menus, file dialogs, drag & drop, autostart and other desktop essentials work out of the box, plus system queries for volume / power / wallpaper / monitors / printers.

**🎨 Self-drawn rendering pipeline** — no Skia-class graphics engine; widgets look the same on every platform, follow the system accent colour and light/dark mode by default, and the theme is fully customizable.

**📊 A complete widget set** — layout primitives, form controls, interactive charts, Markdown rendering; separately, `gui-media` brings audio/video playback and display, and `gui-webview` brings web rendering on the system webview.

**📝 Declarative UI and reactive state** — the interface is described as a tree and mounted in one `mount_window` call; state lives in `Store` / `Signal`, and bound spots refresh with the data:

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

> `cd examples/showcase && moon run .` — the demo board: basic components, interactive icons, system surfaces.

## Ecosystem position

GUI capability in the MoonBit ecosystem has more than one lane: [MoUI](https://github.com/wzzc-dev/MoUI) is built on the Skia rendering engine and targets interface logic shared across platforms, while native-gui renders through the system and aims at **one-stop delivery for desktop apps** — system capabilities out of the box, common widgets consistent across platforms, everyday applications finished in one place.

## Package layout

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
| `NoahLiu/gui-media` | Audio/video engine and player components. |
| `NoahLiu/gui-webview` | Embedded WebView (WebKitGTK / WebView2 / WKWebKit). |

## Quick start

The prerequisite is the MoonBit native toolchain. New to MoonBit? The [documentation site](https://moonbit-native-gui.pages.dev/) covers the toolchain and your first window.

In your own project:

```sh
moon add NoahLiu/native-gui
```

To see it running, clone the repository and run an example — every directory under `examples/` is a standalone module, so **`cd` in and `moon run .`**:

```sh
git clone https://github.com/lb091188/moonbit-native-gui.git
cd moonbit-native-gui/examples/hello   # or any directory in the table below
moon run .
```

| Directory | What it is |
|---|---|
| `examples/hello` | Minimal window: one native window plus basic controls |
| `examples/showcase` | Full demo board: component library, interactive icons, charts, system surfaces |
| `examples/sysmonitor` | System monitor: `/proc`·`/sys` data plus self-drawn charts |
| `examples/browser` | Embedded WebView (extra dependency `gui-webview`) |
| `examples/audio` · `video` | Audio/video players (extra dependency `gui-media`, needs ffmpeg — see [build.md](docs/build.md)) |
| `examples/headless-audio` | No window; playback driven purely from code |

## Platform support

| Platform | Status | Notes |
|---|---|---|
| Ubuntu 24.04 | ✅ | XFCE / GNOME / KDE / Cinnamon |
| Deepin 23 / 25 | ✅ | |
| Windows 10 / 11 | ✅ | |
| macOS | ✅ | Apple Silicon |

## Contributing

Platform compatibility reports, widgets and documentation are all welcome. The basics:

- **Commit gate**: in `gui/`, `moon check` plus `moon test ui render text theme icons sys input win dbus chart mdview style base shell widget` must be clean — zero errors, zero warnings
- **Write down what you learn**: field-tested pitfalls and fixes are recorded with the code, not only in commit messages
- **Small batches**: one coherent change per commit, short commit messages
- **Roadmap**: what is done and what comes next is on the [roadmap](https://moonbit-native-gui.pages.dev/zh/roadmap) (Chinese)

[docs/zh/build.md](docs/zh/build.md) (Chinese): building, linking, adding an example module.

## License

`native-gui` is released under the [MIT License](LICENSE). Third-party assets and their licenses are listed in [THIRD-PARTY-NOTICES.md](docs/THIRD-PARTY-NOTICES.md).

## References

- [MoonBit documentation](https://docs.moonbitlang.cn/)
- Projects this library learned from: [Yue / libyue](https://github.com/yue/yue) · [Yoga](https://github.com/facebook/yoga)
