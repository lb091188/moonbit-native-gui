// 网络页（U4）：只列实体网卡。每块卡一张：名称 + 实时收发速率 + 收发
// 双序列 2 分钟曲线；虚拟网桥 / veth / 隧道不进列表。网卡集合变化时
// 按名字集合重挂卡片（历史与实时值按名字保留）。

///|
fn net_card(app : App, n : NetInfo) -> @widget.Node {
  let hist = net_hist_of(app, n.name)
  let speed = net_speed_of(app, n.name)
  @ui.col(
    [
      @ui.row(
        [
          @ui.text(n.name, font_size=14.0, weight=@text.SemiBold, wrap=false),
          @ui.text_dyn(
            speed.signal(),
            font_size=12.0,
            color="text_secondary",
            align=@text.End,
            wrap=false,
            handle=fn(w) { w.node.set_flex_grow(1.0) },
          ),
        ],
        column_gap=8.0,
        class=[@style.style(min_width=0.0)],
      ),
      @charts.line_chart_t(hist, height=160.0, area=true),
    ],
    row_gap=4.0,
    class=[@style.style(min_width=0.0)],
  )
}

///|
fn page_net(app : App) -> @widget.Node {
  let body = @widget.bind_node(app.net_names_key.signal(), fn(_key) {
    let cards : Array[@widget.Node] = []
    for n in app.nets.get() {
      if n.physical {
        cards.push(net_card(app, n))
      }
    }
    if cards.length() == 0 {
      @ui.text("未检测到实体网卡", color="text_secondary")
    } else {
      @ui.col(cards, row_gap=16.0, class=[@style.style(min_width=0.0)])
    }
  })
  @ui.col(
    [@ui.text("实体网卡", class=[@style.text_title]), body],
    padding=12.0,
    row_gap=8.0,
    class=[@style.style(min_width=0.0)],
  )
}
