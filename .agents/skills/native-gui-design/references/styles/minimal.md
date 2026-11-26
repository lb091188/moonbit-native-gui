# 简约 Minimal

大留白、中性色、细描边、零装饰。信息本身是唯一的视觉主角；纪律感来自间距刻度的一丝不苟。适合工具类、效率类、开发者向应用。

## 主题 JSON

存成 `theme.json`，`mng.toml` 配 `theme = "theme.json"`，存盘即热重载：

```json
{
  "primary": "#2563eb",
  "primary_light": "#dbeafe",
  "primary_hover": "#1d4ed8",
  "success": "#16a34a", "success_light": "#dcfce7",
  "warning": "#d97706", "warning_light": "#fef3c7",
  "danger": "#dc2626", "danger_light": "#fee2e2", "danger_hover": "#b91c1c",
  "info": "#0284c7", "info_light": "#e0f2fe",
  "text_primary": "#111827",
  "text_regular": "#374151",
  "text_secondary": "#6b7280",
  "border": "#e5e7eb",
  "fill_hover": "#f3f4f6",
  "fill_zebra": "#f9fafb",
  "bg_page": "#ffffff",
  "bg_panel": "#fafafa"
}
```

## 口径

- 圆角用基准档（控件 4 / 卡片 6 / 浮层 8），不另放大；刻度不覆盖。
- 层级只靠 `bg_page` 与 `bg_panel` 一层灰度差 + 1px 描边；其余分层用留白做。
- 间距取中高档：页面 `padding: 24px`、区块间 `row-gap: 16px`、件内 `8px`；宁可松不可挤。
- 颜色克制：主色只出现在主操作与选中态；正文灰阶三层（primary / regular / secondary）走完。
- 图标用线性档、`16px` 小尺寸；不用大面积色块与插画。

## 别做什么

- 别给卡片加 hover 位移/阴影类戏法——本库无投影，hover 只换 `fill_hover`。
- 别引入第二个强调色；多彩标签收进语义色五档。
- 空状态用 `empty` 组件一行文案，别配大图。
