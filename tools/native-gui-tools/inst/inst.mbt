// 单实例客户端：`wake(app_id, args)` 把第二实例的命令行送进已运行的应用。
// 帧格式与 gui/shell 的单实例通道逐字一致：`[argc:i32 LE]([len:i32 LE][utf8])*`。
// 套接字路径规则同 shell：`$XDG_RUNTIME_DIR` → `$TMPDIR` → `/tmp`，
// 文件名 `moonbit-instance-<slug>.<uid>.sock`。

///|
/// 单帧载荷上限（字节）。
pub const PAYLOAD_CAP : Int32 = 65536

///|
/// 套接字文件名的 sun_path 安全长度（macOS 的 sun_path 容量 104，留足余量）。
const SOCKET_PATH_LIMIT : Int32 = 100

///|
/// slug 里 app_id 原样保留的最大长度；超出就截断并附内容哈希。
const SLUG_KEEP : Int32 = 40

///|
#borrow(path, data)
extern "c" fn inst_wake_raw(path : Bytes, data : Bytes, len : Int32) -> Int32 = "mnginst_wake"

///|
#borrow(slug, data)
extern "c" fn inst_wake_win_raw(
  slug : Bytes,
  data : Bytes,
  len : Int32,
) -> Int32 = "mnginst_wake_win"

///|
extern "c" fn inst_is_windows() -> Int32 = "mnginst_is_windows"

///|
extern "c" fn inst_getuid() -> Int32 = "mnginst_getuid"

///|
extern "c" fn inst_last_errno() -> Int32 = "mnginst_last_errno"

///|
/// app_id 的 djb2 哈希，十六进制定长 8 位。
fn instance_hash8(s : String) -> String {
  let mut h : Int32 = 5381
  for i = 0; i < s.length(); i = i + 1 {
    h = ((h << 5) + h + s.unsafe_get(i).to_int()) & 0x7FFF_FFFF
  }
  let digits : Array[String] = [
    "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "a", "b", "c", "d", "e", "f",
  ]
  let out = StringBuilder()
  let mut i = 7
  while i >= 0 {
    out.write_string(digits[(h >> (i * 4)) & 15])
    i = i - 1
  }
  out.to_string()
}

///|
/// app_id → 原生侧名字：非 [A-Za-z0-9_-] 换下划线；超长取前缀 + 内容哈希。
fn instance_slug(app_id : String) -> String {
  let out = StringBuilder()
  for c in app_id.to_array() {
    let ok = (c >= 'a' && c <= 'z') ||
      (c >= 'A' && c <= 'Z') ||
      (c >= '0' && c <= '9') ||
      c == '_' ||
      c == '-'
    out.write_char(if ok { c } else { '_' })
  }
  let s = out.to_string()
  if s.length() <= SLUG_KEEP {
    s
  } else {
    s[:SLUG_KEEP].to_owned() + "-" + instance_hash8(app_id)
  }
}

///|
/// 套接字文件所在目录：`$XDG_RUNTIME_DIR` → `$TMPDIR` → `/tmp`。
fn socket_dir() -> String {
  match @env.get_env_var("XDG_RUNTIME_DIR") {
    Some(d) if d != "" => d
    _ =>
      match @env.get_env_var("TMPDIR") {
        Some(t) if t != "" => t
        _ => "/tmp"
      }
  }
}

///|
/// AF_UNIX 套接字文件路径（与应用侧 `@shell.instance_socket_path` 同规则）。
pub fn socket_path(app_id : String) -> String {
  let dir = socket_dir()
  let base = "moonbit-instance-"
  let tail = ".\{inst_getuid()}.sock"
  let budget = SOCKET_PATH_LIMIT -
    dir.length() -
    1 -
    base.length() -
    tail.length()
  let slug = instance_slug(app_id)
  let used = if budget < 8 {
    ""
  } else if slug.length() <= budget {
    slug
  } else {
    slug[:budget].to_owned()
  }
  let sep = if dir == "/" { "" } else { "/" }
  "\{dir}\{sep}\{base}\{used}\{tail}"
}

///|
/// 命令行参数 → 线帧。
pub fn encode_args(args : Array[String]) -> Bytes {
  let parts : Array[Bytes] = args.map(fn(s) { @utf8.encode(s) })
  let mut total = 4
  for p in parts {
    total = total + 4 + p.length()
  }
  let buf = FixedArray::make(total, b'\x00')
  let mut o = 0
  let write_i32 = fn(v : Int32, at : Int32) -> Int32 {
    buf[at] = (v & 255).to_byte()
    buf[at + 1] = ((v >> 8) & 255).to_byte()
    buf[at + 2] = ((v >> 16) & 255).to_byte()
    buf[at + 3] = ((v >> 24) & 255).to_byte()
    at + 4
  }
  o = write_i32(parts.length(), o)
  for p in parts {
    o = write_i32(p.length(), o)
    for i = 0; i < p.length(); i = i + 1 {
      buf[o] = p[i]
      o = o + 1
    }
  }
  Bytes::from_array(buf)
}

///|
/// 是否 Windows（工具侧按平台选探测策略：Windows 无单实例套接字文件面）。
pub fn on_windows() -> Bool {
  inst_is_windows() == 1
}

///|
/// 唤起已有实例并带上命令行参数；没有实例在听时返回 Err。
/// Windows 走 WM_COPYDATA 直发首实例的隐藏消息窗口（与 GUI 第二实例同一条
/// 通路，服务端零改动）；POSIX 走 AF_UNIX 套接字。
pub fn wake(app_id : String, args : Array[String]) -> Result[Unit, String] {
  let frame = encode_args(args)
  if frame.length() > PAYLOAD_CAP {
    return Err("命令行帧超出 \{PAYLOAD_CAP} 字节上限")
  }
  if inst_is_windows() == 1 {
    match
      inst_wake_win_raw(
        @utf8.encode(instance_slug(app_id)),
        frame,
        frame.length(),
      ) {
      r if r > 0 => Ok(())
      -1 => Err("找不到首实例窗口（应用未运行？）")
      _ => Err("win32 errno=\{inst_last_errno()}")
    }
  } else {
    let sock = socket_path(app_id)
    match inst_wake_raw(@utf8.encode(sock), frame, frame.length()) {
      r if r > 0 => Ok(())
      -1 => Err("连不上套接字 " + sock + "（应用未运行？）")
      _ => Err("socket errno=\{inst_last_errno()}")
    }
  }
}
