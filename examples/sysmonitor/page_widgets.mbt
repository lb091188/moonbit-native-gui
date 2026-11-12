// 磁盘页共用的小部件：自绘数据行容器。行列表用「单容器 on_draw 遍历
// 数据」而非每行一个节点：行数随数据增减（热插拔挂载）不用重建视图树，
// 1Hz 刷新只进程级 invalidate 重绘画布；主题切换经 on_theme_change 同样
// invalidate（on_draw 实时读 theme_current）。
//
// 自绘行用 node_of_new + on_draw 字段 + @widget.invalidate()；行高变化直接改
// yoga 节点高度（宿主每帧 relayout，无需手动布局）。

///|
/// 行高（磁盘页）。
fn row_h() -> Double {
  34.0
}

///|
/// 自绘数据行容器：on_draw 里遍历当前数据作画，数据变化经 Store 订阅
/// 只重绘画布；行数变化时同步更新容器高度。draw 签名为
/// (painter, width)；rows 存当前行数（供定高与刷新触发）。
fn draw_rows(
  rows : @base.Store[Int32],
  draw : (@render.Painter, Double) -> Unit,
) -> @widget.Node {
  @widget.node_of_new(fn(c : @widget.Widget) -> @widget.Widget {
    c.node.set_flex_direction(@yoga.Column)
    c.node.set_height(@yoga.fixed(rows.get().to_double() * row_h()))
    c.on_draw = Some(fn(
      _s : @widget.Widget,
      p : @render.Painter,
      r : @base.Rect,
    ) -> Unit {
      draw(p, r.w)
    })
    rows.subscribe(fn(n) {
      c.node.set_height(@yoga.fixed(n.to_double() * row_h()))
      @widget.invalidate()
    })
    // 主题切换后重绘（绘制时读 theme_current）
    ignore(@theme.on_theme_change(fn() { @widget.invalidate() }))
    c
  })
}

///|
/// 斑马纹底色（奇行浅灰）。
fn zebra_bg(i : Int32) -> Bool {
  i % 2 == 1
}
