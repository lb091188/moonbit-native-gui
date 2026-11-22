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
extern "c" fn ffi_inject_text(units : Bytes, len : Int32) -> Int32 = "sys_inject_text"

///|
extern "c" fn ffi_inject_available() -> Int32 = "sys_inject_available"

///|
/// 可模拟的按键。键名与序号的对应表在 sys_stub.c 的 sys_inject_key
/// 注释里，两侧必须同步改。
pub(all) enum Key {
  Enter
  Tab
  Backspace
  Delete
  Escape
  Space
  Home
  End
  PageUp
  PageDown
  Insert
  ArrowUp
  ArrowDown
  ArrowLeft
  ArrowRight
  F1
  F2
  F3
  F4
  F5
  F6
  F7
  F8
  F9
  F10
  F11
  F12
  /// 字符键：仅限字母与数字——真实键码路径，可与修饰键组合出 Ctrl+C 这类
  /// 快捷键；其余符号与文字走 [inject_text]。
  Char(Char)
}

///|
/// 键的桩序号（契约见 sys_stub.c sys_inject_key 的表）。
fn key_id(k : Key) -> Int32 {
  match k {
    Enter => 0
    Tab => 1
    Backspace => 2
    Delete => 3
    Escape => 4
    Space => 5
    Home => 6
    End => 7
    PageUp => 8
    PageDown => 9
    Insert => 10
    ArrowUp => 11
    ArrowDown => 12
    ArrowLeft => 13
    ArrowRight => 14
    F1 => 15
    F2 => 16
    F3 => 17
    F4 => 18
    F5 => 19
    F6 => 20
    F7 => 21
    F8 => 22
    F9 => 23
    F10 => 24
    F11 => 25
    F12 => 26
    Char(_) => 27
  }
}

///|
/// Char 键的码点；其余键 0。
fn key_cp(k : Key) -> Int32 {
  match k {
    Char(c) => c.to_int()
    _ => 0
  }
}

///|
/// 修饰键位掩码（契约见 sys_stub.c）：bit0 Ctrl、bit1 Alt、bit2 Shift、
/// bit3 Meta。大写字母自动补 Shift（真实键盘上大写就是 Shift+键）。
fn key_mods(k : Key, ctrl : Bool, alt : Bool, shift : Bool, meta : Bool) -> Int32 {
  let mut m = 0
  if ctrl {
    m = m | 1
  }
  if alt {
    m = m | 2
  }
  if shift {
    m = m | 4
  }
  if meta {
    m = m | 8
  }
  match k {
    Char(c) =>
      if c >= 'A' && c <= 'Z' {
        m = m | 4
      }
    _ => ()
  }
  m
}

///|
#borrow(key)
extern "c" fn ffi_inject_key(
  key : Int32,
  mods : Int32,
  cp : Int32,
) -> Int32 = "sys_inject_key"

///|
/// 模拟一次按键按下并抬起（可挂修饰键）——文本之外的键盘动作统一入口：
/// 回车确认、Esc 关层、方向键导航、Ctrl+C 复制、F5 刷新等。
/// 权限与通道语义同 [inject_text]；提权目标窗口与密码框按各系统设计不收。
pub fn inject_key(
  key : Key,
  ctrl? : Bool,
  alt? : Bool,
  shift? : Bool,
  meta? : Bool,
) -> Result[Unit, InjectError] {
  let ctrl = ctrl.unwrap_or(false)
  let alt = alt.unwrap_or(false)
  let shift = shift.unwrap_or(false)
  let meta = meta.unwrap_or(false)
  if !inject_available() {
    return Err(Unsupported)
  }
  if sys_platform() == "macos" {
    match permission_probe(PermAccessibility) {
      Ok(PermGranted) => ()
      _ => return Err(PermissionDenied)
    }
  }
  match key {
    Char(c) =>
      if !((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9')) {
        return Err(Failed("字符键仅支持字母与数字，其余符号走文本注入"))
      }
    _ => ()
  }
  let ok = ffi_inject_key(
    key_id(key),
    key_mods(key, ctrl, alt, shift, meta),
    key_cp(key),
  )
  if ok == 1 {
    Ok(())
  } else {
    Err(Failed("按键投递失败（key=\{key_id(key)}）"))
  }
}

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
