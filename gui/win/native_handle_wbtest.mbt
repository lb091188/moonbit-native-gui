// 原生句柄透出（1.1）：裸句柄只有平台语义（Win=HWND / mac=NSWindow* /
// GTK=GtkWidget*），跨平台代码不得依赖。无显示服务环境只验「无效槽回 0」；
// 有后端再验真窗句柄非 0 且两次读数一致。

///|
test "native_handle：无效槽返回 0（无后端可验）" {
  let w : Window = { id: 0, width: 0, height: 0 }
  inspect(w.native_handle(), content="0")
  let bad : Window = { id: 999999, width: 0, height: 0 }
  inspect(bad.native_handle(), content="0")
}

///|
test "native_handle：真窗句柄非 0、两次读数一致" {
  if !init_backend() {
    println("native_handle: skip (无显示服务)")
  } else {
    match Window::new(160, 120, "wbtest-native") {
      None => println("native_handle: skip (建窗失败)")
      Some(w) => {
        let h1 = w.native_handle()
        inspect(h1 != 0, content="true")
        inspect(w.native_handle() == h1, content="true")
        w.close()
        inspect(w.native_handle(), content="0")
      }
    }
  }
}
