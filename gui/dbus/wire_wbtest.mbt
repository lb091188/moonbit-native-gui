// DBus 线路编解码的单元测试：签名解析、消息往返、嵌套结构对齐。

///|
test "签名解析" {
  match parse_signature("a(iiay)") {
    Ok(nodes) => assert_eq(sig_char(nodes[0]), "a(iiay)")
    Err(_) => assert_true(false) // 走到错误分支：a(iiay) 应可解析
  }
  match parse_signature("a{sv}") {
    Ok(nodes) => assert_eq(sig_char(nodes[0]), "a{sv}")
    Err(_) => assert_true(false) // 走到错误分支：a{sv} 应可解析
  }
  match parse_signature("(sa(iiay)ss)") {
    Ok(nodes) => assert_eq(sig_char(nodes[0]), "(sa(iiay)ss)")
    Err(_) => assert_true(false) // 走到错误分支：复合签名应可解析
  }
  assert_true(parse_signature("a") is Err(_))
  assert_true(parse_signature("z") is Err(_))
  assert_true(parse_signature("{s") is Err(_))
}

///|
test "消息往返：方法调用" {
  match
    build_call(
      7,
      "org.example.Dest",
      "/obj/path",
      "org.if.Iface",
      "Member",
      "s",
      [VString("hello")],
    ) {
    Ok(bytes) =>
      match parse_message(bytes[:]) {
        Some(msg) => {
          assert_eq(msg.kind, 1)
          assert_eq(msg.serial, 7)
          assert_eq(msg.path, "/obj/path")
          assert_eq(msg.iface, "org.if.Iface")
          assert_eq(msg.action, "Member")
          assert_eq(msg.sig, "s")
          assert_true(msg.body[0] is VString("hello"))
        }
        None => assert_true(false) // 走到错误分支：应可解析
      }
    Err(_) => assert_true(false) // 走到错误分支：应可构造
  }
}

///|
test "消息往返：空体信号" {
  match
    build_signal(
      3,
      "/StatusNotifierItem",
      "org.kde.StatusNotifierItem",
      "NewIcon",
      "",
      [],
    ) {
    Ok(bytes) =>
      match parse_message(bytes[:]) {
        Some(msg) => {
          assert_eq(msg.kind, 4)
          assert_eq(msg.path, "/StatusNotifierItem")
          assert_eq(msg.action, "NewIcon")
          assert_eq(msg.body.length(), 0)
          assert_eq(msg.sig, "")
        }
        None => assert_true(false) // 走到错误分支：应可解析
      }
    Err(_) => assert_true(false) // 走到错误分支：应可构造
  }
}

///|
test "消息往返：'d' 顶层双精度" {
  match build_reply(1, 3, ":1.3", "d", [VDouble(-0.15625)]) {
    Ok(bytes) =>
      match parse_message(bytes[:]) {
        Some(m) =>
          match m.body[0] {
            VDouble(v) => assert_eq(v.to_string(), "-0.15625")
            _ => assert_true(false) // 走到错误分支：VDouble
          }
        None => assert_true(false) // 走到错误分支：应可解析
      }
    Err(_) => assert_true(false) // 走到错误分支：应可构造
  }
}

///|
test "消息往返：a{sv} 内含 Percentage(d) 的 UPower GetAll 真实形状" {
  let dict = VArray("{sv}", [
    VStruct([VString("IsPresent"), VVariant(VBool(true))]),
    VStruct([VString("Percentage"), VVariant(VDouble(87.5))]),
    VStruct([VString("State"), VVariant(VU32(2))]),
    VStruct([VString("TimeToEmpty"), VVariant(VI64(5400L))]),
  ])
  match build_reply(1, 9, ":1.9", "a{sv}", [dict]) {
    Ok(bytes) =>
      match parse_message(bytes[:]) {
        Some(m) =>
          match m.body[0] {
            VArray(_, entries) => {
              assert_eq(entries.length(), 4)
              match entries[1] {
                VStruct([VString(name), VVariant(VDouble(v))]) => {
                  assert_eq(name, "Percentage")
                  assert_eq(v.to_string(), "87.5")
                }
                _ =>
                  assert_true(false) // 走到错误分支：VStruct[VString, VVariant[VDouble]]
              }
              match entries[3] {
                VStruct([VString(name), VVariant(VI64(t))]) => {
                  assert_eq(name, "TimeToEmpty")
                  assert_eq(t.to_string(), "5400")
                }
                _ =>
                  assert_true(false) // 走到错误分支：VStruct[VString, VVariant[VI64]]
              }
            }
            _ => assert_true(false) // 走到错误分支：VArray
          }
        None => assert_true(false) // 走到错误分支：应可解析
      }
    Err(_) => assert_true(false) // 走到错误分支：应可构造
  }
}

///|
test "消息往返：a{sv} 属性字典" {
  let dict = VArray("{sv}", [
    VStruct([VString("Id"), VVariant(VString("demo"))]),
    VStruct([VString("ItemIsMenu"), VVariant(VBool(true))]),
  ])
  match build_reply(1, 2, ":1.5", "a{sv}", [dict]) {
    Ok(bytes) =>
      match parse_message(bytes[:]) {
        Some(m) => {
          assert_eq(m.kind, 2)
          assert_eq(m.reply_serial, 2)
          assert_eq(m.body.length(), 1)
          match m.body[0] {
            VArray(_, entries) => {
              assert_eq(entries.length(), 2)
              match entries[0] {
                VStruct([VString(name), VVariant(VString(value))]) => {
                  assert_eq(name, "Id")
                  assert_eq(value, "demo")
                }
                _ =>
                  assert_true(false) // 走到错误分支：VStruct[VString, VVariant]
              }
              match entries[1] {
                VStruct([VString(name), VVariant(VBool(b))]) => {
                  assert_eq(name, "ItemIsMenu")
                  assert_true(b)
                }
                _ =>
                  assert_true(false) // 走到错误分支：VStruct[VString, VVariant]
              }
            }
            _ => assert_true(false) // 走到错误分支：VArray
          }
        }
        None => assert_true(false) // 走到错误分支：应可解析
      }
    Err(_) => assert_true(false) // 走到错误分支：应可构造
  }
}

///|
test "消息往返：IconPixmap 嵌套结构 (iiay)" {
  let px = VStruct([
    VI32(2),
    VI32(1),
    VArray("y", [VByte(255), VByte(0), VByte(16), VByte(32)]),
  ])
  match build_reply(1, 1, ":1.1", "(iiay)", [px]) {
    Ok(bytes) =>
      match parse_message(bytes[:]) {
        Some(m) =>
          match m.body[0] {
            VStruct([VI32(w), VI32(h), VArray(_, pixels)]) => {
              assert_eq(w, 2)
              assert_eq(h, 1)
              assert_eq(pixels.length(), 4)
              assert_true(pixels[3] is VByte(32))
            }
            _ => assert_true(false) // 走到错误分支：VStruct[VI32, VI32, VArray]
          }
        None => assert_true(false) // 走到错误分支：应可解析
      }
    Err(_) => assert_true(false) // 走到错误分支：应可构造
  }
}

///|
test "消息往返：ToolTip (sa(iiay)ss)" {
  let tip = VStruct([
    VString(""),
    VArray("(iiay)", []),
    VString("标题"),
    VString("内容"),
  ])
  match build_reply(1, 1, ":1.1", "(sa(iiay)ss)", [tip]) {
    Ok(bytes) =>
      match parse_message(bytes[:]) {
        Some(m) =>
          match m.body[0] {
            VStruct([VString(a), VArray(_, n), VString(t), VString(b)]) => {
              assert_eq(a, "")
              assert_eq(n.length(), 0)
              assert_eq(t, "标题")
              assert_eq(b, "内容")
            }
            _ => assert_true(false) // 走到错误分支：ToolTip
          }
        None => assert_true(false) // 走到错误分支：应可解析
      }
    Err(_) => assert_true(false) // 走到错误分支：应可构造
  }
}

///|
test "畸形与截断输入" {
  assert_true(parse_message(Bytes::make(0, 0)[:]) is None)
  assert_true(parse_message(Bytes::make(5, 0)[:]) is None)
  // 首字节非小端标记应被拒绝
  assert_true(parse_message(Bytes::make(16, 0)[:]) is None)
}

///|
test "DBusMenu GetLayout 应答构造" {
  let entries : Array[DVal] = [
    VStruct([
      VI32(1),
      VArray("{sv}", [
        VStruct([VString("label"), VVariant(VString("退出"))]),
        VStruct([VString("enabled"), VVariant(VBool(true))]),
        VStruct([VString("visible"), VVariant(VBool(true))]),
      ]),
      VArray("v", []),
    ]),
  ]
  let root = VStruct([
    VI32(0),
    VArray("{sv}", [
      VStruct([VString("children-display"), VVariant(VString("submenu"))]),
    ]),
    VArray("v", [VVariant(entries[0])]),
  ])
  match
    build_reply(1, 2, ":1.32", "(u(ia{sv}av))", [VStruct([VU32(3), root])]) {
    Ok(bytes) => {
      assert_true(bytes.length() > 40)
      assert_true(parse_message(bytes[:]) is Some(_))
    }
    Err(_) => assert_true(false) // 走到错误分支：应可构造
  }
}

///|
test "scratch3: GetLayout 应答字节" {
  let input = VStruct([
    VI32(1),
    VArray("{sv}", [
      VStruct([VString("label"), VVariant(VString("退出"))]),
      VStruct([VString("enabled"), VVariant(VBool(true))]),
      VStruct([VString("visible"), VVariant(VBool(true))]),
    ]),
    VArray("v", []),
  ])
  let root = VStruct([
    VI32(0),
    VArray("{sv}", [
      VStruct([VString("children-display"), VVariant(VString("submenu"))]),
    ]),
    VArray("v", [VVariant(input)]),
  ])
  match
    build_reply(1, 2, ":1.32", "(u(ia{sv}av))", [VStruct([VU32(3), root])]) {
    Ok(bytes) => {
      let sb = StringBuilder()
      for i in 0..<bytes.length() {
        let b = bytes[i].to_int()
        let hi = b >> 4
        let lo = b & 15
        sb.write_char(
          if hi < 10 {
            (48 + hi).unsafe_to_char()
          } else {
            (87 + hi).unsafe_to_char()
          },
        )
        sb.write_char(
          if lo < 10 {
            (48 + lo).unsafe_to_char()
          } else {
            (87 + lo).unsafe_to_char()
          },
        )
      }
      println(sb.to_string())
      // 体前 24 字节按 u32 打印
      for k in 0..<6 {
        let off = 64 + k * 4
        let v = bytes[off].to_int() |
          (bytes[off + 1].to_int() << 8) |
          (bytes[off + 2].to_int() << 16) |
          (bytes[off + 3].to_int() << 24)
        println("body[\{k}] @\{off} = \{v}")
      }
    }
    Err(e) => println("err \{e}")
  }
}

///|
test "线路字符串恒为合法 UTF-8" {
  // 中文 + 间隔号 + emoji：配对完整的代理对合成 4 字节序列，不被当成非法值
  let ok = utf8("libyue 演示板 · 🎉")
  assert_eq(ok.length(), 24)
  let emoji = utf8("🎉")
  assert_eq(emoji[0].to_int(), 0xF0)
  assert_eq(emoji[1].to_int(), 0x9F)
  assert_eq(emoji[2].to_int(), 0x8E)
  assert_eq(emoji[3].to_int(), 0x89)
  // 未配对的半截代理对：@utf8.encode 遇到它直接 abort（进程当场终止，托盘注销
  // 都来不及发）。线路出口先换成 U+FFFD，交给总线的字节恒为合法 UTF-8。
  let lone = String::from_array(['x', (0xD83D).unsafe_to_char(), 'y'])
  let fixed = utf8(lone)
  assert_eq(fixed.length(), 5)
  assert_eq(fixed[0].to_int(), 120)
  assert_eq(fixed[1].to_int(), 0xEF)
  assert_eq(fixed[2].to_int(), 0xBF)
  assert_eq(fixed[3].to_int(), 0xBD)
  assert_eq(fixed[4].to_int(), 121)
  // 走一遍真实字段编码：u32 长度按替换后的字节数计
  let buf = Buf::new()
  buf.string(lone)
  assert_eq(buf.len(), 4 + 5 + 1)
}
