# 暗夜科技 Dark Tech

近黑蓝底、荧光强调、等宽数据、细亮描边。控制台气质——GitHub 暗色、终端、开发者仪表盘的同族。适合开发者工具、监控、数据密集型应用。

## 主题 JSON

存成 `theme.json`，`mng.toml` 配 `theme = "theme.json"`，存盘即热重载：

```json
{
  "primary": "#22d3a7",
  "primary_light": "#0e3d31",
  "primary_hover": "#4ae0bd",
  "success": "#34d399", "success_light": "#0c3b2e",
  "warning": "#fbbf24", "warning_light": "#3f2e0a",
  "danger": "#f87171", "danger_light": "#3f1a1a", "danger_hover": "#ff9b9b",
  "info": "#58a6ff", "info_light": "#14294a",
  "text_primary": "#e6edf3",
  "text_regular": "#9fb0c3",
  "text_secondary": "#5c6b7f",
  "border": "#1f2a3a",
  "fill_hover": "#151d29",
  "fill_zebra": "#101721",
  "bg_page": "#0a0e14",
  "bg_panel": "#11161f",
  "chart_palette": ["#22d3a7", "#58a6ff", "#f778ba", "#f2cc60", "#a78bfa"]
}
```

## 口径

- 数据与指标挂等宽族：`family="mono, monospace"`；数值用 `text_heading` 加大、语义色点状态。
- 强调色（荧光青）只给：主操作、活动态、关键数据线；其余全部灰阶。
- 「发光感」用亮色 1px 描边与亮底浅档（`*_light`）模拟——本库无投影，别找 shadow。
- 圆角用基准档（4/6/8）；图表色走 `chart_palette` 荧光序列，深底上画线清楚。
- 层级三板斧：`bg_page` 与 `bg_panel` 一层深浅差、1px 暗描边、hover 用 `fill_hover` 提亮。
- 密度中档：仪表盘网格 `12px` 间距，卡片内 `8px`。

## 别做什么

- 别满屏荧光——荧光色占比超过一成就从「科技」变「夜店」。
- 别在深底上用低对比灰字写重要信息（`text_secondary` 只放辅助说明）。
- 别用彩虹渐变按钮；强调色只有一个，其余语义色只进状态。
