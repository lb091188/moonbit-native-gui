# Single-file components (.mng)

Write the UI as a declarative template and the state/logic in MoonBit, both inside one `.mng` file; the `mng` tool pre-compiles it to `.mbt` before `moon build` — `moon check` remains the only type gate. For commands and project config see [mng commands & config](./mng); for the hot-reload loop and editor see [Hot reload & editor](./mng-dev).

## File structure

```html
<script>
// Page state & logic: verbatim MoonBit. A let binding referenced by the template is a reactive slot.
let count : @base.Store[Int32] = @base.Store::new(0)

fn reset() {
  count.set(0)
}
</script>
<template>
  <!-- single root -->
  <ui-col class="page">
    <ui-stepper v-model="count" max="10" />
    Count: {{ count }}
    <ui-button text="Reset" @click="reset" />
  </ui-col>
</template>
<style>
.page { padding: 24px; row-gap: 8px; align-items: center; }
</style>
```

- `<script>`: verbatim MoonBit, placed at the head of the generated function body. A bare `<script>` tag (legacy `setup`/`lang` attributes still parse).
- `<template>`: single-root tree (multi-root fragments unsupported).
- `<style>`: class-selector styles, see the [style section](#the-style-section).

## Directives

| Directive | Effect | Notes |
|---|---|---|
| `{{ expr }}` | Text interpolation | Expressions are spliced into MoonBit verbatim |
| `:attr="expr"` | Dynamic attribute | Lands on the matching `*_dyn` entry; three quoting styles accepted (below) |
| `@event="handler"` | Event | Wires a script function; unknown event names are compile errors |
| `v-model="store"` | Two-way binding | Passes an `@base.Store` straight into the control's value slot |
| `v-if` / `v-else-if` / `v-else` | Structural condition | Any expression; not on the same element as `v-for` (wrap in a container) |
| `v-show="expr"` | Visibility | Subtree is not rebuilt |
| `v-for="it in items" :key="it.id"` | Keyed list | Source must be an `@base.ListStore`; `(alias, index)` form available |

Three attribute quoting styles: ① outer single quotes around a MoonBit double-quoted string `:text='@shared.tx("On")'`; ② `\"` escapes inside double quotes; ③ JS-style `'multi chars'` inside double quotes (auto-converted at compile time; a single `'a'` stays a Char literal; single-quoted strings containing escapes or embedded double quotes are not converted — compile error with guidance).

Static attributes are parsed and passed through by MoonBit literal rules (`0` / `0.0` / `true` / strings).

**Expressions are spliced verbatim**: concatenate strings via `"\{x}"` or `{{ }}`, never `"a" + 1` (MoonBit's `+` does not concat non-strings); the ceiling is what a MoonBit expression can express, and type safety is fully preserved by `moon check`.

## Component tags

- **`ui-*` built-in table**: `<ui-button>` → `@ui.button` (`-`→`_`); see [Components](/components/).
- **Same-package components**: a script `let` binding or a same-package `fn name` is usable as a tag directly, zero declarations.
- **Cross-package components**: `let name = @pkg.fn` — path from the right value, parameter order/types from the source signature.
- **Irregular landing spots**: when a children parameter is not `Array[@widget.Node]` etc., one override line (an escape hatch, not daily use):
  `// @mng sh-page = @shared.page positional(children)`

### Component props

The first `fn` declaration in the script section that has **only a signature and no body** is the component's parameter list:

```html
<script>
fn user_card(name : String, qty : @base.Store[Int32], on_reset : () -> Unit, wide? : Bool = false) -> @widget.Node {
  ...
}
</script>
<template>
  <user_card name="Alice" :qty="count" @reset="reset" />
</template>
```

- Required parameters are positional; optional ones are `name? : Type = default`.
- Attributes map by parameter name; callback props use `@event` (matched as `name` / `on_name` in the parameter list).
- Without a props header the generated function is `fn <file stem>() -> @widget.Node`.
- Unreferenced props get an automatic shim so `moon check` stays warning-free.

## The `<style>` section

```css
.page { padding: 24px; row-gap: 8px; }
.title { font-size: 18px; font-weight: bold; color: var(--primary); }
.title:hover { color: var(--text_secondary); }
.card:dark { background_color: var(--bg_panel); }
```

- **Class selectors**: `class="a b"` attaches multiple classes (later overrides earlier); a class only affects the widget it is attached to — runtime cascade / element & descendant selectors / `@media` are not supported and are compile errors.
- **Value forms**: lengths need `px` (zero may omit the unit); `width`/`height` also accept `%`; `var(--token)` resolves theme color / scale tokens; `#rrggbb` literals; enum keywords in CSS spelling (`space-between`, `flex-end`…); `flex: g [s [b]]` expands per the CSS shorthand; `transition-duration` in ms; `opacity` / `flex-shrink` unitless.
- **Interactive states**: `.name:hover` / `:active` / `:focus` compile into the style state buckets (paint-time properties only; layout properties in a bucket are compile errors).
- **Dark/light variants**: `var(--token)` colors carry both variants; literal divergence uses `.name:dark { … }`.
- **Text inheritance**: inheritable text properties (`font_size` / `color` / `text_align` / `line_height` …) flow down the widget tree, child declarations win; layout fields do not flow.
- **Hard rule**: style literals in template attributes (`color=` / `font_size=` …) are **compile errors** — they must go into `<style>` or `class`; dynamic `:attr="expr"` is unrestricted.
- **Precedence order**: inherited < component default < constructor attribute < class < `style(...)` rule block.

## Generated code & wiring

Generated code lands next to the template: `<stem>.gen.mbt` provides `pub fn <stem>() -> @widget.Node`, callable like any function:

```moonbit
@ui.mount_window([hello()], title="Template Hello", width=420, height=360)
```

- Generated files carry a `// GENERATED … DO NOT EDIT` header — never hand-edit; change the template and regenerate.
- **Commit generated code** (consumers need no toolchain); CI checks freshness for both dev and production forms (a non-empty diff after regeneration fails the build).
- Dev and production forms share the same `<stem>.gen.mbt` and overwrite each other — pick one before committing and stay consistent.
- Two same-package `.mng` files with the same stem collide (the generated function name is the file stem) — a build error names the files.

## Page context

The library injects no context; two conventions:

- **App level**: the app owns a context singleton (an `App` struct read via `@shared.app()`). Template builds read only this layer — interpolations and `:attr` expressions evaluate at mount time, before the window handle exists.
- **Window level**: enumerate/switch windows via `@widget.host_windows()` / `@widget.active_window()`; window APIs (title, size, borderless…) read the context's `host : Ref[@widget.WindowHost?]` **inside callbacks** — valid only after the mount callback.

## Common errors

| Symptom | Cause & fix |
|---|---|
| `v-for 源须是 @base.ListStore` | Source was a Store/Signal or plain variable — use `let rows : @base.ListStore[T] = @base.ListStore::new()` |
| `v-for 与 v-if 不写在同一元素` | Separate them with a container (outer v-if wrapping v-for, or inline v-if) |
| `String + Int` type errors | Expressions splice verbatim — concatenate via `{{ }}` or `"\{x}"` |
| `moon check` reports generated code out of date | Template and generated code out of sync — re-run `mng dev` (dev form) or `mng build` (production form), then commit |
| Same-package generated-function conflict | Two `.mng` files share a stem (function name = file stem) — rename one |
| `color="#f00"` in a template attribute is a compile error | Style literals must go into `<style>` or `class` — enforced by the compiler, not advisory |
| HOT did not apply, went COLD | v-for row templates / script / new symbols are COLD by design; the `[HOT→COLD]` log line says why |
