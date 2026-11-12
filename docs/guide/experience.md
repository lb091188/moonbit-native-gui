# Experience Guide

Prebuilt packages (§1); clone the repository and run the examples (§2). For building your own app, the from-zero path is in [Getting started](tutorial.md); for working on the library itself, head straight to [Build & run](build.md).

## 1. Try it for real: prebuilt packages

### Download and first run

Open [GitHub Releases](https://github.com/lb091188/moonbit-native-gui/releases) and pick the **Binaries** release (one fixed name, always the latest build), one zip per platform; in China, get it from the [Gitee mirror](https://gitee.com/noahliu0911/moonbit-native-gui/releases/tag/bin):

| Package | Platform |
|---|---|
| `bin-windows-x64.zip` | Windows 10/11 x64 |
| `bin-macos-arm64.zip` | Apple Silicon macOS |
| `bin-linux-x64.zip` | x64 Linux |

Every zip contains the same five executables plus third-party notices (`THIRD-PARTY-NOTICES.md`):

| Executable | Content |
|---|---|
| `hello` | Starter sample: an `.mng` single-file declarative page + basic window demos (multi-window / tray) |
| `components` | Component gallery: widget families, 19 interactive chart types, Markdown / code views, theme following |
| `browser` | Embedded browser demo: address-bar navigation, local site, JS interop, policy interception |
| `audio` / `video` | Audio / video player demos with bundled media files; FFmpeg dynamic libraries are bundled in the Windows / macOS packages |

**Windows**: unzip and double-click the `.exe`; no console window appears. The WebView2 Runtime needed by `browser` ships with the OS.

**macOS**: the five apps are `.app` bundles — after unzipping, **double-click to run**, no Terminal involved. The first launch of each app gets one Gatekeeper block (the packages are ad-hoc signed, not notarized, and the downloaded zip carries the quarantine attribute). Two ways past it:

1. **Clear quarantine in a terminal (recommended, unblocks all five at once)**:

   ```sh
   xattr -dr com.apple.quarantine <folder>
   ```

2. **The GUI way (macOS 15+; right-click → Open no longer offers a bypass)**: click Done on the block dialog → System Settings → Privacy & Security → the Security section → **Open Anyway** next to the blocked app (valid for about an hour after the block, per app).

The `.dylib` files in `lib/` are shared by all five apps — keep that folder next to the `.app` bundles.

**Linux**: unzip, `chmod +x <file>`, run. Runtime libraries (preinstalled on Ubuntu 24.04; install by name on other distros):

```sh
sudo apt install libgtk-3-0 libpango-1.0-0 libx11-6 \
  libwebkit2gtk-4.1-0 libavcodec60 libavformat60 libswscale7
```

### What to try, per demo

#### hello — starter sample and basic window demos

The top half is an `.mng` single-file declarative page (name input with live greeting, count stepper); the bottom half is a command-style basic window demo: three preset windows (memo / palette / about) **toggle open/close** (one window per preset; the button label follows the state), every child window carries a "close this window" button, and the status line shows the live window count; a tray icon stays resident (monochrome silhouette that follows the system light/dark mode, left-click counter). Run `mng dev` and edit the template to watch hot reload.

#### components — component gallery

Switch pages in the left sidebar:

- **Basic components / Form components / Data display**: the ready-made widget families — buttons, inputs, tables, trees, virtual scrolling
- **Charts pages**: line / bar / pie / gauge / scatter / radar / heatmap / candlestick / funnel / box / sankey / relationship / parallel / pictorial bar / sunburst / theme river / tree / treemap / effect scatter — 19 kinds with a cross-cutting interaction layer (hover readouts, zoom & pan, and more)
- **Theme**: dark/light and accent color follow the system; the follow switch lives in the menu (picking a color manually turns following off — expected)

Live demos of the tray, notifications, autostart, single instance and other system capabilities live in `examples/system` (see §2); the drawing board and rich text live in `examples/canvas`.

#### browser — embedded WebView

- Address-bar navigation, back/forward and history
- A local site served through the custom scheme (local content channel)
- JS interop: execute-and-fetch in the page, JS↔native two-way binding demos
- The "policy trigger" menu entries (new window / geolocation / download): intercepted and reported by default, allow from the dialog — the library's policy loop, right there

#### audio / video — media line

Playback / progress / speed control, external and embedded subtitle tracks, A/V sync under speed changes. FFmpeg dynamic libraries are bundled in the Windows / macOS packages; Linux uses the system FFmpeg.

### Known platform differences (honest scope)

- **macOS notifications**: require an `.app` bundle launch — the packages ship `.app` bundles, and notifications work on double-click launch (verified on device); running the bare binary from `Contents/MacOS` still reports unavailable, an OS constraint, not a library defect.
- **Linux**: media and `browser` depend on system FFmpeg and WebKit2gtk respectively — see the install list above.
- Platform status follows the [README platform table](https://github.com/lb091188/moonbit-native-gui) and the [roadmap](/zh/reference/roadmap.md): all three platforms are verified on real machines.

## 2. Run the repository examples

Beyond the prebuilt packages, you can also clone the repository and run the examples directly (the MoonBit toolchain is needed first — see [Build & run](build.md) §1) — every directory under `examples/` is a standalone module, so **`cd` in and `moon run .`**:

```sh
git clone https://github.com/lb091188/moonbit-native-gui.git
cd moonbit-native-gui/examples/hello   # or any directory in the table below
MOON_WORK=off moon run .               # resolve the published library from the registry; drop it to run against your own changes
```

| Directory | What it is |
|---|---|
| `examples/hello` | Starter sample: `.mng` single-file page + basic window demos (multi-window / tray, hot-reloadable via `mng dev`) |
| `examples/components` | Component gallery: all widgets / charts / themes (the `components` prebuilt package) |
| `examples/canvas` | Drawing board and rich text: interactive board (mouse freehand + keyboard lines), Painter drawing, AttributedText |
| `examples/system` | System capabilities: system integration (dialogs / notifications / tray / autostart / single instance / self-update) + read-only probes, left grouped menu |
| `examples/browser` | Embedded WebView browser (extra dependency `gui-webview`) |
| `examples/audio` · `video` | Audio/video players (extra dependency `gui-media`, needs ffmpeg) |
| `examples/sysmonitor` | System monitor: six-item resource menu (CPU / memory / network / disks / GPU / processes) with per-core charts, physical NICs, physical partitions and process management |
| `examples/theme-playground` | Theme fitting room: tune one theme and watch it apply globally |

Beyond the examples: [Components overview](../components/index.md), [Declarative & reactivity](declarative.md), [Layout & styling](layout.md), [System capabilities overview](../capability/sys.md), [Embedded WebView](../capability/webview.md).

## 3. Working on the library

Adding widgets, fixing platforms, reporting compatibility: the toolchain and dependency setup, build gates, test policy and troubleshooting all live in [Build & run](build.md); the package composition is in [Package layout & API reference](../reference/api.md); how to contribute is in the README.
