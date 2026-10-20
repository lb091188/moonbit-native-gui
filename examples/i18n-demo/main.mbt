// 国际化端到端演示。加载 en / zh-CN 两本目录，把同一批键解析出来并排显示。
// 其中 gui.ui.dialog.confirm、gui.ui.message_box.ok 是框架里被改造走 t_or 的 chrome 键——
// 这里加载目录后它们返回译文，不加载时组件会逐字回落到中文默认（见 message_box 默认按钮）。

const EN =
  "[meta]\nlocale = \"en\"\n[gui.ui.dialog]\nconfirm = \"OK\"\ncancel = \"Cancel\"\n[gui.ui.message_box]\nok = \"OK\"\n[demo]\ntitle = \"i18n Demo\"\ngreeting = \"Hello, {name}!\"\nsaved = { one = \"{n} item saved\", other = \"{n} items saved\" }\n"

const ZH =
  "[meta]\nlocale = \"zh-CN\"\n[gui.ui.dialog]\nconfirm = \"确定\"\ncancel = \"取消\"\n[gui.ui.message_box]\nok = \"确定\"\n[demo]\ntitle = \"国际化示例\"\ngreeting = \"你好，{name}！\"\nsaved = { one = \"已保存 {n} 项\", other = \"已保存 {n} 项\" }\n"

// 在指定目录下解析出这六行文案
fn resolve(toml : String) -> Array[String] {
  @i18n.i18n_load(toml)
  [
    @i18n.t_or("demo.title", "—"),
    @i18n.t_with_or("demo.greeting", [("name", "Ada")], "—"),
    @i18n.t_count("demo.saved", 1).unwrap_or("—"),
    @i18n.t_count("demo.saved", 3).unwrap_or("—"),
    @i18n.t_or("gui.ui.dialog.confirm", "—"),
    @i18n.t_or("gui.ui.message_box.ok", "—"),
  ]
}

fn cell(s : String, w : Double) -> @widget.Node {
  @ui.col(
    [@ui.text(s)],
    width=w,
  )
}

fn main {
  let en = resolve(EN)
  let zh = resolve(ZH)
  // 收尾把当前目录留在 zh（框架默认语言），组件此刻用的是中文
  @i18n.i18n_load(ZH)

  let keys = [
    "demo.title",
    "demo.greeting{name=Ada}",
    "demo.saved n=1",
    "demo.saved n=3",
    "gui.ui.dialog.confirm",
    "gui.ui.message_box.ok",
  ]

  let rows : Array[@widget.Node] = []
  let mut i = 0
  while i < keys.length() {
    rows.push(
      @ui.row(
        [
          cell(keys[i], 300.0),
          cell(en[i], 220.0),
          cell(zh[i], 220.0),
        ],
        column_gap=8.0,
      ),
    )
    i += 1
  }
  let head = @ui.row(
    [
      cell("键（source）", 300.0),
      cell("英文（en）", 220.0),
      cell("中文（zh-CN）", 220.0),
    ],
    column_gap=8.0,
  )

  let root = @ui.col(
    [
      @ui.text("国际化端到端演示 · t()/插值/复数/t_or 行为不变"),
      head,
      @ui.col(rows, row_gap=6.0),
    ],
    row_gap=10.0,
    padding=16.0,
  )

  let mounted = @ui.mount_window(
    [root],
    title="i18n Demo",
    width=800,
    height=420,
    handle=fn(_a : @widget.App) { () },
  )
  match mounted {
    None => println("本平台无窗口后端或无显示服务")
    Some(host) => host.run()
  }
}
