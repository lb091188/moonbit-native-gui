// airtype 界面：两页签。首页收服务状态、二维码与最近上屏；设置页收辅助
// 功能授权与快捷指令配置。样式按 native-gui-design 基准：卡片 bg_panel +
// border + 圆角 6，间距取 4 / 8 / 12 / 16，字阶挂预设，色全走 token。

///|
/// 应用状态。服务面三 Store、网址与二维码随服务起来写入，上屏记录随手机
// 发送写入，授权状态随重探定时器写入。
struct App {
  url : @base.Store[String]
  qr : @base.Store[QrImage]
  state : @base.Store[String]
  addr : @base.Store[String]
  conns : @base.Store[String]
  perm : @base.Store[String]
  cfg : @base.Store[String]
  history : @base.Store[Array[String]]
}

///|
fn build_app() -> App {
  // 启动态：地址与二维码随服务监听成功后现算（真局域网 IP + 实际端口）
  {
    url: @base.Store::new("服务启动中…"),
    qr: @base.Store::new(qr_image_of("airtype:starting")),
    state: @base.Store::new("启动中"),
    addr: @base.Store::new("—"),
    conns: @base.Store::new("0"),
    perm: @base.Store::new(perm_text()),
    cfg: @base.Store::new(load_shortcuts()),
    history: @base.Store::new([]),
  }
}

///|
/// 辅助功能授权读数（mac 上屏注入的前置权限；其余平台无需）。
fn perm_text() -> String {
  match @sys.permission_probe(@sys.PermAccessibility) {
    Ok(PermGranted) => "已授权"
    Ok(PermNotNeeded) => "本平台无需"
    _ => "未授权——上屏不可用"
  }
}

///|
/// 状态行：固定宽标签 + 绑定 Store 的值。
fn status_row(label : String, v : @base.Store[String]) -> @widget.Node {
  @ui.row(
    [
      @ui.col([@ui.text(label, class=[@style.text_secondary])], width=80.0),
      @ui.bind_label(v, fn(s) { s }),
    ],
    column_gap=8.0,
    align_items=@yoga.AlignItems::Center,
  )
}

///|
/// 整页：两页签，显隐切换。外层 view 宽高钉满窗口并放开 min 下限（yoga
/// 的 flex 子项 min-size 缺省 auto，不放开整条链都缩不动），tabs 吃满剩余
/// 高让页内容能接纵滚。
fn page(app : App) -> @widget.Node {
  @ui.view(
    [
      @ui.tabs(
        [("首页", home_page(app)), ("设置", settings_page(app))],
        class=[@style.style(flex=1.0, min_height=0.0, min_width=0.0)],
      ),
    ],
    padding=16.0,
    grow=1.0,
    class=[@style.style(width_percent=100.0, min_width=0.0)],
  )
}

///|
/// 首页：服务状态、二维码与地址、最近上屏。纵滚承接内容超高。
fn home_page(app : App) -> @widget.Node {
  @ui.scroll_view(
    [
      @ui.col(
        [service_card(app), qr_card(app), history_card(app)],
        row_gap=12.0,
      ),
    ],
    @ui.ScrollState::new(),
    class=[@style.style(border_width=0.0)],
  )
}

///|
/// 设置页：辅助功能授权、快捷指令配置。纵滚承接内容超高。
fn settings_page(app : App) -> @widget.Node {
  @ui.scroll_view(
    [
      @ui.col([perm_card(app), shortcuts_card(app)], row_gap=12.0),
    ],
    @ui.ScrollState::new(),
    class=[@style.style(border_width=0.0)],
  )
}

///|
/// 服务状态卡：三行读数。
fn service_card(app : App) -> @widget.Node {
  @ui.card(
    [
      status_row("状态", app.state),
      status_row("地址", app.addr),
      status_row("已连接手机", app.conns),
    ],
    title="服务",
    padding=12.0,
    row_gap=8.0,
    class=[@style.style(border_radius=6.0)],
  )
}

///|
/// 二维码卡：白底画布居中（扫码对比度优先，不随主题），地址在下方可选中。
fn qr_card(app : App) -> @widget.Node {
  @ui.card(
    [
      @ui.view(
        [qr_canvas(app.qr)],
        align_items=@yoga.AlignItems::Center,
      ),
      // 地址行左起单行：bind_label 自带 wrap=false + 末端省略号
      @ui.bind_label(app.url, fn(s) { s }, class=[@style.text_accent]),
    ],
    padding=12.0,
    row_gap=8.0,
    class=[@style.style(border_radius=6.0)],
  )
}

///|
/// 最近上屏卡：最新在前，点号分隔；空时给占位文案。
fn history_card(app : App) -> @widget.Node {
  @ui.card(
    [
      @ui.bind_label(
        app.history,
        fn(hs) {
          if hs.length() == 0 {
            "暂无记录——手机发送后在这里出现"
          } else {
            let mut out = ""
            for i, h in hs {
              if i > 0 {
                out = out + " · "
              }
              out = out + h
            }
            out
          }
        },
        class=[@style.text_secondary],
      ),
    ],
    title="最近上屏",
    padding=12.0,
    row_gap=8.0,
    class=[@style.style(border_radius=6.0)],
  )
}

///|
/// 辅助功能卡：授权读数 + 去授权按钮（弹系统引导并直达设置页，两秒重探
/// 在 handle 里接管）。
fn perm_card(app : App) -> @widget.Node {
  @ui.card(
    [
      status_row("授权状态", app.perm),
      @ui.row(
        [
          @ui.view([], grow=1.0),
          @ui.button(
            "去授权",
            variant=@ui.Solid,
            on_click=fn() {
              // ensure 已授时静默；未授弹系统引导框，并附直达设置页
              let _ = @sys.permission_ensure(@sys.PermAccessibility)
              let _ = @sys.open_url(
                "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
              )
              app.perm.set(perm_text())
            },
          ),
        ],
        column_gap=8.0,
      ),
    ],
    title="辅助功能",
    padding=12.0,
    row_gap=8.0,
    class=[@style.style(border_radius=6.0)],
  )
}

///|
/// 快捷指令卡：模板行 + 示例行 + 字段取值分行展示，改动即落盘并生效于
/// 手机页的 chips。
fn shortcuts_card(app : App) -> @widget.Node {
  @ui.card(
    [
      @ui.col(
        [
          @ui.text("一行一个按钮：", class=[@style.text_secondary]),
          @ui.text("  标签|文本|回车", class=[@style.text_secondary]),
          @ui.text("  继续|继续|yes", class=[@style.text_secondary]),
          @ui.text("  请检查刚才的改动|no", class=[@style.text_secondary]),
          @ui.text(
            "标签＝按钮名，可省略；文本＝发到电脑的内容；回车＝yes 或 no——yes 发完自动补回车，no 只上屏。回车段可省略，省略时等同 yes。",
            class=[@style.text_secondary],
          ),
        ],
        row_gap=4.0,
      ),
      @ui.textarea(
        app.cfg,
        placeholder="继续",
        rows=6,
        on_change=fn(s) { apply_shortcuts(s) },
      ),
    ],
    title="快捷指令",
    padding=12.0,
    row_gap=8.0,
    class=[@style.style(border_radius=6.0)],
  )
}
