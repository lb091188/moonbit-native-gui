# Hot reload & editor

The `mng dev` loop and editor support. Grammar in [Single-file components (.mng)](./sfc); commands and `mng.toml` in [mng commands & config](./mng).

## The mng dev loop

```sh
cd my_app && mng dev
```

- **Watch surface**: all project templates (per `mng.toml [dev].templates`) + project source files (`.mbt` (excluding `*.gen.mbt`) / `moon.pkg` / `moon.mod` / `moon.work`) + theme files (when the `theme` key is set).
- **First pass**: generates dev-form `<stem>.gen.mbt` next to each template (the hot-reload surface lives in the `@mngdev` library package) → `moon build` → launches the app. With `run` empty, the executable is grabbed from the Artifacts output.
- Dev artifacts live under `.mng/`: app logs, source maps (`.mng/map/`), IR patches, LSP hover scratch files — no generated clutter in source directories.

## Change classification: HOT / COLD

Every save is classified by contract, and the log truthfully reports which path was taken:

| Change | Path | Feel |
|---|---|---|
| Structural add/remove/move, `:attr` retargeting, class & `<style>` values | **HOT** (IR patch pushed over the single-instance channel, in-place remount) | sub-second |
| Expression text within the restricted grammar (literals / Store / arithmetic & comparison / if / `@shared.tx`·`tr` / interpolation) | **HOT** (dev registry registers the new expression) | sub-second |
| Script section, `v-for` row templates, new symbols / functions, custom components, out-of-table parameters | **COLD** (build → kill → relaunch) | seconds |
| Out-of-grammar expressions | COLD, with a `[HOT→COLD]` log line giving the reason | seconds |

- **COLD returns to the edited page** (woken by template stem) — no manual navigation.
- **State preservation**: Stores created at the script section's outer level stay alive (the counter survives a structural hot patch); page-local state resets with the patch; widget-internal state (focus / scroll / IME composition) resets with the subtree.
- **Handshake prevents false application**: patches carry `rev` + a key-set digest; on stale, the app skips the whole remount and acks — the tool turns that pass into COLD, so "patch failed but UI stuck on the old tree" cannot happen.
- After a fix-up save the UI may flash the old state once and self-correct — a known artifact.

## File additions & removals

- **Adding** an `.mng` while running → log `[NEW]`, auto-generated and folded into the next rebuild.
- **Removing** → `[GONE]`, unregisters and clears generated code (if the generated header doesn't match, only the path is reported, protecting handwritten files).
- Editing project sources like `main.mbt` → `[SRC]`, COLD restart.

## Theme hot reload

With `theme = "assets/theme.json"` in `mng.toml`, saving the theme JSON **reloads it instantly** (`@theme.from_json` re-applied, no restart). Tune colors by edit-save-look.

## App-side wiring (@mngdev)

One line in the template package's `moon.pkg` (`mng new` writes it for you; only hand-wired projects need it):

```
"NoahLiu/native-gui/mngdev" @mngdev
```

The app copies zero dev-surface code; production builds swap in production-form generated code and the dev surface is entirely absent.

## VS Code extension (tools/vscode-mng)

Install: `cd tools/vscode-mng && npx @vscode/vsce package`, then install the vsix (`--force` to overwrite), or see its README. Capabilities:

- **Highlighting**: TextMate (MoonBit in script, the style subset in `<style>`, template tags and interpolations) + **semantic highlighting** (LSP `semanticTokens`: type/variable/parameter/function/method/namespace tiers; any theme with semantic highlighting enabled differentiates; falls back to pure TextMate without the LSP).
- **Completion**: tags = built-in `ui-*` table + in-page/cross-package components; attributes = component parameters + `v-*` / `@events`; expressions = props/slots/functions + common module prefixes; class names = the file's `<style>`.
- **Hover**: component parameter tables; real type hover forwards through the source map to `moon ide` for the compiler's answer, falling back to static hover on any failure (no regression).
- **Go to definition**: in-page declarations, component source files, `@alias.member`.
- **Diagnostics**: on save `mng lsp` didSave regenerates in place and runs `moon check`; type errors are **mapped back to template coordinates** in Problems (no more reading errors against generated code).
- **Command palette**: `MNG: dev` (launches `mng dev` in the integrated terminal), `MNG: new page` (calls `mng new page`, opens the file).
- Generated files nest under their template by default (view-only, nothing on disk changes).

LSP degradation: the extension handshakes the `mng-schema` bit via `mng --version`; on mismatch completion/diagnostics degrade to empty while highlighting and snippets keep working.

## Known artifacts

- After a fix-up save the UI may flash the old state once and self-correct (handshake re-entry window).
- Dev-form and production-form generated code overwrite each other — pick one before committing (see [mng commands & config](./mng#generated-code-discipline)).
