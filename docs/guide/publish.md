# Packaging & auto-update

The full path from `moon run` to "users install and receive updates": declare packaging in `mng.toml` → `mng package` produces installers and update carriers locally → push an `app-v*` tag so the CI matrix builds all platforms and drafts a Release → inside the app, `@ui.update_dialog` checks, downloads, installs and restarts.

Full design notes and decisions live in `proposals/package-update.md` (Chinese).

## Artifacts

| Platform | Installer (Release download) | Update carrier (self-replace) |
| --- | --- | --- |
| macOS (Apple Silicon) | `.dmg` | `.zip` (contains the `.app`) |
| Windows x64 | NSIS `setup.exe` | `.zip` (contains the bare exe and siblings) |
| Linux x64 | `.deb` | `.AppImage` (single-file self-replace) |

Installers are not update carriers — updates are "full download + SHA256 verify + atomic replace" and do not depend on a system package manager.

## Packaging declaration (mng.toml)

```toml
[package]
id = "com.example.myapp"   # reverse-DNS id for desktop registration & updates
name = "MyApp"             # display name (.app / installer / desktop entry)
version = "0.1.0"          # app version, 3-segment semver; independent of moon.mod
icon = "assets/icon.png"   # source icon (1024 PNG preferred; sizes derive per platform)
resources = ["assets"]     # bundled resource dirs/files (relative to mng.toml)

[package.sign]
# optional; when absent mac skips codesign/notarize and win skips signtool
notarize_profile = "myapp-notary"      # mac notarization (xcrun notarytool profile)
win_cert = "cert.pfx"                  # Windows certificate file
win_cert_pw_env = "WIN_CERT_PW"        # read the password from this env var (never committed)
```

## Local packaging: `mng package`

From the project root (where `mng.toml` lives):

```sh
moon run path/to/mng -- package
```

It runs `moon build . --target native --release --strip` internally and drops artifacts into `.mng/dist/`. Cross-compiling is not possible (the native backend drives the host C toolchain), so **a machine only packages its own platform** — the CI matrix is the only channel for all-platform artifacts.

Per-platform dependencies (system tools or automatic):

- **macOS**: `sips` / `iconutil` for icns, `hdiutil` for DMG, `codesign`, `ditto` for the update zip
- **Windows**: NSIS (`makensis`, on PATH or via choco); the ICO frame is built in-house; `signtool` optional
- **Linux**: `dpkg-deb` for deb; `appimagetool` auto-downloads to `~/.mng/tools` when missing

## CI release: push an `app-v*` tag

`.github/workflows/release-app.yml` runs `mng package` on all three platforms when you push an `app-v<version>` tag; the summary job computes SHA256/sizes into `update.json` and creates a **draft Release** (publish after review). `workflow_dispatch` validates the matrix without releasing.

Version consistency: the tag version must equal `mng.toml`'s `version`; mismatches are skipped by the manifest generator with a log line.

## Local release: `mng publish`

When CI is unavailable or you only need your own platform, run this at the project root after `mng package`:

```sh
moon run path/to/mng -- publish            # --tag defaults to app-v<version>, --repo is resolved by gh
moon run path/to/mng -- publish --no-upload --repo owner/name   # generate update.json only, no upload
```

Behavior: scan `.mng/dist/` for version-matching artifacts → compute SHA256/sizes → write `update.json` (carriers into `platforms`, installers ship with the Release only) → create a draft Release via `gh` and upload (appends with `--clobber` if it exists). [gh](https://cli.github.com/) must be installed and authenticated (`gh auth login`).

Cross-platform manifests: drop artifacts produced elsewhere (e.g. the other two platforms downloaded from a CI artifact) into `.mng/dist/` before publishing — the parser takes everything by file name. The publish timestamp stays empty (`pub_date` is an empty string); the Release page shows the real time.

## In-app updates

Shortest wiring (a playable demo lives in showcase → System → App self-update):

```moonbit
let open : @base.Store[Bool] = @base.Store::new(false)
let flow = @ui.make_update_flow()
let actions = @ui.sys_update_actions(
  flow,
  "https://github.com/<owner>/<repo>/releases/latest/download/update.json",
  "0.1.0",                    // same source as mng.toml version
  quit=fn() { host.quit() },  // install done: relaunch already fired, exit now
)
// mount once in the tree (a zero-height anchor; opens into the overlay layer)
@ui.update_dialog(open, flow, actions, current_version="0.1.0")
```

Division of labor: `update_dialog` owns the state machine and the view; the check/download/install actions are injected `UpdateActions` closures — buttons mark state first (the loading indicator shows immediately), then fire the closure, which feeds results back through `flow.report_check / report_download / report_install`. `sys_update_actions` is the default wiring straight into `@sys.update_*`; bring your own scheduling (background thread, progress, cancel) by swapping the three closures — the component surface stays the same.

Call `@sys.update_cleanup()` early at startup to remove leftover `*.mng-old` files from a previous update.

## update.json format

```json
{
  "version": "0.2.0",
  "notes": "Release 0.2.0",
  "pub_date": "2026-11-08T00:00:00Z",
  "platforms": {
    "darwin-aarch64":  { "url": "…zip", "size": 123456, "sha256": "…" },
    "windows-x86_64":  { "url": "…zip", "size": 123456, "sha256": "…" },
    "linux-x86_64":    { "url": "…AppImage", "size": 123456, "sha256": "…" }
  },
  "signature": null,
  "sig_alg": null,
  "deltas": null
}
```

`signature` / `sig_alg` / `deltas` are reserved slots (always `null` in v1): Ed25519 signing lands in v1.5 and delta updates in v2 without a breaking format change.

## Trust model (v1)

HTTPS enforced (`http://` manifests are rejected outright) + SHA256 verification (protects against corruption, not a compromised source). Ed25519 manifest signing arrives with v1.5.

## Known trade-offs (v1)

- **Synchronous download**: `@sys` runs subprocesses synchronously, so the UI stalls during large downloads (`sys_update_actions` defers each action by one tick so the loading state paints first); an async executor comes with the platform thread batch
- **No download percentage / cancel**: no file-size primitive in sys yet; both arrive with the async executor
- **No rollback on mac**: once the zip overwrites the `.app` the old version is gone; failure semantics stop at the unzip stage
