# assets/brand — 品牌资产

| 文件 | 是什么 |
| --- | --- |
| `app-icon.svg` | 应用图标 master（1024 视口，矢量，全档缩放源） |
| `app-icon-mono.svg` | 单色剪影（托盘 / Android themed icon 预留；整体替换 fill 即染色） |
| `LICENSE` | 资产许可：CC BY 4.0（仓库代码仍为根 LICENSE 的 MIT） |

色板、构图与版权口径的定案见 [experience/brand.md](../../experience/brand.md)。

## 色板速查

| 角色 | 色值 |
| --- | --- |
| 品牌主色（启光蓝） | `#2E33C9`（标题栏 `#2428A5`） |
| 强调色（月兔玫红） | `#C73E94`（耳窝 `#F1D3E6`） |
| 夜蓝 | `#14213D`（五官同色） |
| 浅底 | `#F5F7FA` |
| 控制点 | `#E8F0FB` |

## 再生成与导出

- 各平台 PNG 由 `scripts/gen_brand_icons.py` 从 `app-icon.svg` 生成：macOS iconset 十档（icns 由 `mng package` 的 sips + iconutil 合成）、Windows ICO 源、Linux PNG、favicon。
- 移动端（Android adaptive / 鸿蒙分层 / iOS 满版）随移动端批次加导出档，master 不变。

## 使用注意

- 16px 档直接缩 master；图标自带浅底圆角方，深浅界面都稳。
- 单色场景（终端、托盘深色菜单栏）用 `app-icon-mono.svg`。
- 对外署名口径：**造型原创，配色致敬 MoonBit 月兔**；不用于暗示 MoonBit 官方背书。
