# Experience Guide

Three ways to use native-gui; this guide covers the first two. For working on the library itself, head straight to [Build & run](build.md).

## 1. Try it for real: prebuilt packages

### Download and first run

Open [GitHub Releases](https://github.com/lb091188/moonbit-native-gui/releases) and pick the **Binaries** release (one fixed name, always the latest build), one zip per platform:

| Package | Platform |
|---|---|
| `bin-windows-x64.zip` | Windows 10/11 x64 |
| `bin-macos-arm64.zip` | Apple Silicon macOS |
| `bin-linux-x64.zip` | x64 Linux |

Every zip contains the same five executables plus third-party notices (`THIRD-PARTY-NOTICES.md`):

| Executable | Content |
|---|---|
| `hello` | Minimal window (baseline for binary size and startup time) |
| `showcase` | Full demo board: widget families, 14 interactive chart types, Markdown / code views, theme following, system-integration page, system-capability probe page |
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

#### hello — minimal window

Launch and a native window appears, with no third-party windowing library behind it — the tangible sample of the lightweight-artifact / fast-startup claim.

#### showcase — components / charts / system capabilities

Switch pages in the left sidebar:

- **Basic components / Form components / Data display**: the ready-made widget families — buttons, inputs, tables, trees, virtual scrolling
- **Charts page**: line / bar / pie / gauge / scatter / radar / heatmap / candlestick / funnel / box / sankey / tree / treemap / sunburst — 14 kinds with a cross-cutting interaction layer (hover readouts)
- **Theme**: dark/light and accent color follow the system; the follow switch lives in the menu (picking a color manually turns following off — expected)
- **System integration page**: live demos of the tray, desktop notification, global shortcut, autostart, clipboard and other facade APIs
- **System capability probe page**: five read-only probe groups (system desktop / monitors & windows / app & files / browser data / clipboard & power & bus), demonstrating capability detection with structured degradation — an unavailable capability reports a structured reason instead of failing silently

#### browser — embedded WebView

- Address-bar navigation, back/forward and history
- A local site served through the custom scheme (local content channel)
- JS interop: execute-and-fetch in the page, JS↔native two-way binding demos
- The "policy trigger" menu entries (new window / geolocation / download): intercepted and reported by default, allow from the dialog — the library's policy loop, right there

#### audio / video — media line

Playback / progress / speed control, external and embedded subtitle tracks, A/V sync under speed changes. FFmpeg dynamic libraries are bundled in the Windows / macOS packages; Linux uses the system FFmpeg.

### Known platform differences (honest scope)

- **macOS notifications**: require an `.app` bundle launch — the packages ship `.app` bundles now, so double-click launches should have them (real-machine verification in progress); running the bare binary from `Contents/MacOS` still reports unavailable, an OS constraint, not a library defect.
- **Linux**: media and `browser` depend on system FFmpeg and WebKit2gtk respectively — see the install list above.
- Platform status follows the [README platform table](https://github.com/lb091188/moonbit-native-gui) and the [roadmap](zh/roadmap.md): all three platforms are verified on real machines.

## 2. Build apps on the library

In your own project:

```sh
moon add NoahLiu/native-gui
```

Minimal window:

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

Going deeper: [Components](components.md), [Declarative & reactivity](declarative.md), [Layout & styling](layout.md), [System capabilities](system-capabilities.md), [Embedded WebView](webview.md).

## 3. Working on the library

Adding widgets, fixing platforms, reporting compatibility: the toolchain and dependency setup, build gates, test policy and troubleshooting all live in [Build & run](build.md); the package composition is in [Package layout](packages.md); how to contribute is in the README.
