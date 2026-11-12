# Components overview (@ui)

Every self-drawn widget and the component library live in `NoahLiu/native-gui/ui` (alias `@ui`); each component is a **constructor returning `@widget.Node`**. Parameters always follow the code (`gui/ui/*.mbt`).

> Runnable examples for every component are gathered in `examples/components` — one source file per page.

## Family pages

| Page | Contents |
|---|---|
| [Layout & containers](containers.md) | `view` / `col` / `row` / `panel` / `split` / `scroll_view` |
| [Text & basic controls](basics.md) | `text` / `image` / `icon` / `code_view` / `code_editor` / `terminal` / `gif` / divider |
| [Form controls](form.md) | `button` / `input` / `checkbox` / `select` / `slider` / `form` etc. |
| [Date & time](date.md) | `calendar` / `date_picker` / range pickers |
| [Data display](display.md) | Tags / badges / cards / progress / timeline / carousel |
| [Tables & virtual lists](table.md) | `table` / `table_v` / `virt_list` / `sticky_list` |
| [Navigation](navigation.md) | `menu` / `tabs` / `breadcrumb` / `pagination` / `tree` etc. |
| [Overlays & messages](overlay.md) | `dialog` / `message_box` / `popover` / `tooltip` / context menu |
| [Drag, hover & window events](interaction.md) | Drag sources & targets / hover & cursor groups / window show-hide |
| [Reactive controls](reactive.md) | `when` / `for_list` / visibility & list diffing |

## Conventions (read this first)

**Typed parameters + a `class` style channel.** Components take typed parameters only — size, colour, value — not CSS string tables. Overriding the look goes two ways: loose parameters (`font_size` / `background_color` and friends), or `class? : Array[@style.Style]` layering `Style` value blocks, where the last `class` in the array wins. Both fold onto one fixed order: loose parameters (properties) < `class` < the explicit rule block a component takes (`style(...)` / `anon`) — later wins. The full style layer is in [design.md (Chinese)](https://github.com/lb091188/moonbit-native-gui/blob/master/experience/design.md).

**State lives in `Store`, no glue code.** The current value of a value control (checkbox / radio / switch / slider / input / progress …) is held by an `@base.Store[T]`: the component reads and writes it, and an external change refreshes the component. Display components come through two entries — `x` takes a value, `x_dyn` takes a `Signal[T]` — sharing one drawing path.

**Events are always `on_*`.** Callbacks are named `on_click` / `on_change` / `on_drop` …; `handle?` is an escape hatch — take back the internal `@widget.Widget` handle for operations the framework does not expose — not an event.

**Keyboard accessibility is built in.** Form-family controls (button / checkbox / radio / switch / stepper / slider / rate / select / color picker / date-time / segmented) claim a focus id by default and join the Tab chain; the focus border turns the theme accent. Space/Enter activate, arrow keys adjust the value or move the selection per control semantics.

**Typography presets (the old `TextRole` is retired):** roles were folded into `@style` type-scale presets applied via `class` — `text_heading` (18 SemiBold) · `text_title` (14 SemiBold) · `text_secondary` (12, secondary colour) · `text_accent` (13 SemiBold, primary); body 13 is the `text` default and needs no preset. Sizes read from `@theme` type-scale tokens.

**`SemanticType`:** `Primary` · `Success` · `Warning` · `Danger` · `Info`. Values are stored as theme token names and resolved live on theme switch, never frozen as snapshots.

## Declarative mounting

### `mount_window(children : Array[Node], title?="", width?=800, height?=600, handle? : (WindowHost) -> Unit)`

- Describe a tree and mount it into a window: build the host (window + event loop + overlay layer + IME channel) → mount → hand it back for the caller's `run`. Returns `None` when no display service exists. This stack offers no `center`/`on_close` parameters: centering is left to the WM, closing stops the host loop, and cleanup goes after `run()`

### `mount_window_render(render : () -> Array[Node], title?, width?, height?, handle?)`

- The render-slot form, an alternative to a static node array: `render` is called once at mount to build the first frame; after that, all reactivity relies on the tree's `for_list`/`when`/`*_dyn` self-subscribing, self-diffing

## Related docs

- Tutorial and first window: [Getting started](../guide/tutorial.md)
- Declarative tree / `Store` / `Signal`: [Declarative & reactivity](../guide/declarative.md)
- Layout styling (`Style` fields and the `class` channel): [Layout & styling](../guide/layout.md)
- System capabilities (`@sys`): [System capabilities overview](../capability/sys.md)
- Field-tested platform pitfalls: [adaptation.md](https://github.com/lb091188/moonbit-native-gui/blob/master/experience/adaptation.md)
