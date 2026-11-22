// 文本注入（对外打字）：把任意文本投进系统当前聚焦的输入框，效果等同真实
// 键盘敲入。三平台实现：mac 走 CGEvent 键盘事件挂 UTF-16 串；Windows 走
// SendInput 的 KEYEVENTF_UNICODE；Linux 走 X11 XTest（运行期 dlopen，改键
// 映射挂 Unicode keysym——Wayland 会话只有 XWayland 应用收得到）。
// mac 需「辅助功能」授权（复用 permission 族的探测口）；提权目标窗口
// （管理员进程）与密码框按各系统设计不收注入。

///|
pub(all) enum InjectError {
  /// 当前平台没有注入通道（Windows / Linux 未做）
  Unsupported
  /// mac 辅助功能未授权，或权限探测失败
  PermissionDenied
  /// 平台注入调用失败，带原因
  Failed(String)
}

///|
pub impl Show for InjectError with fn output(self, logger) {
  match self {
    Unsupported => logger.write_string("InjectError::Unsupported")
    PermissionDenied => logger.write_string("InjectError::PermissionDenied")
    Failed(msg) => {
      logger.write_string("InjectError::Failed(")
      logger.write_string(msg)
      logger.write_string(")")
    }
  }
}

///|
pub extend InjectError with Show::{to_string, output}

///|
/// units 是 UTF-16LE 字节串，len 是 UTF-16 单元数（不是字节数）。
#borrow(units)
extern "c" fn ffi_inject_text(units : Bytes, len : Int32) -> Int32 = "yue_sys_inject_text"

///|
extern "c" fn ffi_inject_available() -> Int32 = "yue_sys_inject_available"

///|
/// 当前平台是否有文本注入通道：mac / Windows 恒有；Linux 要 DISPLAY 非空
/// 且 X11 + Xtst 库都 dlopen 得到（每次调用真实探测，高频场景调用方缓存）。
pub fn inject_available() -> Bool {
  ffi_inject_available() == 1
}

///|
/// 把文本投进系统当前聚焦的输入框。语义：
/// - 先探通道，无通道给 [Unsupported]；
/// - mac 先探「辅助功能」授权，未授给 [PermissionDenied]——弹引导框是应用
///   层引导流程的事（配合 [permission_ensure] 用），这里只报状态；其余平台
///   无此概念；
/// - 文本按 UTF-16 每至多 20 个单元一片投递，代理对不劈开；
/// - 全部片投递成功给 Ok，任一片失败给 [Failed]。
pub fn inject_text(text : String) -> Result[Unit, InjectError] {
  if !inject_available() {
    return Err(Unsupported)
  }
  if sys_platform() == "macos" {
    match permission_probe(PermAccessibility) {
      Ok(PermGranted) => ()
      _ => return Err(PermissionDenied)
    }
  }
  if text.length() == 0 {
    return Ok(())
  }
  let chunks = inject_chunks(text)
  let mut failed = 0
  for c in chunks {
    if ffi_inject_text(c, c.length() / 2) != 1 {
      failed = failed + 1
    }
  }
  if failed > 0 {
    Err(Failed("注入失败片数 \{failed}/\{chunks.length()}"))
  } else {
    Ok(())
  }
}

///|
/// UTF-16 分片（UTF-16LE 小头字节序）：每片至多 20 个单元；片界劈在代理对
/// 中间时该片带 21 个单元——emoji 等增补面字符永远不劈开。
fn inject_chunks(text : String) -> Array[Bytes] {
  let enc = @utf16.encode(text, bom=false, endianness=Little)
  let n = enc.length() / 2
  let chunks : Array[Bytes] = []
  let mut i = 0
  while i < n {
    let mut j = i + 20
    if j > n {
      j = n
    }
    // 片界落在高代理与低代理之间（后面还有单元）→ 延一个单元，成对保留
    let edge = enc[(j - 1) * 2].to_int() | (enc[(j - 1) * 2 + 1].to_int() << 8)
    if j < n && edge >= 0xD800 && edge <= 0xDBFF {
      j = j + 1
    }
    let from = i * 2
    chunks.push(Bytes::makei((j - i) * 2, fn(k) { enc[from + k] }))
    i = j
  }
  chunks
}
