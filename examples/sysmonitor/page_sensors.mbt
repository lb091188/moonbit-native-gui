// 显卡页（U4）：每块物理卡两张曲线（使用率 0-100 / 显存 GB 自适应）。
// 数据来自 main.mbt 的 1Hz sample_once；型号取启动枚举结果拼进小节标题。

///|
fn page_sensors(app : App) -> @widget.Node {
  // 每块物理卡两张图：使用率（0-100 固定轴）+ 显存（GB，自适应轴，
  // 采样值入序列时已换算 GiB）。
  let gpus0 = app.gpus.get()
  fn gpu_label(i : Int32, what : String) -> String {
    let model = if i < gpus0.length() && gpus0[i].model != "" {
      "（\{gpus0[i].model}）"
    } else {
      ""
    }
    "显卡 \{i + 1}\{model} \{what}"
  }
  let nodes : Array[@widget.Node] = []
  if app.gpu_busy_hists.length() == 0 {
    nodes.push(@ui.text("未检测到显卡", color="text_secondary"))
  }
  for i in 0..<app.gpu_busy_hists.length() {
    nodes.push(
      @ui.text(gpu_label(i, "使用率（%）"), class=[@style.text_title]),
    )
    nodes.push(
      @charts.line_chart_t(
        app.gpu_busy_hists[i],
        height=220.0,
        y_range=Some((0.0, 100.0)),
        area=true,
      ),
    )
    nodes.push(
      @ui.text(gpu_label(i, "显存（GB）"), class=[@style.text_title]),
    )
    nodes.push(
      @charts.line_chart_t(app.gpu_vram_hists[i], height=220.0, area=true),
    )
  }
  @ui.col(nodes, padding=12.0, row_gap=6.0, class=[@style.style(min_width=0.0)])
}
