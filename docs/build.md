# Build & run

The full path from an empty machine to a running window: what to install, what to type, where the artefacts land, what to grab if you would rather not build, and how to fix the errors (§1–§6). The second half covers the mechanism behind all of it — how link flags are hosted, the stub-edited-but-not-relinked pitfall, and where vendored files come from (§7–§12). The rationale and the per-platform field records live in the "Build & linking" section of [adaptation.md](https://github.com/lb091188/moonbit-native-gui/blob/master/proposals/adaptation.md).

## 1. Install the MoonBit toolchain

```sh
# Linux / macOS
curl -fsSL https://cli.moonbitlang.com/install/unix.sh | bash
# Windows (PowerShell)
irm https://cli.moonbitlang.com/install/powershell.ps1 | iex
```

Then check `moon version --all`: moon / moonc / core must come from the same install. A `moon upgrade` that dies halfway in a non-interactive terminal swaps the binaries but leaves `~/.moon/lib/core` behind, and the mixed versions surface as "no method" on code that is fine.

## 2. Install the development dependencies

The library draws its own pixels over native FFI, so a build needs four things: **a C toolchain, pkg-config, Python 3, and — on Linux — the GTK3 / Pango / FontConfig / X11 development packages**. Python 3 is not optional: the link parameters are produced by `gui/scripts/prebuild.py`, which moon executes when building a native target (which interpreter actually runs it is the first row of §6).

### Linux (Debian / Ubuntu family)

```sh
sudo apt install build-essential pkg-config python3 \
  libgtk-3-dev libpango1.0-dev libfontconfig1-dev libx11-dev
```

Add only what you use: `libwebkit2gtk-4.1-dev` for the embedded WebView (`@web`); `libavformat-dev libavcodec-dev libswscale-dev libswresample-dev libavutil-dev` for the media modules (`NoahLiu/gui-media` / `ffmpeg-mbt`).

⚠️ **The `python` command itself must be Python 3.** On deepin 20, CentOS 7 and similar machines `/usr/bin/python` is still 2.7, moon picks it first, and the Chinese comments at the top of the script trip `SyntaxError: Non-ASCII character ... pep-0263` — every native build fails before it starts. Both fixes are in the first row of §6.

### macOS

Xcode's command line tools are all you need — no GTK, no brew. Windows, text and image decoding go through the system Cocoa / CoreText / ImageIO frameworks: prebuild compiles the Objective-C stubs itself and emits the `-framework` flags.

```sh
xcode-select --install
```

The media module additionally needs ffmpeg: `brew install ffmpeg`, or let prebuild fetch our own arm64 archive from Releases (§10).

### Windows (10 / 11, x64)

Python 3 plus the MSVC C++ toolchain — Python 3 runs prebuild, and the toolchain is the "Desktop development with C++" workload of VS 2022 Build Tools:

```powershell
winget install Python.Python.3.12
winget install Microsoft.VisualStudio.2022.BuildTools -e --override "--quiet --wait --norestart --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended"
```

moon **locates MSVC out of the box** on Windows: plain PowerShell / Git Bash can `moon run` directly, without the "x64 Native Tools Command Prompt" or a manual `call vcvars64.bat`. "Also install CMake and ATL" belongs to the old CMake-based build chain and does not apply here.

## 3. Verify the environment

```sh
moon version --all                 # the three pieces come from one install
python -V && python3 -V            # both must be 3.x — the first one especially
pkg-config --modversion gtk+-3.0   # Linux: a version number = dev packages present
cc --version                       # Linux / macOS: a C toolchain is reachable
```

Windows has no pkg-config step; the check there is simply that `moon build --target native` gets through linking.

## 4. Build and run

### In your own project

```sh
moon add NoahLiu/native-gui
moon run . --target native
```

Link parameters are emitted by the library's prebuild to every main package that depends on it. `moon.pkg` carries no `link` section and no `cc-link-flags` — hand-writing them conflicts with prebuild (§8).

### In this repository

The repo is a `moon.work` workspace holding the library, the probes, five sub-modules, seven examples and the tools. **Name the modules you build; don't sweep the whole workspace**: a bare `moon test` also pulls in examples / experiment / the media modules, which have platform-coverage gaps that are not library defects.

```sh
cd gui && moon check                       # library gate: zero errors, zero warnings
cd gui && moon test ui render text theme icons sys input win dbus chart mdview style base shell widget
cd examples/hello && moon run .            # any example: cd in and run
moon build examples/showcase --target native   # from the repo root, by path
```

### Artefact locations and release builds

```sh
moon build examples/hello --target native --release --strip
```

Artefacts follow the module name: `_build/native/<debug|release>/build/<module>/<module>.exe`. MoonBit's native backend **appends `.exe` on all three platforms** (Linux and macOS included) — rename it when you use it. On macOS, `scripts/make_app.sh` wraps the artefact into a `.app`.

## 5. Rather not build: prebuilt binaries

**The honest state of things**: Releases currently carries one entry, `vendor-v1`, and it holds the **build-time vendor inputs** (the two FFmpeg archives, `miniaudio.h`, the WebView2 pair — see §10), not double-clickable applications. The binary release chain is in place (`release-bin.yml`: push a `bin-*` tag → Linux and Windows each build the hello + showcase pair → `bin-linux-x64.zip` / `bin-windows-x64.zip` attached to the Release), but **the new stack has not published a bin release yet**; macOS artefacts are not published, per that workflow's header note.

So "let me just see it" still means building one example per §4 — `examples/hello` needs nothing beyond the dependency list in §2.

## 6. Failure → fix

| Symptom | Cause | Fix |
|---|---|---|
| `SyntaxError: Non-ASCII character '\xe7' ... but no encoding declared; see pep-0263` followed by `Failed to run prebuild script` | moon **ignores the shebang** for `.py` prebuild scripts and takes the first usable interpreter in PATH in the order `python` → `python3`, which lands on Python 2 | One-off: `MOON_PYTHON_OVERRIDE=python3 moon build`. Permanent: `ln -s "$(command -v python3)" ~/.local/bin/python`, make sure that directory is first in PATH, then **open a new terminal** (Debian-family only prepends `~/.local/bin` at login, and only if it already exists) |
| `Running prebuild script for module ... needs \`python\` or \`python3\` executable in PATH` | no Python 3 on the machine | install python3 per §2 |
| prebuild prints "缺少 gtk+-3.0 开发包"-style warnings on stderr and keeps going, then linking fails with `undefined reference to gtk_*` / `pango_*` | development packages incomplete: when a probe fails, prebuild only warns and **emits no link entry**, so the error surfaces one step later | install the apt list from §2, re-run `moon build`; add `moon clean` if it still links the old result |
| `Package 'webkit2gtk-4.1' not found`, and only `@web` is unusable | not a defect, by design: without webkit, `@web` degrades to a placeholder and the capability reports `Unsupported` rather than breaking the whole link | install `libwebkit2gtk-4.1-dev` if you need the embedded browser |
| `moon.mod.json ... is no longer supported` | a third-party package in the dependency cache still ships the old manifest (the registry side cannot be rewritten) | run `moon fmt` over each `.mooncakes/**/moon.{mod,pkg}.json` until resolution converges (what CI does) |
| You edited `gui/<pkg>/*.c` but behavior is unchanged, and `moon build` says `no work to do` | a stub edit does not necessarily trigger a relink | §9 |
| prebuild hangs on a download or reports a sha256 mismatch | a vendor file is missing and no mirror is reachable | §10: point `NATIVE_GUI_VENDOR_BASE` at a mirror, or place the file by hand |
| audio / video on Windows reports a missing DLL | the FFmpeg runtime DLLs are not in place | §10 "Windows runtime FFmpeg DLLs" |
| `Failed to acquire file lock` | another moon process holds the build directory (IDE and terminal running at once) | wait for it to finish |

`moon check` does not execute prebuild — it only type-checks and lints. So "check is green, build fails immediately" is almost always one of the prebuild rows above; don't go reading library source for it.

## 7. Where linking comes from

- moon runs the library module's `gui/scripts/prebuild.py` at build time, wired up via `options(--moonbit-unstable-prebuild)` in `gui/moon.mod`. It emits `link_configs` for the current system and propagates them automatically to every main package that depends on this library module. The declaration carries a script path only, **no command field** — which interpreter runs it is moon's choice per the first row of §6.
- prebuild also probes system libraries: on Linux it looks for GTK3 / Pango / FontConfig / X11, `webkit2gtk-4.1` for the embedded WebView, and ffmpeg for the media module. If GTK is not found, it exits non-zero with a fix hint; if webkit is not found, `@web` degrades to a placeholder implementation and the capability reports `Unsupported`, instead of failing the whole link.
- The result: after `moon add NoahLiu/native-gui`, `moon run` works with zero configuration. Link flags are never written and should not be written.

## 8. Notes for contributors

- Library packages carry no `link` section — moon would generate an `.exe` without a `main`, and the build fails.
- Never hand-write `cc-link-flags` — linking is emitted entirely by prebuild; manual edits conflict with it.
- New platform C capabilities follow the "single `stub.c`, multiple branches + prebuild macros" layout; see `gui/win/stub.c` for precedent. The link flags still belong to prebuild.

The rules for aligning FFI declarations with trampolines are in `.agents/skills/moonbit-c-binding/`.

## 9. The one pitfall: editing a C stub doesn't relink

moon compiles `.c` / `.cpp` native stubs into a static library, so changing stub code does not necessarily trigger a relink: `moon build` may report `no work to do` and keep running the old exe, and `moon test` binaries link the stale archive the same way. In both cases the symptom is "the code changed but the behavior didn't", and an old crash may still be there.

**Tell**: you edited `gui/<pkg>/*.c` or `.cpp`, but `moon build` says there is nothing to do and the behavior is unchanged.

**Fix**, pick one:

```sh
moon clean                 # full rebuild, the easiest path
# or delete only the matching artifacts (paths vary with build layout and target):
rm -rf gui/_build/native/**/build/<pkg>/     # recompile this package
rm -rf _build/native/debug/build/examples/<example>/<example>   # relink this example
```

Then run `moon build` / `moon test` again: the stub is recompiled and a fresh exe is linked.

When debugging, first reproduce with a new main target: a fresh target is always linked fresh. If main runs fine but the test crashes, the test binary almost certainly linked a stale archive, not a logic bug. The finer per-platform records are in [adaptation.md](https://github.com/lb091188/moonbit-native-gui/blob/master/proposals/adaptation.md).

## 10. Vendored large files and mirrors

Three third-party files — plus both FFmpeg runtime archives (the Windows dll zip and the macOS arm64 dylib tarball) — are kept out of git; committing them would permanently bloat the git history. They are downloaded by **each module's own prebuild** when missing. Anything already in place is left alone; prebuild only fills gaps.

| File | Downloaded by | When |
|---|---|---|
| `WebView2LoaderStatic.lib` (11 MB), `WebView2.h` (2.8 MB) | `modules/gui-webview/prebuild.py` | **Windows only**; Linux / macOS skip them and save 14 MB |
| `miniaudio.h` (4 MB) | `modules/gui-media/prebuild.py` | Whenever missing (every platform compiles it) |
| `ffmpeg-windows-x64-9.0-lgpl-shared.zip` (~64 MB, 7 dlls) | `modules/ffmpeg-mbt/prebuild.py` | **Windows only**, when the runtime dlls are missing; falls back to BtbN upstream |
| `ffmpeg-macos-arm64-9.0.2-lgpl-shared.tar.gz` (~10 MB, 5 dylibs + headers) | same script | **macOS arm64 only**, when `vendor/mac` is missing; machines with brew ffmpeg go through pkg-config and skip it |

Those two FFmpeg archives are **built by us**, not upstream artefacts (macOS is compiled from source with an LGPLv3, `@rpath`-only closure; the Windows zip repackages the runtime dlls from a BtbN lgpl-shared build). Their license texts and the LGPL source-offer obligation are recorded in [THIRD-PARTY-NOTICES.md](/THIRD-PARTY-NOTICES.md).

- **Verification first**: a file is written only if its sha256 matches the constant in that prebuild script, so any mirror is verifiable.
- **Mirrors**: GitHub Release → Gitee, with no latency probing — but the modules differ. Webview and ffmpeg **race the mirrors in parallel** (whichever returns a sha-verified file first wins, so the total cost is the fastest mirror); gui-media tries them serially in order.
- **Timeouts**: 20 s per source, plus an overall **budget** (`urlopen`'s timeout is socket-level — it does not cover DNS stalls or a slow trickle, and relying on it alone can hang a build). The budget scales with size: 60 s for the mac archive, `miniaudio.h` and the WebView2 pair; **360 s** for the 64 MB Windows dll archive — otherwise "data still flowing, budget already spent" kills that path.
- **Swapping or adding a source**: edit one line of `VENDOR_BASES` in `modules/gui-webview/prebuild.py` and of `_VENDOR_BASES` in `modules/gui-media/prebuild.py` (a third copy, `modules/ffmpeg-mbt/prebuild.py`, handles the dll archive with the same mirror and timeout rules). The three copies are deliberate — every module must be able to publish standalone. Don't go looking for "two copies": run `grep -rn "releases/download/vendor-v1" --include=prebuild.py .` and count them. **The Gitee user differs from GitHub** (the repo lives under `noahliu0911` on Gitee vs `lb091188` on GitHub); copying the wrong one returns 404, and it only shows up when GitHub is unreachable.
- **Intranet and offline**: the `NATIVE_GUI_VENDOR_BASE` environment variable takes a single base or a comma-separated list, tried first; setting it also disables the parallel race (webview goes serial). You can also place the files at their target paths by hand.
- If every source fails, prebuild does not abort; it prints the manual-placement hint and leaves the missing-file error to the link step.

Licenses and provenance: [THIRD-PARTY-NOTICES.md](/THIRD-PARTY-NOTICES.md).

### Windows runtime FFmpeg DLLs (prerequisite for audio / video)

On Windows, `ffmpeg-mbt` is linked by prebuild against the `vendor/*.lib` import libraries, so the produced exe depends at load time on five DLLs: `avcodec-63` / `avformat-63` / `avutil-61` / `swscale-10` / `swresample-7` (`avdevice-63` / `avfilter-12` are version-locked companions; the full list is quoted as seven).

- **Missing DLLs no longer crash at startup**: those five are delay-loaded, and the build bakes the absolute path of `vendor/win/bin` into the exe — on first call `ffmpeg_supported()` resolves them in the order "exe directory / PATH → build-time directory" (`src/ffmpeg_win_dll.c`, `/DELAYLOAD`). If none is found, the media backend reports unavailable and the window still opens.
- **No DLL juggling during development**: the `ffmpeg-windows-…zip` download in the table above exists exactly for this — it is unpacked into `modules/ffmpeg-mbt/vendor/win/bin` (not committed), which the loader falls back to. Projects pulled in via `moon add` benefit from the same path. macOS is symmetric: `vendor/mac` or brew ffmpeg (pkg-config); Linux: the system FFmpeg dev package (`libav*-dev`, probed via pkg-config).
- **App-local staging is only needed for release / distribution**: put the DLLs next to the exe (the loader's first search location), or let the script do it (it runs `moon build` first when the exe is missing; `--run` launches afterwards):

```sh
python scripts/win_ffmpeg_dll.py                 # stage both audio and video
python scripts/win_ffmpeg_dll.py audio           # audio only
python scripts/win_ffmpeg_dll.py video --run     # stage, then launch
python scripts/win_ffmpeg_dll.py --dll-dir D:\ffmpeg\bin   # you already have a bin dir
python scripts/win_ffmpeg_dll.py --dry-run       # print the plan only
```

  Source order: `--dll-dir` → exe directory → prebuild location → PATH → winget → scoop → old cache; re-run once after `moon clean` (DLLs follow the exe directory).
- **Manual sourcing**: `winget install BtbN.FFmpeg.LGPL.Shared.9.0` — same provenance as the `vendor/` import libraries (BtbN / LGPL / **shared** / 9.0). ⚠️ Don't use `Gyan.FFmpeg`: those are static builds (`bin/` holds three exe files and zero DLLs — nothing to borrow); BtbN's `*.GPL` static branches are the same. Look for **Shared**; package managers only place files somewhere, they don't make DLLs findable — it is still app-local or PATH.
- Bundling and version-string obligations when shipping prebuilt binaries: [THIRD-PARTY-NOTICES.md](/THIRD-PARTY-NOTICES.md).

## 11. Adding an example module

Dependency isolation is per module, not per package: the imports in `moon.mod` decide a module's whole dependency closure, and `moon.pkg` can only pick packages already resolved there. So "one example must not drag in the others" requires **one module per example** — packing several examples into one `moon.mod` re-couples them. To add one:

1. Create `examples/<name>/` with `main.mbt` + `moon.pkg`, and its **own** `moon.mod`:
   `name = "NoahLiu/native-gui-examples-<name>"`, importing only the modules this example really uses.
2. Append `examples/<name>` to `members` in `moon.work`.
3. Name it explicitly in CI if it needs to build or smoke-test; never replace that with a single `moon build` over the whole workspace (a failure then tells you nothing about who broke it).
4. Artifacts follow the module name: `_build/native/<mode>/build/NoahLiu/native-gui-examples-<name>/native-gui-examples-<name>.exe`
   (`scripts/make_app.sh` and `release-bin.yml` depend on this layout).

`examples/assets/` is a shared asset directory, not a module — don't put code there.

## 12. Related

- Platform adaptation pitfalls and verification: [adaptation.md](https://github.com/lb091188/moonbit-native-gui/blob/master/proposals/adaptation.md)
- Environment setup and your first project: [tutorial.md](tutorial.md)
- Components and API: [components.md](components.md)
