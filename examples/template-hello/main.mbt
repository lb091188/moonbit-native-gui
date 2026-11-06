// 单文件组件（.mng）最小示例：`mng build` 产出生成码 hello.gen.mbt，本文件
// 像调普通函数一样接进窗口。跑法：moon run examples/template-hello（需要显示服务）。
// 开发热更：在应用侧带 dev 面（参考 examples/showcase/shared/mng_dev.mbt）后
// 用 `mng dev`——本示例保持最小，只演示生产链路。

///|
fn main {
  let app = match @ui.mount_window(
    [hello()],
    title="Template Hello",
    width=420,
    height=360,
  ) {
    None => {
      println("TEMPLATE-HELLO-SKIP: 本平台没有窗口后端或没有显示服务")
      return
    }
    Some(a) => a
  }
  app.run()
}
