// 使用者视角：只有 MoonBit 类型和回调，没有任何平台相关代码。
//
// 跑法：moon run examples/hello（需要显示服务；没有时打印一行提示后退出）

///|
fn main {
  let app = match @ui.mount_window(
    [
      @ui.view(
        [
          @ui.text("Hello, MoonBit!", font_size=18.0),
          @ui.text("你好，月兔！", font_size=18.0),
          @ui.text("Built with native-gui on MoonBit", role=@ui.Secondary),
          @ui.link("view on mooncakes.io", fn() {
            let _ = @sys.open_url("https://mooncakes.io")
          }),
        ],
        row_gap=6.0,
        grow=1.0,
        align_items=@yoga.AlignItems::Center,
        justify_content=@yoga.JustifyContent::Center,
      ),
    ],
    title="Hello, MoonBit!",
    width=400,
    height=300,
  ) {
    None => {
      println("HELLO-SKIP: 本平台没有窗口后端或没有显示服务")
      return
    }
    Some(a) => a
  }
  app.run()
}
