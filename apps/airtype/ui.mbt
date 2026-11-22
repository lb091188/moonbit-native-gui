// airtype 界面：标题区 → 二维码卡片 → 状态卡片 → 最近上屏卡片。
// 间距按刻度（4 / 8 / 12 / 16），字阶挂预设，卡片 bg_panel + border + 圆角 6。

///|
/// 应用状态。服务面三 Store、网址与二维码随服务起来写入，上屏记录随手机
// 发送写入。
struct App {
  url : @base.Store[String]
  qr : @base.Store[QrImage]
  state : @base.Store[String]
  addr : @base.Store[String]
  conns : @base.Store[String]
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
    history: @base.Store::new([]),
  }
}

///|
/// 状态行：固定宽标签 + 绑定 Store 的值。
fn status_row(label : String, v : @base.Store[String]) -> @widget.Node {
  @ui.row(
    [
      @ui.col([@ui.text(label, class=[@style.text_secondary])], width=88.0),
      @ui.bind_label(v, fn(s) { s }),
    ],
    column_gap=8.0,
    align_items=@yoga.AlignItems::Center,
  )
}

///|
/// 最近上屏卡片：最新在前，点号分隔；空时给占位文案。
fn history_card(app : App) -> @widget.Node {
  @ui.view(
    [
      @ui.text("最近上屏", class=[@style.text_title]),
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
    row_gap=8.0,
    padding=12.0,
    background_color="bg_panel",
    border_color="border",
    corner_radius=6.0,
    grow=1.0,
  )
}

///|
/// 整页。
fn page(app : App) -> @widget.Node {
  @ui.col(
    [
      @ui.col(
        [
          @ui.text("airtype", class=[@style.text_heading]),
          @ui.text(
            "手机扫码进网页打字，发送后直接打进电脑聚焦的输入框",
            class=[@style.text_secondary],
          ),
        ],
        row_gap=4.0,
      ),
      @ui.view(
        [qr_canvas(app.qr)],
        padding=12.0,
        background_color="bg_panel",
        border_color="border",
        corner_radius=6.0,
        align_items=@yoga.AlignItems::Center,
      ),
      @ui.bind_label(app.url, fn(s) { s }, class=[@style.text_secondary]),
      @ui.view(
        [
          status_row("服务状态", app.state),
          status_row("局域网地址", app.addr),
          status_row("已连接手机", app.conns),
        ],
        row_gap=8.0,
        padding=12.0,
        background_color="bg_panel",
        border_color="border",
        corner_radius=6.0,
      ),
      history_card(app),
    ],
    padding=16.0,
    row_gap=12.0,
    grow=1.0,
  )
}
