// inspector 客户端：`call(app_id, req)` 连应用内的检查服务、发一行命令、
// 收一段 TSV 响应。与服务端（gui/inspector/stub.c 的 yi_insp_* 族）逐端
// 对配：POSIX 走 AF_UNIX 套接字（写完 shutdown 判请求完、读到 EOF 判响应完），
// Windows 走命名管道（长度前缀帧）。路径规则同单实例客户端 inst：
// `$XDG_RUNTIME_DIR` → `$TMPDIR` → `/tmp`，文件名 `moonbit-inspect-<slug>.<uid>.sock`。

///|
/// 请求单行上限（与服务端一致）。
pub const REQUEST_CAP : Int32 = 4096

///|
/// 响应上限（与服务端一致，256KB）。
pub const RESPONSE_CAP : Int32 = 262144

///|
/// 套接字文件名的 sun_path 安全长度（macOS sun_path 容量 104，留足余量）。
const INSP_PATH_LIMIT : Int32 = 100

///|
#borrow(path, slug, req, out)
extern "c" fn mnginsp_call(
  path : Bytes,
  slug : Bytes,
  req : Bytes,
  req_len : Int32,
  out : Bytes,
  cap : Int32,
  timeout_ms : Int32,
) -> Int32 = "mnginsp_call"

///|
extern "c" fn mnginsp_getuid() -> Int32 = "mnginsp_getuid"

///|
/// app_id 的 djb2 哈希，十六进制定长 8 位（与单实例 slug 同规）。
fn insp_hash8(s : String) -> String {
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
/// app_id → slug：非 [A-Za-z0-9_-] 换下划线；超 40 截断并附内容哈希。
pub fn insp_slug(app_id : String) -> String {
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
  if s.length() <= 40 {
    s
  } else {
    s[:40].to_owned() + "-" + insp_hash8(app_id)
  }
}

///|
/// 套接字文件所在目录：`$XDG_RUNTIME_DIR` → `$TMPDIR` → `/tmp`。
fn insp_socket_dir() -> String {
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
/// 服务端套接字路径（与应用侧 `@inspector.inspect_socket_path` 同规则）。
pub fn insp_socket_path(app_id : String) -> String {
  let dir = insp_socket_dir()
  let base = "moonbit-inspect-"
  let tail = ".\{mnginsp_getuid()}.sock"
  let budget = INSP_PATH_LIMIT -
    dir.length() -
    1 -
    base.length() -
    tail.length()
  let slug = insp_slug(app_id)
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
/// 发一条命令、收完整响应（一次性连接）。`Err` 给可读原因。
pub fn call(
  app_id : String,
  req : String,
  timeout_ms~ : Int32 = 5000,
) -> Result[String, String] {
  let frame = @utf8.encode(req)
  if frame.length() > REQUEST_CAP {
    return Err("请求超出 \{REQUEST_CAP} 字节上限")
  }
  let out = Bytes::make(RESPONSE_CAP, 0)
  let n = mnginsp_call(
    @utf8.encode(insp_socket_path(app_id)),
    @utf8.encode(insp_slug(app_id)),
    frame,
    frame.length(),
    out,
    RESPONSE_CAP,
    timeout_ms,
  )
  if n < 0 {
    Err("连不上检查通道（应用没起或未注入 MNG_INSPECT=1）errno=\{-n}")
  } else {
    Ok(@utf8.decode_lossy(out[0:n].to_owned()))
  }
}
