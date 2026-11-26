# 中国风 Chinoiserie

宣纸底、墨字、朱砂点睛。留白意境取自书画——疏可走马，密不透风；现代工具的外壳，传统文人的气息。适合文化、茶饮、出版、礼盒类应用。

## 主题 JSON

存成 `theme.json`，`mng.toml` 配 `theme = "theme.json"`，存盘即热重载：

```json
{
  "primary": "#9e2b25",
  "primary_light": "#f5e3e0",
  "primary_hover": "#87231e",
  "success": "#4a7c59", "success_light": "#e3efe7",
  "warning": "#b8860b", "warning_light": "#f7ecd4",
  "danger": "#a61b1b", "danger_light": "#f5dbdb", "danger_hover": "#8f1515",
  "info": "#2e5e8c", "info_light": "#e0eaf4",
  "text_primary": "#2b2b28",
  "text_regular": "#4a4a45",
  "text_secondary": "#8a8a80",
  "border": "#d8d2c4",
  "fill_hover": "#f0ebe0",
  "fill_zebra": "#f5f1e8",
  "bg_page": "#f7f4ec",
  "bg_panel": "#fdfbf5"
}
```

## 口径

- 标题与展示文字挂衬线候选族：`family="Songti SC, STSong, STZhongsong, SimSun, Noto Serif CJK SC, serif"`——按 CSS 族列表语义取第一个可用者，全缺回落 serif；正文保持缺省黑体族保证小字清晰。
- 留白大：页面 `padding: 24px` 起步、区块间 `24px`、标题前后各留一档；**宁疏勿密**。
- 朱砂只做点睛：主按钮、选中态、一枚印章式小方块（`tag` 实底白字，`6px` 圆角）；面积不超过界面一成。
- 对称与轴线：详情类页面左右对称布局，标题居中；列表类维持左对齐但行距放宽（`row-gap: 12px`）。
- 分隔用 `divider` 居中断线（带字档）替代通栏细线。
- 圆角用基准档小值（4/6），弧要含蓄。

## 别做什么

- 别满屏中国结、云纹类堆砌——意象靠配色与留白传达，不靠装饰图形。
- 别把朱砂大面积铺底；宣纸色面积必须占绝对多数。
- 别在数据密集区用衬线；衬线只进标题与引言。
