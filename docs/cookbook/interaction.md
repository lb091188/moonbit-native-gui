# 交互场景

import 清单见[场景总览](index.md#公共前提)；交互场景给完整程序。

## 输入框取值与回车提交

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

## 列表增删项

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
- 行内会变的字段各自做成 `Store`；见[声明式与响应式](../guide/declarative.md)。
- 列表长了外包[超高滚动](layout.md#内容超高滚动)的 `scroll_view`；万行级用 `virt_list` / `table_v`。

## 确认弹窗

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

## 轻提示

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

语义色：`@ui.Primary` / `@ui.Success` / `@ui.Warning` / `@ui.Danger` / `@ui.Info`。需要用户点确认的场景用[确认弹窗](#确认弹窗)。

## 定时刷新

`@shell.set_timeout(毫秒, 回调)` 是一次性定时器，循环靠回调尾自排；启动点放 `mount_window` 的 `handle` 回调。

```moonbit
fn main {
  let ticks : @base.Store[Int32] = @base.Store::new(0)
  let app = match @ui.mount_window(
    [@ui.bind_label(ticks, fn(n : Int32) { "已运行 \{n} 拍" })],
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

- 挂载前（构造期）调用 `set_timeout` 不生效；启动点用 `handle` / `Node::on_mount` / 事件回调，见[声明式与响应式](../guide/declarative.md)。
- 停止循环：加 `Store[Bool]` 开关，`pump` 开头检查、不满足就不自排。

## 按条件显隐

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

注意：切换不重新初始化节点，输入框内容保留；要全新状态自己清 store 或改用 `bind_node`。`Signal` 版与泛型版见[组件：响应式控制](../components/reactive.md)。

## 表单项与错误提示

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
          toast("提交成功", @ui.Success)   // toast 见[轻提示](#轻提示)
        }
      })],
      class=[@style.style(justify_content=@yoga.JustifyContent::FlexEnd)],
    ),
  ],
  row_gap=12.0,
)
```

注意：校验时机自定——提交回调或 `input` 的 `on_change`。

## 打开第二个窗口

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

注意：`open_window` 宽高是 `Int32`；无窗口后端返回 `None`。多窗口门面见[组件总览](../components/index.md#声明式挂载)。

## 记住窗口位置尺寸

`WindowHost::remember_geometry(app_id)` 一行接上：开窗后先恢复上次的位置/尺寸/最大化档（文件不存在就什么都不动——首次运行保持默认），关窗或退出时自动写回。手动落盘时机用 `save_geometry()`；不想记了把 `remember_id` 清空即可。

```moonbit
let app = match @ui.mount_window(page(), title="MyApp", width=1280, height=800) {
  None => return
  Some(a) => a
}
app.remember_geometry("com.example.myapp")   // 与打包 id 同源
app.mount(page())
app.run()
```

状态文件按平台落在应用自有目录（macOS `~/Library/Application Support/<id>/`、Linux `$XDG_STATE_HOME` 或 `~/.local/state`/`<id>/`、Windows `%APPDATA%\<id>\`），文件名都是 `window-state.json`；窗口落在屏幕外这类怪状态删掉文件即可复位。边界：恢复不做屏幕钳位；多窗应用对同一 id 只记一份，各窗分开记就换不同的 id 后缀。
