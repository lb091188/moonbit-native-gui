# 品牌定案：品牌色与应用图标

2026-11-09 收口。范围：品牌色板、应用图标构图、版权口径、导出矩阵。实测坑与工具细节归 `experience/adaptation.md`，对外使用说明归 `docs/`。

## 品牌色板

| 角色 | 色值 | 用途 |
| --- | --- | --- |
| 品牌主色（启光蓝） | `#2E33C9` | 应用图标窗口、文档站点缀、品牌物料 |
| 品牌强调色（月兔玫红） | `#C73E94` | 图标月兔、插画点缀 |
| 夜蓝 | `#14213D` | 深底插画、单色剪影默认色 |
| 浅底 | `#F5F7FA` | 图标底、浅底插画 |

- 主色色值取自用户另一项目 light-up（mindbase monorepo）的「启光」品牌主色（`frontend/packages/pub/scss/base.scss` 的 `--color-primary`）；仅借色，native-gui 不挂「启光」名。
- 强调色采样自 MoonBit 官网月兔 logo（2026-11-09 实测主色 `#C73E94`、月亮浅蓝 `#C3DEF6`）。
- **品牌色不进控件主题**：`default_theme().primary` 维持 `#2D68C4` 不动。品牌物料与用户默认界面观感是两件事；真要换默认主色属可见行为变化，须随 minor 版本（0.4.0+）并在 changelog 写明。

## 应用图标

- 构图：月兔从应用窗口上沿探出半张脸，双耳越出窗沿；窗口扁平几何、**空内容区**，标题栏 + 三个控制点。
- 造型要点：圆头 + 长椭圆耳 + 圆点眼 + 单弧微笑；窗口是 GUI 通用符号（非显示器），跨桌面/移动端成立。
- 尺寸策略：单 master SVG 缩放全档；16px 仍可辨（兔耳 + 窗口轮廓）。
- 源资产：`assets/brand/app-icon.svg`（master）、`assets/brand/app-icon-mono.svg`（单色剪影，托盘 / Android themed icon 预留，改 fill 即可染色）。

## 版权口径

- 造型原创；配色致敬 MoonBit 官方月兔，不复制其造型元素（月亮底座、`<>` 眼、`01` 符号）。
- 对外口径写「配色致敬 MoonBit 月兔」，不暗示官方背书。
- 项目开源不商用；资产按 `assets/brand/LICENSE`（CC BY 4.0）分发。

## 导出矩阵

| 平台 | 产物 | 生成路径 |
| --- | --- | --- |
| macOS | iconset 十档 → icns | `mng package`（sips + iconutil），源 PNG 由导出脚本出 |
| Windows | ICO | `mng package`，源 PNG 同上 |
| Linux | PNG 多档 | 导出脚本 + `mng package` |
| Web / 文档站 | favicon 16/32/48、apple-touch 180、logo | 导出脚本 |
| 移动端（预留） | Android adaptive 前景/背景分层、鸿蒙分层、iOS 1024 满版 | 移动端批次再加，master 不变 |

导出脚本 `scripts/gen_brand_icons.py`：SVG → PNG 各档（macOS 用 `qlmanage` 渲染，坑与口径见脚本头注释）。
