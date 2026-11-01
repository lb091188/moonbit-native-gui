# 常见场景教程

按「我想做 X」检索的场景手册：布局、交互、样式主题、系统能力四域 19 个场景，每个都是**目标 → 思路 → 代码 → 常见坑**四段。与[五分钟上手](tutorial.md)互补——那边是从零建工程走到第一个窗口的线性路径，这边是跑通之后回头查「这一步怎么写」。代码片段全部对照当前 API 与 `examples/showcase` 真实源码核对，可直接抄进入口文件（`cmd/main/main.mbt`）。

## 公共前提

**工程与 import**。以下场景默认你已经按[五分钟上手](tutorial.md) §2–§3 建好工程、跑通第一个窗口。`moon.pkg` 的 import 用这一份（比上手教程多几行，全带上省得逐场景回来补；多用到的才实际编译进去）：

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

**片段怎么用**。布局类场景给出的是「替换 `mount_window` 第一个参数里的节点树」；交互类场景给出完整可跑的最小程序。节点构造器都返回 `@widget.Node`，按树嵌套即可。

**两个全局约定**，后面反复用到：

- **两条写入路径**：容器构造器的命名参数（`padding=` / `width=` …）与 `class=[@style.style(...)]` 样式块。命名参数是糖、只有一条去向（折进样式槽）；`class` 数组**尾赢**——后一个块的同名属性盖过前一个。见[布局样式](layout.md)。
- **两根轴**：flex 容器有主轴与交叉轴，方向由 `flex_direction` 决定——`col` 主轴是纵向、`row` 主轴是横向。`justify_content` 管**主轴**、`align_items` 管**交叉轴**。分不清轴，居中就会挂错位置，见 §1.1。

---

## 一、布局

### 1.1 让内容居中（横向 / 纵向 / 双向）

**目标**：一段文字在窗口正中间；或者只横向居中、只纵向居中。

**思路**：先问容器是行还是列，再问要居中的是哪根轴。两根轴各有各的属性，写错轴是布局问题里最高频的坑。

| 容器 | 主轴 | 横向居中 | 纵向居中 |
|---|---|---|---|
| `col`（主轴纵向） | 纵 | `align_items`（命名参数） | `justify_content`（走 `class` 或 `view`） |
| `row` / `view(direction=Row)`（主轴横向） | 横 | `justify_content`（走 `class` 或 `view`） | `align_items`（命名参数） |

**代码**。双向居中，`view` 写法——两根轴都是命名参数，最直接（`examples/hello` 同款）：

```moonbit
@ui.view(
  [@ui.text("Hello, MoonBit!", class=[@style.text_heading])],
  grow=1.0,                                     // 撑满窗口剩余空间
  align_items=@yoga.AlignItems::Center,         // 交叉轴（横向）居中
  justify_content=@yoga.JustifyContent::Center, // 主轴（纵向）居中
)
```

同样的效果用 `col` 写——`col` 的命名参数只收 `align_items`（横向），纵向主轴要走 `class` 通道：

```moonbit
@ui.col(
  [@ui.text("Hello, MoonBit!", class=[@style.text_heading])],
  grow=1.0,
  align_items=@yoga.AlignItems::Center,
  class=[@style.style(justify_content=@yoga.JustifyContent::Center)],
)
```

**只横向居中**：上面的代码去掉 `justify_content` 那行（`view` 写法）或去掉 `class`（`col` 写法）。
**只纵向居中**：只保留 `justify_content`，去掉 `align_items`——子项按缺省在交叉轴拉伸铺满宽度，文字垂直居中、左右占满，标题栏式排版常用。

**常见坑**：

- **写了居中却没反应**——九成是容器没撑满。容器只有内容高时，主轴没有自由空间可分，居中无从谈起。给容器 `grow=1.0`（吃满父的剩余空间）或显式 `height`。
- **从 `examples/hello` 抄代码到 `row` 里行为变了**——`hello` 的根容器是 `view`（缺省方向 Column），`align_items=Center` 在那里是横向居中；放进 `row` 就成了纵向居中。轴随容器方向变，属性名不变。
- **`@ui.text(align=...)` 不是这个场景**——那控制的是折行文本**内部**的对齐；「文本块在容器里居中」是容器的事，用本节的 `align_items` / `justify_content`。
- 枚举写完整形态 `@yoga.AlignItems::Center` 最不易错；`@yoga.Center` 这类短形态也能用（`@yoga.Wrap` 见 §1.5）。

### 1.2 顶栏 + 自适应内容 + 底栏（三段式）

**目标**：顶栏标题固定高，底栏按钮条固定高，中间内容区吃掉全部剩余高度、内容多了内部滚动。

**思路**：外层一个 `col` 三个孩子；中段包一层 `col(grow=1.0)` 把剩余高度全拿走，滚动视口放里面、`height=0.0` 表示视口高交给父层分配。

**代码**：

```moonbit
let body = @ui.ScrollState::new()
@ui.col(
  [
    // 顶栏：按内容定高
    @ui.row(
      [@ui.text("设置", class=[@style.text_title])],
      padding=12.0,
    ),
    // 中段：grow 吃掉剩余高，内部滚动
    @ui.col(
      [
        @ui.scroll_view(
          [
            @ui.text("第 1 段很长的内容……"),
            @ui.text("第 2 段很长的内容……"),
            // ……
          ],
          body,
          height=0.0,  // 视口高不由自己定，交给父层
        ),
      ],
      grow=1.0,
      min_height=0.0,  // 不写它，内容一多这层会被顶回「自然高」，底栏被挤出窗口
    ),
    // 底栏：按钮靠右，见 §1.6
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

**常见坑**：

- **中段忘了 `grow=1.0`**——三段全按内容高排，底栏直接顶到内容下面，不贴窗底。
- **中段忘了 `min_height=0.0`**——flex 子项的缺省最小尺寸是内容尺寸（min:auto），内容一长就把这层撑回自然高，滚动视口拿不到固定视口、整窗溢出。滚动视口自身已补这条，外面自己包的这一层要手写。详见[布局样式](layout.md)「必须知道的几个口径」。

### 1.3 左侧栏 + 弹性主区（分栏）

**目标**：左边固定宽的侧栏，右边吃掉剩余宽度；或者两栏等分；或者中间一条可拖的分隔把手。

**思路**：固定宽给 `width=`，弹性给 `grow=1.0`，等分给 `width_percent=50.0`，可拖直接用 `split`。

**代码**。固定侧栏 + 弹性主区：

```moonbit
@ui.row(
  [
    @ui.col([@ui.text("导航"), @ui.text("设置")], width=180.0),
    @ui.col([@ui.text("主内容区")], grow=1.0),
  ],
  align_items=@yoga.AlignItems::Stretch,  // row 的 align_items 缺省 Center；要两栏顶满高改 Stretch
)
```

两栏等分（宽度跟随窗口变化）：

```moonbit
@ui.row(
  [
    @ui.col([@ui.text("左半")], width_percent=50.0),
    @ui.col([@ui.text("右半")], width_percent=50.0),
  ],
)
```

中间可拖的分栏（`ratio` 是首栏占比，可限最小宽）：

```moonbit
@ui.split(
  @ui.col([@ui.text("文件树")]),
  @ui.col([@ui.text("编辑区")]),
  ratio=0.3,
  min_first=160.0,
)
```

**常见坑**：`row` 的 `align_items` **缺省是 Center**（`col` 缺省 Stretch）——两栏内容高度不一致时会看到「各自垂直居中、底边不齐」，想要等高两栏显式写 `align_items=@yoga.AlignItems::Stretch`。

### 1.4 内容超高滚动

**目标**：内容比可视区域长，出纵向滚动条；内容比可视区域宽（代码、表格），出横向滚动条。

**思路**：`scroll_view` 是滚动容器，`ScrollState` 持有偏移状态，必传；`height` 是视口高。纵向滚动是缺省档，横向要显式 `hscroll=true`。

**代码**：

```moonbit
let st = @ui.ScrollState::new()
@ui.scroll_view(
  [
    @ui.text("第 1 行"),
    @ui.text("第 2 行"),
    // …很多行…
  ],
  st,
  height=300.0,  // 视口高；包在 grow 层里时给 0.0，见 §1.2
)
```

横向滚动（内容不可折行时的标准做法）：

```moonbit
@ui.scroll_view(
  [@ui.text("一条非常非常长、不希望被折行的内容")],
  @ui.ScrollState::new(),
  height=40.0,
  hscroll=true,
)
```

**常见坑**：

- **视口高没有着落**——`height` 既不给、父层也不给，视口塌掉滚不动。要么显式 `height=`，要么放进 `grow=1.0` 的层里给 `height=0.0`。
- **代码块不用外包**——`code_view` 自带横向滚动（宽跟随容器），再包一层 `scroll_view` 反而双重滚动条。
- 滚动条是悬停时满色的浮动拇指，不占布局宽度；偏移状态全在 `ScrollState` 里，想读「滚没滚到底」用它（`st.at_bottom()`）。

### 1.5 一排标签超宽自动换行

**目标**：一排标签（或图标、按钮）横向排，容器不够宽时自动折到下一行，窗口缩放时自动 reflow。

**思路**：`row` 容器加 `flex_wrap`。换行的行间距用 `row_gap`，列间距用 `column_gap`。

**代码**（`examples/showcase` 图标网格同款）：

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

**常见坑**：折行没生效时，先确认两件事——容器是 `row`（`flex_wrap` 在行方向容器上折行）；包裹它的各层没有把最小尺寸钉在内容尺寸上（被内容顶住就永远折不动，必要时那层显式 `min_width=0.0, min_height=0.0`）。min:auto 口径详见[布局样式](layout.md)。

### 1.6 底部按钮右对齐

**目标**：对话框、表单底部那排「取消 / 确定」靠右放。

**思路**：`row` 主轴是横向，主轴对齐走 `justify_content`，`FlexEnd` 即靠右。`row` 命名参数不收 `justify_content`，走 `class` 通道。

**代码**：

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

主轴对齐的其余档位同表：`FlexStart`（靠左，缺省）、`Center`（居中）、`SpaceBetween`（两端对齐、中间均分）、`SpaceAround` / `SpaceEvenly`（含边距的均分，后者完全等距）。`col` 容器把同一套用在纵向上（见 §1.1 的轴对照表）。

---

## 二、交互

### 2.1 输入框取值与回车提交

**目标**：一个单行输入框，用户打字时实时回显，回车时取值提交。

**思路**：输入框的值住在 `Store[String]` 里，组件与你的代码读写同一份；`on_change` 每次变更回调，`on_enter` 回车回调。多行输入 `textarea` 同构。

**代码**（完整可跑）：

```moonbit
fn main {
  let name : @base.Store[String] = @base.Store::new("")
  // 派生信号：输入变，回显自动跟着变
  let greeting = @base.Signal::computed(fn() {
    let n = name.get()
    if n == "" { "请输入名字" } else { "你好，\{n}！" }
  })
  let app = match @ui.mount_window(
    [
      @ui.input(name, placeholder="你的名字", clearable=true,
        on_enter=fn() {
          // 回车提交：直接读 store
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

**常见坑**：

- **在 `on_change` 里把值再 `set` 回同一个 store** 会自己触发自己，注意别写回环。
- 回显用 `text_dyn`（吃 `Signal`）或 `bind_label`（吃 `Store`），不要在 `on_change` 里手动改另一个控件的文本——那是命令式写法，框架替你做了。
- Ctrl/Cmd+C/X/V 已默认接系统剪贴板，右键有编辑菜单，不用自己接。

### 2.2 列表增删项

**目标**：一个待办列表：输入新条目点「添加」，每行带「删」按钮。

**思路**：列表数据住 `ListStore`，渲染用 `for_list`——keyed 差分只动变化的行，不整表重建。

**代码**：

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

**常见坑**：

- **`key~` 决定差分**——同 key 视为同一行。用文本内容做 key 时，两条相同文本的条目会互相干扰；要支持重复条目就给每条配唯一 id（`ListStore` 里存带 id 的结构），或改用按位置的 `for_list_indexed`。
- 行内会变的字段（勾选态等）各自做成 `Store`，别靠整行重挂刷新。更多口径见[声明式与响应式](declarative.md) §5。
- 列表长了要滚动：把 `for_list` 放进 §1.4 的 `scroll_view`；上万行的表格用 `virt_list` / `table_v`。

### 2.3 确认弹窗

**目标**：点「清空」先弹确认框，确认才执行。

**思路**：`dialog` 的可见性由一个 `Store[Bool]` 驱动——按钮只管把 store 置真，对话框自己弹出；确认、取消、✕、Esc 四个出口都先自动收起再回调。

**代码**：

```moonbit
fn main {
  let ask_clear : @base.Store[Bool] = @base.Store::new(false)
  let items : @base.ListStore[String] = @base.ListStore::new(["a", "b"])
  let app = match @ui.mount_window(
    [
      @ui.button("清空列表", variant=@ui.Danger, on_click=fn() {
        ask_clear.set(true)
      }),
      // 对话框挂在树里任意位置；呈现走浮层图层，不占布局
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

**常见坑**：不要在 `on_confirm` 里再手动 `ask_clear.set(false)`——四个出口都先收再回调，重复置值无害但多余。要不要「点遮罩关闭」由 `close_on_mask` 控制（缺省 false，模态确认框建议关）。

### 2.4 轻提示（toast）

**目标**：操作成功后顶部弹出一条「已保存」，2 秒多自动消失，不打断操作。

**思路**：`toast_layer` 在建界面时调用**一次**，拿到一个推送函数；之后任何回调里随时推一条。

**代码**：

```moonbit
fn main {
  // 在 mount_window 之前建好这一层
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

第二个参数是语义色：`@ui.Primary` / `@ui.Success` / `@ui.Warning` / `@ui.Danger` / `@ui.Info`。多条提示自动堆叠。需要用户点确认的场景用 §2.3 的对话框，toast 只做单向通知。

### 2.5 定时刷新

**目标**：每 500ms 刷一次界面（时钟、进度、轮询数据都走这条）。

**思路**：`@shell.set_timeout(毫秒, 回调)` 是一次性定时器，循环靠**回调尾自排**。定时器通道在宿主建好后才就位，所以循环的启动点要放在挂载之后——最顺的位置是 `mount_window` 的 `handle` 回调。

**代码**：

```moonbit
fn main {
  let ticks : @base.Store[Int] = @base.Store::new(0)
  let app = match @ui.mount_window(
    [@ui.bind_label(ticks, fn(n : Int) { "已运行 \{n} 拍" })],
    title="定时刷新",
    width=320, height=140,
    handle=fn(_app : @widget.App) {
      fn pump() {
        ticks.update(fn(n) { n + 1 })
        let _ = @shell.set_timeout(500, pump)  // 尾部自排 = 循环
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

**常见坑**：

- **`set_timeout` 写在构造期是空操作**——`main` 里 `mount_window` 之前 timer 通道还没装上，第一拍跑在空通道上。要么放 `handle` / `Node::on_mount`，要么放事件回调里首次启动。这是本库最常见的一类「为什么我的定时器不动」，详见[声明式与响应式](declarative.md) §2 的坑注。
- 循环体要能自己停：加个 `Store[Bool]` 开关，`pump` 开头检查、不满足就不自排。

### 2.6 按条件显隐

**目标**：勾选「显示详情」才出现详情区；或者两块内容二选一切换。

**思路**：`when_store_bool` 按布尔 store 切显隐——节点不销毁、状态不丢。两支常驻、来回切用 `when_else_store`。

**代码**：

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

两支切换：

```moonbit
@ui.when_else_store(is_login, @ui.text("欢迎回来"), @ui.text("请先登录"))
```

**常见坑**：显隐切换**不会**重新初始化节点——切换后里面输入框的内容还在。这是特性（状态不丢），想要「每次出现都是全新状态」就得自己清 store，或者改用 `bind_node` 整棵替换。`when` 家族还有 `Signal` 版与泛型版，见[组件速查](components.md)「响应式控制」。

### 2.7 表单项与错误提示

**目标**：左标签右控件的表单布局，提交时校验，错误文案显示在对应项下方。

**思路**：`form_item` 自带「标签 + 控件 + 常驻错误行」结构，错误行高度固定预留、出不出错都不跳布局；错误文案住一个 `Store[String]`，空串即无错误。

**代码**：

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

**常见坑**：校验时机自己定——示例放在提交回调里；要「输入即校验」就把同样的逻辑挂进 `input` 的 `on_change`。错误行的空间从建起就预留着，不会因为出错把下面内容顶下去。

### 2.8 打开第二个窗口

**目标**：主窗点按钮，弹出一扇独立的副窗。

**思路**：`App::open_window(宽, 高, 标题)` 返回新窗口的 `App`，用它的 `mount` 挂内容。`app` 在 `mount_window` 返回后才存在，而按钮树在它之前构造——用一个 `Ref` 把 app 递进去。

**代码**：

```moonbit
fn main {
  let host : Ref[@widget.App?] = Ref(None)
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

**常见坑**：`open_window` 的宽高是 `Int32`；无窗口后端时返回 `None`，按上面代码 match 掉。多窗口的门面（计数、激活、关闭）见[组件速查](components.md)「声明式挂载」与 `examples/showcase` 的「窗口」页。

---

## 三、样式与主题

### 3.1 换主色 / 跟随系统深浅

**目标**：应用默认跟随系统深浅与主色；想手动换个主色，或显式接管跟随。

**思路**：全部控件的色值读 theme token、换主题即时生效，不需要重建树。手动换主色一行 `theme_apply`；接管跟随用 `App::follow_system_theme`。

**代码**。运行期按钮切换主色：

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

跟随系统深浅与强调色（默认就开的话可跳过；周期轮询系统状态）：

```moonbit
@ui.mount_window(
  [/* … */],
  title="主题",
  handle=fn(a : @widget.App) {
    let _ = a.follow_system_theme(interval_ms=2000)  // 返回退订函数
  },
)
```

**常见坑**：自己的代码里**不要固化色值快照**——用 `@style.style(background_color="...")` 写死十六进制能跑，但换主题后它不跟；优先用语义档（`tag_of_type` 的 `SemanticType`、`text_secondary` 等 class 预设），确需自定义色再写死。

### 3.2 给控件定制样式（hover / active / focus）

**目标**：某个卡片悬停时描边变色、圆角更大，带过渡；只影响这一个控件。

**思路**：`class` 通道叠一个 `@style.style(...)` 块；`hover` / `active` / `focus` 三个槽各收一个嵌套 `Style`，状态进入时合并生效；`transition_ms` 让可插值的属性（颜色、边框宽、圆角、字号、行高）平滑过渡。

**代码**：

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

**常见坑**：

- `class` 是数组、**尾赢**——想覆盖组件内置样式，把你的块放在数组后面；放前面会被内置块盖掉。
- `transition_ms` 只作用于可插值的属性，其余属性状态切换时瞬变。
- 全局统一改圆角/改字体不必逐控件叠 class，theme 层有全局开关（`@theme.corners_round_set` 等），见[组件速查](components.md)与 [design 文档](https://github.com/lb091188/moonbit-native-gui/blob/master/proposals/design.md)。

---

## 四、系统能力

系统能力族统一 `Result` 语义：不支持的环境返回错误值而不是崩溃；三平台支持矩阵见[系统能力总览](system-capabilities.md)。

### 4.1 打开链接 / 定位文件

**目标**：点一下打开网页；或在系统文件管理器里定位某个文件。

**思路**：`@sys.open_url` 开 URL（交浏览器或协议处理程序）；`@sys.open_file` 把文件交系统默认程序；`@shell.reveal_in_file_manager` 在文件管理器中定位并选中。

**代码**：

```moonbit
@ui.col(
  [
    @ui.link("打开文档站", fn() {
      let _ = @sys.open_url("https://moonbit-native-gui.pages.dev")
    }),
    @ui.button("打开图片", on_click=fn() {
      let _ = @sys.open_file("/home/me/photo.png")   // 交系统默认看图程序
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

**目标**：点「复制」把一段文本放进系统剪贴板，toast 提示成功。

**思路**：`clipboard_set_text` 直写系统剪贴板，返回 `Bool` 表示成败。

**代码**：

```moonbit
@ui.button("复制安装命令", on_click=fn() {
  if @sys.clipboard_set_text("moon add NoahLiu/native-gui") {
    toast("已复制", @ui.Success)   // toast 见 §2.4
  }
})
```

读剪贴板用 `clipboard_get_text() -> String?`（无内容或不可用时 `None`）。另外输入框内部已默认接系统剪贴板（Ctrl/Cmd+C/X/V 互通），不用为输入框单独写。

### 4.3 桌面通知

**目标**：构建完成、下载结束这类后台事件，给用户发一条系统通知。

**思路**：`@shell.notify_send(标题, 正文, 应用名)`；先 `notify_supported()` 探测。Linux 走 D-Bus、Windows 走托盘气泡、macOS 走 UN 中心。

**代码**：

```moonbit
@ui.button("发通知", on_click=fn() {
  if @shell.notify_supported() {
    match @shell.notify_send("构建完成", "3 个目标已产出", "我的应用") {
      Ok(_id) => toast("已发送", @ui.Info)
      Err(e) => println("通知失败：\{e}")
    }
  } else {
    println("当前环境不支持通知")
  }
})
```

**常见坑**：

- 通知要在事件回调里发（如按钮点击、任务完成），不要在构造期发。
- macOS 桌面横幅要求以 `.app` bundle 形态运行，首次使用会请求系统授权；未 bundle 的裸二进制可能只进通知中心不弹条。细节见[体验文档](experience.md)与 `proposals/adaptation.md`。

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
| 开第二个窗口 | `App::open_window` + `mount` | §2.8 |
| 换主色 / 跟随深浅 | `theme_apply` / `follow_system_theme` | §3.1 |
| 控件 hover 定制 | `class` + `hover=` + `transition_ms` | §3.2 |
| 打开链接 / 定位文件 | `@sys.open_url` / `@shell.reveal_in_file_manager` | §4.1 |
| 复制到剪贴板 | `@sys.clipboard_set_text` | §4.2 |
| 桌面通知 | `@shell.notify_send` | §4.3 |

## 下一步

- 一个场景要的控件本文没展开，去[组件速查](components.md)查签名；状态绑定的完整口径在[声明式与响应式](declarative.md)；布局字段全集在[布局样式](layout.md)。
- 想看这些场景在大程序里怎么组合：`cd examples/showcase && moon run .`，左边菜单每页都是独立源文件（`examples/showcase/pages/*.mbt`），对着抄。
- 最小工程从零起步：[五分钟上手](tutorial.md)。
