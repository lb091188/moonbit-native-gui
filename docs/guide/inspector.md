# Inspector

The built-in read-only inspection channel: view the widget tree, read effective styles, capture the last frame. The embedded panel serves humans; the socket service serves AI tools and scripts — both read the same data.

## Component type name (kind)

Every widget carries a component type name at construction (e.g. `Button`, `Table`, `CodeEditor`), shown in the inspector's tree table, detail rows and the `tree` command. `kind` and the screen-reader `role` have separate jobs:

- `role`: closed enumeration for screen readers (`button`, `text_input`, ...).
- `kind`: open-string component type name for humans and AI — "what widget is this".

Wrapper layers and dynamic trees can override it with `with_kind("Name")`.

## Embedded panel

Import `gui/inspector` on demand and drop `inspector_panel()` into any page:

- Widget tree table: indented by parent chain, row label "Kind·role「name」 #id"; click a row for detail readings (id/parent/kind/role/name/state/value/text/enabled/rect).
- Style classes tab: lists registered classes; edit five fields (background/text/border color/border width/corner radius), applied next frame; "restore" reverts.
- Manual or auto refresh (500ms default); tree data comes from the frame-end semantic snapshot — the same one screen readers use.

## Service (MNG_INSPECT injection)

The app process can host a read-only inspection service that `mng` queries over a socket:

- **Injection-only switch**: `MNG_INSPECT=1` is injected by `mng dev` / `mng mcp --run`; without injection nothing starts and nothing listens. The app calls one line, `@inspector.inspect_auto_install()`, in `main` to wire it up (the `mng new` template already has it).
- **Socket location**: `moonbit-inspect-<app>.<uid>.sock` under `$XDG_RUNTIME_DIR` → `$TMPDIR` → `/tmp`, disjoint from the single-instance channel; occupied socket degrades silently to not listening.
- **App name**: from `MNG_INSPECT_APP` (injected by the tooling), default `app`.

Three commands — one-line request, TSV-lines response (256KB cap; over-long responses are cut to the last complete line with a trailing `truncated`):

| Command | Response |
|---|---|
| `tree` | Full-tree dump, one widget per line; header row first, columns kind/role/name/id/parent/x/y/w/h/state/value/text/enabled |
| `style <id>` | Effective style for the id: the first five rows are the style-editor fields (background/color/border_color/border_width/border_radius), followed by **every set field** with a group prefix (text./box./edge./border./flex./pos./misc., e.g. `text.font_size`, `flex.flex_direction`) |
| `highlight <id>` | Highlights that widget in the target app (light-blue translucent fill + outline, Chrome-DevTools-like); `highlight 0` clears. The overlay is hit-transparent and stays out of the semantic tree |
| `shot [--full] [path]` | Save a PNG. Default captures the last presented frame (viewport view); `--full` repaints the page scroll container's content at full content height (scrolling-screenshot semantics, including off-viewport content; virtual lists only include mounted rows; content beyond 20000px is clipped and noted). Without a path goes to the temp dir as `mng-shot-<title>-<timestamp>.png`; reply carries the actual path |

## mng inspect

One-shot query and print:

```sh
mng inspect tree              # full tree as TSV
mng inspect style 42          # style readings for id=42
mng inspect shot              # capture a frame to the temp dir, reply prints the path
mng inspect --app libyue.hello tree   # explicit app id
```

If the app is not running or not injected, you get "cannot connect to the inspection channel".

## mng inspect --gui (graphical inspector)

A standalone Chrome-DevTools-like inspector window shipped by mngui (the mng binary itself never links GUI libs — it only forwards arguments):

```sh
mng inspect --gui              # derive the app id from the project, then open
mng inspect --gui --app libyue.hello
mngui --inspect --app libyue.hello   # running mngui directly also works
```

- Left pane: indented widget tree (Kind·role「name」 #id), click to select, 300ms auto-refresh.
- Right pane: detail readings for the selected row (id/parent/kind/role/name/state/value/text/rect/enabled) plus the full style field set grouped (editor five first, then text/size/edges/border/flex/position/misc).
- Select-to-highlight: a highlight overlay is drawn live on the target app window and follows layout changes; closing the window clears it.
- If the app is not running or not injected, the status bar shows "not connected" and reconnects automatically.

## mng mcp (AI clients)

A stdio-transport MCP server wrapping the three capabilities as tools:

```sh
mng mcp --run "moon run examples/hello"   # spawn the app with MNG_INSPECT=1
mng mcp                                    # connect to an already-running app
```

Point your AI client at `mng mcp` as an MCP server; three tools:

| Tool | Params | Purpose |
|---|---|---|
| `inspector_tree` | none | Read the widget tree (same as `tree`) |
| `inspector_style` | `id` integer | Read the five style fields |
| `inspector_shot` | `path` optional, `full` optional | Save a screenshot, reply carries the path (no binary in the conversation); `full=true` repaints the whole page content |

Typical flow: `inspector_tree` to find widget ids, then `inspector_style` for styles and `inspector_shot` to see the screen.

## Headless test access

`@uitest`'s `Tester` has two direct methods that skip the socket, with the same assertions contract as the service:

- `dump_tree()`: runs a frame-end sync then flattens TSV, same header as the `tree` command.
- `shot(path)`: writes the viewport frame bitmap as PNG (content available after `frame()`).
- `shot_full(path)`: writes the full-page repaint as PNG (same semantics as the service's `shot --full`).

```moonbit
t.frame()
let out = t.dump_tree()
assert_true(out.contains("Button\tbutton\t"))
```
