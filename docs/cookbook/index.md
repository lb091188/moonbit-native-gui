# How-to overview

A scenario manual indexed by "I want to do X", split across four pages: [Layout recipes](layout.md), [Interaction recipes](interaction.md), [Theme recipes](theme.md), [System capability recipes](system.md). Each recipe gives a description, paste-ready code, and notes. Starting from zero: the [five-minute start](../guide/tutorial.md).

## Prerequisites

Use this `moon.pkg` import list (each recipe references what it needs):

```
import {
  "NoahLiu/yoga-mbt/src" @yoga,
  "NoahLiu/native-gui/base" @base,
  "NoahLiu/native-gui/shell" @shell,
  "NoahLiu/native-gui/widget" @widget,
  "NoahLiu/native-gui/ui",
  "NoahLiu/native-gui/style" @style,
  "NoahLiu/native-gui/sys" @sys,
  "NoahLiu/native-gui/theme" @theme,
}
```

- Layout recipes show a node tree that replaces the first argument of `mount_window`; interaction recipes are complete programs.
- Two write paths: constructor loose parameters (`padding=` / `width=` …) and `class=[@style.style(...)]` style blocks; `class` arrays are last-wins. See [Layout & styling](../guide/layout.md).
- A flex container has two axes: the main axis of `col` is vertical, of `row` horizontal; `justify_content` aligns along the main axis, `align_items` along the cross axis.

## Recipe index

| I want to… | Key API | Recipe |
|---|---|---|
| Center content (h/v/both) | `align_items` / `justify_content` | [Layout · Centering](layout.md#centering-content-horizontal-vertical-both) |
| Header + body + footer | `col` + `grow` + `scroll_view` | [Layout · Three sections](layout.md#header-flexible-body-footer) |
| Sidebar + main / halves / draggable split | `grow` / `width_percent` / `split` | [Layout · Splitting](layout.md#sidebar-flexible-main-area-splitting) |
| Scroll content (v/h) | `scroll_view` + `ScrollState` | [Layout · Scrolling](layout.md#scrolling-overflowing-content) |
| Wrap a row of tags | `flex_wrap=@yoga.FlexWrap::Wrap` | [Layout · Wrapping](layout.md#wrapping-a-row-of-tags) |
| Right-align buttons | `justify_content=FlexEnd` (class) | [Layout · Right-align](layout.md#right-aligning-a-button-row) |
| Read input / submit on Enter | `input` + `Store[String]` + `on_enter` | [Interaction · Input](interaction.md#reading-input-and-submitting-on-enter) |
| Add/remove list items | `ListStore` + `for_list` | [Interaction · Lists](interaction.md#adding-and-removing-list-items) |
| Confirmation dialog | `dialog` + `Store[Bool]` | [Interaction · Dialog](interaction.md#a-confirmation-dialog) |
| Action feedback toast | `toast_layer` | [Interaction · Toast](interaction.md#a-toast) |
| Refresh on a timer | `@shell.set_timeout` with tail self-rearm | [Interaction · Timer](interaction.md#refreshing-on-a-timer) |
| Show/hide on a condition | `when_store_bool` / `when_else_store` | [Interaction · Visibility](interaction.md#showing-and-hiding-on-a-condition) |
| Form validation | `form` + `form_item(error=)` | [Interaction · Forms](interaction.md#form-items-with-error-messages) |
| Open a second window | `WindowHost::open_window` + `mount` | [Interaction · Windows](interaction.md#opening-a-second-window) |
| Change accent / follow system | `theme_apply` / `follow_system_theme` | [Theme · Accent](theme.md#changing-the-accent-following-the-system) |
| Per-widget hover styling | `class` + `hover=` + `transition_ms` | [Theme · States](theme.md#giving-widgets-interactive-styles) |
| Open links / reveal files | `@sys.open_url` / `@shell.reveal_in_file_manager` | [System · Open](system.md#opening-links-revealing-files) |
| Copy to clipboard | `@sys.clipboard_set_text` | [System · Clipboard](system.md#copying-to-the-clipboard) |
| Desktop notification | `@shell.notify_send` | [System · Notifications](system.md#desktop-notifications) |
| Draw what no widget gives you / wire a custom block to keyboard & mouse | `node_of_new` + `on_draw` / `on_pointer` / `on_key` | [Custom draw & input](../guide/custom-draw.md) |

## Next steps

- Widget signatures: [Components overview](../components/index.md); state binding: [Declarative & reactivity](../guide/declarative.md); every layout field: [Layout & styling](../guide/layout.md).
- Full programs combining these recipes: `cd examples/showcase && moon run .`; each page's source is under `examples/showcase/pages/*.mbt`.
