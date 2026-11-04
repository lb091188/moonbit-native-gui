# Charts (@chart)

`moon.pkg`:

```
"NoahLiu/native-gui/chart" @charts,
```

Each chart is a constructor: pass a `Store` (data lives in the `Store`, external writes refresh the chart), give it a width/height, get a node back. Live demo: the showcase "Charts" page (source `examples/showcase/pages/charts.mbt`).

## Common charts

| Constructor | Data | Notes |
|---|---|---|
| `line_chart_t` | `Store[Array[LineSeries]]` | Lines; `area=true` fills, `show_last` marks the last value |
| `bar_chart_t` | `Store[Array[BarItem]]` | Columns / bars (`horizontal=true` for horizontal); positive & negative values |
| `donut_chart_t` | `Store[Array[DonutSlice]]` | Donut; `center` for the middle text |
| `scatter_t` | `Store[Array[(Double, Double)]]` | Scatter; `trend=true` adds a trend line |
| `candlestick_t` | `Store[Array[Candle]]` | Candlesticks; up/down colors configurable |
| `boxplot_t` | `Store[Array[(String, Array[Double])]]` | Box plots |
| `gauge_t` | `Store[Double]` | Gauge; `thresholds` for banded colors |
| `radar_chart_t` | Two Stores: indicators + series | Radar |
| `funnel_t` | `Store[Array[BarItem]]` | Funnel |
| `heatmap_t` | `Store[HeatGrid]` | Heatmap |
| `sankey_t` | `Store[SankeyData]` | Sankey |
| `tree_chart_t` | `Store[TreeItem]` | Tree diagram |
| `geo_map_t` | `Store[Array[GeoRegion]]` | Map regions, optional flight lines |

Series data is built with `make`: `LineSeries::make("CPU", max_points=120)` (ring-buffer cap), `BarItem::make("Jan", 12.0)`, `LineSeries::with_points(s, [1.0, 2.0])` for a one-shot load.

```moonbit
let line : @base.Store[Array[@charts.LineSeries]] = @base.Store::new([
  @charts.LineSeries::make("CPU", max_points=120),
])
@charts.series_push(line, 0, 42.0)   // feed one point into series 0 at runtime
let chart = @charts.line_chart_t(line, area=true, width=560.0, height=260.0)
```

The value range is computed automatically; pin it with `y_range=(0.0, 100.0)`.

## Interactive variants

`line_chart_it` / `bar_chart_it` / `donut_chart_it` ship with a tooltip, a clickable legend and DataZoom (wheel zoom anchored at the cursor, drag to pan); pass `zoom_state=Some(zoom)` to own the zoom state externally.

## Exporting PNG

- `ci_save_chart(draw, w, h, path)`: re-render a draw callback offscreen, then write to disk.
- Interactive charts expose a `handle`: take the canvas from the widget and call `ci_save(canvas, path)`.

Failures return `CiSaveError` (bad format / write failed), never silent.

## Full family

Same signature pattern (Store in, node out): `eff_chart_t` (animated effect scatter), `par_chart_t` (parallel coordinates), `pb_chart_t` (pixel bar), `sun_chart_t` (sunburst), `tm_chart_t` (treemap), `gph_chart_t` (graph), `trv_chart_t` (theme river). Per-symbol details: [API reference](../reference/api.md).
