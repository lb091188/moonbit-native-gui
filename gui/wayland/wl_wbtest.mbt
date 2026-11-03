// Wayland 线路客户端回归：线编码纯函数 + 真合成器集成（无 Wayland 会话跳过）。

///|
test "wl：消息头编码（size<<16 | opcode，含 8 字节头）" {
  let body : FixedArray[Byte] = FixedArray::make(4, b'\x00')
  let _ = wl_put_u32(body, 0, 2)
  let msg = wl_msg(1, 1, Bytes::from_array(body))
  assert_eq(msg.length(), 12)
  // object_id = 1
  assert_eq(wl_get_u32(msg, 0), 1)
  // size<<16 | opcode = 12<<16 | 1
  assert_eq(wl_get_u32(msg, 4), (12 << 16) | 1)
  // 体：new_id = 2
  assert_eq(wl_get_u32(msg, 8), 2)
}

///|
test "wl：string 编码（长度 + 字节 + NUL）与 pad4" {
  let b = @utf8.encode("wl_compositor")
  let body : FixedArray[Byte] = FixedArray::make(32, b'\x00')
  let o = wl_put_string(body, 0, "wl_compositor")
  // 4 长度 + 13 字节 + NUL = 18（不含对齐）
  assert_eq(o, 4 + b.length() + 1)
  assert_eq(wl_get_u32(Bytes::from_array(body), 0), b.length())
  assert_eq(body[4 + b.length()], b'\x00')
  // pad4：18 → 20
  assert_eq(wl_pad4(18), 20)
  assert_eq(wl_pad4(16), 16)
  assert_eq(wl_pad4(0), 0)
}

///|
test "wl：global 事件解析（名字去尾 NUL、版本在 pad4 后）" {
  // 手工拼一条 global(name=7, "wl_shm", version=1) 事件（头 8 + name 4 +
  // strlen 4 + 6 字节 + NUL + pad2 + version 4 = 28 → size 28）
  let total = 8 + 4 + 4 + 6 + 1 + 2 + 4
  let buf : FixedArray[Byte] = FixedArray::make(total, b'\x00')
  let mut o = wl_put_u32(buf, 0, 2) // object_id = registry
  o = wl_put_u32(buf, o, (total << 16) | 0) // size<<16 | opcode 0
  o = wl_put_u32(buf, o, 7) // name
  o = wl_put_string(buf, o, "wl_shm") // strlen 含 NUL 口径由发送方决定
  o = wl_pad4(o)
  let _ = wl_put_u32(buf, o, 1) // version
  let msg = Bytes::from_array(buf)
  match wl_parse_global(msg) {
    None => fail("global 解析失败")
    Some(g) => {
      assert_eq(g.name, 7)
      assert_eq(g.iface, "wl_shm")
      assert_eq(g.version, 1)
    }
  }
  // 短消息一律拒（不猜）
  assert_true(wl_parse_global(Bytes::make(8, b'\x00')) is None)
}

///|
test "wl：socket 路径推导（WAYLAND_DISPLAY 绝对路径/相对/缺省）" {
  // 环境相关的三档只验证「不为空即合理」：CI 无 Wayland 会话给 None，
  // 有会话给 $XDG_RUNTIME_DIR/<display> 或绝对路径
  match wl_socket_path() {
    None => ()
    Some(p) => assert_true(p.length() > 0, msg="socket 路径为空串")
  }
}

///|
test "wl：真合成器集成（无 Wayland 会话跳过）" {
  match wl_socket_path() {
    None => println("wl: skip（无 Wayland 会话）")
    Some(_) =>
      match wl_display_available() {
        false => println("wl: skip（连不上显示服务器）")
        true =>
          match wl_connect() {
            Err(e) => fail("wl_display_available 真但连不上: \{e}")
            Ok(fd) =>
              match wl_globals(fd) {
                Err(e) => {
                  wl_close(fd)
                  fail("registry 握手失败: \{e}")
                }
                Ok(gs) => {
                  wl_close(fd)
                  println("wl: \{gs.length()} 个 global")
                  // wl_compositor 是每个合规合成器都有的（version ≥ 1）
                  let mut has_compositor = false
                  for g in gs {
                    if g.iface == "wl_compositor" && g.version >= 1 {
                      has_compositor = true
                    }
                  }
                  assert_true(
                    has_compositor,
                    msg="合成器没广告 wl_compositor（registry 枚举漏了？）",
                  )
                }
              }
          }
      }
  }
}
