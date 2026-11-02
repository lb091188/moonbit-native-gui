// 工具侧进程原语（标准头 C，无 GUI 依赖）。
// 与 gui/sys 的 pr_* 同职责但只保留 dev 循环要的那几口：跑构建命令、起应用、
// 探活/杀、毫秒节拍。stdout/stderr 一律进文件或继承终端，不做捕获解析。
// 参数走 `\0` 分隔的 blob（C 侧不解析引号与空格）。

///|
#borrow(file, blob)
extern "c" fn ffi_run_wait(
  file : Bytes,
  blob : Bytes,
  blob_len : Int,
  timeout_ms : Int,
) -> Int = "mngpr_run_wait"

///|
#borrow(file, blob, out_path)
extern "c" fn ffi_spawn(
  file : Bytes,
  blob : Bytes,
  blob_len : Int,
  out_path : Bytes,
) -> Int = "mngpr_spawn"

///|
extern "c" fn ffi_alive(pid : Int) -> Int = "mngpr_alive"

///|
extern "c" fn ffi_kill(pid : Int) -> Int = "mngpr_kill"

///|
extern "c" fn ffi_sleep_ms(ms : Int) -> Unit = "mngpr_sleep_ms"

///|
extern "c" fn ffi_last_errno() -> Int = "mngpr_last_errno"

///|
fn args_blob(args : Array[String]) -> Bytes {
  let buf = StringBuilder()
  for a in args {
    buf.write_string(a)
    buf.write_char('\u{0}')
  }
  @utf8.encode(buf.to_string())
}

///|
fn errno_msg() -> String {
  "errno=\{ffi_last_errno()}"
}

///|
/// 运行命令并等它结束（stdio 继承调用方）；返回退出码。
/// 超时先 SIGTERM 再 SIGKILL（子进程成组），返回 Err。
pub fn run_wait(file : String, args : Array[String], timeout_ms : Int) -> Result[Int, String] {
  let blob = args_blob(args)
  let rc = ffi_run_wait(@utf8.encode(file), blob, blob.length(), timeout_ms)
  if rc == -2 {
    Err(file + " 超时（\{timeout_ms}ms）")
  } else if rc < 0 {
    Err(file + " 起不来（" + errno_msg() + "）")
  } else {
    Ok(rc)
  }
}

///|
/// 起一个后台进程，stdout/stderr 追加到 `out_path`；返回 pid。
pub fn spawn(file : String, args : Array[String], out_path : String) -> Result[Int, String] {
  let blob = args_blob(args)
  let pid = ffi_spawn(@utf8.encode(file), blob, blob.length(), @utf8.encode(out_path))
  if pid <= 0 {
    Err(file + " 起不来（" + errno_msg() + "）")
  } else {
    Ok(pid)
  }
}

///|
/// 进程是否还活着（僵尸按已死算，顺带收尸）。
pub fn alive(pid : Int) -> Bool {
  ffi_alive(pid) == 1
}

///|
/// 请求终止（先整组再单进程的 SIGTERM）。
pub fn kill(pid : Int) -> Bool {
  ffi_kill(pid) == 1
}

///|
/// 毫秒节拍。
pub fn sleep_ms(ms : Int) -> Unit {
  ffi_sleep_ms(ms)
}
