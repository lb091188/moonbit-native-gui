// 系统调用面（桩 `dbus_stub.c`，只用标准头）：Unix 套接字、uid、Double 位
// 模式。fd 监视与延迟任务**不走 C**——本包不认识任何事件循环，由宿主注入
// （见 [dbus_set_post_delayed] 与 [dbus_pump]），因此 dbus 不依赖 glib、
// 也不依赖 GUI 层。

///|
/// MoonBit 字符串按 UTF-16 码元存放，未配对的半截代理对会让 `@utf8.encode`
/// 直接 abort（进程当场终止，托盘注销都来不及发）。线路出口统一过这里：先把
/// 这类码元换成 U+FFFD 再编码，交给总线的字节恒为合法 UTF-8。
fn utf8(s : String) -> Bytes {
  @utf8.encode(replace_lone_surrogates(s))
}

///|
/// 码元是不是孤立代理对（有效配对在迭代时已合成整个码点，不会落进这个区间）。
fn is_lone_surrogate(code : Int) -> Bool {
  code >= 0xD800 && code <= 0xDFFF
}

///|
/// 把字符串里的孤立代理对逐个替换成 U+FFFD；干净串原样返回（托盘字符串恒为
/// 干净串，不多分配）。
fn replace_lone_surrogates(s : String) -> String {
  let mut dirty = false
  for c in s {
    if is_lone_surrogate(c.to_int()) {
      dirty = true
      break
    }
  }
  if !dirty {
    s
  } else {
    let sb = StringBuilder()
    for c in s {
      if is_lone_surrogate(c.to_int()) {
        sb.write_char('\u{FFFD}')
      } else {
        sb.write_char(c)
      }
    }
    sb.to_string()
  }
}

// ---------------------------------------------------------------------------
// FFI（桩：dbus_stub.c）
// ---------------------------------------------------------------------------

///|
/// 装退出信号兜底（SIGINT/SIGTERM 只置标志，主循环下一拍取走）。
extern "c" fn ffi_install_quit_signals() -> Unit =
  "yue_dbus_install_quit_signals"

///|
/// 取走退出信号标志：读到过就清零，一次信号对应一次退出动作。
extern "c" fn ffi_quit_signal() -> Int = "yue_dbus_quit_signal"

///|
#borrow(path)
extern "c" fn ffi_unix_connect(path : Bytes) -> Int = "yue_dbus_unix_connect"

///|
#borrow(buf)
extern "c" fn ffi_read(
  fd : Int,
  buf : Bytes,
  off : Int,
  len : Int,
) -> Int = "yue_dbus_read"

///|
#borrow(buf)
extern "c" fn ffi_write(
  fd : Int,
  buf : Bytes,
  off : Int,
  len : Int,
) -> Int = "yue_dbus_write"

///|
extern "c" fn ffi_poll(fd : Int, events : Int, timeout_ms : Int) -> Int =
  "yue_dbus_poll"

///|
extern "c" fn ffi_close(fd : Int) -> Unit = "yue_dbus_close"

///|
extern "c" fn ffi_getuid() -> Int = "yue_dbus_getuid"

///|
/// Double → IEEE 754 位模式（DBus 'd' 编码）。
extern "c" fn ffi_f64_to_bits(v : Double) -> Int64 = "yue_dbus_f64_to_bits"

///|
/// IEEE 754 位模式 → Double（DBus 'd' 解码）。
extern "c" fn ffi_f64_from_bits(bits : Int64) -> Double =
  "yue_dbus_f64_from_bits"

///|
/// 读环境变量（走 `sys` 的 C 层 getenv，反映进程内写删后的实时值）。
fn env_get(name : String) -> String? {
  @sys.sys_getenv(name)
}
