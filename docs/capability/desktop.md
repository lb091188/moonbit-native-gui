# Desktop & display

Desktop appearance (color temperature / wallpaper) and display devices (monitors / window management). Uniform `Result` semantics and the support matrix: [System capabilities overview](sys.md).

## Desktop Session Type

On Linux, "X11 or Wayland" decides whether a whole family of tools can be trusted. In a Wayland session the X tools still start and still exit 0 (XWayland answers underneath), but the readings belong to the compatibility layer — so this library degrades them explicitly at the probe instead of passing off fake numbers as success.

| Function | Description |
|---|---|
| `session_type() -> SessionType` | read the process environment: `X11` / `Wayland` / `Unknown` |
| `session_type_of(xdg_session_type, wayland_display) -> SessionType` | pure parse helper: `XDG_SESSION_TYPE` speaks first (recognizes `wayland` / `x11`, case and blanks insensitive); when unset, a non-empty `WAYLAND_DISPLAY` means Wayland |
| `in_wayland_session() -> Bool` | the gate the capability families use |

Degraded by it: **night light** (`nl_supported()` is false; set/reset give `Unsupported`), **window management** (`win_supported()` false; list/activate/close give `Unsupported`), **idle detection and global shortcuts** (Linux reads the X server and X grabs, which a Wayland session does not have — see the session table in the [roadmap (Chinese)](/zh/reference/roadmap.md)). **Monitor enumeration is not degraded**: the XWayland virtual output really exists, but read it as "not the physically connected display" — do not drive layout or hardware decisions from it; the Wayland-native channel is planned (`proposals/wayland-native.md` P2).

## Night Light Color Temperature

Color temperature is expressed as a percentage 0-100: 0 = warmest, 100 = 6500K neutral, i.e. no change. Two backends are auto-detected: `redshift` is preferred when present (`-P -O <K>` sets the temperature once), otherwise `xrandr --output <preferred output> --gamma R:G:B` — the more the blue channel is attenuated, the warmer; the green channel stays 1.00.

| Function | Description |
|---|---|
| `nl_supported() -> Bool` | either redshift or xrandr works and the session is not Wayland; all probes are read-only calls with no side effects |
| `nl_set_temperature(percent) -> Result[Unit, NightlightError]` | set color temperature (0-100, out-of-range clamped; the redshift path maps 0→2500K / 100→6500K) |
| `nl_reset() -> Result[Unit, NightlightError]` | reset (redshift `-x` / `xrandr --gamma 1.00:1.00:1.00`; without `--output` it affects all outputs) |

Error `NightlightError`: `Unsupported` (not Linux, a Wayland session, or both redshift and xrandr unavailable, or xrandr has no connected output) / `CommandFailed(String)`. On a Wayland session `nl_supported()` is always false: redshift / xrandr only touch the XWayland compatibility layer, so the process starts, exits 0, and the screen stays as it was — reported as unsupported rather than a false success. The xrandr path takes the current primary output; without a primary output it takes the first connected one.

```moonbit
let _ = @sys.nl_set_temperature(30) // warmer
let _ = @sys.nl_reset()
```

## Wallpaper

Windows calls `SystemParametersInfoW` (SPI_SETDESKWALLPAPER) directly. Linux dispatches by `XDG_CURRENT_DESKTOP`, with DE recognition handled by a pure function inside the sys package. **XFCE** uses `xfconf-query` to read/write the `/backdrop/<screen>/monitor<output>/<workspace>/last-image` property on the xfce4-desktop channel; with multiple monitors it takes a connected output. **KDE** uses `qdbus6`/`qdbus` to call plasmashell's `evaluateScript`; this repo has not verified KDE on real hardware. The remaining gsettings-based desktops are driven by one target table (same table for read and write): **GNOME** and the derivatives sharing its schema (**Budgie/Unity**) read `picture-uri` on `org.gnome.desktop.background`, falling back to `picture-uri-dark` when unset; **Cinnamon** reads its own fork, `org.cinnamon.desktop.background picture-uri`; **MATE** reads `org.mate.background picture-filename`, which stores a bare path, so writes do not add `file://`.

| Function | Description |
|---|---|
| `wp_get() -> Result[String, WallpaperError]` | read the current wallpaper path |
| `wp_set(path) -> Result[Unit, WallpaperError]` | set the wallpaper; changes the desktop appearance |

Error `WallpaperError`: `Unsupported` (subprocess unavailable on Linux, or KDE's qdbus absent) / `UnknownDesktop(String)` (neither the XFCE/KDE branches nor a row of the gsettings target table — LXQt, Deepin, Wayland compositors; carries the raw `XDG_CURRENT_DESKTOP`) / `CommandFailed(String)` / `ParseFailed(String)` / `InvalidParam(String)`. An XFCE write creates the property when it does not exist.

```moonbit
match @sys.wp_get() {
  Ok(p) => println("Current wallpaper: \{p}")
  Err(e) => println("Cannot read: \{e}")
}
let _ = @sys.wp_set("/home/me/Pictures/wall.png")
```

## Monitor Configuration

Linux parses `xrandr --query` output and macOS calls CoreGraphics directly (the `CGGetOnlineDisplayList` family); both give each output's name / connection status / current resolution × refresh rate / position / physical size / supported mode list. Resolution and position are **physical pixels**. The refresh rate is an integer in centihertz (×100, e.g. 5995 = 59.95Hz), avoiding float parsing and comparison.

| Function | Description |
|---|---|
| `mon_list() -> Result[Array[MonitorInfo], MonitorError]` | enumerate outputs, including unconnected ones, preserving xrandr order (Linux); macOS lists online displays only |
| `mon_current() -> Result[Array[CurrentOutput], MonitorError]` | simplified snapshot of current outputs (connected and with a current mode), without the mode list |

`MonitorInfo{ name, connected, primary, width, height, refresh_centi, pos_x, pos_y, mm_width, mm_height, modes }`; `MonitorMode{ width, height, refresh_centi, preferred, current }`; `CurrentOutput{ name, width, height, refresh_centi, pos_x, pos_y }`. Error `MonitorError`: `Unsupported` (Windows, or macOS with no online display found / probing on other platforms) / `CommandFailed(String)` (Linux xrandr failed to run or exited nonzero) / `ParseFailed(String)` (not a single output entry).

Four macOS readout differences: `connected` is always true (macOS has no public list of "connected but switched-off" displays — offline displays simply don't appear); `name` is `Built-in` (built-in panel) or `Display-<CGDirectDisplayID>` (everything else) — the public CG API has no display name, and `NSScreen.localizedName` belongs to the ObjC side; `refresh_centi` is 0 for some modes of built-in panels (the backend reports "unknown" rather than faking a number), and `mm_width`/`mm_height` likewise default to 0; `MonitorMode.preferred` is always false — the current SDK exposes no "preferred/native mode" signal, and the current mode is not passed off as one.

```moonbit
match @sys.mon_current() {
  Ok(outs) => for o in outs {
      println("\{o.name}  \{o.width}x\{o.height}@\{o.refresh_centi / 100}Hz")
    }
  Err(e) => println("Cannot read: \{e}")
}
```

## System Window Management

Window list (id / desktop / host / title), activate by id or title, close by title. Windows calls `EnumWindows` / `SetForegroundWindow` / `WM_CLOSE` directly; Linux parses `wmctrl -l` and uses its activate / close actions. On a Wayland session the Linux branch gives `Unsupported`: `wmctrl` only lists XWayland windows, and its actions exit 0 without touching a real window. An ordinary MoonBit process can call these — no GUI host needed.

| Function | Description |
|---|---|
| `win_supported() -> Bool` | always true on Windows; macOS goes through CGWindowList / AX; on Linux requires wmctrl (a missing wmctrl surfaces on Unix via exit code 127) and is false on a Wayland session |
| `win_list() -> Result[Array[WindowInfo], WinError]` | window list |
| `win_activate(id_or_title) -> Result[Unit, WinError]` | activate by window id (wmctrl's `0x...` hex) or title |
| `win_close(title) -> Result[Unit, WinError]` | close a window by title |

`WindowInfo{ id, desktop, host, title }`: id can be passed straight back to `win_activate`; desktop is the desktop the window is on, -1 means sticky (spans all desktops). Error `WinError`: `Unsupported` / `CommandFailed(String)` / `ParseFailed(String)` / `InvalidParam(String)`.

Activation and closing change real window state: the interfaces are fully implemented; the application layer should call them only on user action.

```moonbit
match @sys.win_list() {
  Ok(wins) => for w in wins { println("\{w.id}  \{w.title}") }
  Err(e) => println("Unavailable: \{e}")
}
let _ = @sys.win_activate("ZCode")   // by title
let _ = @sys.win_close("ZCode")
```
