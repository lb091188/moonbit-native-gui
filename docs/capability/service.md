# System services

Permissions, power, info, printing, clipboard, autostart and other system-level services. Uniform `Result` semantics and the support matrix: [System capabilities overview](sys.md).

## System Permissions (macOS)

Unavoidable system authorizations form a cross-cutting family. macOS goes through TCC: probes use public entry points (`AXIsProcessTrusted` / `CGPreflightScreenCaptureAccess`), and requests pop the **system's own guidance dialog** ("open System Settings") — nothing is clicked on the user's behalf. Windows / Linux have no such concept, so they are always `PermNotNeeded`. There are only two states — "granted / not granted": "not yet requested" and "denied" are indistinguishable at the public API layer, so applications follow the rhythm "probe → request → guide → re-probe once the user is back".

| Function | Description |
|---|---|
| `permission_supported() -> Bool` | whether the current platform has a permission family (macOS) |
| `permission_probe(kind) -> Result[PermissionStatus, PermissionError]` | probe the current state: `PermGranted` / `PermNotGranted` / `PermNotNeeded` |
| `permission_request(kind) -> Result[Unit, PermissionError]` | pop the system guidance dialog; **does not block** — the caller re-probes at a suitable moment afterwards |

`PermissionKind`: `PermAccessibility` (accessibility — needed to activate/operate other apps' windows), `PermScreenRecording` (screen recording — needed to read other apps' window titles).

```moonbit
match @sys.permission_probe(@sys.PermAccessibility) {
  Ok(@sys.PermGranted) => () // go ahead
  Ok(_) => {
    let _ = @sys.permission_request(@sys.PermAccessibility)
    // guidance dialog popped; re-probe when the user is back
  }
  Err(e) => println(e)
}
```

The other tier — "operation elevation" (one pop each: an admin password box on macOS, UAC on Windows in future) — is not part of this family and is handled with each capability batch (e.g. the write side of the macOS power-plan tier goes through `osascript` with admin authorization).

## Power Plans

Three `powerprofilesctl` commands read the available plan set, read the current plan, and switch plans. When `power-profiles-daemon` is not installed the shell surfaces it via exit code 127 → `PpUnsupported`.

| Function | Description |
|---|---|
| `pp_supported() -> Bool` | powerprofilesctl is present and queryable |
| `pp_profiles() -> Result[Array[PowerProfile], PowerProfileError]` | available plan list, in backend output order; it equals the recommended order when the recommended plan comes first |
| `pp_current() -> Result[PowerProfile, PowerProfileError]` | the current plan |
| `pp_set(profile) -> Result[Unit, PowerProfileError]` | switch plan; has side effects and requires authorization — the caller runs its own authorization flow |

`PowerProfile`: `PPerformance` / `PBalanced` / `PPowerSaver`. Error `PowerProfileError`: `PpUnsupported` / `PpCommandFailed(String)` / `PpParseFailed(String)`.

```moonbit
match @sys.pp_profiles() {
  Ok(profiles) if profiles.contains(@sys.PBalanced) => {
    let _ = @sys.pp_set(@sys.PBalanced)
  }
  _ => ()
}
```

## System Information

Reads `/proc` and `/sys` text only: distro identity (`/etc/os-release`), machine DMI identity (`/sys/class/dmi/id/`), physical memory (`/proc/meminfo`), uptime (`/proc/uptime`). Non-Linux uniformly yields `Unsupported`. A missing file or insufficient permission yields `Err` carrying the path — never an empty string.

| Function | Description |
|---|---|
| `si_os() -> Result[OsInfo, SysInfoError]` | distro: `OsInfo{ pretty_name, id, version_id }` |
| `si_machine() -> Result[MachineInfo, SysInfoError]` | machine: `MachineInfo{ vendor, product, serial }`; the serial is readable only by root on most distros, and unreadable yields `Err` |
| `si_memory() -> Result[MemoryInfo, SysInfoError]` | memory: `MemoryInfo{ total_kb, available_kb }`; unit kB, available_kb is MemAvailable |
| `si_uptime() -> Result[Double, SysInfoError]` | uptime (seconds) |

Error `SysInfoError`: `SiUnsupported` (not Linux) / `SiReadFailed(String)` (carries the path) / `SiParseFailed(String)`.

```moonbit
let os = @sys.si_os() // Ok({ pretty_name: "Ubuntu 24.04.5 LTS", id: "ubuntu", .. })
let mem = @sys.si_memory()
let up = @sys.si_uptime() // Ok(84088.08)
```

## Printers

Windows calls winspool directly — `EnumPrintersW` for the list, `GetDefaultPrinterW` for the default name — and prints via `ShellExecuteW` with the "print" verb. Linux reads the printer list (`-p`) and default printer (`-d`) via `lpstat` and submits jobs via `lp`. Without CUPS installed, lpstat surfaces it via exit code 127 → `PrtUnsupported`.

| Function | Description |
|---|---|
| `prt_supported() -> Bool` | Windows checks that the winspool list is retrievable; Linux checks lpstat availability |
| `prt_list() -> Result[Array[PrinterInfo], PrinterError]` | printer list (name + availability status) |
| `prt_default() -> Result[String, PrinterError]` | default printer name |
| `prt_print(printer? = "", path, copies? = 1) -> Result[Unit, PrinterError]` | submit a print job; Linux defaults printer to the system default, Windows uses the "print" verb and does not support a copies parameter. Has side effects — real queued printing |

`PrinterStatus`: `Idle` / `Printing` / `Paused` (paused, accepts no new jobs) / `Disabled`; `prt_status_available(status)` tells whether it can accept jobs. `PrinterInfo{ name, status }`. Error `PrinterError`: `PrtUnsupported` / `PrtCommandFailed(String)` / `PrtParseFailed(String)` / `PrtInvalidParam(String)` (empty file path, copies < 1).

```moonbit
match @sys.prt_default() {
  Ok(name) => {
    let _ = @sys.prt_print(printer=name, path="/tmp/doc.pdf")
  }
  Err(e) => println("No default printer: \{e}")
}
```

## Environment Variables & Directory Enumeration

Two small primitives: in-process environment-variable read/write/delete (`envx` — reads go through the standard library's `core/env`, write/delete through the C-layer setenv/unsetenv) and directory enumeration (`fsx` — C-layer opendir/readdir or Win32 FindFirstFileW).

| Function | Purpose |
|---|---|
| `envx_get(name) -> String?` | read the current process environment; None when absent |
| `envx_set(name, value) -> Result[Unit, EnvxError]` | write the current process environment only; visible to subprocesses spawned afterwards |
| `envx_unset(name) -> Result[Unit, EnvxError]` | delete; an absent variable also counts as success — idempotent |
| `envx_common() -> Map[String, String]` | common set: PATH / HOME / LANG / SHELL / USER read as fixed, plus an `XDG_*` prefix scan (included only when present) |
| `fsx_list_dir(path) -> Result[Array[String], FsError]` | enumerate a directory's child names; excludes `.` `..`, non-recursive, includes hidden entries |
| `fsx_set_env(name, value, overwrite) -> Result[Unit, FsError]` | write an environment variable; with overwrite=false and the variable already present, the original value is kept and the result is still Ok |
| `fsx_unset_env(name) -> Result[Unit, FsError]` | delete an environment variable (the low level under envx_unset) |

The semantics are "in-process effect": a write changes only the current process environment — it never touches the system's persistent configuration and never affects the parent process. Errors: `EnvxError::ExInvalidParam(String)` (empty variable name) / `ExFailed(String)` (the C layer rejects, e.g. the name contains '='); `FsError::InvalidParam(String)` / `OpenFailed(String)` (directory cannot be opened, carries the path) / `EnvFailed(String)`. A known edge of `fsx_list_dir`: a child name containing '\n' gets split apart.

```moonbit
let path = @sys.envx_get("PATH")
let _ = @sys.envx_set("MY_FLAG", "1")
let _ = @sys.envx_unset("MY_FLAG")
match @sys.fsx_list_dir("/usr/share/applications") {
  Ok(names) => for n in names if n.ends_with(".desktop") { println(n) }
  Err(e) => println("Cannot open: \{e}")
}
```

## Clipboard Watching

Text read/write and change watching. Windows calls Win32 `CF_UNICODETEXT` directly. Linux prefers GtkClipboard, which requires the host to have run gtk_init; when the probe returns 0 it falls back to the command line `xclip`. The callback dispatches the new text when the text content changes. This module is pure polling — any MoonBit process can use it, and callbacks run in the caller's context.

| Function | Description |
|---|---|
| `cbw_get_text() -> Result[String, ClipboardError]` | read the clipboard text once; unavailable / no text in the selection yields the corresponding Err |
| `cbw_start_watch(interval_ms? = 800, cb) -> ClipboardWatcher` | start watching; the polling interval is clamped to 100..60000. The baseline is the content at startup, so the initial content does not fire the callback |
| `cbw_stop(watcher)` | stop watching; sets a park flag, runs at most one more tick, then terminates itself. Idempotent |

Error `ClipboardError`: `Unsupported` (platform/backend both unavailable) / `CommandFailed(String)`. A read failure silently skips that tick without firing the callback. The polling hangs on a GUI timer, so it only dispatches once the message loop is running.

```moonbit
let w = @sys.cbw_start_watch(interval_ms=500, fn(text) {
  println("New clipboard content: \{text}")
})
// ……when needed
@sys.cbw_stop(w)
```

## Autostart

Cross-platform query, enable, and disable of launch-at-login. The semantics are unified in the MoonBit layer, so callers don't need to be aware of the platform.

| Platform | Mechanism | Entry location |
|---|---|---|
| Linux | Writes `<app_id>.desktop` into the XDG autostart directory | `$XDG_CONFIG_HOME/autostart/`, falling back to `$HOME/.config/autostart/` when unset |
| Windows | Writes a value under HKCU `Software\Microsoft\Windows\CurrentVersion\Run` | The value name is the app_id; the value is the double-quoted executable path |
| macOS | LaunchAgents plist + `launchctl load` / `unload` (verified on device) | `~/Library/LaunchAgents/<app_id>.plist` — Label is the app_id, ProgramArguments holds the executable, RunAtLoad true |

| Function | Description |
|---|---|
| `autostart_supported() -> Bool` | Runtime probe; true on all three platforms |
| `autostart_is_enabled(app_id) -> Result[Bool, AutostartError]` | Queries the current state; on Linux it honours the two system-side disable bits `Hidden` and `X-GNOME-Autostart-enabled`; on macOS the plist's presence is the enabled state |
| `autostart_enable(app_id)` / `autostart_disable(app_id) -> Result[Unit, AutostartError]` | Enable and disable; both idempotent: a repeated enable overwrites, and disabling an an entry that never existed also succeeds |
| `autostart_path(app_id) -> Result[String, AutostartError]` | Describes where the entry lands, for troubleshooting: the full `.desktop` path on Linux, `HKCU\…\Run\<app_id>` on Windows, `~/Library/LaunchAgents/<app_id>.plist` on macOS |
| `autostart_exe_path() -> String?` | Full path of the current process's executable; this is what enable writes |
| `autostart_valid_app_id(app_id) -> Bool` | Validates an app_id against the DBus well-known-name rules: at least two dot-separated elements, each starting with a letter or an underscore |
| `autostart_dir_of` / `autostart_escape_exec` / `autostart_desktop_entry` / `autostart_desktop_enabled` / `autostart_run_value` / `autostart_run_value_exe` | Pure functions: autostart-dir resolution, Exec escaping, `.desktop` content and parsing, Windows Run value format and reverse parsing |

```moonbit
match @sys.autostart_enable("com.example.MyApp") {
  Ok(_) => ()      // launches on next login / reboot (see autostart_path for the location)
  Err(e) => println(e.to_string())
}
match @sys.autostart_is_enabled("com.example.MyApp") { ... }
match @sys.autostart_disable("com.example.MyApp") { ... }   // idempotent
```

The error type `AutostartError{Unsupported, InvalidAppId, NoExecutablePath, IoFailed(String)}` keeps "unsupported" and "failed" separate; nothing fails silently. The library adds the exec-path quotes per platform convention: both the `.desktop` Exec and the Windows REG_SZ wrap the whole path in one pair of double quotes, so callers should not add another layer.

Edge cases: the autostart target is the absolute path of the current process's executable — when the app runs from a temporary location such as an AppImage or a portable unpacked directory, moving the directory invalidates the old entry, so enable must be run again. Cleanup tools may empty the Linux autostart directory, and group policy may disable the Windows Run key (the entry stays but never runs); both are environment-side behaviors the library does not probe for. On macOS, enable/disable go through the deprecated-but-present `launchctl load` / `unload` (the newer `bootstrap` needs the user's uid, which this API family does not expose); a failed `load` does not undo the written plist — it still takes effect next login — but is reported as an error.
