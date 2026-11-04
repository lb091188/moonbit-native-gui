# 图表（@chart）

`moon.pkg` 引入：

```
"NoahLiu/native-gui/chart" @charts,
```

每个图表是一个构造器：收一个 `Store`（数据住了 `Store`，外部改值即刷新），给宽高，返回节点。现场演示：showcase「图表」页（源码 `examples/showcase/pages/charts.mbt`）。

## 常用图表

| 构造器 | 数据 | 说明 |
|---|---|---|
| `line_chart_t` | `Store[Array[LineSeries]]` | 折线；`area=true` 填充，`show_last` 末值标注 |
| `bar_chart_t` | `Store[Array[BarItem]]` | 柱状 / 条形（`horizontal=true` 横向）；支持正负值 |
| `donut_chart_t` | `Store[Array[DonutSlice]]` | 环形图；`center` 给中心文字 |
| `scatter_t` | `Store[Array[(Double, Double)]]` | 散点；`trend=true` 出趋势线 |
| `candlestick_t` | `Store[Array[Candle]]` | K 线；涨跌色可改 |
| `boxplot_t` | `Store[Array[(String, Array[Double])]]` | 箱线图 |
| `gauge_t` | `Store[Double]` | 仪表盘；`thresholds` 分段着色 |
| `radar_chart_t` | 指标 + 系列两个 `Store` | 雷达图 |
| `funnel_t` | `Store[Array[BarItem]]` | 漏斗 |
| `heatmap_t` | `Store[HeatGrid]` | 热力图 |
| `sankey_t` | `Store[SankeyData]` | 桑基图 |
| `tree_chart_t` | `Store[TreeItem]` | 树图 |
| `geo_map_t` | `Store[Array[GeoRegion]]` | 地图分区，可叠航线 |

系列数据用 `make` 构造：`LineSeries::make("CPU", max_points=120)`（`max_points` 环形缓冲上限）、`BarItem::make("1月", 12.0)`、`LineSeries::with_points(s, [1.0, 2.0])` 一次喂点。

```moonbit
let line : @base.Store[Array[@charts.LineSeries]] = @base.Store::new([
  @charts.LineSeries::make("CPU", max_points=120),
])
@charts.series_push(line, 0, 42.0)   // 动态喂第 0 条系列一个点
let chart = @charts.line_chart_t(line, area=true, width=560.0, height=260.0)
```

纵向取值范围自动算；要钉死给 `y_range=(0.0, 100.0)`。

## 交互版

`line_chart_it` / `bar_chart_it` / `donut_chart_it` 三个交互版自带 tooltip、可点击图例与 DataZoom（滚轮以鼠标为锚点缩放、左键拖拽平移）；`zoom_state=Some(zoom)` 传外部 `CiZoom` 自持缩放状态。

## 导出 PNG

- `ci_save_chart(draw, w, h, path)`：把一个绘制回调离屏复渲染后落盘。
- 交互图带 `handle`：句柄上取画布后 `ci_save(canvas, path)`。

失败给 `CiSaveError`（格式非法 / 写失败），不静默。

## 全家福

其余图型同样签名规律（`Store` 进、节点出）：`eff_chart_t`（特效散点，动画自驱动）、`par_chart_t`（平行坐标）、`pb_chart_t`（像素条形）、`sun_chart_t`（旭日）、`tm_chart_t`（矩形树图）、`gph_chart_t`（关系图）、`trv_chart_t`（河流图）。逐签名见 [API 参考](../reference/api.md)。
