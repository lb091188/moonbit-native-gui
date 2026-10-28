---
layout: home
hero:
  name: native-gui
  text: A cross-platform desktop GUI framework for MoonBit
  tagline: One MoonBit codebase ships native Windows 🟩 / Linux 🟩 / macOS 🟩 windows, with desktop capabilities ready to use and zero config after moon add — all three on the same real-device checklist.
  actions:
    - theme: brand
      text: Get started in 5 minutes
      link: /tutorial
    - theme: alt
      text: Build & environment
      link: /build
    - theme: alt
      text: Package structure
      link: /README
    - theme: alt
      text: GitHub
      link: https://github.com/lb091188/moonbit-native-gui
features:
  - title: Self-drawn widgets, one look everywhere
    details: The library's own rasterizer draws every control, so rendering is identical across platforms; light/dark mode and the system accent color are followed by default, and the theme is fully customizable.
  - title: Declarative UI with reactive state
    details: Describe the interface as a tree of @widget.Node values and mount it with one mount_window call; keep state in Store / Signal and bound spots refresh themselves.
  - title: Desktop-grade system integration
    details: Tray, notifications, native menus, global shortcuts, file dialogs, drag & drop, clipboard, autostart and OS queries sit behind one @sys / @shell facade; the system-probe page shows this machine's real readings item by item.
  - title: Content batteries included
    details: 20 chart types with a cross-cutting interactive layer, a GFM Markdown view and multi-language code highlighting; the embedded WebView and the audio/video engine live in the optional gui-webview / gui-media modules.
  - title: Honest degradation
    details: Every capability family exposes a probe and returns a structured Unsupported / NotFound on environments that lack it, instead of crashing or pretending success.
  - title: Pay only for what you import
    details: 15 packages in the main module — an unimported package never enters your binary; heavier capabilities (the WebView, media) live in their own modules, outside the default dependency closure.
---

## Quick start

```sh
moon add NoahLiu/native-gui
```

```moonbit
fn main {
  let app = match @ui.mount_window(
    [@ui.text("Hello, MoonBit!", font_size=18.0)],
    title="Hello, MoonBit!",
    width=400,
    height=300,
  ) {
    None => {
      // no window backend or no display service on this platform
      return
    }
    Some(a) => a
  }
  app.run()
}
```

`@ui.*` comes from `NoahLiu/native-gui/ui` — the full package table is in the [documentation index](/README).

Before `moon add`, get the environment in place: the library uses native FFI, so it needs a C toolchain, Python 3 and (on Linux) the GTK3 family of development packages. The per-platform lists, the self-check commands and what to do when a build fails immediately are all in [Build & run](/build).
