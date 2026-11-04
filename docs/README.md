# Documentation Index

For what native-gui is, see the [home page](/). The site structure mirrors the top navigation — find docs by goal:

## Guide (zero to app)

| Document | Content |
|---|---|
| [Five-minute start](guide/tutorial.md) | Install the toolchain, create a project, and build your first window with a click counter |
| [Try the demos](guide/experience.md) | Run the prebuilt packages or the repository examples |
| [App developer experience](guide/dev-experience.md) | Project mechanics and first-time blockers: the template layout, the two levels of `moon add` vs `import`, why the two adjustments are needed, and a blockers table |
| [Build & run](guide/build.md) | Three-platform dependency lists, build commands and artefact paths, prebuilt-binary status, common failures |
| [Layout & styling](guide/layout.md) | Flexbox semantics and the `Style` field set of `@style`, plus the `class` channel |
| [Declarative & reactivity](guide/declarative.md) | The node tree and `mount_window`, `Store` / `Signal`, `for_list` / `when`, in-place replacement |
| [Canvas](guide/canvas.md) | Mounting a draw area, common `Painter` techniques, requesting redraws, offscreen PNG export |
| [Custom draw & input](guide/custom-draw.md) | Wiring a custom block to pointer / hover / focus / scroll, with a mini sketchpad skeleton |

## How-to cookbook

| Document | Content |
|---|---|
| [How-to overview](cookbook/index.md) | The "I want to do X" index + shared import list |
| [Layout recipes](cookbook/layout.md) | Centering, three-section layouts, splits, scrolling, wrapping, right-aligning |
| [Interaction recipes](cookbook/interaction.md) | Input, lists, dialogs, toasts, timers, visibility, form validation, multiple windows |
| [Theme recipes](cookbook/theme.md) | Accent colors, following the system, hover / active / focus style slots |
| [System capability recipes](cookbook/system.md) | Opening links & revealing files, clipboard, desktop notifications |

## Components (@ui)

| Document | Content |
|---|---|
| [Components overview](components/index.md) | Conventions, `mount_window`, and the family pages at a glance |
| Family pages | [Layout & containers](components/containers.md) / [Text & basics](components/basics.md) / [Forms](components/form.md) / [Date & time](components/date.md) / [Data display](components/display.md) / [Tables & virtual lists](components/table.md) / [Navigation](components/navigation.md) / [Overlays & messages](components/overlay.md) / [Drag, hover & window events](components/interaction.md) / [Reactive controls](components/reactive.md) |

## Capabilities

| Document | Content |
|---|---|
| [System capabilities overview](capability/sys.md) | Platform matrix, the shared subprocess and D-Bus layers, capability page entries |
| [Volume & media](capability/media.md) | System volume, MPRIS media control & watching, gui-media audio/video playback |
| [Apps & history](capability/apps-history.md) | App lookup, VS Code history, browser history / downloads / bookmarks, Firefox history, recent files |
| [Desktop & display](capability/desktop.md) | Session type, night light, wallpaper, monitor configuration, window management |
| [System services](capability/service.md) | macOS permissions, power plans, system info, printers, env vars, clipboard watch, autostart |
| [Embedded WebView](capability/webview.md) | Using the `gui-webview` module, with per-platform notes |
| [Charts](capability/chart.md) | `@chart`: twenty chart types, interactive variants, PNG export |
| [Markdown view](capability/mdview.md) | `@mdview`: one entry point for Markdown, selection & copy |
| [Page routing](capability/router.md) | `@router`: route tree, link binding, load & eviction policies |
| [i18n](capability/i18n.md) | `@i18n`: TOML catalogs, interpolation & plurals, locale-change subscriptions |

## Reference

| Document | Content |
|---|---|
| [Package layout](reference/packages.md) | The 17 package aliases and the two standalone modules at a glance |
| [API reference](reference/api.md) | The auto-generated per-symbol reference on mooncakes.io, with shortcuts to all seventeen packages |
| [Roadmap](zh/reference/roadmap.md) | Public roadmap (Chinese only) |
| [Third-party notices](THIRD-PARTY-NOTICES.md) | Licenses and provenance: in-repo assets, binaries we build and host on Releases, and the obligations that follow |

Internal engineering records — platform adaptation field notes, the Linux tray design, the frontend-style design and the GPU architecture decision — live in the repository's [`proposals/`](https://github.com/lb091188/moonbit-native-gui/tree/master/proposals) directory and are not published on this site.

For the project overview and quick start, see [README.md](https://github.com/lb091188/moonbit-native-gui/#readme) at the repository root.

[中文文档索引](/zh/README.md)
