# Embedded WebView

`NoahLiu/gui-webview` embeds the system WebView as a native child inside a self-drawn UI. Its scope is **browser-grade expressiveness plus native capability pairing**: use web content for rich UI and interaction, and expose native capabilities to pages through bindings. It is not a full browser replica — bookmarks, history, multi-tab, extension management and permission-management panels are browser-product surface and out of scope here.

## Capabilities

- **Navigation**: `load_url` / `load_html` / back / forward / reload / stop; title, URL, started, committed, finished, failed and redirect events.
- **Interop**: `execute_javascript` (replies paired by sequence number), DOM capture (body / links / meta / structure), raw bindings (page calls native; replies arrive via `on_invoke`).
- **Policies**: new window (block / allow), downloads (auto mode = default: the event is reported and the engine default destination is used, no dialog from the library; ask mode = the request is held pending, resolved via `respond_download(id, allow, path)` — **the save dialog belongs to the app layer**; the browser example demos it with the `sys` file dialog).
- **Others**: cookie queries, custom schemes (`register_protocol`, file-root form), persistence probing, renderer-terminated events.

Events are reported per view through a queue (`on_event`); when the queue is full the oldest entry is dropped — events are hints, not a ledger.

## Permission requests and code signing

The `Permission` event plus `set_permission_mode` and `respond_permission(allow)` **remain part of the API**, implemented per platform:

- **Linux (WebKitGTK)**: the `permission-request` signal, covering geolocation / media and more.
- **Windows (WebView2)**: `PermissionRequested` + deferral.
- **macOS (WKWebView)**: media capture only (`requestMediaCapturePermissionForOrigin`, macOS 12+); geolocation has no callback in the public `WKUIDelegate`.

**On macOS this callback requires the app to be properly bundled and code-signed** (with `NSCameraUsageDescription` / `NSMicrophoneUsageDescription`). In unsigned / bare-binary form WebKit enumerates no capture devices, the page's `getUserMedia` hangs and the callback never fires — an engine-side reality, not a stub bug (measurements in `proposals/adaptation.md` and `experiment/webkit_media_probe/`). The examples therefore do not demo permissions; incoming events are denied by default and logged as one event line, so requests never dangle inside the engine.

## Platform differences

| Platform | Engine | Notable differences |
|---|---|---|
| Linux | WebKitGTK | Requires distro WebKitGTK dev packages; downloads go through `download-started` + `decide-destination` (ask mode holds the destination until `respond_download`), permissions / new windows / renderer termination have public signals |
| Windows | WebView2 | Loader and SDK headers are downloaded by prebuild; downloads / permissions / new windows use public COM events (ask mode holds the `DownloadStarting` deferral, destination via `put_ResultFilePath`) |
| macOS | WKWebView | Downloads via `WKDownload` (macOS 11.3+, destination held through the `decideDestination` completion handler and answered later); permissions are media-only and need signing; per-directory persistence needs a bundle id, bare binaries honestly report non-persistent |
