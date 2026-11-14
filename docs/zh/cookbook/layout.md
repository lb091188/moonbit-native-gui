# 布局场景

import 清单与两条写入路径见[场景总览](index.md#公共前提)。

## 内容对齐

| 容器 | 主轴 | 横向居中 | 纵向居中 |
|---|---|---|---|
| `col`（主轴纵向） | 纵 | `align_items`（命名参数） | `justify_content`（走 `class` 或 `view`） |
| `row` / `view(direction=Row)`（主轴横向） | 横 | `justify_content`（走 `class` 或 `view`） | `align_items`（命名参数） |

双向居中，`view` 写法（`examples/hello` 同款）：

```moonbit
@ui.view(
  [@ui.text("Hello, MoonBit!", class=[@style.text_heading])],
  grow=1.0,                                     // 撑满父级剩余空间
  align_items=@yoga.AlignItems::Center,         // 交叉轴（横向）居中
  justify_content=@yoga.JustifyContent::Center, // 主轴（纵向）居中
)
```

`col` 写法——命名参数只收 `align_items`，纵向主轴走 `class` 通道：

```moonbit
@ui.col(
  [@ui.text("Hello, MoonBit!", class=[@style.text_heading])],
  grow=1.0,
  align_items=@yoga.AlignItems::Center,
  class=[@style.style(justify_content=@yoga.JustifyContent::Center)],
)
```

只横向居中：去掉 `justify_content`。只纵向居中：只保留 `justify_content`，子项交叉轴缺省拉伸铺满宽度。

注意：

- 容器须撑满父级（`grow=1.0` 或显式 `height`），否则无自由空间可分配。
- 轴随容器方向变：`align_items=Center` 在 `view`（缺省方向 Column）是横向居中，在 `row` 是纵向居中。
- `@ui.text(align=...)` 控制折行文本内部对齐；文本块在容器中居中用上表属性。
- 枚举写完整形态 `@yoga.AlignItems::Center`；短形态 `@yoga.Center` 等价。

## 顶栏 + 自适应内容 + 底栏（三段式）

顶栏与底栏按内容定高，中段吃掉剩余高度、内部滚动。外层 `col` 三段；中段包 `col(grow=1.0)`，滚动视口 `height=0.0` 交给父层分配。

```moonbit
let body = @ui.ScrollState::new()
@ui.col(
  [
    @ui.row(
      [@ui.text("设置", class=[@style.text_title])],
      padding=12.0,
    ),
    @ui.col(
      [
        @ui.scroll_view(
          [
            @ui.text("第 1 段很长的内容……"),
            @ui.text("第 2 段很长的内容……"),
            // ……
          ],
          body,
          height=0.0,  // 视口高交给父层
        ),
      ],
      grow=1.0,
      min_height=0.0,
    ),
    @ui.row(
      [
        @ui.button("取消"),
        @ui.button("保存", variant=@ui.Solid),
      ],
      column_gap=8.0,
      padding=12.0,
      class=[@style.style(justify_content=@yoga.JustifyContent::FlexEnd)],
    ),
  ],
)
```

注意：

- 中段不写 `grow=1.0`，三段全按内容高排，底栏不贴窗底。
- 中段不写 `min_height=0.0`，内容一长被 min:auto 顶回自然高，滚动视口拿不到固定视口。滚动视口自身已补这条，外面自包的层要手写；见[布局样式](../guide/layout.md)「必须知道的几个口径」。

## 侧栏与分栏：固定宽 / 弹性 / 等分 / 可拖

固定宽 `width=`、弹性 `grow=1.0`、等分 `width_percent=50.0`、可拖 `split`。

```moonbit
@ui.row(
  [
    @ui.col([@ui.text("导航"), @ui.text("设置")], width=180.0),
    @ui.col([@ui.text("主内容区")], grow=1.0),
  ],
)
```

```moonbit
@ui.row(
  [
    @ui.col([@ui.text("左半")], width_percent=50.0),
    @ui.col([@ui.text("右半")], width_percent=50.0),
  ],
)
```

```moonbit
@ui.split(
  @ui.col([@ui.text("文件树")]),
  @ui.col([@ui.text("编辑区")]),
  ratio=0.3,
  min_first=160.0,
)
```

注意：`row` 的 `align_items` 缺省 Stretch，与 `col` 一致，行内子项自动等高；要子项按内容高、整行纵向居中显式写 `Center`。

## 内容超高滚动

`scroll_view` 是滚动容器，`ScrollState` 持有偏移状态（必传），`height` 是视口高；纵向滚动缺省，横向 `hscroll=true`。

```moonbit
let st = @ui.ScrollState::new()
@ui.scroll_view(
  [
    @ui.text("第 1 行"),
    @ui.text("第 2 行"),
    // …很多行…
  ],
  st,
  height=300.0,
)
```

```moonbit
@ui.scroll_view(
  [@ui.text("一条非常非常长、不希望被折行的内容")],
  @ui.ScrollState::new(),
  height=40.0,
  hscroll=true,
)
```

注意：

- 视口高要有出处：显式 `height=`，或放进 `grow=1.0` 的层给 `height=0.0`。
- `code_view` 自带横向滚动，不必外包 `scroll_view`。
- 滚动条悬停满色、不占布局宽；`st.at_bottom()` 判是否滚到底。

## 一排标签超宽自动换行

`row` 加 `flex_wrap`；行间距 `row_gap`、列间距 `column_gap`。

```moonbit
@ui.row(
  [
    @ui.tag_of_type("MoonBit", @ui.Primary),
    @ui.tag_of_type("跨平台", @ui.Success),
    @ui.tag_of_type("原生窗口", @ui.Info),
    @ui.tag_of_type("自绘", @ui.Warning),
    @ui.tag_of_type("深浅主题", @ui.Danger),
    // …标签多了自然折行
  ],
  column_gap=8.0,
  class=[@style.style(flex_wrap=@yoga.FlexWrap::Wrap, row_gap=8.0)],
)
```

注意：折行不生效时查两点——容器是 `row`；外层没有把最小尺寸钉在内容尺寸上（必要时该层写 `min_width=0.0, min_height=0.0`）。见[布局样式](../guide/layout.md) min:auto 口径。

## 底部按钮右对齐

`row` 主轴横向，主轴对齐走 `justify_content`，`FlexEnd` 即靠右；`row` 命名参数不收它，走 `class` 通道。

```moonbit
@ui.row(
  [
    @ui.button("取消"),
    @ui.button("确定", variant=@ui.Solid),
  ],
  column_gap=8.0,
  class=[@style.style(justify_content=@yoga.JustifyContent::FlexEnd)],
)
```

其余档位：`FlexStart`（缺省）、`Center`、`SpaceBetween`、`SpaceAround`、`SpaceEvenly`。`col` 把同一套用在纵向（见[内容对齐](#内容对齐)表）。
