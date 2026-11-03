# 常见场景教程

按「我想做 X」检索的场景手册：布局、交互、样式主题、系统能力四域 19 个场景，每场景给说明、可抄代码与注意事项。代码片段对照当前 API 与 `examples/showcase` 源码核对。工程从零起步见[五分钟上手](tutorial.md)。

## 公共前提

`moon.pkg` 的 import 用这一份（各场景按需引用）：

```
import {
  "NoahLiu/yoga-mbt/src" @yoga,
  "NoahLiu/native-gui/base" @base,
  "NoahLiu/native-gui/shell" @shell,
  "NoahLiu/native-gui/widget" @widget,
  "NoahLiu/native-gui/ui",
  "NoahLiu/native-gui/style" @style,
  "NoahLiu/native-gui/sys" @sys,
  "NoahLiu/native-gui/theme" @theme,
}
```

- 布局类场景给出节点树，替换 `mount_window` 的第一个参数；交互类场景是完整程序。
- 两条写入路径：构造器命名参数（`padding=` / `width=` …）与 `class=[@style.style(...)]` 样式块；`class` 数组尾赢，同名属性后者生效。见[布局样式](layout.md)。
- flex 容器两根轴：`col` 主轴纵向、`row` 主轴横向；`justify_content` 管主轴、`align_items` 管交叉轴。

---

## 一、布局

### 1.1 内容对齐

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

### 1.2 顶栏 + 自适应内容 + 底栏（三段式）

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
- 中段不写 `min_height=0.0`，内容一长被 min:auto 顶回自然高，滚动视口拿不到固定视口。滚动视口自身已补这条，外面自包的层要手写；见[布局样式](layout.md)「必须知道的几个口径」。

### 1.3 左侧栏 + 弹性主区

固定宽 `width=`、弹性 `grow=1.0`、等分 `width_percent=50.0`、可拖 `split`。

```moonbit
@ui.row(
  [
    @ui.col([@ui.text("导航"), @ui.text("设置")], width=180.0),
    @ui.col([@ui.text("主内容区")], grow=1.0),
  ],
  align_items=@yoga.AlignItems::Stretch,
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

注意：`row` 的 `align_items` 缺省 Center（`col` 缺省 Stretch）；等高两栏显式写 `Stretch`。

### 1.4 内容超高滚动

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

### 1.5 一排标签超宽自动换行

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

注意：折行不生效时查两点——容器是 `row`；外层没有把最小尺寸钉在内容尺寸上（必要时该层写 `min_width=0.0, min_height=0.0`）。见[布局样式](layout.md) min:auto 口径。

### 1.6 底部按钮右对齐

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

其余档位：`FlexStart`（缺省）、`Center`、`SpaceBetween`、`SpaceAround`、`SpaceEvenly`。`col` 把同一套用在纵向（见 §1.1 表）。

---

## 二、交互

### 2.1 输入框取值与回车提交

输入框的值住 `Store[String]`；`on_change` 每次变更回调，`on_enter` 回车回调。多行输入 `textarea` 同构。

```moonbit
fn main {
  let name : @base.Store[String] = @base.Store::new("")
  let greeting = @base.Signal::computed(fn() {
    let n = name.get()
    if n == "" { "请输入名字" } else { "你好，\{n}！" }
  })
  let app = match @ui.mount_window(
    [
      @ui.input(name, placeholder="你的名字", clearable=true,
        on_enter=fn() {
          println("提交：\{name.get()}")
        }),
      @ui.text_dyn(greeting),
    ],
    title="输入框",
    width=360, height=160,
  ) {
    None => return
    Some(a) => a
  }
  app.run()
}
```

注意：

- 不在 `on_change` 里把收到的值 `set` 回同一 store。
- 回显用 `text_dyn`（吃 `Signal`）或 `bind_label`（吃 `Store`）。
- Ctrl/Cmd+C/X/V 默认接系统剪贴板，右键有编辑菜单。

### 2.2 列表增删项

列表数据住 `ListStore`，渲染走 `for_list`，keyed 差分只动变化的行。

```moonbit
fn main {
  let todos : @base.ListStore[String] = @base.ListStore::new(["买牛奶", "写周报"])
  let draft : @base.Store[String] = @base.Store::new("")
  let app = match @ui.mount_window(
    [
      @ui.row(
        [
          @ui.input(draft, placeholder="新条目", width=200.0),
          @ui.button("添加", variant=@ui.Solid, on_click=fn() {
            let s = draft.get()
            if s != "" {
              todos.push(s)
              draft.set("")
            }
          }),
        ],
        column_gap=8.0,
      ),
      @ui.for_list(
        todos,
        build=fn(item, _i) {
          @ui.row(
            [
              @ui.text(item),
              @ui.button("删", variant=@ui.Text, on_click=fn() {
                todos.remove(fn(x) { x == item })
              }),
            ],
            column_gap=8.0,
          )
        },
        key~=fn(item) { item },
      ),
    ],
    title="待办",
    width=360, height=320,
  ) {
    None => return
    Some(a) => a
  }
  app.run()
}
```

注意：

- `key~` 相同视为同一行；要支持重复条目，给每条配唯一 id，或用按位置的 `for_list_indexed`。
- 行内会变的字段各自做成 `Store`；见[声明式与响应式](declarative.md) §5。
- 列表长了外包 §1.4 的 `scroll_view`；万行级用 `virt_list` / `table_v`。

### 2.3 确认弹窗

`dialog` 的可见性由 `Store[Bool]` 驱动；确认、取消、✕、Esc 四个出口都先收起再回调。对话框挂树里任意位置，呈现走浮层图层。

```moonbit
fn main {
  let ask_clear : @base.Store[Bool] = @base.Store::new(false)
  let items : @base.ListStore[String] = @base.ListStore::new(["a", "b"])
  let app = match @ui.mount_window(
    [
      @ui.button("清空列表", variant=@ui.Danger, on_click=fn() {
        ask_clear.set(true)
      }),
      @ui.dialog(
        ask_clear,
        "清空列表？",
        [@ui.text("删除后不可恢复。")],
        confirm_text="清空",
        on_confirm=fn() {
          items.splice(0, items.length(), [])
        },
      ),
    ],
    title="确认弹窗",
    width=360, height=160,
  ) {
    None => return
    Some(a) => a
  }
  app.run()
}
```

注意：`on_confirm` 里不必再 `ask_clear.set(false)`；「点遮罩关闭」由 `close_on_mask` 控制（缺省 false）。

### 2.4 轻提示

`toast_layer` 建界面时调用一次，得推送函数；之后任意回调里推一条，2.6 秒自动消失，多条堆叠。

```moonbit
fn main {
  let toast = @ui.toast_layer(duration_ms=2600)
  let app = match @ui.mount_window(
    [
      @ui.button("保存", variant=@ui.Solid, on_click=fn() {
        toast("已保存", @ui.Success)
      }),
    ],
    title="轻提示",
    width=320, height=140,
  ) {
    None => return
    Some(a) => a
  }
  app.run()
}
```

语义色：`@ui.Primary` / `@ui.Success` / `@ui.Warning` / `@ui.Danger` / `@ui.Info`。需要用户点确认的场景用 §2.3 的对话框。

### 2.5 定时刷新

`@shell.set_timeout(毫秒, 回调)` 是一次性定时器，循环靠回调尾自排；启动点放 `mount_window` 的 `handle` 回调。

```moonbit
fn main {
  let ticks : @base.Store[Int] = @base.Store::new(0)
  let app = match @ui.mount_window(
    [@ui.bind_label(ticks, fn(n : Int) { "已运行 \{n} 拍" })],
    title="定时刷新",
    width=320, height=140,
    handle=fn(_app : @widget.WindowHost) {
      fn pump() {
        ticks.update(fn(n) { n + 1 })
        let _ = @shell.set_timeout(500, pump)
      }
      pump()
    },
  ) {
    None => return
    Some(a) => a
  }
  app.run()
}
```

注意：

- 挂载前（构造期）调用 `set_timeout` 不生效；启动点用 `handle` / `Node::on_mount` / 事件回调，见[声明式与响应式](declarative.md) §2。
- 停止循环：加 `Store[Bool]` 开关，`pump` 开头检查、不满足就不自排。

### 2.6 按条件显隐

`when_store_bool` 按布尔 store 切显隐，节点不销毁、状态不丢；两支常驻、来回切用 `when_else_store`。

```moonbit
let show : @base.Store[Bool] = @base.Store::new(false)
@ui.col(
  [
    @ui.checkbox("显示详情", show),
    @ui.when_store_bool(show, @ui.text("这里是详情内容……")),
  ],
  row_gap=8.0,
)
```

```moonbit
@ui.when_else_store(is_login, @ui.text("欢迎回来"), @ui.text("请先登录"))
```

注意：切换不重新初始化节点，输入框内容保留；要全新状态自己清 store 或改用 `bind_node`。`Signal` 版与泛型版见[组件速查](components.md)「响应式控制」。

### 2.7 表单项与错误提示

`form_item` 是「标签 + 控件 + 常驻错误行」，错误行高度固定预留；错误文案住 `Store[String]`，空串即无错误。

```moonbit
let email : @base.Store[String] = @base.Store::new("")
let nick : @base.Store[String] = @base.Store::new("")
let email_err : @base.Store[String] = @base.Store::new("")
@ui.col(
  [
    @ui.form(
      "注册",
      [
        @ui.form_item("邮箱", @ui.input(email, placeholder="you@example.com"),
          error=email_err),
        @ui.form_item("昵称", @ui.input(nick, placeholder="显示名")),
      ],
    ),
    @ui.row(
      [@ui.button("提交", variant=@ui.Solid, on_click=fn() {
        let v = email.get()
        if v == "" {
          email_err.set("邮箱不能为空")
        } else if !v.contains("@") {
          email_err.set("邮箱格式不对")
        } else {
          email_err.set("")
          toast("提交成功", @ui.Success)   // toast 见 §2.4
        }
      })],
      class=[@style.style(justify_content=@yoga.JustifyContent::FlexEnd)],
    ),
  ],
  row_gap=12.0,
)
```

注意：校验时机自定——提交回调或 `input` 的 `on_change`。

### 2.8 打开第二个窗口

`WindowHost::open_window(宽, 高, 标题)` 返回子窗 `WindowHost`，用它的 `mount` 挂内容；`app` 在 `mount_window` 返回后才有，经 `Ref` 递进回调。

```moonbit
fn main {
  let host : Ref[@widget.WindowHost?] = Ref(None)
  let app = match @ui.mount_window(
    [
      @ui.button("打开副窗", on_click=fn() {
        match host.val {
          Some(a) =>
            match a.open_window(320, 220, "副窗") {
              Some(child) =>
                child.mount(
                  [
                    @ui.col(
                      [@ui.text("我是副窗", class=[@style.text_title])],
                      padding=16.0,
                    ),
                  ],
                )
              None => ()
            }
          None => ()
        }
      }),
    ],
    title="主窗",
    width=360, height=200,
  ) {
    None => return
    Some(a) => a
  }
  host.val = Some(app)
  app.run()
}
```

注意：`open_window` 宽高是 `Int32`；无窗口后端返回 `None`。多窗口门面见[组件速查](components.md)「声明式挂载」。

---

## 三、样式与主题

### 3.1 换主色 / 跟随系统深浅

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

### 3.2 给控件交互样式

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

---

## 四、系统能力

系统能力族统一 `Result` 语义，不支持的环境返回错误值；三平台支持矩阵见[系统能力总览](system-capabilities.md)。

### 4.1 打开链接 / 定位文件

`@sys.open_url` 开 URL；`@sys.open_file` 把文件交系统默认程序；`@shell.reveal_in_file_manager` 在文件管理器中定位并选中。

```moonbit
@ui.col(
  [
    @ui.link("打开文档站", fn() {
      let _ = @sys.open_url("https://moonbit-native-gui.pages.dev")
    }),
    @ui.button("打开图片", on_click=fn() {
      let _ = @sys.open_file("/home/me/photo.png")
    }),
    @ui.button("在文件管理器中显示", on_click=fn() {
      match @shell.reveal_in_file_manager("/home/me/photo.png") {
        Ok(_) => ()
        Err(e) => println("定位失败：\{e}")
      }
    }),
  ],
  row_gap=8.0,
)
```

### 4.2 复制到剪贴板

`clipboard_set_text` 直写系统剪贴板，返回 `Bool`。

```moonbit
@ui.button("复制安装命令", on_click=fn() {
  if @sys.clipboard_set_text("moon add NoahLiu/native-gui") {
    toast("已复制", @ui.Success)   // toast 见 §2.4
  }
})
```

读用 `clipboard_get_text() -> String?`。输入框内部已默认接系统剪贴板。

### 4.3 桌面通知

`@shell.notify_send(应用名, 标题, 正文, ...)`，先 `notify_supported()` 探测。Linux 走 D-Bus、Windows 走托盘气泡、macOS 走 UN 中心（`notify_backend_name()` 按平台报真名）。

常用可选参：`icon?`（Linux 的主题图标名）、`timeout_ms?`（Linux 时长，Win32 自 Vista 起由系统定）、`replaces_id?`（非 0 覆盖同 id 那张）、`progress?`（0..100，Linux 画进度条、Win32 拼进正文）、`kind?`（0 信息 / 1 警告 / 2 错误）、`urgent?`（缺省 `true`，见下）。

```moonbit
@ui.button("发通知", on_click=fn() {
  if @shell.notify_supported() {
    match @shell.notify_send("我的应用", "构建完成", "3 个目标已产出") {
      Ok(_id) => toast("已发送", @ui.Info)
      Err(e) => println("通知失败：\{e}")
    }
  } else {
    println("当前环境不支持通知")
  }
})
```

`urgent?` 是**打扰档**，只有 macOS 吃：`true` 走时间敏感档，应用在前台忙时也直接出横幅；`false` 退普通档，前台忙时静默、只进通知中心。用户在系统设置里关掉「时间敏感」授权后，即便传 `true` 同样回到静默。Linux / Windows 收下忽略——Linux 的 freedesktop urgency hint 不做映射（`critical` 是常驻不消失的语义，与这一档不是一回事）。

注意：在事件回调里发。macOS 桌面横幅要求 `.app` bundle 形态运行，首次使用请求系统授权；见[体验文档](experience.md)。

---

## 场景检索表

| 我想… | 关键 API | 本页章节 |
|---|---|---|
| 内容居中（横/纵/双向） | `align_items` / `justify_content` | §1.1 |
| 顶栏 + 内容 + 底栏 | `col` + `grow` + `scroll_view` | §1.2 |
| 侧栏 + 主区 / 等分 / 可拖分栏 | `grow` / `width_percent` / `split` | §1.3 |
| 内容滚动（纵/横） | `scroll_view` + `ScrollState` | §1.4 |
| 标签超宽换行 | `flex_wrap=@yoga.FlexWrap::Wrap` | §1.5 |
| 按钮靠右 | `justify_content=FlexEnd`（class） | §1.6 |
| 输入框取值 / 回车提交 | `input` + `Store[String]` + `on_enter` | §2.1 |
| 列表增删 | `ListStore` + `for_list` | §2.2 |
| 确认弹窗 | `dialog` + `Store[Bool]` | §2.3 |
| 操作反馈轻提示 | `toast_layer` | §2.4 |
| 定时刷新 | `@shell.set_timeout` 回调尾自排 | §2.5 |
| 按条件显隐 | `when_store_bool` / `when_else_store` | §2.6 |
| 表单校验 | `form` + `form_item(error=)` | §2.7 |
| 开第二个窗口 | `WindowHost::open_window` + `mount` | §2.8 |
| 换主色 / 跟随深浅 | `theme_apply` / `follow_system_theme` | §3.1 |
| 控件 hover 定制 | `class` + `hover=` + `transition_ms` | §3.2 |
| 打开链接 / 定位文件 | `@sys.open_url` / `@shell.reveal_in_file_manager` | §4.1 |
| 复制到剪贴板 | `@sys.clipboard_set_text` | §4.2 |
| 桌面通知 | `@shell.notify_send` | §4.3 |
| 画控件拼不出的内容 / 自绘区接键鼠（画板、节点编辑器） | `node_of_new` + `on_draw` / `on_pointer` / `on_key` | [画布与自绘](canvas.md) |

## 下一步

- 控件签名：[组件速查](components.md)；状态绑定：[声明式与响应式](declarative.md)；布局字段全集：[布局样式](layout.md)。
- 场景组合的完整程序：`cd examples/showcase && moon run .`，每页源码在 `examples/showcase/pages/*.mbt`。
- 从零起步：[五分钟上手](tutorial.md)。
