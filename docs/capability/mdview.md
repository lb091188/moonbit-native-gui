# Markdown view (@mdview)

`moon.pkg`:

```
"NoahLiu/native-gui/mdview" @mdview,
```

One entry point: give it Markdown text, get a mountable node.

```moonbit
@mdview.markdown_view(
  "# Title\n\nBody **bold** and a [link](https://example.com)",
  on_link=fn(u : String) {
    let _ = @sys.open_url(u)   // hand the link to the default program
  },
)
```

## Supported syntax

- Headings, paragraphs, **bold**, *italic*, ~~strikethrough~~, inline code
- Links: `[text](url)`, autolinks, reference links; clicks go through the `on_link` callback — with no `on_link`, clicks do nothing
- Nested lists, task lists (real checkboxes)
- Blockquotes, thematic breaks
- Fenced code blocks, tables (column alignment)
- Footnotes (superscript in text + definitions at the end)
- Emoji (measured in UTF-16 units, so mixed layouts don't drift)

## Selection & copy

`selectable=true` enables paragraph-level selection: highlight boundaries follow the real layout, selection spans multiple lines, `Ctrl/Cmd+C` copies the original text (soft wraps add no line breaks). Clicking a link still opens it; only clicks on empty space start a selection.

## Events & handle

- `on_link`: link click callback, receives the url string.
- `handle`: the internal widget handle for operations the framework doesn't expose.
