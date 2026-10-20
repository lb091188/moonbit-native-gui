// 本地化/图标/排版三页：
//  - page_iconfont：运行时加载 [icons] TOML（工具产物）并网格预览 @ui.iconfont；
//  - page_i18n：内置默认语言 + 外置 locale 覆盖，zh|en 并排快照；
//  - page_rtl：RTL 布局镜像（Style.direction）与文本 run 基方向（set_base_dir）对比。
// 说明页文本用 @ui.text；开关用 @base.Store + @widget.invalidate 触发重排重绘。

const ICONFONT_TOML : String =
  "# 演示用 iconfont 子集（工具 icon_convert 的产物形态）\n[icons]\n\"square\" = \"M-1000,-1000L1000,-1000L1000,1000L-1000,1000Z\"\n\"ring\" = \"M0,-1000C553,-1000,1000,-553,1000,0C1000,553,553,1000,0,1000C-553,1000,-1000,553,-1000,0C-1000,-553,-553,-1000,0,-1000ZM0,-660C-364,-660,-660,-364,-660,0C-660,364,-364,660,0,660C364,660,660,364,660,0C660,-364,364,-660,0,-660Z\"\n\"tri\" = \"M-1000,600L0,-900L1000,600Z\"\n\"diamond\" = \"M0,-1000L1000,0L0,1000L-1000,0Z\"\n"

///|
fn iconfont_cell(name : String) -> @widget.Node {
  @ui.col(
    [
      @ui.iconfont(name, size=40.0),
      @ui.text(name, role=@ui.Secondary),
    ],
    row_gap=4.0,
    width=120.0,
  )
}

///|
pub fn page_iconfont(_app : @shared.App) -> @widget.Node {
  let _loaded = @icons.iconfont_load(ICONFONT_TOML)
  let names = @icons.iconfont_names()
  let cells : Array[@widget.Node] = []
  let mut i = 0
  while i < names.length() {
    let row_cells : Array[@widget.Node] = []
    let mut j = 0
    while j < 5 && i + j < names.length() {
      row_cells.push(iconfont_cell(names[i + j]))
      j += 1
    }
    cells.push(@ui.row(row_cells, column_gap=8.0))
    i += 5
  }
  @ui.col(
    [
      @ui.text("运行时加载 iconfont（工具产出的 [icons] 定点路径），复用矢量自绘", role=@ui.Section),
      @ui.text("已装入 " + names.length().to_string() + " 个：@ui.iconfont(name) 与内置 @ui.icon 同盒子口径", role=@ui.Secondary),
      @ui.col(cells, row_gap=12.0),
    ],
    row_gap=10.0,
    padding=16.0,
  )
}

const I18N_ZH : String =
  "[meta]\nlocale = \"zh-CN\"\n[demo]\ntitle = \"国际化示例\"\ngreeting = \"你好，{name}！\"\nitems = \"已保存 {n} 项\"\n[gui.ui.dialog]\nconfirm = \"确定\"\n"

const I18N_EN : String =
  "[meta]\nlocale = \"en\"\n[demo]\ntitle = \"i18n Demo\"\ngreeting = \"Hello, {name}!\"\nitems = \"{n} items saved\"\n[gui.ui.dialog]\nconfirm = \"OK\"\n"

///|
fn i18n_col(text : String) -> Array[@widget.Node] {
  @i18n.i18n_load(text)
  [
    @ui.text(@i18n.t_or("demo.title", "—")),
    @ui.text(@i18n.t_with_or("demo.greeting", [("name", "Ada")], "—")),
    @ui.text(@i18n.t_count("demo.items", 3).unwrap_or("—")),
    @ui.text("对话框默认按钮：" + @i18n.t_or("gui.ui.dialog.confirm", "确定"), role=@ui.Secondary),
  ]
}

///|
pub fn page_i18n(_app : @shared.App) -> @widget.Node {
  let zh = i18n_col(I18N_ZH)
  let en = i18n_col(I18N_EN)
  @i18n.i18n_load(I18N_ZH) // 收尾留在中文默认
  let zh_children : Array[@widget.Node] = [@ui.text("中文 zh-CN", role=@ui.Section)]
  for n in zh {
    zh_children.push(n)
  }
  let en_children : Array[@widget.Node] = [@ui.text("English en", role=@ui.Section)]
  for n in en {
    en_children.push(n)
  }
  let zh_box = @ui.card(zh_children, padding=12.0)
  let en_box = @ui.card(en_children, padding=12.0)
  @ui.col(
    [
      @ui.text("内置默认语言 + 独立 locale 文件外置扩展", role=@ui.Section),
      @ui.text("未加载任何文件时 t_or 回落内置默认；i18n_load 一份 locale 即覆盖/扩展。", role=@ui.Secondary),
      @ui.row([zh_box, en_box], column_gap=16.0),
    ],
    row_gap=10.0,
    padding=16.0,
  )
}

///|
pub fn page_rtl(app : @shared.App) -> @widget.Node {
  let rtl = @base.Store::new(false)
  // 文本 run 基方向开关：置位后 @widget.invalidate 触发重排重绘
  let toggle = @ui.button(
    "切换文本基方向 (LTR/RTL)",
    on_click=fn() {
      let v = !rtl.get()
      rtl.set(v)
      @text.set_base_dir(if v { @text.Rtl } else { @text.Ltr })
      @widget.invalidate()
      app.toast_push("文本基方向 → " + (if v { "RTL" } else { "LTR" }), @ui.Info)
    },
  )
  let mixed = @ui.text("Hello مرحبا World 123 — 混排 bidi", font_size=16.0)
  // 布局镜像对比：两个三元素行，一个 class 带 Direction=Rtl
  let items = ["一", "二", "三"].map(x => @ui.card([@ui.text(x)], padding=10.0))
  let ltr_row = @ui.col(
    [@ui.text("LTR 主轴", role=@ui.Secondary), @ui.row(items, column_gap=8.0)],
    row_gap=4.0,
  )
  let rtl_row = @ui.col(
    [
      @ui.text("RTL 布局镜像（Style.direction）", role=@ui.Secondary),
      @ui.row(
        items,
        column_gap=8.0,
        class=[@style.style().set_direction(Some(@style.Rtl))],
      ),
    ],
    row_gap=4.0,
  )
  @ui.col(
    [
      @ui.text("RTL 文本 run 与布局镜像", role=@ui.Section),
      toggle,
      mixed,
      @ui.row([ltr_row, rtl_row], column_gap=24.0),
    ],
    row_gap=12.0,
    padding=16.0,
  )
}
