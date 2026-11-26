# 工业 Industrial

车间 HMI 与 Brutalist 的杂交：直角、粗黑描边、高对比、工程感数据。可靠先于愉悦——像一台仪器，不像一个玩具。适合工控、监控台、终端工具。

## 主题 JSON

存成 `theme.json`，`mng.toml` 配 `theme = "theme.json"`，存盘即热重载：

```json
{
  "primary": "#e8590c",
  "primary_light": "#ffe8d9",
  "primary_hover": "#d9480f",
  "success": "#2b8a3e", "success_light": "#d3f9d8",
  "warning": "#f5b700", "warning_light": "#fff3bf",
  "danger": "#c92a2a", "danger_light": "#ffc9c9", "danger_hover": "#b02525",
  "info": "#1971c2", "info_light": "#d0ebff",
  "text_primary": "#171715",
  "text_regular": "#3f3f3c",
  "text_secondary": "#737370",
  "border": "#171715",
  "fill_hover": "#e6e6e3",
  "fill_zebra": "#efefec",
  "bg_page": "#e9e9e6",
  "bg_panel": "#f6f6f3"
}
```

## 口径

- **全直角**：主题里覆盖半径刻度——`"radius_scale": [0.0, 0.0, 0.0]`；控件类真圆（开关滑珠等几何圆）不受影响。
- 描边拉粗：`border_width: 2.0`，边框色用 `text_primary` 同值（token `border` 已配 #171715）。
- 密度取低档：`padding: 12px`、`row-gap: 6px`，信息排得紧凑像面板不像海报。
- 数据与读数挂等宽族：`family="mono, monospace"`；指标数值用 `text_heading` 加大。
- 状态色即语义色：正常绿 / 警告黄 / 故障红，用 `tag_of_type` 呈现，不上装饰色。
- 分区靠 `divider` 与粗描边容器，不靠圆角卡片。

## 别做什么

- 别用渐变与玻璃——仪器面板没有这些东西；透明度只用于禁用态。
- 别用衬线与手写族；全 sans + 等宽。
- 警示橙是唯一的强调色，别再引入紫、青等其他亮色。
