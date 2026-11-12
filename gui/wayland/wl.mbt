// Wayland 协议客户端（自写线路；P3 地基）。
//
// 消息格式（wayland.dtd 口径）：
//   - object_id: u32（`wl_display` 恒 1；客户端自建对象从 2 起编号）
//   - size<<16 | opcode: u32（size 含 8 字节头）
//   - 参数：int/uint/fd 定长小端；string = u32 长度 + 字节 + NUL，整消息补到
//     4 对齐；new_id 也是 u32（客户端侧在消息体里给）
//
// 异步语义：请求发出去不等应答；唯一的往返屏障是 `wl_display.sync` 的
// `callback.done`——枚举 registry 的 global 就靠「发 sync → 读到 done 为止」
// 这段窗口collect 事件。
//
// 本文件只到「连上 + registry 握手 + 枚举全局」：wlr-data-control /
// wlr-foreign-toplevel / wlr-output-management / wlr-gamma-control /
// ext-idle-notify 的协议客户踩这层地基建，本批不含（fd 传递 SCM_RIGHTS 与
// 各协议的 new_id/事件表随各自落地批补）。

///|
/// 一个 registry global（name 是 compositor 侧序号，interface/version 是
/// 协议面；绑定要 name）。
pub(all) struct WlGlobal {
  name : Int32
  iface : String
  version : Int32
}

///|
/// 显示服务器 socket 路径：`$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY`（后者缺省
/// `wayland-0`）。取不到返回 None（没有 Wayland 会话）。
pub fn wl_socket_path() -> String? {
  match @env.get_env_var("WAYLAND_DISPLAY") {
    Some(d) =>
      // 绝对路径形态（少数合成器给）直接用；否则拼 XDG_RUNTIME_DIR
      if d.has_prefix("/") {
        Some(d)
      } else {
        match @env.get_env_var("XDG_RUNTIME_DIR") {
          Some(dir) => Some(dir + "/" + d)
          None => None
        }
      }
    None =>
      match @env.get_env_var("XDG_RUNTIME_DIR") {
        Some(dir) => Some(dir + "/wayland-0")
        None => None
      }
  }
}

// ---------------------------------------------------------------------------
// FFI（桩：wayland_stub.c）
// ---------------------------------------------------------------------------

///|
#borrow(path)
extern "c" fn ffi_wl_connect(path : Bytes) -> Int32 = "yue_wl_unix_connect"

///|
#borrow(buf)
extern "c" fn ffi_wl_read(
  fd : Int32,
  buf : Bytes,
  off : Int32,
  len : Int32,
) -> Int32 = "yue_wl_read"

///|
#borrow(buf)
extern "c" fn ffi_wl_write(
  fd : Int32,
  buf : Bytes,
  off : Int32,
  len : Int32,
) -> Int32 = "yue_wl_write"

///|
extern "c" fn ffi_wl_poll(
  fd : Int32,
  events : Int32,
  timeout_ms : Int32,
) -> Int32 = "yue_wl_poll"

///|
extern "c" fn ffi_wl_close(fd : Int32) -> Unit = "yue_wl_close"

///|
/// 连显示服务器（成功回 fd；调用方用完 `wl_close`）。没有 Wayland 会话 /
/// 平台不支持给 Err。
pub fn wl_connect() -> Result[Int32, String] {
  match wl_socket_path() {
    None =>
      Err(
        "没有 Wayland 会话（WAYLAND_DISPLAY / XDG_RUNTIME_DIR 未设置）",
      )
    Some(p) => {
      let fd = ffi_wl_connect(@utf8.encode(p))
      if fd < 0 {
        Err("连不上 Wayland socket: \{p}")
      } else {
        Ok(fd)
      }
    }
  }
}

///|
/// 关连接（幂等）。
pub fn wl_close(fd : Int32) -> Unit {
  ffi_wl_close(fd)
}

// ---------------------------------------------------------------------------
// 线编码（纯函数；单测钉住）
// ---------------------------------------------------------------------------

///|
/// 消息头 + 参数体拼装（object_id, opcode, 参数字节）→ 完整消息字节。
/// size 字段由本函数算（含 8 字节头）。
pub fn wl_msg(object_id : Int32, opcode : Int32, body : Bytes) -> Bytes {
  let total = 8 + body.length()
  let out : FixedArray[Byte] = FixedArray::make(total, b'\x00')
  // object_id: u32 小端
  out[0] = (object_id & 0xFF).to_byte()
  out[1] = ((object_id >> 8) & 0xFF).to_byte()
  out[2] = ((object_id >> 16) & 0xFF).to_byte()
  out[3] = ((object_id >> 24) & 0xFF).to_byte()
  // size<<16 | opcode
  let so = (total << 16) | (opcode & 0xFFFF)
  out[4] = (so & 0xFF).to_byte()
  out[5] = ((so >> 8) & 0xFF).to_byte()
  out[6] = ((so >> 16) & 0xFF).to_byte()
  out[7] = ((so >> 24) & 0xFF).to_byte()
  for i in 0..<body.length() {
    out[8 + i] = body[i]
  }
  Bytes::from_array(out)
}

///|
/// u32 小端追加进参数体。
pub fn wl_put_u32(buf : FixedArray[Byte], off : Int32, v : Int32) -> Int32 {
  buf[off] = (v & 0xFF).to_byte()
  buf[off + 1] = ((v >> 8) & 0xFF).to_byte()
  buf[off + 2] = ((v >> 16) & 0xFF).to_byte()
  buf[off + 3] = ((v >> 24) & 0xFF).to_byte()
  off + 4
}

///|
/// wayland string 追加（u32 长度 + 字节 + NUL，**不含**尾部对齐——对齐在
/// 消息出口按 4 补；返回新偏移）。空串也是「长度 0 + 一个 NUL」。
pub fn wl_put_string(buf : FixedArray[Byte], off : Int32, s : String) -> Int32 {
  let b = @utf8.encode(s)
  let n = wl_put_u32(buf, off, b.length())
  for i in 0..<b.length() {
    buf[n + i] = b[i]
  }
  buf[n + b.length()] = b'\x00'
  n + b.length() + 1
}

///|
/// 消息体按 4 对齐补零（返回补齐后的长度）。
pub fn wl_pad4(len : Int32) -> Int32 {
  (len + 3) / 4 * 4
}

///|
/// 从消息字节读 u32 小端。
pub fn wl_get_u32(b : Bytes, off : Int32) -> Int32 {
  b[off].to_int() |
  (b[off + 1].to_int() << 8) |
  (b[off + 2].to_int() << 16) |
  (b[off + 3].to_int() << 24)
}

// ---------------------------------------------------------------------------
// registry 握手
// ---------------------------------------------------------------------------

///|
/// wl_display.get_registry(registry: new_id)：**opcode 1**（wl_display 的请求
/// 序是 sync=0 / get_registry=1——wayland.xml 口径，搞反过：服务端会把
/// get_registry 当 sync 建出一个 callback，registry 永远拿不到 global）。
pub fn wl_get_registry(fd : Int32, registry_id : Int32) -> Result[Unit, String] {
  let body : FixedArray[Byte] = FixedArray::make(4, b'\x00')
  let _ = wl_put_u32(body, 0, registry_id)
  wl_send(fd, wl_msg(1, 1, Bytes::from_array(body)))
}

///|
/// wl_display.sync(callback: new_id)：**opcode 0**，体是 new_id。done 事件
/// 回来才代表「此前发的请求服务端都处理完了」——枚举 global 的屏障。
pub fn wl_sync(fd : Int32, callback_id : Int32) -> Result[Unit, String] {
  let body : FixedArray[Byte] = FixedArray::make(4, b'\x00')
  let _ = wl_put_u32(body, 0, callback_id)
  wl_send(fd, wl_msg(1, 0, Bytes::from_array(body)))
}

///|
/// wl_registry.bind(name, interface, version, id: new_id)：opcode 0。
pub fn wl_bind(
  fd : Int32,
  registry_id : Int32,
  name : Int32,
  iface : String,
  version : Int32,
  new_id : Int32,
) -> Result[Unit, String] {
  let b = @utf8.encode(iface)
  // name(4) + string(4+n+1) + version(4) + new_id(4)，string 后补对齐
  let str_len = 4 + b.length() + 1
  let total = 4 + wl_pad4(str_len) + 4 + 4
  let body : FixedArray[Byte] = FixedArray::make(total, b'\x00')
  let mut o = wl_put_u32(body, 0, name)
  o = wl_put_string(body, o, iface)
  o = wl_pad4(o)
  o = wl_put_u32(body, o, version)
  let _ = wl_put_u32(body, o, new_id)
  wl_send(fd, wl_msg(registry_id, 0, Bytes::from_array(body)))
}

///|
/// 发一条消息（整段写出；写一半断了的按错误回）。
pub fn wl_send(fd : Int32, msg : Bytes) -> Result[Unit, String] {
  let mut off = 0
  while off < msg.length() {
    let n = ffi_wl_write(fd, msg, off, msg.length() - off)
    if n > 0 {
      off += n
    } else if n == -1 {
      // EAGAIN：等可写再试（给 2s 上限，别死等）
      if ffi_wl_poll(fd, 4, 2000) <= 0 {
        return Err("写 Wayland socket 超时")
      }
    } else {
      return Err("写 Wayland socket 失败（fd=\{fd}）")
    }
  }
  Ok(())
}

///|
/// 读一段可用字节追加进 acc（返回读到的字节数；0=EOF，-1=暂无，-3=错误）。
/// acc 是调用方的累积缓冲（FixedArray + 长度 Ref）——先读进临时 Bytes 再搬
/// （extern 收 Bytes，与 dbus 的 Conn 同形态）。
pub fn wl_read_into(
  fd : Int32,
  acc : FixedArray[Byte],
  acc_len : Ref[Int32],
) -> Int32 {
  if ffi_wl_poll(fd, 1, 0) <= 0 {
    return -1
  }
  let room = acc.length() - acc_len.val
  if room <= 0 {
    return -1
  }
  let tmp : Bytes = Bytes::make(room, b'\x00')
  let n = ffi_wl_read(fd, tmp, 0, room)
  if n > 0 {
    for i in 0..<n {
      acc[acc_len.val + i] = tmp[i]
    }
    acc_len.val = acc_len.val + n
  }
  n
}

///|
/// 枚举 registry 的全局对象：get_registry → sync → 读到 done 为止，其间
/// 收 global 事件（opcode 0：name u32 + interface string + version u32）。
/// global_remove（opcode 1）忽略——枚举是一次性快照。
pub fn wl_globals(fd : Int32) -> Result[Array[WlGlobal], String] {
  let reg_id = 2
  let cb_id = 3
  let _ = wl_get_registry(fd, reg_id)
  let _ = wl_sync(fd, cb_id)
  let out : Array[WlGlobal] = []
  let acc : FixedArray[Byte] = FixedArray::make(4096, b'\x00')
  let acc_len = Ref(0)
  let mut done = false
  let mut spins = 0
  while !done && spins < 2000 {
    spins += 1
    let n = wl_read_into(fd, acc, acc_len)
    if n == 0 {
      return Err("Wayland 连接被对端关闭")
    }
    if n < 0 {
      continue
    }
    // 把 acc 里的完整消息逐条吃掉
    let mut consumed = 0
    while acc_len.val - consumed >= 8 {
      let obj = wl_get_u32(Bytes::from_array(acc), consumed)
      let so = wl_get_u32(Bytes::from_array(acc), consumed + 4)
      let size = so >> 16
      let opcode = so & 0xFFFF
      if size < 8 || acc_len.val - consumed < size {
        break // 消息还没收全
      }
      let msg : Bytes = Bytes::from_array(acc)[consumed:consumed + size].to_owned()
      if obj == cb_id && opcode == 0 {
        done = true // callback.done
      } else if obj == reg_id && opcode == 0 {
        // global(name u32, interface string, version u32)
        match wl_parse_global(msg) {
          Some(g) => out.push(g)
          None => ()
        }
      }
      consumed += size
    }
    // 剩余字节搬到缓冲头
    if consumed > 0 {
      let rest = acc_len.val - consumed
      for i in 0..<rest {
        acc[i] = acc[consumed + i]
      }
      acc_len.val = rest
    }
  }
  if !done {
    return Err("等 wl_display.sync 的 done 超时")
  }
  Ok(out)
}

///|
/// 解 global 事件体（跳过 8 字节头）：name u32 + string + version u32。
pub fn wl_parse_global(msg : Bytes) -> WlGlobal? {
  // 头 8 + name 4 + string 长度 4 = 16 字节才够读前两个字段
  if msg.length() < 16 {
    return None
  }
  let name = wl_get_u32(msg, 8)
  let slen = wl_get_u32(msg, 12)
  // 字符串字节 + NUL 必须在消息里（越界/畸形一律拒，不猜）
  if slen < 0 || 16 + slen + 1 > msg.length() {
    return None
  }
  // wayland 的 string 长度**含结尾 NUL**（实物核过）：名字去掉尾部 NUL，
  // 下一个字段从 pad4(16 + slen) 起
  let raw = @utf8.decode_lossy(msg[16:16 + slen])
  let iface = if raw.has_suffix("\u{0}") {
    raw[0:raw.length() - 1].to_owned()
  } else {
    raw
  }
  let voff = wl_pad4(16 + slen)
  if voff + 4 > msg.length() {
    return None
  }
  let version = wl_get_u32(msg, voff)
  Some({ name, iface, version, })
}

///|
///  Compositor 在不在（能不能连上 + 过完 registry 握手）。没有 Wayland 会话
/// 的机器（X11/Windows/macOS）恒 false。
pub fn wl_display_available() -> Bool {
  match wl_connect() {
    Err(_) => false
    Ok(fd) =>
      match wl_globals(fd) {
        Ok(_) => {
          wl_close(fd)
          true
        }
        Err(_) => {
          wl_close(fd)
          false
        }
      }
  }
}
