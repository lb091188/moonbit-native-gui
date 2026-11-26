# 玻璃拟态 Glassmorphism

深色基底上浮着半透明磨砂面板——`@ui.glass` 是库内一等能力（糊掉它下方已画的内容，固定一档）。轻盈、层叠、克制的光感。适合媒体、创意工具、启动器类应用。

## 主题 JSON

存成 `theme.json`，`mng.toml` 配 `theme = "theme.json"`，存盘即热重载；边框色用带 alpha 的 hex：

```json
{
  "primary": "#8fb3ff",
  "primary_light": "#26314a",
  "primary_hover": "#aac6ff",
  "success": "#5fd4a0", "success_light": "#1d3a2e",
  "warning": "#e8c268", "warning_light": "#3d3521",
  "danger": "#ff7a7a", "danger_light": "#3f2323", "danger_hover": "#ff9494",
  "info": "#6ec3ff", "info_light": "#1c3242",
  "text_primary": "#eef2f9",
  "text_regular": "#b8c4d6",
  "text_secondary": "#77879c",
  "border": "#3a4658",
  "fill_hover": "#252e3d",
  "fill_zebra": "#1c2430",
  "bg_page": "#10141c",
  "bg_panel": "#1a212e"
}
```

## 口径

- 玻璃面板三层件：`@ui.glass` 容器 + 1px 亮描边（`border_color` 亮于底两档）+ `8px` 圆角；描边是玻璃的「厚度」，不能省。
- **glass 糊的是它下方已画的内容**，不是窗口背后的桌面——深底上先铺彩色内容块（图表、色卡、图片），玻璃面板压上去才有磨砂观感；空深底上只放一块玻璃等于半透明灰板。
- 层级用透明度阶：底层 `bg_page`、内容层普通面板、顶层玻璃浮层；同屏玻璃面板最多一到两块。
- 文字在玻璃上必须用 `text_primary` 全亮档，正文灰阶往下压一档即 `text_regular`，不再往下（透明底上对比度容易失守）。
- 语义色统一用本主题的浅调亮色（success 青、warning 琥珀、danger 珊瑚），深底上饱和度别拉满。

## 别做什么

- 别把整页做成玻璃——玻璃是「浮层语言」，铺满就失去层叠感。
- 别在玻璃上再叠玻璃；两层模糊互相糊。
- 别用纯黑底（#000）——玻璃需要底色有蓝灰倾向才透得干净。
