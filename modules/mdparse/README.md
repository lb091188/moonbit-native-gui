# mdparse — Markdown 语法解析

把 Markdown 源文解析成 AST。只做解析：不含渲染、序列化、HTML 输出、增量解析。

派生自 [mizchi/markdown](https://github.com/mizchi/markdown.mbt) `0.8.3`，保留其解析链路。来源、删改范围与授权见 [`NOTICE.md`](NOTICE.md) 与 [`LICENSE`](LICENSE)。

## 用法

作为模块依赖：

```text
import {
  "NoahLiu/native-gui-mdparse@0.1.0",
}
```

```moonbit
///|
fn example() -> Unit {
  let res = @mdparse.parse("# 标题\n\n段落含 **粗体** 与 [链接](https://example.com)。\n")
  for block in res.document.children {
    println(block)
  }
  // 引用式链接的文档级定义：label → url
  for def in res.definitions {
    println("\{def.label} => \{def.url}")
  }
}
```

`parse(source, wikilinks? = false)` 返回 `ParseResult`：

| 字段 | 类型 | 含义 |
| --- | --- | --- |
| `document` | `Document` | 文档根，`children : Array[Block]` |
| `definitions` | `Array[LinkDefinition]` | 引用式链接/图片的文档级定义（`label`、`url`） |

## 支持的语法

- 块级：ATX/Setext 标题、围栏代码（info 串）、缩进代码、引用、GFM 提示块、有序/无序列表（含 start）、任务列表、表格（列对齐）、定义列表、分隔线、脚注定义、数学块、HTML 块、`:::name` 指令块、frontmatter
- 行内：粗体、斜体、删除线、行内代码、链接、引用式链接、自动链接、图片、引用式图片、脚注引用、软/硬换行、行内 HTML、行内数学、`[[WikiLink]]`、行内指令

## AST

`Block` 与 `Inline` 两个枚举是解析结果的全部形态；渲染、遍历、测试都按它们模式匹配。字段以 `types.mbt` 为准。

## 平台

`supported_targets = "native"`。纯 MoonBit，无第三方依赖（只用 `moonbitlang/core`）。
