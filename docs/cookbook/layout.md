# Layout recipes

Import list and ground rules: see [How-to overview](index.md#prerequisites).

## Centering content (horizontal / vertical / both)

| Container | Main axis | Center horizontally | Center vertically |
|---|---|---|---|
| `col` (main axis vertical) | vertical | `align_items` (parameter) | `justify_content` (via `class` or `view`) |
| `row` / `view(direction=Row)` (main axis horizontal) | horizontal | `justify_content` (via `class` or `view`) | `align_items` (parameter) |

Both axes, `view` form (same as `examples/hello`):

```moonbit
@ui.view(
  [@ui.text("Hello, MoonBit!", class=[@style.text_heading])],
  grow=1.0,                                     // fill the parent's remaining space
  align_items=@yoga.AlignItems::Center,         // cross axis (horizontal): center
  justify_content=@yoga.JustifyContent::Center, // main axis (vertical): center
)
```

`col` form — loose parameters only take `align_items`, so the vertical main axis goes through `class`:

```moonbit
@ui.col(
  [@ui.text("Hello, MoonBit!", class=[@style.text_heading])],
  grow=1.0,
  align_items=@yoga.AlignItems::Center,
  class=[@style.style(justify_content=@yoga.JustifyContent::Center)],
)
```

Horizontal only: drop `justify_content`. Vertical only: keep only `justify_content`; children stretch to full width on the cross axis by default.

Notes:

- The container must fill its parent (`grow=1.0` or an explicit `height`), otherwise there is no free space to distribute.
- The axis follows the container's direction: `align_items=Center` centers horizontally in a `view` (default direction Column) and vertically in a `row`.
- `@ui.text(align=...)` controls alignment inside a wrapped text block; centering the block in its container uses the table above.
- Enums are written in full form `@yoga.AlignItems::Center`; short forms like `@yoga.Center` are equivalent.

## Header + flexible body + footer

Header and footer size to content; the body consumes all remaining height and scrolls internally. Outer `col` with three children; the body is wrapped in `col(grow=1.0)` with the scroll viewport at `height=0.0`.

```moonbit
let body = @ui.ScrollState::new()
@ui.col(
  [
    @ui.row(
      [@ui.text("Settings", class=[@style.text_title])],
      padding=12.0,
    ),
    @ui.col(
      [
        @ui.scroll_view(
          [
            @ui.text("A long first paragraph…"),
            @ui.text("A long second paragraph…"),
            // …
          ],
          body,
          height=0.0,  // viewport height delegated to the parent
        ),
      ],
      grow=1.0,
      min_height=0.0,
    ),
    @ui.row(
      [
        @ui.button("Cancel"),
        @ui.button("Save", variant=@ui.Solid),
      ],
      column_gap=8.0,
      padding=12.0,
      class=[@style.style(justify_content=@yoga.JustifyContent::FlexEnd)],
    ),
  ],
)
```

Notes:

- Without `grow=1.0` on the body, all three sections size to content and the footer does not sit at the window bottom.
- Without `min_height=0.0` on the wrapping layer, long content pushes it back to its natural height (min:auto) and the scroll viewport never gets a fixed viewport. The scroll view handles this itself; a layer you wrap around it must state it. See [Layout & styling](../guide/layout.md).

## Sidebar + flexible main area (splitting)

Fixed width via `width=`, flexibility via `grow=1.0`, equal halves via `width_percent=50.0`, draggable divider via `split`.

```moonbit
@ui.row(
  [
    @ui.col([@ui.text("Nav"), @ui.text("Settings")], width=180.0),
    @ui.col([@ui.text("Main area")], grow=1.0),
  ],
  align_items=@yoga.AlignItems::Stretch,
)
```

```moonbit
@ui.row(
  [
    @ui.col([@ui.text("Left")], width_percent=50.0),
    @ui.col([@ui.text("Right")], width_percent=50.0),
  ],
)
```

```moonbit
@ui.split(
  @ui.col([@ui.text("File tree")]),
  @ui.col([@ui.text("Editor")]),
  ratio=0.3,
  min_first=160.0,
)
```

Note: `row`'s `align_items` defaults to Center (`col` defaults to Stretch); write `Stretch` explicitly for full-height panes.

## Scrolling overflowing content

`scroll_view` is the scrolling container; `ScrollState` holds the offset state (required); `height` is the viewport height. Vertical scrolling is the default; horizontal needs `hscroll=true`.

```moonbit
let st = @ui.ScrollState::new()
@ui.scroll_view(
  [
    @ui.text("Line 1"),
    @ui.text("Line 2"),
    // …many lines…
  ],
  st,
  height=300.0,
)
```

```moonbit
@ui.scroll_view(
  [@ui.text("A very long line that must not wrap")],
  @ui.ScrollState::new(),
  height=40.0,
  hscroll=true,
)
```

Notes:

- The viewport height needs a source: an explicit `height=`, or `height=0.0` inside a `grow=1.0` layer.
- `code_view` scrolls horizontally on its own; no `scroll_view` wrapper needed.
- The scrollbar colors in on hover and takes no layout width; `st.at_bottom()` reads whether the bottom is reached.

## Wrapping a row of tags

A `row` container plus `flex_wrap`; spacing between wrapped lines uses `row_gap`, between items `column_gap`.

```moonbit
@ui.row(
  [
    @ui.tag_of_type("MoonBit", @ui.Primary),
    @ui.tag_of_type("Cross-platform", @ui.Success),
    @ui.tag_of_type("Native windows", @ui.Info),
    @ui.tag_of_type("Self-drawn", @ui.Warning),
    @ui.tag_of_type("Theming", @ui.Danger),
    // …more tags wrap naturally
  ],
  column_gap=8.0,
  class=[@style.style(flex_wrap=@yoga.FlexWrap::Wrap, row_gap=8.0)],
)
```

Note: if wrapping does not kick in, check two things — the container is a `row`, and no enclosing layer pins its minimum size to content size (if needed write `min_width=0.0, min_height=0.0` on it). See the min:auto rules in [Layout & styling](../guide/layout.md).

## Right-aligning a button row

A `row`'s main axis is horizontal; main-axis alignment is `justify_content`, and `FlexEnd` means right. `row` takes no such loose parameter — use the `class` channel.

```moonbit
@ui.row(
  [
    @ui.button("Cancel"),
    @ui.button("OK", variant=@ui.Solid),
  ],
  column_gap=8.0,
  class=[@style.style(justify_content=@yoga.JustifyContent::FlexEnd)],
)
```

Other modes: `FlexStart` (default), `Center`, `SpaceBetween`, `SpaceAround`, `SpaceEvenly`. A `col` applies the same set vertically (see [Centering](#centering-content-horizontal--vertical--both)).
