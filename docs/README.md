# Documentation Index

For what native-gui is, see the [home page](/). Find docs by goal:

## Routing

| Document | Content |
|---|---|
| [dev-experience.md](dev-experience.md) | App developer experience: from zero to your first window — toolchain, project setup (the two adjustments the `moon new` template needs), running, and common blockers |
| [tutorial.md](tutorial.md) | Five-minute start: install the toolchain, create a project, and build your first window with a click counter |
| [howto.md](howto.md) | How-to guides: 19 "I want to…" recipes (layout / interaction / styling & theme / system capabilities), each with goal, approach, code and pitfalls |
| [components.md](components.md) | Component quick-reference (`@ui`): constructor signatures and purposes for every widget, grouped by family |
| [declarative.md](declarative.md) | Declarative layer and reactivity: the node tree and `mount_window`, `Store` / `Signal`, `for_list` / `when`, in-place replacement |
| [layout.md](layout.md) | Layout: the Flexbox layout semantics, the `Style` field set of `@style`, and the `class` channel |
| [build.md](build.md) | Build and run: installing the dependencies from scratch (per-platform lists + a self-check), build commands and artefact paths, the state of prebuilt binaries, failure → fix; library-development mechanics in the second half |
| [packages.md](packages.md) | Package layout: the 17 package aliases and the two optional modules at a glance |
| [system-capabilities.md](system-capabilities.md) | System capabilities overview (`@sys`): volume, app lookup, color temperature, wallpaper, monitors, window management, clipboard watch, autostart, system info, printers, recent files, browser history and more, with unified `Result` semantics; plus the shared subprocess and D-Bus call layers |
| [webview.md](webview.md) | Embedded WebView: using the `gui-webview` module, with per-platform notes |
| [zh/roadmap.md](zh/roadmap.md) | Public roadmap: positioning, what you can use today, platform and feature matrix, commitments and versioning, next steps, open decisions, explicit non-goals (Chinese only) |
| [experience.md](experience.md) | Experience guide: try it for real — run the prebuilt demos or the repository examples; app building and library work are routed to the App developer experience and Build & run |
| [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md) | Third-party licenses and provenance: assets shipped in-repo, binaries we build and host on Releases, and the obligations that follow (Chinese only) |

Internal engineering records — platform adaptation field notes, the Linux tray design, the frontend-style design and the GPU architecture decision — live in the repository's [`proposals/`](https://github.com/lb091188/moonbit-native-gui/tree/master/proposals) directory and are not published on this site.

For the project overview and quick start, see [README.md](https://github.com/lb091188/moonbit-native-gui/#readme) at the repository root.

[中文文档索引](/zh/README.md)
