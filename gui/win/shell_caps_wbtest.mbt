// 窗口外壳能力探测（3.1②）：无窗口后端全 false、操作给 Unsupported；
// 有后端再验「三平台都真的档」与透视的 Result 档（合成器位环境相关，条件进）。

// 注：「无窗口后端全 false」只在真无显示服务的进程里成立（有桌面时同进程
// 其他用例会先把后端起起来），这里只钉两条确定性：解码不崩、无效槽必 Err。

///|
test "shell_caps：解码不崩、无效槽透视给 Err" {
  let w : Window = { id: 0, width: 0, height: 0, }
  let caps = w.shell_caps()
  inspect(caps.layer == caps.layer, content="true")
  match w.set_transparent_bg(true) {
    Err(_) => ()
    Ok(_) => fail("无效槽透视应给 Err")
  }
}

///|
test "shell_caps：真窗探测，三平台共档全真、透视按能力走" {
  if !init_backend() {
    println("shell_caps: skip (无显示服务)")
  } else {
    match Window::new(160, 120, "wbtest-caps") {
      None => println("shell_caps: skip (建窗失败)")
      Some(w) => {
        let caps = w.shell_caps()
        inspect(caps.title, content="true")
        inspect(caps.borderless, content="true")
        inspect(caps.layer, content="true")
        // 透视：能力在就开得成、关得掉；不在（无合成器）不在此支。
        // Windows 另有一道前置——带边框的窗不支持透视，按契约先切无边框再开
        // （前置不满足时 setter 给 Failed，不是 Unsupported，见 set_transparent_bg）。
        if caps.transparent_bg {
          w.set_borderless(true)
          inspect(w.set_transparent_bg(true) is Ok(_), content="true")
          inspect(w.set_transparent_bg(false) is Ok(_), content="true")
          w.set_borderless(false)
        }
        w.close()
      }
    }
  }
}
