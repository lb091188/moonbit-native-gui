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

## Phone side

The scanned page is just an input box and a send button: type → send → the text appears in the computer's focused input and the page shows "delivered". Reconnection is automatic; after the app restarts the token has changed, so rescan.

## Security notes

- The URL carries a one-time random token (32 chars): devices on the same LAN without it get neither the page nor the WebSocket.
- Plain HTTP: traffic is visible inside the LAN — do not use on untrusted networks. Self-signed HTTPS requires manual trust on phones; poor UX, not in this phase.
- Password fields are not injected: macOS by design ignores synthesized events there.

## Known limits

- Phone and computer must share a LAN and the computer must have an RFC1918 private address (10.x / 172.16~31.x / 192.168.x); otherwise the app shows "no network".
- The address comes from a physical interface's private address — with a proxy TUN / fake-ip adapter present, its 198.18.x address is never picked.
- Injection targets the **currently focused** input — check the focus on the computer before sending.
