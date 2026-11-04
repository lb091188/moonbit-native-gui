# Apps & history

Application lookup and read-only access to on-machine usage records. Uniform `Result` semantics and the support matrix: [System capabilities overview](sys.md).

## Application Lookup

Two parts: the installed-app inventory and the app binary lookup. Linux scans XDG `.desktop` entries; the user directory overrides the system directory. Windows recursively scans the Start Menu (user-level + machine-wide) for `.lnk` files — an entry's exec is the full lnk path, directly launchable via ShellExecute, and categories is marked `StartMenu`. macOS scans `.app` bundles under `/System/Applications`, `/Applications` (each with one `Utilities` level) and `~/Applications`, reading the public keys of `Contents/Info.plist`: name from CFBundleDisplayName → CFBundleName → bundle directory name, id from CFBundleIdentifier (bundle name when missing), exec is `Contents/MacOS/<CFBundleExecutable>`, icon is `Contents/Resources/<CFBundleIconFile>` (`.icns` appended when the key has no extension, empty string when absent); binary plists or unreadable bundles still yield an entry under the bundle name instead of vanishing from the inventory. Two macOS fields are empty: `categories` (no desktop-Categories equivalent) and the localized name (it lives in `.lproj`, out of reach of public plist keys, so `locale_name` equals `name`).

| Function | Description |
|---|---|
| `appfind_installed() -> Result[Array[AppEntry], AppFindError]` | installed-app inventory; yields `NoScanDir` when every scan directory is missing |
| `appfind_installed_with(list_dir) -> Result[Array[AppEntry], AppFindError]` | same as above, with directory enumeration injected by the caller — for callers without an fsx layer and for tests; Linux branch only |
| `appfind_executable(name) -> Result[String, AppFindError]` | Linux searches `~/.local/bin`, `/usr/local/bin`, `/usr/bin`, `/bin`, `/usr/sbin`, `/sbin` in order; Windows searches each `PATH` directory for name / name.exe; macOS follows each `PATH` segment (`:`-separated, absolute paths) then `~/.local/bin`, `/usr/local/bin`, `/opt/homebrew/{bin,sbin}`, `/usr/bin`, `/bin`, `/usr/sbin`, `/sbin`; yields `NotFound` when nothing matches |

`AppEntry{ id, name, locale_name, exec, icon, categories }`: id is the desktop id (the .desktop filename without extension), name is the display name, locale_name is the localized name (`Name[zh_CN]` preferred, falling back to Name), exec / icon kept verbatim, categories split on semicolons. Results are deduplicated by desktop id (user directory overrides system directory) and sorted by name; entries whose Type is not Application, with NoDisplay=true, or missing Name are filtered out.

```moonbit
// Installed inventory: inject a directory-listing function (e.g. your own readdir wrapper)
match @sys.appfind_installed_with(fn(dir) { my_list_dir(dir) }) {
  Ok(apps) => for a in apps {
      println("\{a.locale_name}  \{a.exec}")
    }
  Err(e) => println("Unavailable: \{e}")
}
// Binary lookup
match @sys.appfind_executable("code") {
  Ok(path) => println("code located at \{path}")
  Err(@sys.AppFindError::NotFound(_)) => println("Not installed")
  Err(_) => println("Platform not supported")
}
```

## VS Code Local History & Recent Workspaces

Reads local VS Code user data: the local history snapshot list for a file (`User/History`) and recent workspaces. Paths for all three platforms are implemented, each located by its user-data directory.

| Function | Description |
|---|---|
| `vsc_supported() -> Bool` | whether the machine has readable VS Code user data |
| `vsc_local_history(file_path) -> Result[Array[VscHistoryEntry], VscodeError]` | history snapshots of a file (time-descending); an absolute path or a `file://` URI both work; an empty array when there is no history |
| `vsc_recent() -> Result[Array[String], VscodeError]` | recently opened workspace / folder paths (most recently active first); an empty array when there is no window state |

`VscHistoryEntry{ path, timestamp }`: path is the absolute path of the snapshot file — the file's full text at that moment; timestamp is Unix milliseconds, converted to seconds by `timestamp_seconds()`. Error `VscodeError`: `Unsupported` (cannot locate the user-data directory) / `StorageUnavailable` (VS Code has never run on this machine) / `StorageCorrupted(String)` / `HistoryCorrupted(String)`.

```moonbit
match @sys.vsc_local_history("/home/me/proj/src/main.mbt") {
  Ok(snaps) => for s in snaps {
      println("\{s.timestamp_seconds()}  \{s.path}")
    }
  Err(e) => println("Unavailable: \{e}")
}
match @sys.vsc_recent() {
  Ok(paths) => if paths.length() > 0 {
      println("Recent workspace: \{paths[0]}")
    }
  Err(e) => println("Unavailable: \{e}")
}
```

## Browser History & Download Records

Read-only access to the History databases of Chrome / Chromium / Edge / Brave; all profiles are auto-detected (Default and Profile 1..24). Only the Linux path detection is implemented; other platforms yield `BhUnsupported`.

| Function | Description |
|---|---|
| `bh_supported() -> Bool` | whether the current platform is supported |
| `bh_browsers() -> Result[Array[BrowserProfile], BrowserHistoryError]` | list profiles with a readable History database; yields `BhNoBrowser` when none is readable |
| `bh_history(limit? = 200) -> Result[Array[HistoryItem], BrowserHistoryError]` | browsing history — aggregates all profiles, sorted by last-visit time descending, hidden redirect entries filtered out; limit ≤ 0 takes everything |
| `bh_downloads(limit? = 50) -> Result[Array[DownloadItem], BrowserHistoryError]` | download records (sorted by start time descending) |
| `bh_search(keyword, limit? = 50) -> Result[Array[HistoryItem], BrowserHistoryError]` | substring search on url or title, ASCII case-insensitive; an empty keyword matches everything |
| `bh_download_state_name(state) -> String` | download state number → name (in progress / complete / cancelled / interrupted) |

`BrowserProfile{ browser, profile, history_path }`: browser is google-chrome / chromium / microsoft-edge / brave, profile is the directory name (Default or Profile N). `HistoryItem{ url, title, visit_count, last_visit_time }` (times are Unix milliseconds, 0 when unknown); `DownloadItem{ target_path, received_bytes, total_bytes, start_time, end_time, state }`. Error `BrowserHistoryError`: `BhUnsupported` / `BhNoConfigDir` / `BhNoBrowser` / `BhIoFailed(String)` — a single profile read failure is skipped; only an all-fail case errors.

```moonbit
match @sys.bh_history(limit=6) {
  Ok(items) => for it in items {
      let title = if it.title == "" { "(No title)" } else { it.title }
      println("[\{it.visit_count} visits] \{title}\n  \{it.url}")
    }
  Err(e) => println("Unavailable: \{e}")
}
match @sys.bh_downloads(limit=3) {
  Ok(ds) => for d in ds {
      println("\{d.target_path}  \{@sys.bh_download_state_name(d.state)}")
    }
  Err(_) => ()
}
let _ = @sys.bh_search("moonbit", limit=10)
```

## Browser Bookmarks (Chrome Family)

Read-only parsing of the `Bookmarks` JSON files of Chrome / Chromium / Edge / Brave. The JSON parse reuses the package's hand-written parser — Chrome stores date_added and friends as numeric strings, integer fields keep Int64 precision, and microsecond values convert to Unix milliseconds. All profiles are auto-detected (Default and Profile 1..24).

| Function | Description |
|---|---|
| `bm_supported() -> Bool` | Linux (this file implements only the Linux path detection) |
| `bm_browsers() -> Result[Array[BookmarkProfile], BookmarkError]` | list profiles with a readable Bookmarks file |
| `bm_bookmarks(browser) -> Result[BookmarkNode, BookmarkError]` | the first readable bookmark tree of a given browser; the browser identifier takes "google-chrome"/"chromium"/"microsoft-edge"/"brave", the profile takes Default first, then Profile 1..24 |

`BookmarkProfile{ browser, profile, bookmarks_path }`; `BookmarkNode{ name, url?, children, added, root }` (added is Unix milliseconds; root labels the owning root: bookmark_bar / other / synced). The returned tree has a virtual root — name `"<browser>/<profile>"`, children merge the three roots. `BookmarkNode::is_folder()` / `is_url()` classify nodes, and `bm_flatten(node)` gives a preorder flattened url-bookmark list. Error `BookmarkError`: `BmUnsupported` / `BmNoConfigDir` / `BmNoBrowser` / `BmIoFailed(String)`.

```moonbit
match @sys.bm_bookmarks("google-chrome") {
  Ok(root) =>
    for n in @sys.bm_flatten(root) {
      println("\{n.name}  →  \{n.url}")
    }
  Err(e) => println("Cannot read: \{e}")
}
```

## Firefox Browsing History

Reads each profile's `places.sqlite` (the `moz_places` table) under `~/.mozilla/firefox/`. Entries reuse `browser_history.mbt`'s `HistoryItem`; times convert from Unix-epoch microseconds to milliseconds. Sorting / truncation / column selection reuse the pure functions exported by the same file.

| Function | Description |
|---|---|
| `ffx_supported() -> Bool` | profiles.ini location is implemented for Linux / macOS / Windows |
| `ffx_profiles() -> Result[Array[FirefoxProfile], FirefoxHistoryError]` | list profiles with a readable places.sqlite |
| `ffx_history(limit? = 200) -> Result[Array[HistoryItem], FirefoxHistoryError]` | browsing history — aggregates all detected profiles, sorted by last-visit time descending; limit ≤ 0 takes everything |

`FirefoxProfile{ profile, places_path }` (profile is the `Path=` directory name from profiles.ini; absolute paths take the last segment). Hidden entries are filtered out; a single profile read failure is skipped, and `FfxIoFailed` is yielded only when all fail. Error `FirefoxHistoryError`: `FfxUnsupported` / `FfxNoProfile` (Firefox not installed or never started) / `FfxIoFailed(String)`. When profiles.ini is missing it falls back to fixed candidate names (default / default-release / default-esr / default-nightly / dev-edition-default); profile directories with a random prefix are not picked up.

```moonbit
match @sys.ffx_history(limit=10) {
  Ok(items) => for it in items { println("\{it.title}  \{it.url}") }
  Err(e) => println("Cannot read: \{e}")
}
```

## Recent Files (GTK recently-used.xbel)

Parses freedesktop's `recently-used.xbel`. GTK apps write this list via `GtkRecentManager` / xdg-desktop-portal-gtk; Thunar / Nautilus / GIO all append to it when opening a file. File location: `$XDG_DATA_HOME/recently-used.xbel` (default `$HOME/.local/share/`). The XML parser is a hand-written thin scanner: it reads only bookmark nodes and the attributes of `bookmark:application` / `mime:mime-type` child nodes, XML-entity decodes attribute values, and percent-decodes the `file://` URI in href; timestamps convert from ISO 8601 to Unix milliseconds.

| Function | Description |
|---|---|
| `rf_supported() -> Bool` | Linux and the file is readable |
| `rf_recent(limit? = 100) -> Result[Array[RecentItem], RecentError]` | recent file list, modified-descending with ties by path ascending; limit ≤ 0 takes everything |
| `rf_by_app(name, limit? = 100) -> Result[Array[RecentItem], RecentError]` | filter by application name — exact match on the name of `bookmark:application` — also descending |

`RecentItem{ uri, path, mime, added, modified, app_count }`: path is the local path after stripping the `file://` prefix from href and percent-decoding (non-file:// schemes give an empty string); mime is the MIME type (None when that node is absent); added / modified are Unix milliseconds (0 when missing or invalid); app_count is how many applications recorded this file. Error `RecentError`: `RfUnsupported` / `RfNoDataDir` / `RfNoFile` / `RfParseFailed(String)`. Pure decode/conversion functions: `rf_xml_unescape` / `rf_percent_decode` / `rf_uri_to_path` / `rf_iso_to_unix_ms` / `rf_sort_recent`.

```moonbit
match @sys.rf_recent(limit=8) {
  Ok(items) => for it in items { println("\{it.path}  (\{it.modified})") }
  Err(e) => println("Cannot read: \{e}")
}
```
