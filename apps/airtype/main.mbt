// airtype 主入口：批 2 阶段先立窗口与二维码自绘，服务与投字链路随批 3 接入。

///|
fn main {
  let app = build_app()
  let mounted = @ui.mount_window(
    [page(app)],
    title="airtype",
    width=460,
    height=640,
    handle=
      fn(a : @widget.WindowHost) {
        ignore(a.follow_system_theme())
      },
  )
  match mounted {
    Some(a) => {
      a.run()
      println("airtype: done")
    }
    None => println("airtype: skip（本平台没有窗口后端或没有显示服务）")
  }
}
