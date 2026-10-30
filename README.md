# native-gui [![CI](https://github.com/lb091188/moonbit-native-gui/actions/workflows/ci.yml/badge.svg)](https://github.com/lb091188/moonbit-native-gui/actions/workflows/ci.yml)

> **Where it came from**: this library started as a MoonBit binding of [Cheng Zhao (zcbenz)](https://github.com/zcbenz)'s [Yue / libyue](https://github.com/yue/yue), with layout following [Yoga](https://github.com/facebook/yoga)'s flexbox. Neither is a runtime dependency any more — both stay as references for behaviour and as sources of material. Thanks also to [MoonBit](https://github.com/moonbitlang).

A **cross-platform desktop GUI framework** for [MoonBit](https://github.com/moonbitlang) — one MoonBit codebase ships native windows on Windows 🟩 / Linux 🟩 / macOS 🟩, with tray, notifications, shortcuts, file dialogs and other desktop capabilities ready to use and zero configuration after `moon add`. All three platforms (Windows / Linux / macOS) share one codebase and one synchronised real-machine checklist.

English | [简体中文](README_ZH.md)

📚 **Documentation**: <https://moonbit-native-gui.pages.dev/>

📦 **Zero-setup demos**: prebuilt packages for all three platforms (hello / showcase / browser / audio / video) are on [GitHub Releases](https://github.com/lb091188/moonbit-native-gui/releases) — unzip and run; where to click and what to look for: the [experience guide](https://moonbit-native-gui.pages.dev/experience).

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

## Quick start

Three lanes, the same split as the [experience guide](https://moonbit-native-gui.pages.dev/experience):

**1. Zero-setup demo** — grab the platform zip from the single [Binaries](https://github.com/lb091188/moonbit-native-gui/releases) release, unzip and run; the walkthrough lives in the [experience guide](https://moonbit-native-gui.pages.dev/experience).

**2. Build an app on the library** — lanes 2 and 3 need a development environment: the MoonBit native toolchain, a C toolchain, Python 3, pkg-config and — on Linux — the GTK3 family of dev packages; install lists in [Build & run](https://moonbit-native-gui.pages.dev/build). In your own project:

```sh
moon add NoahLiu/native-gui
```

To see it running, clone the repository and run an example — every directory under `examples/` is a standalone module, so **`cd` in and `moon run .`**:

```sh
git clone https://github.com/lb091188/moonbit-native-gui.git
cd moonbit-native-gui/examples/hello   # or any directory in the table below
MOON_WORK=off moon run .               # resolve the published library from the registry; drop it to run against your own changes
```

| Directory | What it is |
|---|---|
| `examples/hello` | Minimal window: one native window plus basic controls |
| `examples/showcase` | Full demo board: component library, interactive icons, charts, system surfaces |
| `examples/browser` | Embedded WebView (extra dependency `gui-webview`) |
| `examples/audio` · `video` | Audio/video players (extra dependency `gui-media`, needs ffmpeg) |
| `examples/headless-audio` | No window; playback driven purely from code |

If `moon run` fails before it ever opens a window, it is almost always a missing build dependency — see [Build & run](https://moonbit-native-gui.pages.dev/build).

**3. Work on the library** — toolchain and dependency setup, build gates, test policy and troubleshooting all live in [Build & run](https://moonbit-native-gui.pages.dev/build); the package composition is in [Package layout](https://moonbit-native-gui.pages.dev/packages).

## Platform support

| Platform | Status | Notes |
|---|---|---|
| Ubuntu 24.04 | ✅ | XFCE / GNOME / KDE / Cinnamon |
| Deepin 23 / 25 | ✅ | |
| Deepin 20 / Debian 10 base | ❌ | **not a supported target**: this library builds through prebuild on the Python 3.7 baseline, but the wall is `SYS_pidfd_open` in the runtime C sources that ship with the MoonBit toolchain (glibc's frozen syscall table — new kernel headers don't add it). Pitfalls and self-rescue notes: [Build & run](https://moonbit-native-gui.pages.dev/build) |
| Windows 10 / 11 | ✅ | |
| macOS | ✅ | Apple Silicon |

## Contributing

Platform compatibility reports, widgets and documentation are all welcome. The basics:

- **Commit gate**: in `gui/`, `moon check` plus `moon test ui render text theme icons sys input win dbus chart mdview style base shell widget` must be clean — zero errors, zero warnings
- **Write down what you learn**: field-tested pitfalls and fixes are recorded with the code, not only in commit messages
- **Small batches**: one coherent change per commit, short commit messages
- **Roadmap**: what is done and what comes next is on the [roadmap](https://moonbit-native-gui.pages.dev/zh/roadmap) (Chinese)

[Build & run](https://moonbit-native-gui.pages.dev/build): environment from scratch, build commands and artefact paths, prebuilt binaries, failure → fix, plus the linking mechanism and how to add an example module.

## License

`native-gui` is released under the [MIT License](LICENSE). Third-party assets and their licenses are listed in [THIRD-PARTY-NOTICES.md](docs/THIRD-PARTY-NOTICES.md).

## References

- [MoonBit documentation](https://docs.moonbitlang.cn/)
- Projects this library learned from: [Yue / libyue](https://github.com/yue/yue) · [Yoga](https://github.com/facebook/yoga)
