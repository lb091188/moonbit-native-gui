# System capability recipes

The capability family uses a uniform `Result` semantics and returns error values in unsupported environments; the three-platform matrix is in [System capabilities overview](../capability/sys.md). Import list and ground rules: see [How-to overview](index.md#prerequisites).

## Opening links / revealing files

`@sys.open_url` opens a URL; `@sys.open_file` hands a file to the system's default program; `@shell.reveal_in_file_manager` locates and selects it in the file manager.

```moonbit
@ui.col(
  [
    @ui.link("Open the docs", fn() {
      let _ = @sys.open_url("https://moonbit-native-gui.pages.dev")
    }),
    @ui.button("Open image", on_click=fn() {
      let _ = @sys.open_file("/home/me/photo.png")
    }),
    @ui.button("Reveal in file manager", on_click=fn() {
      match @shell.reveal_in_file_manager("/home/me/photo.png") {
        Ok(_) => ()
        Err(e) => println("reveal failed: \{e}")
      }
    }),
  ],
  row_gap=8.0,
)
```

## Copying to the clipboard

`clipboard_set_text` writes the system clipboard directly and returns a `Bool`.

```moonbit
@ui.button("Copy install command", on_click=fn() {
  if @sys.clipboard_set_text("moon add NoahLiu/native-gui") {
    toast("Copied", @ui.Success)   // toast, see [A toast](interaction.md#a-toast)
  }
})
```

Read with `clipboard_get_text() -> String?`. Input fields already talk to the system clipboard themselves.

## Desktop notifications

`@shell.notify_send(app_name, title, body, ...)`; probe with `notify_supported()` first. Linux goes over D-Bus, Windows uses the tray balloon, macOS uses the UN center (`notify_backend_name()` reports the real backend per platform).

Common optional arguments: `icon?` (theme icon name on Linux), `timeout_ms?` (Linux only — Vista and later ignore it for balloons), `replaces_id?` (non-zero replaces that notification), `progress?` (0..100 — a bar on Linux, appended to the body on Windows), `kind?` (0 info / 1 warning / 2 error), `urgent?` (defaults to `true`, see below).

```moonbit
@ui.button("Send notification", on_click=fn() {
  if @shell.notify_supported() {
    match @shell.notify_send("My App", "Build finished", "3 targets produced") {
      Ok(_id) => toast("Sent", @ui.Info)
      Err(e) => println("notify failed: \{e}")
    }
  } else {
    println("notifications not supported here")
  }
})
```

`urgent?` is the **interruption level**, honoured on macOS only: `true` posts at the time-sensitive level, so the banner appears even while the app is in the foreground; `false` posts at the default level, which stays silent while the app is busy and only lands in Notification Center. If the user turns off time-sensitive authorization in System Settings, `true` degrades to the same silence. Linux and Windows accept and ignore it — the freedesktop urgency hint is deliberately not mapped (`critical` means "never disappears", a different thing).

Notes: send from event callbacks. On macOS the desktop banner requires running as an `.app` bundle, and first use asks for system authorization; see the [experience guide](../guide/experience.md).
