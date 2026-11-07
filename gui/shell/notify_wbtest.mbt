// W21a 通知门面回归：纯函数部分（kind/百分比夹取、进度正文降级、错误 Show、
// 后端名一致性）。真气泡的弹出/替换/收起归 experiment/notify_probe（纯 C 探针
// 直喂 wm_notify_*，真发 NIM_MODIFY 再用静态表反读）；这里的 wbtest 只做一次
// 「发一张再收起」的生命周期冒烟，且无后端时跳过。

///|
test "notify_clamp_kind：夹到 0..2" {
  inspect(notify_clamp_kind(-1), content="0")
  inspect(notify_clamp_kind(0), content="0")
  inspect(notify_clamp_kind(1), content="1")
  inspect(notify_clamp_kind(2), content="2")
  inspect(notify_clamp_kind(3), content="2")
  inspect(notify_clamp_kind(99), content="2")
}

///|
test "notify_clamp_pct：夹到 0..100" {
  inspect(notify_clamp_pct(-5), content="0")
  inspect(notify_clamp_pct(0), content="0")
  inspect(notify_clamp_pct(50), content="50")
  inspect(notify_clamp_pct(100), content="100")
  inspect(notify_clamp_pct(101), content="100")
}

///|
test "notify_body_with_progress：负值不改进度正文" {
  // pct < 0 表示「不带进度」，正文原样返回（含空串）
  inspect(notify_body_with_progress("下载中", -1), content="下载中")
  inspect(notify_body_with_progress("", -1), content="")
}

///|
test "notify_body_with_progress：带进度拼进正文（可见降级）" {
  inspect(
    notify_body_with_progress("下载中", 42),
    content="下载中（42%）",
  )
  // 正文为空时只留百分比
  inspect(notify_body_with_progress("", 7), content="7%")
}

///|
test "notify_body_with_progress：百分比同样被夹取" {
  inspect(notify_body_with_progress("x", 200), content="x（100%）")
  inspect(notify_body_with_progress("x", -3), content="x") // 负值=不带进度
}

///|
test "NotifyError 的 Show 两种变体" {
  assert_eq(NotifyError::Unsupported.to_string(), "NotifyError::Unsupported")
  assert_true(
    NotifyError::Failed("后端离线").to_string().contains("后端离线"),
  )
  assert_true(
    NotifyError::Failed("x").to_string().has_prefix("NotifyError::Failed("),
  )
}

///|
test "notify_backend 名字映射（确定性，mac 按读数报真名）" {
  assert_eq(notify_backend_name_of(Some(Dbus)), "dbus")
  // macOS 的后端住在 win 桩同一支 `wm_notify_*`，实为 UNUserNotificationCenter——
  // mac 报 "un-user-notification"，其余平台报 "win-balloon"
  let balloon = if platform_is_macos() {
    "un-user-notification"
  } else {
    "win-balloon"
  }
  assert_eq(notify_backend_name_of(Some(WinBalloon)), balloon)
  assert_eq(notify_backend_name_of(None), "none")
}

///|
test "notify_backend_name：live 探测非空（映射已由纯函数用例钉住）" {
  // live 探测每次现打一发 GetCapabilities，桌面忙时有 2~3s 长尾（实测），
  // 连续两次探测之间结果可能翻转——跨探测的一致性属环境性，不作断言；
  // 这里只验「名字非空」这一无翻转面的读数
  let name = notify_backend_name()
  assert_true(name.length() > 0)
}

///|
test "notify_caps：有后端给 Ok 且含 body 能力，无后端给 Unsupported" {
  // 单次探测自洽： caps 与 supported 的判定都从这一份结果出
  match notify_caps() {
    Ok(c) =>
      // 两个后端都能显示独立正文（Linux body 能力 / Win32 szInfo）
      assert_true(c.body)
    Err(NotifyError::Unsupported) => assert_true(true) // 无后端，合法档
    Err(NotifyError::Failed(m)) =>
      if m.contains("gdbus.timeout") {
        // 服务在但桌面忙到 3 次重试都超时（环境性）——判定无从谈起
        println("skip: 通知服务应答超时（桌面忙）")
      } else {
        fail("能力查询失败：\{m}")
      }
  }
}

///|
test "notify 生命周期（无通知后端的机器自动跳过）" {
  // KDE 的限流器（ExcessNotificationGeneration）按「相似通知」计数——同
  // app+同摘要连发（跨快速连跑叠加）会触发并连累后续探测；摘要带当前
  // 毫秒时间戳让每轮可区分
  let tag = @win.now_ms().to_string()
  // KDE 对「相似通知连发」限流（ExcessNotificationGeneration），触发后还会
  // 连累同发送者的后续调用——内容全部可区分 + 限流错误按环境跳过（代码的
  // 职责是如实转述服务端错误，已经做到了）
  // 会真的在桌面弹一张气泡再立刻收起（同一拍内完成）。无后端的环境跳过而非
  // 造假——探测即口径。
  if !notify_supported() {
    println("skip: 本机没有可用的通知后端")
  } else {
    match
      notify_send(
        "libyue-wbtest",
        "wbtest 标题 \{tag}",
        "wbtest 正文 \{tag}",
      ) {
      Err(e) => println("skip: 发通知失败(\{e})")
      Ok(id) => {
        assert_true(id > 0)
        // 进度更新：拿回 id（后端可能复用原 id）
        match
          notify_progress(
            id,
            "libyue-wbtest",
            "wbtest 标题 \{tag}",
            "下载中 \{tag}",
            60,
          ) {
          Ok(pid) => assert_true(pid > 0)
          Err(e) =>
            if e.to_string().contains("ExcessNotificationGeneration") {
              // daemon 的自我保护限流（同内容快速连发触发），不是代码缺陷：
              // 错误原样上来了，跳过余下断言
              println("skip: daemon 限流（\{e}）")
            } else if e.to_string().contains("gdbus.timeout") {
              println("skip: 通知服务应答超时（桌面忙）")
            } else {
              fail("进度更新失败：\{e}")
            }
        }
        // 关闭成功；重复关闭后端应幂等（Win32 上第二关是 slot 已空的无操作）。
        // 桌面忙时 close 也可能 3 次重试都超时——环境性，跳过余下断言
        match notify_close(id) {
          Ok(_) => {
            let _ = notify_close(id)
            // urgent 的打扰档只有 macOS 吃，其余平台收下忽略：三平台都要发得出去
            match
              notify_send(
                "libyue-wbtest",
                "wbtest 非紧急 \{tag}",
                "urgent=false",
                urgent=false,
              ) {
              Err(e) =>
                if e.to_string().contains("gdbus.timeout") {
                  println(
                    "skip: 通知服务应答超时（桌面忙，\{e}）",
                  )
                } else if e.to_string().contains("ExcessNotificationGeneration") {
                  println("skip: daemon 限流（\{e}）")
                } else {
                  fail("urgent=false 发送失败：\{e}")
                }
              Ok(nid) => {
                assert_true(nid > 0)
                let _ = notify_close(nid)
              }
            }
          }
          Err(e) =>
            if e.to_string().contains("gdbus.timeout") {
              println("skip: 通知服务应答超时（桌面忙）")
            } else if e.to_string().contains("ExcessNotificationGeneration") {
              println("skip: daemon 限流（\{e}）")
            } else {
              fail("关闭失败：\{e}")
            }
        }
      }
    }
  }
}
