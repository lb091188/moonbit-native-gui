// 单实例门面回归：app_id → 原生名字的派生、命令行帧编解码与解码防御、
// 套接字臂的同进程自环（声称 → 唤起 → 抽帧）、门面端到端（回调收到参数）。
// 真·双进程防多开归人工清单（测试文档/测试用例.md SC-0.3 与系统集成页）。

///|
test "instance_slug：点与非 [A-Za-z0-9_-] 换下划线" {
  assert_eq(instance_slug("com.example.app"), "com_example_app")
  assert_eq(
    instance_slug("io.github.lb091188.moon-launcher"),
    "io_github_lb091188_moon-launcher",
  )
  // 长 app_id：截到 SLUG_KEEP 再附内容哈希，同 id 恒得同 slug，不同 id 不撞名
  let a = instance_slug("io.moonbitlibyue.very.long.application.id.for.truncation")
  let b = instance_slug("io.moonbitlibyue.very.long.application.id.for.truncation")
  let c = instance_slug("io.moonbitlibyue.very.long.application.id.for.truncatioX")
  assert_eq(a.length(), SLUG_KEEP + 1 + 8)
  assert_eq(a, b)
  assert_true(a != c)
}

///|
test "instance_socket_path_in：目录拼接与 sun_path 预算" {
  let p = instance_socket_path_in("/tmp", "com.example.app")
  assert_true(p.has_prefix("/tmp/moonbit-instance-com_example_app."))
  assert_true(p.has_suffix(".sock"))
  assert_true(p.length() <= SOCKET_PATH_LIMIT)
  // 根目录不出现双斜杠
  assert_true(instance_socket_path_in("/", "com.example.app").has_prefix("/moonbit-"))
  // 长目录：slug 被截进预算，整条路径仍不撞 sun_path 上限
  let deep = instance_socket_path_in(
    "/var/folders/ab/cd1234567890abcdefghij0klm/T", "com.example.app",
  )
  assert_true(deep.length() <= SOCKET_PATH_LIMIT)
  assert_true(deep.has_prefix("/var/folders/ab/"))
}

///|
test "命令行帧往返：空表 / 单条 / 多条含中文与空串" {
  let cases : Array[Array[String]] = [
    [],
    ["showcase"],
    ["/bin/app", "", "第二个实例的参数 中文", "-x", "--flag=1"],
  ]
  for c in cases {
    let raw = instance_encode_args(c)
    assert_true(raw.length() >= 4)
    assert_eq(instance_decode_args(raw), Some(c))
  }
}

///|
test "命令行帧解码防御：截断与自相矛盾的计数" {
  // 空帧与不足 4 字节的帧
  assert_true(instance_decode_args(Bytes::new(0)) is None)
  assert_true(instance_decode_args(Bytes::new(3)) is None)
  // 零帧（argc=0）就是空参数表
  assert_eq(instance_decode_args(Bytes::new(4)), Some([]))
  // 砍掉末字节：条目长度凑不齐
  let two = instance_encode_args(["aa", "bb"])
  assert_true(instance_decode_args(two[:two.length() - 1].to_owned()) is None)
  // argc 字段被抬到 9，但帧里只装得下 1 条
  let one = instance_encode_args(["only"])
  let raw = FixedArray::make(one.length(), b'\x00')
  for i = 0; i < one.length(); i = i + 1 {
    raw[i] = one[i]
  }
  raw[0] = b'\x09'
  assert_true(instance_decode_args(Bytes::from_array(raw)) is None)
}

///|
test "套接字臂：同进程声称 → 唤起 → 抽帧（Windows 无此臂，跳过）" {
  if @sys.sys_platform() == "windows" {
    println("[skip] 套接字臂不在 Windows 编译")
  } else {
    let path = instance_socket_path("io.moonbitlibyue.wbtest.socket")
    let pb = @utf8.encode(path)
    // 首次声称成为首实例；同进程再声称幂等（返回码 1）
    assert_eq(yi_inst_listen(pb), 1)
    assert_eq(yi_inst_listen(pb), 1)
    let frame = instance_encode_args(["toggle", "第二个实例的参数"])
    assert_eq(yi_inst_wake(pb, frame, frame.length()), 1)
    assert_eq(yi_inst_poll(), 1)
    let buf = Bytes::new(INSTANCE_PAYLOAD_CAP)
    let n = yi_inst_take(buf, INSTANCE_PAYLOAD_CAP)
    assert_true(n > 0)
    assert_eq(
      instance_decode_args(buf[:n].to_owned()),
      Some(["toggle", "第二个实例的参数"]),
    )
    // 抽完即清
    assert_eq(yi_inst_poll(), 0)
  }
}

///|
test "套接字臂：判活的空连接不能占死待抽槽（Windows 无此臂，跳过）" {
  if @sys.sys_platform() == "windows" {
    println("[skip] 套接字臂不在 Windows 编译")
  } else {
    let pb = @utf8.encode(instance_socket_path("io.moonbitlibyue.wbtest.empty"))
    assert_eq(yi_inst_listen(pb), 1)
    // 第二进程判活就是「连一下就走」：写零字节再关，收端读到 EOF 但帧长 0
    assert_eq(yi_inst_wake(pb, Bytes::new(1), 0), 1)
    assert_eq(yi_inst_poll(), 0)
    // 真帧紧随其后：空连接若占了待抽槽，这里就永远读不到东西
    let frame = instance_encode_args(["toggle"])
    assert_eq(yi_inst_wake(pb, frame, frame.length()), 1)
    assert_eq(yi_inst_poll(), 1)
    let buf = Bytes::new(INSTANCE_PAYLOAD_CAP)
    let n = yi_inst_take(buf, INSTANCE_PAYLOAD_CAP)
    assert_eq(instance_decode_args(buf[:n].to_owned()), Some(["toggle"]))
  }
}

///|
test "门面端到端：声称 → 唤起 → 回调收到参数" {
  let id = "io.moonbitlibyue.wbtest.facade"
  let got : Ref[Array[String]] = Ref([])
  let before = instance_wake_count()
  on_instance_wake(fn(a : Array[String]) -> Unit { got.val = a })
  match instance_claim(id) {
    Ok(Primary) => {
      // 同进程二次声称幂等
      match instance_claim(id) {
        Ok(Primary) => ()
        _ => assert_true(false) // 走到错误分支：本进程已是首实例
      }
      match instance_wake(id, ["toggle"]) {
        Ok(_) => ()
        Err(e) => assert_eq("唤起失败: \{e}", "唤起成功")
      }
      // 套接字/Win32 臂抽一拍落地；D-Bus 臂靠同步调用里的泵直达回调，
      // 同进程自环时那一拍未必轮到，故只在真没落地时记一条 skip。
      let _ = dispatch_instance_wake()
      let delivered = instance_wake_count() > before
      match instance_arm(id) {
        Some(Dbus) =>
          if !delivered {
            println("[skip] D-Bus 臂同进程自环：本拍未落地")
          }
        _ => assert_true(delivered)
      }
      if delivered {
        assert_eq(got.val, ["toggle"])
      }
    }
    Ok(Existing) => println("[skip] 本机已有同名实例在跑")
    Err(e) => println("[skip] 本平台后端不可用: \{e}")
  }
}

///|
test "instance_backend_name 四档与非法 app_id" {
  assert_eq(instance_backend_name(Dbus), "dbus")
  assert_eq(instance_backend_name(Win32), "win32")
  assert_eq(instance_backend_name(Socket), "socket")
  assert_eq(instance_backend_name(Unavailable), "none")
  // 三平台同一套字法规格：没有点分元素 / 有空格都拒
  match instance_claim("nodots") {
    Err(InvalidAppId(id)) => assert_eq(id, "nodots")
    _ => assert_true(false)
  }
  match instance_wake("com.app name", []) {
    Err(InvalidAppId(_)) => ()
    _ => assert_true(false)
  }
  // 本机至少要有一档可用（三平台各自的臂）
  assert_true(instance_supported())
}
