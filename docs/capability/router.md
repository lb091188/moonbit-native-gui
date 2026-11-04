# Page routing (@router)

Single-window multi-page apps: one route tree of any depth + an authoritative selection key per level. Sidebars, segmented bars, breadcrumbs, buttons, native menu items — every one is just a link host, wired through the same binding entry. `moon.pkg`:

```
"NoahLiu/native-gui/router" @router,
```

## Three-step wiring

**1. Define the tree**: `route_leaf` carries the content builder, `route_branch` carries children:

```moonbit
let routes : Array[@router.Route] = [
  @router.route_branch("Settings", [
    @router.route_leaf("General", fn() { @ui.col([@ui.text("General settings")]) }),
    @router.route_leaf("Appearance", fn() { @ui.col([@ui.text("Appearance")]) }),
  ]),
  @router.route_leaf("About", fn() { @ui.col([@ui.text("About")]) }),
]
```

**2. Build the router**: `new_router(routes)`; read a level's selection key with `nav.store_at(0)` (levels are 0-based).

**3. Attach hosts** — one line each for sidebar and content area:

```moonbit
let nav = @router.new_router(routes)
// sidebar
nav.sidebar([("Settings", ["General", "Appearance"])], label_of=fn(k) { k })
// content area: mounts whichever page is selected
nav.view(None)
```

Drop both into the `mount_window` node tree. Full wiring (sidebar in a scroll view, native menu items, toggle buttons) is in the showcase source `examples/showcase/main.mbt`.

## Keys and paths

Each level stores its short key; uniqueness is scoped to **the same parent** (same key under different parents is legal); path = level keys joined with `/`. `nav.path()` reads the current path, `nav.goto("Settings/Appearance")` navigates, `nav.resolve("Settings/Appearance")` splits it into level keys. A branch's key defaults to the first leaf until an explicit `goto`.

## Link binding

Hosts know nothing about routing — they bind a key: menu items, buttons, table rows take `nav.on_link(key)` (a `() -> Unit` to attach); wrap an existing node with `nav.route_link(key, node)`. Native menus (`@shell.MenuBar`) attach `nav.on_link(name)` the same way.

- Breadcrumb: `nav.breadcrumb()` returns a node directly.
- Multiple levels: `children_at(depth)` lists a level's keys, `store_at(depth)` / `route_at(depth)` read or write that level's state.

## Load & eviction

`LoadPolicy`: `Eager` (build immediately at startup — for nodes whose construction effects are needed early), `Prefetch` (idle first-order queue, the `Router` default), `Lazy` (build on first selection — heavy probe pages). Nodes override individually; `None` follows the owning `Router`'s default.

`EvictPolicy`: `Keep` (mounted subtrees stay intact; switching pages only toggles visibility, each keeps its scroll position), `Lru(n)` (a level's slot keeps at most n mounted subtrees; the least recently used is evicted).

Prefetch controls: `start_prefetch` / `stop_prefetch` pace the queue, `build_now(path)` builds immediately, `purge_built` / `purge_all_built` evict manually. Queries: `is_built` / `built_count` / `pending_count`.

## Locale changes & routing

When the whole UI switches language, page content must be remounted in place: register `nav.localize_remount()` and a locale-change broadcast triggers the remount (see [i18n](i18n.md)). Since `route_leaf`'s `build` runs at mount time, remounted pages pick up the new language.
