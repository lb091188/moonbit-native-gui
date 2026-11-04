# 样式与主题场景

import 清单见[场景总览](index.md#公共前提)。

## 换主色与跟随系统深浅

控件色值读 theme token，换主题即时生效。手动换主色 `theme_apply`；跟随系统深浅与强调色 `follow_system_theme`。

```moonbit
@ui.row(
  [
    @ui.button("紫色", on_click=fn() {
      @theme.theme_apply(@theme.theme_from_accent("#7c4dff"))
    }),
    @ui.button("绿色", on_click=fn() {
      @theme.theme_apply(@theme.theme_from_accent("#2e7d32"))
    }),
  ],
  column_gap=8.0,
)
```

```moonbit
@ui.mount_window(
  [/* … */],
  title="主题",
  handle=fn(a : @widget.WindowHost) {
    let _ = a.follow_system_theme(interval_ms=2000)  // 返回退订函数
  },
)
```

注意：写死的十六进制色不随主题；优先语义档（`SemanticType`、`text_secondary` 等预设），确需固定色再写死。

## 给控件交互样式

`class` 通道叠 `@style.style(...)`；`hover` / `active` / `focus` 三个槽各收一个嵌套 `Style`，状态进入时合并生效；`transition_ms` 过渡颜色、边框宽、圆角、字号、行高。

```moonbit
@ui.card(
  [@ui.text("悬停我试试")],
  class=[
    @style.style(
      border_radius=8.0,
      transition_ms=150.0,
      hover=@style.style(
        border_color="#7c4dff",
        background_color="#f5f0ff",
        border_radius=12.0,
      ),
    ),
  ],
)
```

注意：

- `class` 数组尾赢：覆盖组件内置样式把自己的块放数组后部。
- 全局圆角、字体走 theme 层开关（`@theme.corners_round_set` 等）。
- 自绘块不消费样式槽，直接读宿主维护的 `hovered` / `focused` 标志：见[自绘与键鼠](../guide/custom-draw.md)。
