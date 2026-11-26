// 模板应用入口：页面在 pages/home.mng（单文件组件），生成码 pages/home.gen.mbt
// 入口只有生产语义：单实例声称 + 检查服务接线 + 挂窗。dev 三通道由 dev 形态
// 生成码自装（生产构建换生产形态生成码后 dev 面整体不在包里），唤起泵在
// ui 库内自排。

///|
fn main {
  match @shell.instance_claim("local.showcase") {
    Ok(@shell.Existing) => {
      let _ = @shell.instance_wake("local.showcase", [])
      println("APP-INST: 已有实例，已唤起并退出")
      return
    }
    Err(e) => println("APP-INST: 单实例降级：" + e.to_string())
    Ok(@shell.Primary) => ()
  }
  // 检查服务接线：MNG_INSPECT 注入才启用（mng dev 自动注入），
  // 生产未注入时泵空转零监听；F12/⌘⌥I 附窗开关也由它装。
  // release 要产物级剔除：删本行并去掉主包 moon.pkg 的 inspector import
  @inspector.inspect_auto_install()
  let app = match @ui.mount_window(
    [@pages.combo()],
    title="native-gui Showcase",
    width=1440,
    height=900,
  ) {
    None => {
      println("APP-SKIP: 本平台没有窗口后端或没有显示服务")
      return
    }
    Some(a) => a
  }
  app.run()
}
