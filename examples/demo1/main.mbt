// 模板应用入口：页面在 pages/home.mng（单文件组件），生成码 pages/home.gen.mbt
// 入口只有生产语义：单实例声称 + 挂窗。dev 三通道由 dev 形态生成码自装
// （生产构建换生产形态生成码后 dev 面整体不在包里），唤起泵在 ui 库内自排。

///|
fn main {
  match @shell.instance_claim("noahliu.native-gui-examples-demo1") {
    Ok(@shell.Existing) => {
      let _ = @shell.instance_wake("noahliu.native-gui-examples-demo1", [])
      println("APP-INST: 已有实例，已唤起并退出")
      return
    }
    Err(e) => println("APP-INST: 单实例降级：" + e.to_string())
    Ok(@shell.Primary) => ()
  }
  let app = match @ui.mount_window(
    [@pages.home()],
    title="demo1 — mng 模板示例",
    width=420,
    height=360,
  ) {
    None => {
      println("APP-SKIP: 本平台没有窗口后端或没有显示服务")
      return
    }
    Some(a) => a
  }
  app.run()
}
