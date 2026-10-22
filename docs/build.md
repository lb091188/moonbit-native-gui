# Build & linking

Link parameters are **fully hosted by prebuild** — neither users nor contributors hand-write link flags. This page explains what the mechanism means for you, and the one pitfall after editing a native stub: not relinking. The mechanism and the per-platform field records live in the "Build & linking" section of [adaptation.md](https://github.com/lb091188/moonbit-native-gui/blob/master/proposals/adaptation.md).

## 1. Where linking comes from

- moon runs the library module's `gui/scripts/prebuild.py` at build time, wired up via `options(--moonbit-unstable-prebuild)` in `gui/moon.mod`. It emits `link_configs` for the current system and propagates them automatically to every main package that depends on this library module.
- prebuild also probes system libraries: on Linux it looks for GTK3 / Pango / FontConfig / X11, `webkit2gtk-4.1` for the embedded WebView, and ffmpeg for the media module. If GTK is not found, it exits non-zero with a fix hint; if webkit is not found, `@web` degrades to a placeholder implementation and the capability reports `Unsupported`, instead of failing the whole link.
- The result: after `moon add NoahLiu/native-gui`, `moon run` works with zero configuration. Link flags are never written and should not be written.

## 2. Notes for contributors

- Library packages carry no `link` section — moon would generate an `.exe` without a `main`, and the build fails.
- Never hand-write `cc-link-flags` — linking is emitted entirely by prebuild; manual edits conflict with it.
- New platform C capabilities follow the "single `stub.c`, multiple branches + prebuild macros" layout; see `gui/win/stub.c` for precedent. The link flags still belong to prebuild.

The rules for aligning FFI declarations with trampolines are in the repository-root [AGENTS.md](https://github.com/lb091188/moonbit-native-gui/blob/master/AGENTS.md) and `.agents/skills/moonbit-c-binding/`.

## 3. The one pitfall: editing a C stub doesn't relink

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

## 4. Vendored large files and mirrors

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

## 5. Adding an example module

Dependency isolation is per module, not per package: the imports in `moon.mod` decide a module's whole dependency closure, and `moon.pkg` can only pick packages already resolved there. So "one example must not drag in the others" requires **one module per example** — packing several examples into one `moon.mod` re-couples them. To add one:

1. Create `examples/<name>/` with `main.mbt` + `moon.pkg`, and its **own** `moon.mod`:
   `name = "NoahLiu/native-gui-examples-<name>"`, importing only the modules this example really uses.
2. Append `examples/<name>` to `members` in `moon.work`.
3. Name it explicitly in CI if it needs to build or smoke-test; never replace that with a single `moon build` over the whole workspace (a failure then tells you nothing about who broke it).
4. Artifacts follow the module name: `_build/native/<mode>/build/NoahLiu/native-gui-examples-<name>/native-gui-examples-<name>.exe`
   (`scripts/make_app.sh` and `release-bin.yml` depend on this layout).

`examples/assets/` is a shared asset directory, not a module — don't put code there.

## 6. Related

- Platform adaptation pitfalls and verification: [adaptation.md](https://github.com/lb091188/moonbit-native-gui/blob/master/proposals/adaptation.md)
- Environment setup and your first project: [tutorial.md](tutorial.md)
- Components and API: [components.md](components.md)
