# NOTICE — 来源、修改与授权

本模块是 [mizchi/markdown](https://github.com/mizchi/markdown.mbt) 的派生作品（fork），**只保留语法解析链路**。

- 上游版本：`mizchi/markdown@0.8.3`
- 上游许可：MIT（Copyright (c) 2024 mizchi）
- 本模块许可：MIT（见同目录 [`LICENSE`](LICENSE)），保留上游版权声明，另记本仓库的修改
- 上游仓库：https://github.com/mizchi/markdown.mbt
- 本仓库：https://github.com/lb091188/moonbit-native-gui

## 保留了哪些文件

`src/` 下全部为上游代码的派生副本，文件名为上游原名：

```
attributes.mbt  entity.mbt  entity_data.mbt  unicode.mbt  plugin.mbt
scanner.mbt  scanner_search.mbt  inline_marker_search.mbt
block_parser.mbt  block_parser_code.mbt  block_parser_directive.mbt
block_parser_frontmatter.mbt  block_parser_heading.mbt  block_parser_html.mbt
block_parser_link_def.mbt  block_parser_list.mbt  block_parser_math.mbt
block_parser_table.mbt
inline_parser.mbt  inline_parser_emphasis.mbt  inline_parser_link.mbt
types.mbt
```

## 删除了什么

上游同包内与解析无关的部分一律未纳入：

- 渲染：`renderer*.mbt`（HTML renderer、literal renderer、autolink、tagfilter）
- 序列化：`serializer*.mbt`
- 增量解析：`incremental.mbt`
- 基准：`bench*.mbt`
- 前端资产与 CLI：`cmd/`、`frontend/`、`playground/`、`js/`、`wasm/`、`e2e/`
- 模块级依赖：`moonbitlang/async`、`moonbitlang/parser`、`moonbitlang/x`、`mizchi/syntree`、`mizchi/moomaid`

## 本仓库做了哪些修改

1. **删除未使用的渲染辅助函数**：`inline_parser.mbt` 的 `strip_code_span_padding`、`is_code_span_pad`、`normalize_code_span`（只被渲染链路调用）。
2. **行尾扫描改标量实现**：`scanner_search.mbt` 的 `find_line_end` 去掉 `#cfg(target=...)` 分派与 `@v128` SIMD 分支，统一走 `find_line_end_scalar`；同步移除 `moonbitlang/core/v128` 依赖。
3. **包配置**：`moon.pkg` 只保留 `moonbitlang/core/debug` 依赖，`warnings = "-79"` 关闭 `derive(Eq, Debug)` 的「隐式方法提升」提示（不依赖该提升）。
4. **目标平台**：`supported_targets = "native"`（上游为 `js+wasm+wasm-gc+native`）。

除上述四点外，`src/` 内容与上游对应文件一致。

## 分发义务

本模块随本仓库源码分发，`LICENSE` 与本文件必须同批保留。对外发布编译产物时，按仓库根 `THIRD-PARTY-NOTICES.md` 的清单把本模块 `LICENSE` 一并收进发布包的 `licenses/` 目录。
