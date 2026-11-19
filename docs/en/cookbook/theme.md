# Theme recipes

Import list and ground rules: see [How-to overview](index.md#prerequisites).

## Changing the accent / following the system

Controls read theme tokens, so a theme change takes effect immediately. Set an accent with `theme_apply`; follow system dark/light and accent with `follow_system_theme`.

```moonbit
@ui.row(
  [
    @ui.button("Purple", on_click=fn() {
      @theme.theme_apply(@theme.theme_from_accent("#7c4dff"))
    }),
    @ui.button("Green", on_click=fn() {
      @theme.theme_apply(@theme.theme_from_accent("#2e7d32"))
    }),
  ],
  column_gap=8.0,
)
```

```moonbit
@ui.mount_window(
  [/* … */],
  title="Theme",
  handle=fn(a : @widget.WindowHost) {
    let _ = a.follow_system_theme(interval_ms=2000)  // returns an unsubscribe function
  },
)
```

Note: hard-coded hex colors do not track the theme; prefer the semantic routes (`SemanticType`, class presets like `text_secondary`) and hard-code only truly fixed colors.

## Giving widgets interactive styles

Add a `@style.style(...)` block through the `class` channel; the `hover` / `active` / `focus` slots each take a nested `Style` that merges in while the state is active; `transition_ms` smooths colors, border width, radius, font size, and line height.

```moonbit
@ui.card(
  [@ui.text("Hover me")],
  class=[
    @style.style(
      border_radius=8.0,
      transition_ms=150.0,
      hover=@style.style(
        border_color="#7c4dff",
        background_color="#f5f0ff",
        border_radius=12.0,
      ),
    ),
  ],
)
```

Notes:

- `class` arrays are last-wins: to override a widget's built-in style, put your block later in the array.
- Global corner and font changes use the theme layer's switches (`@theme.corners_round_set` etc.).
- Custom blocks don't consume style slots; they read the host-maintained `hovered` / `focused` flags directly: see [Custom draw & input](../components/custom-draw.md).
