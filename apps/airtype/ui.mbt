// airtype 界面：标题区 → 二维码卡片 → 状态卡片 → 最近上屏卡片。
// 间距按刻度（4 / 8 / 12 / 16），字阶挂预设，卡片 bg_panel + border + 圆角 6。

///|
/// 应用状态。服务面三 Store 与上屏记录随批 3 的服务回调写入。
struct App {
  url : String
  qr : @qrc.QrCode
  state : @base.Store[String]
  addr : @base.Store[String]
  conns : @base.Store[String]
  history : @base.Store[Array[String]]
}

///|
fn build_app() -> App {
  // 批 2 占位地址：验二维码绘制链路；真地址随批 3 服务起来现算
  let url = "http://192.168.1.2:8787/?t=batch2-placeholder"
  {
    url,
    qr: make_qr(url),
    state: @base.Store::new("服务未启动"),
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
/// 最近上屏卡片：单行显示最新一条（超长省略），空时给占位文案。
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
      @ui.text(app.url, class=[@style.text_secondary], align=@text.Center),
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
