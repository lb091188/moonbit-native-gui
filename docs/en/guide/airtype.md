# airtype: type from your phone

airtype is a standalone app in this repo (`apps/airtype`): your computer runs a LAN service and shows a QR code; scan it with your phone, type on the web page, hit send, and the text lands in whatever input is focused on the computer — no IME, no chat-app relay.

- Platforms: macOS verified; Linux (X11 sessions) and Windows merged, pending on-device verification. On Linux Wayland sessions only XWayland apps receive injections; on Windows, elevated target windows (admin processes) reject them by OS design.
- The generic capability shipped with it: [text injection](../capability/sys.md) in `gui/sys` (post arbitrary text into the system-focused input), reusable by any app.

## Run

```sh
moon run apps/airtype
```

The window shows four cards:

| Card | Content |
|---|---|
| Accessibility | permission status for mac injection + the "Authorize" button |
| QR code | scan with the phone camera to open the typing page |
| Service | service status, LAN address, connected phones |
| Recent | previews of recently typed text |

Default port is 8787; override with the `AIRTYPE_PORT` environment variable:

```sh
AIRTYPE_PORT=9000 moon run apps/airtype
```

## First-time authorization (mac)

Injection posts synthesized keyboard events, which macOS gates behind the Accessibility permission:

1. Click "去授权" (Authorize); the system dialog appears and System Settings opens.
2. Tick this app under Privacy & Security → Accessibility (for a bare `moon run` process the terminal app is the one to tick).
3. Return to the window; the status flips to authorized within two seconds.

Without the grant the phone can still connect and send, but the page gets an "injection failed" reply.

### Authorization for packaged builds (`mng package`) and how to reset

- macOS tracks Accessibility grants by code-signing identity. `mng package` defaults to an ad-hoc signature (no certificate): **every repackage changes the binary, which macOS treats as a different app — the old grant no longer applies** (the symptom: already ticked, still reports unauthorized). This is expected during development; for grants that survive updates, set a developer-certificate identity in `mng.toml [package] sign_mac` before packaging.
- Reset steps when switching to a packaged build:
  1. System Settings → Privacy & Security → Accessibility: remove the old airtype entry (the one granted to the earlier bare binary; delete same-named duplicates too);
  2. Put the `.app` in a fixed location (e.g. /Applications), launch it, click "去授权" and tick the current copy;
  3. For a `.app` extracted from a zip, strip the quarantine attribute first to avoid randomized-path translocation breaking the grant: `xattr -dr com.apple.quarantine airtype.app`;
  4. Last resort, full reset (affects Accessibility grants of all apps, use with care): `tccutil reset Accessibility`.

## Phone side

The scanned page has three zones: a top bar (title left, connection status right), an input area filling all the space in between (long text fully visible), and a single-row action bar.

- "发送" (Send) types the text into the computer's focused input; "⏎" fires a real Enter keypress on the computer — fill and submit are two independent steps, just like a real keyboard.
- Quick-command chips share the row: one tap sends a preset phrase and optionally follows with Enter — handy for "continue"-style prompts.
- Tapping any button keeps the soft keyboard up — focus never leaves the input, so you can type and send continuously without re-tapping.
- "⛶" toggles fullscreen (supported on Android and desktop browsers; iOS Safari lacks the API, where the button is a no-op).
- Chips are configured on the computer in the 快捷指令 card, one button per line: `text`, or `label|text|enter(yes/no)`. Edits persist immediately; the phone pulls updates when it returns to the foreground.
- A 10-second heartbeat detects dead connections; after unlocking the phone the connection recovers within about two seconds, no manual refresh.
- After the app restarts the token has changed, so rescan.

## Security notes

- The URL carries a one-time random token (32 chars): devices on the same LAN without it get neither the page nor the WebSocket.
- Plain HTTP: traffic is visible inside the LAN — do not use on untrusted networks. Self-signed HTTPS requires manual trust on phones; poor UX, not in this phase.
- Password fields are not injected: macOS by design ignores synthesized events there.

## Known limits

- Phone and computer must share a LAN and the computer must have an RFC1918 private address (10.x / 172.16~31.x / 192.168.x); otherwise the app shows "no network".
- The address comes from a physical interface's private address — with a proxy TUN / fake-ip adapter present, its 198.18.x address is never picked.
- Injection targets the **currently focused** input — check the focus on the computer before sending.
