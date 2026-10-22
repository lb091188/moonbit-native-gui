// 单实例门面（防多开 + 二次启动唤起已有实例）：三平台同一个 API，平台差异
// 收敛在后端选择里。
//
// 后端选择（按平台探测出的顺序逐个试，某个臂答「已有实例」就停在那一档）：
// 1. Windows：`win` 的命名互斥体 + 隐藏顶层窗（WM_COPYDATA 送命令行帧）。
// 2. Linux：优先 D-Bus 会话总线的知名名声称（`dbus/instance.mbt`）；连不上
//    会话总线（headless、无 dbus 的桌面）时回落到第 3 档。
// 3. macOS 与 Linux 回落档：AF_UNIX 套接字（`shell_stub.c`），套接字文件既当
//    「谁在先」的判据，也当唤起通道。
//
// 用法（三步）：起进程时 `instance_claim(app_id)`，非首实例就 `instance_wake`
// 后自行退出；首实例调 `on_instance_wake` 挂回调，宿主每拍调
// `dispatch_instance_wake`。`app_id` 用反向域名（如 `com.example.app`），
// 三平台都按同一套字法规格校验。

///|
/// 单实例后端。
pub(all) enum InstanceBackend {
  /// D-Bus 知名名声称（Linux）
  Dbus
  /// 命名互斥体 + 隐藏窗口（Windows）
  Win32
  /// AF_UNIX 套接字（macOS，以及 Linux 无会话总线时的回落档）
  Socket
  /// 本平台没有可用后端
  Unavailable
}

///|
/// 声称结果。
pub(all) enum InstanceClaim {
  /// 本进程是首实例，窗口照常开
  Primary
  /// 已有首实例在跑，应当唤起它并退出
  Existing
}

///|
/// 单实例错误。
pub(all) enum InstanceError {
  /// app_id 不合字法规格（要 ≥2 个点分元素、每元素 [A-Za-z0-9_-] 且不以数字开头）
  InvalidAppId(String)
  /// 没找到可唤起的首实例（名字没被占用过，或对面窗口已消失）
  NoInstance
  /// 后端失败原因（总线报错 / 操作系统错误码）
  Backend(String)
  /// 本平台没有可用后端
  Unsupported
}

///|
pub impl Show for InstanceError with fn output(self, logger) {
  match self {
    InvalidAppId(id) => logger.write_string("InvalidAppId(\{id})")
    NoInstance => logger.write_string("NoInstance")
    Backend(m) => logger.write_string("Backend(\{m})")
    Unsupported => logger.write_string("Unsupported")
  }
}

///|
pub extend InstanceError with Show::{to_string, output}

///|
/// 单帧载荷上限（字节），与 C 侧缓冲同值。
pub const INSTANCE_PAYLOAD_CAP : Int = 65536

///|
/// 套接字文件名的 sun_path 安全长度（macOS 的 sun_path 容量 104，留足余量）。
const SOCKET_PATH_LIMIT : Int = 100

///|
/// slug 里 app_id 原样保留的最大长度；超出就截断并附内容哈希，保证同一
/// app_id 每次派生出同一个名字。
const SLUG_KEEP : Int = 40

// ---- 原生口：AF_UNIX 套接字臂（shell_stub.c，Windows 侧是失败桩）----

///|
#borrow(path)
extern "c" fn yi_inst_listen(path : Bytes) -> Int = "yi_inst_listen"

///|
#borrow(path, data)
extern "c" fn yi_inst_wake(
  path : Bytes,
  data : Bytes,
  len : Int,
) -> Int = "yi_inst_wake"

///|
extern "c" fn yi_inst_poll() -> Int = "yi_inst_poll"

///|
#borrow(out)
extern "c" fn yi_inst_take(out : Bytes, cap : Int) -> Int = "yi_inst_take"

///|
extern "c" fn yi_inst_last_errno() -> Int = "yi_inst_last_errno"

///|
extern "c" fn yi_inst_getuid() -> Int = "yi_inst_getuid"

// ---- 进程级状态 ----

///|
/// 本进程已声称的 app_id → 所用的臂。
let g_arms : Ref[Map[String, InstanceBackend]] = Ref(Map([]))

///|
/// 唤起回调（各臂收到帧后都汇到这里）。
let g_on_wake : Ref[((Array[String]) -> Unit)?] = Ref(None)

///|
/// 本进程派发过的唤起条数（诊断与测试用）。
let g_wake_count : Ref[Int] = Ref(0)

// ---- 派生与编解码（纯函数）----

///|
/// app_id 的 djb2 哈希，十六进制定长 8 位。
fn instance_hash8(s : String) -> String {
  let mut h : Int = 5381
  for i = 0; i < s.length(); i = i + 1 {
    h = ((h << 5) + h + s.unsafe_get(i).to_int()) & 0x7FFF_FFFF
  }
  let digits : Array[String] = [
    "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "a", "b", "c", "d", "e",
    "f",
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
/// app_id → 原生侧用的名字：点与非 [A-Za-z0-9_-] 字符换下划线；超过
/// `SLUG_KEEP` 的取前缀加内容哈希（同 app_id 恒得同 slug）。
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
/// 套接字文件所在目录：`$XDG_RUNTIME_DIR`（Linux 每用户私有）→
/// `$TMPDIR`（macOS 每用户私有）→ `/tmp`。
fn instance_socket_dir() -> String {
  match @sys.sys_getenv("XDG_RUNTIME_DIR") {
    Some(d) if d != "" => d
    _ =>
      match @sys.sys_getenv("TMPDIR") {
        Some(t) if t != "" => t
        _ => "/tmp"
      }
  }
}

///|
/// AF_UNIX 套接字文件路径：目录 + `moonbit-instance-<slug>.<uid>.sock`。
/// 文件名带 uid，共用 `/tmp` 时不同用户互不认领；slug 按剩余预算截断，
/// 保证整条路径不撞 sun_path 上限。
pub fn instance_socket_path(app_id : String) -> String {
  instance_socket_path_in(instance_socket_dir(), app_id)
}

///|
/// 同上，目录由调用方给（便于覆盖长名截断的行为）。
fn instance_socket_path_in(dir : String, app_id : String) -> String {
  let base = "moonbit-instance-"
  let tail = ".\{yi_inst_getuid()}.sock"
  let budget = SOCKET_PATH_LIMIT - dir.length() - 1 - base.length() - tail.length()
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
/// 命令行参数 → 线帧 `[argc:i32 LE]([len:i32 LE][utf8])*`。
/// 两臂都按这条帧原样搬运，C 侧不解析。
pub fn instance_encode_args(args : Array[String]) -> Bytes {
  let parts : Array[Bytes] = args.map(fn(s){ @utf8.encode(s) })
  let mut total = 4
  for p in parts {
    total = total + 4 + p.length()
  }
  let buf = FixedArray::make(total, b'\x00')
  let mut o = 0
  let write_i32 = fn(v : Int, at : Int) -> Int {
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
/// 读 `[o,o+4)` 的小端 int32。
fn instance_read_i32(raw : Bytes, o : Int) -> Int {
  raw[o].to_int() |
    (raw[o + 1].to_int() << 8) |
    (raw[o + 2].to_int() << 16) |
    (raw[o + 3].to_int() << 24)
}

///|
/// 线帧 → 命令行参数；帧不完整、计数与长度不自洽、超出载荷上限都给 None。
pub fn instance_decode_args(raw : Bytes) -> Array[String]? {
  if raw.length() < 4 {
    return None
  }
  let argc = instance_read_i32(raw, 0)
  if argc < 0 || argc > 4096 {
    return None
  }
  let mut o = 4
  let out : Array[String] = []
  let mut left = argc
  while left > 0 {
    left = left - 1
    if o + 4 > raw.length() {
      return None
    }
    let n = instance_read_i32(raw, o)
    o = o + 4
    if n < 0 || o + n > raw.length() || raw.length() > INSTANCE_PAYLOAD_CAP {
      return None
    }
    let body = FixedArray::make(n, b'\x00')
    for i = 0; i < n; i = i + 1 {
      body[i] = raw[o + i]
    }
    out.push(@utf8.decode_lossy(Bytes::from_array(body)))
    o = o + n
  }
  Some(out)
}

// ---- 后端探测与选路 ----

///|
/// 本平台将使用的臂（不建任何资源）：Windows 用原生档，macOS 用套接字档，
/// Linux 先看会话总线连不连得上，连不上落套接字档。
pub fn instance_backend() -> InstanceBackend {
  match @sys.sys_platform() {
    "windows" =>
      if @win.inst_supported() {
        Win32
      } else {
        Unavailable
      }
    "macos" => Socket
    _ =>
      match @dbus.dbus_ensure_session() {
        Ok(_) => Dbus
        Err(_) => Socket
      }
  }
}

///|
/// 是否有可用的单实例后端。
pub fn instance_supported() -> Bool {
  match instance_backend() {
    Unavailable => false
    _ => true
  }
}

///|
/// 本平台的尝试顺序：前面的臂答「已有实例」即止，报错（那一档压根不可用）
/// 才顺延到下一档。
fn claim_order() -> Array[InstanceBackend] {
  match instance_backend() {
    Dbus => [Dbus, Socket]
    b => [b]
  }
}

///|
/// 记下本进程用哪个臂声称了这个 app_id；D-Bus 档同批把唤起桥接装好。
fn note_arm(app_id : String, be : InstanceBackend) -> Unit {
  g_arms.val.set(app_id, be)
  match be {
    Dbus => @dbus.on_wake(fn(args : Array[String]) -> Unit { fire_wake(args) })
    _ => ()
  }
}

///|
/// 后端名（状态行与诊断用）。
pub fn instance_backend_name(be : InstanceBackend) -> String {
  match be {
    Dbus => "dbus"
    Win32 => "win32"
    Socket => "socket"
    Unavailable => "none"
  }
}

// ---- 唤起收方 ----

///|
/// 一条唤起落地：计数 + 调回调（没挂回调也只计数，不报错）。
fn fire_wake(args : Array[String]) -> Unit {
  g_wake_count.val = g_wake_count.val + 1
  match g_on_wake.val {
    Some(cb) => cb(args)
    None => ()
  }
}

///|
/// 注册唤起回调（每进程一次，后注册覆盖先注册）。第二实例送来的命令行参数
/// 原样给到回调，含 argv[0]，按需取舍。
pub fn on_instance_wake(cb : (Array[String]) -> Unit) -> Unit {
  g_on_wake.val = Some(cb)
  // D-Bus 档的桥接由 dbus 侧持有，先 claim 后注册也要接得上
  let mut has_dbus = false
  for _id, be in g_arms.val {
    match be {
      Dbus => has_dbus = true
      _ => ()
    }
  }
  if has_dbus {
    @dbus.on_wake(fn(args : Array[String]) -> Unit { fire_wake(args) })
  }
}

///|
/// 本进程收到过的唤起条数（诊断与测试用）。
pub fn instance_wake_count() -> Int {
  g_wake_count.val
}

///|
/// 抽一条套接字臂的帧并派发；读到完整帧并派发给回调时给 true。
fn socket_drain() -> Bool {
  if yi_inst_poll() != 1 {
    return false
  }
  let buf = Bytes::new(INSTANCE_PAYLOAD_CAP)
  let n = yi_inst_take(buf, INSTANCE_PAYLOAD_CAP)
  if n <= 0 {
    return false
  }
  match instance_decode_args(buf[0:n].to_owned()) {
    Some(args) => {
      fire_wake(args)
      true
    }
    None => false
  }
}

///|
/// 抽一条 Win32 臂的帧并派发。
fn win32_drain() -> Bool {
  if !@win.inst_poll() {
    return false
  }
  match instance_decode_args(@win.inst_take()) {
    Some(args) => {
      fire_wake(args)
      true
    }
    None => false
  }
}

///|
/// 本进程实际用哪一档声称了这个 app_id（没声称过给 None；状态行与测试用）。
pub fn instance_arm(app_id : String) -> InstanceBackend? {
  g_arms.val.get(app_id)
}

///|
/// 宿主每拍调一次：抽走本拍到达的唤起并派发，命中给 true。
/// D-Bus 档的入站调用在 `@dbus.dbus_pump` 里直达回调，本函数在该档下就是
/// 顺带泵一次总线（托盘/通知已在泵它，多调无害）。
pub fn dispatch_instance_wake() -> Bool {
  let before = g_wake_count.val
  let mut seen_dbus = false
  for _id, be in g_arms.val {
    match be {
      Dbus =>
        if !seen_dbus {
          seen_dbus = true
          @dbus.dbus_pump()
        }
      Socket => {
        let _ = socket_drain()
      }
      Win32 => {
        let _ = win32_drain()
      }
      Unavailable => ()
    }
  }
  g_wake_count.val > before
}

// ---- 门面三条口 ----

///|
/// 声称「本 app_id 在本机只有一个实例」。
/// 同进程对同一 app_id 重复调恒给 `Ok(Primary)`（幂等）。
pub fn instance_claim(app_id : String) -> Result[InstanceClaim, InstanceError] {
  if !@dbus.valid_app_id(app_id) {
    return Err(InvalidAppId(app_id))
  }
  match g_arms.val.get(app_id) {
    Some(_) => return Ok(Primary)
    None => ()
  }
  let slug = instance_slug(app_id)
  let sock = instance_socket_path(app_id)
  let mut last = "没有可用后端"
  for be in claim_order() {
    match be {
      Dbus =>
        match @dbus.claim_name(app_id) {
          Ok(@dbus.PrimaryOwner) | Ok(@dbus.AlreadyOwner) => {
            note_arm(app_id, Dbus)
            return Ok(Primary)
          }
          Ok(@dbus.AlreadyExists) | Ok(@dbus.InQueue) => return Ok(Existing)
          Err(e) => last = "dbus: \{e}"
        }
      Win32 =>
        match @win.inst_listen(slug) {
          1 => {
            note_arm(app_id, Win32)
            return Ok(Primary)
          }
          2 => return Ok(Existing)
          _ => last = "win32: errno=\{@win.inst_last_errno()}"
        }
      Socket =>
        match yi_inst_listen(@utf8.encode(sock)) {
          1 => {
            note_arm(app_id, Socket)
            return Ok(Primary)
          }
          2 => return Ok(Existing)
          _ => last = "socket: errno=\{yi_inst_last_errno()}"
        }
      Unavailable => ()
    }
  }
  Err(Backend(last))
}

///|
/// 唤起已有实例，把第二实例的命令行参数 `args` 带过去。
/// 各档按顺序试：D-Bus 档不通（没有总线或对方不是用总线声称的）就走套接字档。
pub fn instance_wake(
  app_id : String,
  args : Array[String],
) -> Result[Unit, InstanceError] {
  if !@dbus.valid_app_id(app_id) {
    return Err(InvalidAppId(app_id))
  }
  let frame = instance_encode_args(args)
  if frame.length() > INSTANCE_PAYLOAD_CAP {
    return Err(Backend("命令行帧超出 \{INSTANCE_PAYLOAD_CAP} 字节上限"))
  }
  let slug = instance_slug(app_id)
  let sock = instance_socket_path(app_id)
  let mut last = "没有可用后端"
  for be in claim_order() {
    match be {
      Dbus =>
        match @dbus.wake_existing(app_id, args) {
          Ok(_) => return Ok(())
          Err(e) => last = "dbus: \{e}"
        }
      Win32 =>
        match @win.inst_wake(slug, frame) {
          r if r > 0 => return Ok(())
          -1 => last = "win32: 找不到首实例窗口"
          _ => last = "win32: errno=\{@win.inst_last_errno()}"
        }
      Socket =>
        match yi_inst_wake(@utf8.encode(sock), frame, frame.length()) {
          r if r > 0 => return Ok(())
          -1 => last = "socket: 连不上套接字 \{sock}"
          _ => last = "socket: errno=\{yi_inst_last_errno()}"
        }
      Unavailable => ()
    }
  }
  Err(Backend(last))
}
