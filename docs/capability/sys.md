# System capabilities overview (@sys)

The system-capability API family: system volume, application lookup, night-light color temperature, wallpaper, monitor configuration, system window management, clipboard watching, subprocess execution, power plans, system information, printers, environment variables, directory enumeration, recent files, browser bookmarks and Firefox history, VS Code local history. All are read-only or write through an authorized system service. Every call returns a `Result`; unsupported environments yield the corresponding error value instead of crashing. Each `*_supported()` call really probes the current environment.

Split by domain: [Volume & media](media.md), [Apps & history](apps-history.md), [Desktop & display](desktop.md), [System services](service.md).

## Platform Status

> All three platforms (Windows / Linux / macOS) have run the same checklist on real hardware: **✅ verified on device**, with the implementation named in parentheses for troubleshooting. **❌ Unsupported** = the platform does not provide it and the facade says so honestly — not "broken". Per-case evidence and platform differences live in `测试文档/测试用例.md`.

| Capability | Windows | Linux | macOS |
|---|---|---|---|
| clipboard / autostart / subprocess / files (fsx) / env vars (envx) | ✅ direct call | ✅ | ✅ verified on device (pbpaste/pbcopy + NSPasteboard stub; LaunchAgents plist + `launchctl load/unload`) |
| system info / wallpaper / launcher (open & reveal) | ✅ direct call | ✅ | ✅ verified on device (`sw_vers`/`ioreg`/`sysctl` + in-stub `host_statistics64`/`kern.boottime`; osascript desktop picture, main display only; `open` / `open -R`) |
| volume / printers (list+default+print) | ✅ direct call | ✅ | ✅ verified on device (osascript `volume settings`; the sink name is given as empty per contract when unavailable; macOS ships CUPS, same `lpstat`/`lp` path as Linux) |
| user idle detection | ✅ direct call | ✅ | ✅ verified on device (`CGEventSourceSecondsSinceLastEventType`, HID system state — no accessibility permission needed) |
| app lookup | ✅ direct call | ✅ | ✅ verified on device (`.app` bundle scan + public keys of `Contents/Info.plist`; `categories` and the localized name have no public equivalent, given as empty / fallback) |
| recent files | ✅ direct call | ✅ | ❌ Unsupported (sharedfilelist is a private format; not offered) |
| window management / power plans | ✅ direct call | ✅ X11 sessions (**Unsupported on Wayland sessions** — XWayland only sees its own compatibility layer) | ❌ Unsupported (Accessibility needs prior user consent / `pmset` does not map to the three-value scheme semantics) |
| browser/vscode data | ✅ (LOCALAPPDATA paths) | ✅ | ✅ (`Library/Application Support/<vendor>/<product>` paths) |
| sysmonitor process data | ✅ (ships its own stub/sysmon.c) | ✅ | ✅ verified on device (the example module ships its own stub; the mac path is pending) |
| night-light color temperature | ✅ direct call (`SetDeviceGammaRamp`) | ✅ X11 sessions (**Unsupported on Wayland sessions**: gamma lands on XWayland only — the process runs, exits 0, and nothing changes on screen) | ❌ no public API (CoreBrightness is private; a f.lux-style click-through overlay is used instead) |
| monitor enumeration (monitor) | ✅ direct call (`EnumDisplayDevicesW` / `EnumDisplaySettingsExW`) | ✅ (xrandr; **on a Wayland session the reading is the XWayland virtual output**, named like `XWAYLAND0`) | ✅ verified on device (CoreGraphics direct calls: `CGGetOnlineDisplayList` / `CGDisplayBounds` / `CGDisplayCopyAllDisplayModes`; online displays only, names given as `Built-in` / `Display-<id>`; readings are always physical pixels, so `MonitorInfo` needs no scale field) |

The public macOS entry points and underlying calls: `open`/`open -R`, `sw_vers`, `ioreg -rd1 -c IOPlatformExpertDevice`, `sysctl hw.model/hw.memsize/kern.boottime`, `osascript` (System Events `volume settings` and desktop picture), `launchctl load/unload` + `~/Library/LaunchAgents/*.plist`, `lpstat`/`lp`, plus in-stub `host_statistics64`, `CGEventSourceSecondsSinceLastEventType`, `CGGetOnlineDisplayList`/`CGDisplayBounds`/`CGDisplayCopyDisplayMode`/`CGDisplayCopyAllDisplayModes`/`CGDisplayScreenSize`.

The Windows direct calls under the hood: SystemParametersInfoW (wallpaper), ShellExecuteW (launch/reveal/print), PowerGet/SetActiveScheme, the registry (product and DMI info), GlobalMemoryStatusEx, GetTickCount64, EnumWindows, EnumPrintersW, IAudioEndpointVolume (COM), GetLastInputInfo. For pitfalls and header/link requirements, see [adaptation.md](https://github.com/lb091188/moonbit-native-gui/blob/master/experience/adaptation.md).

The full demo is the "System Probes" page of the showcase demo (`cd examples/showcase && moon run .`) — each section can "re-probe" to show this machine's real results item by item, and unsupported capabilities show their error text. For field-tested conclusions and rationale per capability across distros / desktop environments — including the logind path, wpctl/pactl differences and direct SQLite reads — see [adaptation.md](https://github.com/lb091188/moonbit-native-gui/blob/master/experience/adaptation.md).

## Shared Infrastructure: Subprocess Execution (procrun)

The shared "spawn → bounded-time reap → capture stdout/stderr to temp files" wrapper used by all command-line capabilities (volume, monitors, wallpaper, night light, printers, power plans, Firefox profile location): the command name resolves via PATH; the subprocess is forced to the C locale; exit code 0 normalizes to `Ok`, and a nonzero exit normalizes to `Err` carrying stderr.

| Function | Description |
|---|---|
| `pr_available() -> Bool` | whether the current platform supports subprocess execution; true on the three main platforms Linux / macOS / Windows, based on the sys package's own C stubs |
| `pr_run(cmd, args, timeout_ms? = 5000) -> Result[ProcOutput, ProcError]` | run a command and normalize the result; a timed-out process is force-terminated |

`ProcOutput{ stdout, exit_code }`; error `ProcError`: `Unsupported` (not one of the Linux / macOS / Windows main platforms) / `SpawnFailed(String)` (a missing command surfaces via the subprocess's exit code 127, folded into a nonzero exit) / `Timeout(String)` / `NonZeroExit(Int, String)` / `Signaled(Int)`.

"Command missing" and "present but failed" carry different semantics: the former normalizes to `*Supported == false` or `Unsupported` (e.g. `PpUnsupported`, `PrtUnsupported`); the latter is `CommandFailed`.

```moonbit
match @sys.pr_run("wpctl", ["get-volume", "@DEFAULT_SINK@"]) {
  Ok(out) => println(out.stdout)
  Err(@sys.ProcError::NonZeroExit(_, err)) => println("Failed: \{err}")
  Err(e) => println(e)
}
```

## Shared Infrastructure: Generic D-Bus Call Layer (@dbus)

Method calls and property read/write against any service — the common foundation for modules such as media control (MPRIS). Connections reuse the process-level session/system connections of `bus.mbt`; encoding/decoding reuses the wire protocol of `wire.mbt`. Synchronous calls time out at 1.5 seconds; a response timeout yields `gdbus.timeout`.

| Function | Description |
|---|---|
| `gdbus_call_session(dest, path, iface, action, args) -> Result[GDBusValue, GDBusError]` | session-bus method call |
| `gdbus_call_system(dest, path, iface, action, args) -> Result[GDBusValue, GDBusError]` | system-bus method call |
| `gdbus_get_property_session(dest, path, iface, prop)` / `gdbus_get_property_system(...)` | read a property via `org.freedesktop.DBus.Properties.Get`; the return value already has the variant wrapper stripped |
| `gdbus_set_property_session(dest, path, iface, prop, value)` / `gdbus_set_property_system(...)` | write a property via `Properties.Set`; pass a bare value as value — the variant wrapper is added at this layer |

Value model `GDBusValue`: `GVNone` (no return value, cannot be a call argument) / `GVBool` / `GVInt32` / `GVUInt32` / `GVInt64` / `GVU64` ('t', unsigned 64-bit values such as Size/Time in udisks) / `GVDouble` / `GVString` / `GVPath` ('o') / `GVArray(element signature, element table)` / `GVDict(a{sv}, values already have the variant wrapper stripped, Map serialized in insertion order)` / `GVVariant` (keeps the wrapper) / `GVStruct`. On the response side, `{sv}` arrays fold into `GVDict`, and multiple return values fold into `GVStruct`. Error `GDBusError{ name, message }`: name is a D-Bus error name or a local prefix `gdbus.io` (cannot connect / disconnected) / `gdbus.timeout` / `gdbus.encode`.

```moonbit
match
  @dbus.gdbus_get_property_system(
    "org.freedesktop.timedate1",
    "/org/freedesktop/timedate1",
    "org.freedesktop.timedate1",
    "NTP",
  ) {
  Ok(@dbus.GVBool(on)) => println("NTP enabled: \{on}")
  Ok(_) => ()
  Err(e) => println("Bus call failed: \{e.name} \{e.message}")
}
```

## Boundaries

- While the browser runs, its History database keeps taking new writes; the read result is a snapshot at the moment of reading.
- Firefox's places.sqlite often stays in WAL mode; this implementation reads only the main database file, so the latest records not yet checkpointed into it are not readable. When aggregating multiple profiles, the same url appears once per profile — consistent with the Chrome-side aggregation.
- `appfind_executable` hits when a directory has an entry of that name; it does not read file contents or check the executable permission bit.
- Volume setting relies on the corresponding system service being online (Windows IAudioEndpointVolume / Linux PipeWire-Pulse); when the service is absent, write interfaces return an error value.
- Printing / switching power plans change real system state: the interfaces are fully implemented, but call them only on explicit user action — never trigger them on the user's behalf in probe or query paths.
- Both the clipboard watcher's and the ripple animation's timers are driven by the message loop and have no cancel id (`set_timer`): the way to stop them is for the callback to return false, so handle-class APIs (`cbw_stop` / `eff_stop`) should be called explicitly before a component is destroyed.

[中文文档](/zh/capability/sys.md)
