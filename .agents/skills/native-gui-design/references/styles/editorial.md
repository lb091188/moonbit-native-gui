# 编辑杂志风 Editorial

纸白底、衬线大标题、强烈的字阶对比、细分割线。内容是主角，界面退成版面。适合阅读器、刊物、作品集、报告类应用。

## 主题 JSON

存成 `theme.json`，`mng.toml` 配 `theme = "theme.json"`，存盘即热重载；字阶覆盖把大标题档拉大制造对比：

```json
{
  "primary": "#b45309",
  "primary_light": "#f5e6d3",
  "primary_hover": "#92400e",
  "success": "#3f6212", "success_light": "#e7efd4",
  "warning": "#a16207", "warning_light": "#f5ecd0",
  "danger": "#b91c1c", "danger_light": "#f6dcdc", "danger_hover": "#991b1b",
  "info": "#1e5f8a", "info_light": "#ddeaf3",
  "text_primary": "#1c1917",
  "text_regular": "#44403c",
  "text_secondary": "#78716c",
  "border": "#d6d3d1",
  "fill_hover": "#f0eeea",
  "fill_zebra": "#f7f5f0",
  "bg_page": "#fffdf8",
  "bg_panel": "#faf8f2",
  "type_scale": [12.0, 13.0, 15.0, 22.0]
}
```

## 口径

- 标题挂衬线候选族：`family="Georgia, Songti SC, STSong, Noto Serif CJK SC, serif"`；正文保持缺省黑体族——衬线进标题、sans 进正文，两族分工不混。
- 字阶对比是骨架：大标题 `22`（type_scale 覆盖后第 3 档）、次级 `15`、正文 `13`、辅助 `12`；每页字阶跨度至少三档。
- 版心与栏：正文列宽收窄（`max_width` 控制在 40 字符上下），两侧留白大；多栏用 `row` + `split`。
- 分隔用 `divider` 细线（不带字档），区块之间一线到底；结构装置（编号、眉标）只在内容真是序列时才用。
- 强调色（赭红）只给：链接、刊名、期号类点睛；正文黑白灰。
- 图片与引文块用 `bg_panel` 微差底 + 不描边，靠留白框住。

## 别做什么

- 别满页都是大字——一页只允许一个大标题档；对比来自克制。
- 别给正文加衬线或行内换族；族切换发生在「标题 vs 正文」这条线上。
- 别用圆角卡片包文章——版面靠留白与细线分块，卡片是产品页的语言。
