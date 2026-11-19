# Markdown 视图（@mdview）

`moon.pkg` 引入：

```
"NoahLiu/native-gui/mdview" @mdview,
```

一个入口，给 Markdown 文本返回可挂节点：

```moonbit
@mdview.markdown_view(
  "# 标题\n\n正文 **加粗** 与 [链接](https://example.com)",
  on_link=fn(u : String) {
    let _ = @sys.open_url(u)   // 链接点击交默认程序打开
  },
)
```

## 支持的语法

- 标题 / 段落 / **粗体** / *斜体* / ~~删除线~~ / 行内代码
- 链接：`[文字](url)`、自动链接、引用式链接；点击经 `on_link` 回调，不给 `on_link` 时点击无动作
- 嵌套列表、任务列表（真复选框）
- 引用、分隔线
- 围栏代码块、表格（列对齐）
- 脚注（正文上标 + 文末定义）
- emoji（区间按 UTF-16 计量，混排不错位）

## 选中复制

`selectable=true` 打开段落级拖选：混排行里高亮边界跟着真实排版走，跨行连选，`Ctrl/Cmd+C` 复制出原文（软折行不插换行）。点在链接字上仍是打开链接，落空才开始选。

## 事件与句柄

- `on_link`：链接点击回调，收 url 字符串。
- `handle`：拿到内部控件句柄，用于框架未暴露的操作。
