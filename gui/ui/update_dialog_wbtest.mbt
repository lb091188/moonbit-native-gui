// update_dialog 状态机账本用例:三个报告口的转移与账本字段清写。

///|
/// 枚举等值判(老工具链 enum 不自动派生 Eq,match 三对)
fn retry_is(r : UpdateRetry, want : UpdateRetry) -> Bool {
  match (r, want) {
    (RetryNone, RetryNone)
    | (RetryCheck, RetryCheck)
    | (RetryDownload, RetryDownload) => true
    _ => false
  }
}

test "UpdateFlow:检查链三种出口" {
  let flow = make_update_flow()
  // 初始
  assert_true(match flow.state.get() { Idle => true; _ => false })
  // begin_check:标检查中、清上一轮
  flow.begin_check()
  assert_true(match flow.state.get() { Checking => true; _ => false })
  // 已是最新
  flow.report_check(Ok(None))
  assert_true(match flow.state.get() { UpToDate => true; _ => false })
  // 有新版:记清单 + Available 带版本与说明
  flow.begin_check()
  flow.report_check(
    Ok(
      Some(
        {
          version: "0.9.9",
          notes: "修复若干",
          pub_date: "2026-11-08T00:00:00Z",
          assets: [],
        },
      ),
    ),
  )
  assert_true(
    match flow.state.get() {
      Available(v, n) => v == "0.9.9" && n == "修复若干"
      _ => false
    },
  )
  match flow.found {
    Some(m) => assert_eq(m.version, "0.9.9")
    None => abort("found 未记清单")
  }
  // 检查失败:可重检查
  flow.begin_check()
  flow.report_check(Err("拉取清单失败(退出码 6)"))
  assert_true(
    match flow.state.get() {
      Failed(msg, retry) =>
        msg.contains("退出码") && retry_is(retry, RetryCheck)
      _ => false
    },
  )
}

test "UpdateFlow:下载与安装链" {
  let flow = make_update_flow()
  // 下载成功:记载体路径 + Ready
  flow.begin_download()
  assert_true(match flow.state.get() { Downloading => true; _ => false })
  flow.report_download(Ok("/tmp/showcase-0.9.9-darwin-aarch64.zip"))
  assert_true(match flow.state.get() { Ready => true; _ => false })
  assert_eq(flow.carrier, "/tmp/showcase-0.9.9-darwin-aarch64.zip")
  // 安装失败:Failed 且无重试钮
  flow.begin_install()
  assert_true(match flow.state.get() { Installing => true; _ => false })
  flow.report_install(Err("拿不到自身可执行路径"))
  assert_true(
    match flow.state.get() {
      Failed(_, retry) => retry_is(retry, RetryNone)
      _ => false
    },
  )
  // 安装成功:不走状态(进程应已退出,态停在 Installing 即终态)
  flow.begin_install()
  flow.report_install(Ok(()))
  assert_true(match flow.state.get() { Installing => true; _ => false })
  // 下载失败:可重下载
  flow.begin_download()
  flow.report_download(Err("SHA256 不符"))
  assert_true(
    match flow.state.get() {
      Failed(_, retry) => retry_is(retry, RetryDownload)
      _ => false
    },
  )
}

test "UpdateFlow:begin_check 清上一轮、reset 回初始" {
  let flow = make_update_flow()
  flow.report_check(
    Ok(
      Some(
        {
          version: "1.0.0",
          notes: "",
          pub_date: "",
          assets: [],
        },
      ),
    ),
  )
  flow.report_download(Ok("/tmp/x.AppImage"))
  assert_eq(flow.carrier, "/tmp/x.AppImage")
  // 重新检查:上一轮清单与载体都该清
  flow.begin_check()
  assert_true(match flow.found { None => true; _ => false })
  assert_eq(flow.carrier, "")
  // reset 回 Idle
  flow.report_check(Err("网络断"))
  flow.reset()
  assert_true(match flow.state.get() { Idle => true; _ => false })
  assert_true(match flow.found { None => true; _ => false })
  assert_eq(flow.carrier, "")
}

test "UpdateFlow:state 是 Store,订阅口收得到转移" {
  let flow = make_update_flow()
  let seen : @base.Store[Int] = @base.Store::new(0)
  flow.state.subscribe(fn(_st : UpdateState) -> Unit {
    seen.update_always(fn(n) { n + 1 })
  })
  flow.begin_check()
  flow.report_check(Ok(None))
  // 初订阅 1 次(begin_check 前已 set 一次?Store::new 不通知)+ 两次转移
  assert_true(seen.get() >= 2)
}
