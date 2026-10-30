# Experience Guide

Run native-gui on all three platforms with **zero setup**: grab the prebuilt demo packages from GitHub Releases and walk each demo's what-to-try points. Prefer building from source? See §5.

## 1. Download prebuilt packages

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
| `audio` / `video` | Audio / video player demos with bundled media files (`assets/audio`, `assets/video`; FFmpeg dynamic libraries are bundled in the Windows / macOS packages) |

## 2. First run

**Windows**: unzip and double-click the `.exe`; no console window appears. The WebView2 Runtime needed by `browser` ships with the OS.

**macOS**: the bundled `.dylib` files must stay in the same directory as the executables. The first launch of each binary gets one Gatekeeper block (the packages are ad-hoc signed, not notarized, and the downloaded zip carries the quarantine attribute). Two ways past it:

1. **Clear quarantine in a terminal (recommended, unblocks all five at once)**:

   ```sh
   xattr -dr com.apple.quarantine <folder>
   ```

2. **The GUI way (macOS 15+; right-click → Open no longer offers a bypass)**: click Done on the block dialog → System Settings → Privacy & Security → the Security section → **Open Anyway** next to the blocked app (valid for about an hour after the block, per executable).

**Linux**: unzip, `chmod +x <file>`, run. Runtime libraries (preinstalled on Ubuntu 24.04; install by name on other distros):

```sh
sudo apt install libgtk-3-0 libpango-1.0-0 libx11-6 \
  libwebkit2gtk-4.1-0 libavcodec60 libavformat60 libswscale7
```

## 3. What to try, per demo

### hello — minimal window

Launch and a native window appears, with no third-party windowing library behind it — the tangible sample of the lightweight-artifact / fast-startup claim.

### showcase — components / charts / system capabilities

Switch pages in the left sidebar:

- **Basic components / Form components / Data display**: the ready-made widget families — buttons, inputs, tables, trees, virtual scrolling
- **Charts page**: line / bar / pie / gauge / scatter / radar / heatmap / candlestick / funnel / box / sankey / tree / treemap / sunburst — 14 kinds with a cross-cutting interaction layer (hover readouts)
- **Theme**: dark/light and accent color follow the system; the follow switch lives in the menu (picking a color manually turns following off — expected)
- **System integration page**: live demos of the tray, desktop notification, global shortcut, autostart, clipboard and other facade APIs
- **System capability probe page**: five read-only probe groups (system desktop / monitors & windows / app & files / browser data / clipboard & power & bus), demonstrating capability detection with structured degradation — an unavailable capability reports a structured reason instead of failing silently

### browser — embedded WebView

- Address-bar navigation, back/forward and history
- A local site served through the custom scheme (local content channel)
- JS interop: execute-and-fetch in the page, JS↔native two-way binding demos
- The "policy trigger" menu entries (new window / geolocation / download): intercepted and reported by default, allow from the dialog — the library's policy loop, right there

### audio / video — media line

Playback / progress / speed control, external and embedded subtitle tracks, A/V sync under speed changes. FFmpeg dynamic libraries are bundled in the Windows / macOS packages; Linux uses the system FFmpeg.

## 4. Known platform differences (honest scope)

- **macOS notifications**: only available when launched from an `.app` bundle; running the bare binary reports unavailable — an OS constraint, not a library defect. Tray / hotkeys and the rest work from the bare binary.
- **Linux**: media and `browser` depend on system FFmpeg and WebKit2gtk respectively — see the §2 install list.
- Platform status follows the [README platform table](https://github.com/lb091188/moonbit-native-gui) and the [roadmap](zh/roadmap.md): all three platforms are verified on real machines.

## 5. Building from source

Install the [MoonBit toolchain](https://www.moonbitlang.com), then:

```sh
git clone https://github.com/lb091188/moonbit-native-gui
cd moonbit-native-gui
moon run examples/showcase --target native   # or examples/<other>
```

Dependency setup and failure fixes are in [Build & run](build.md); see the [tutorial](tutorial.md) for a five-minute start.
