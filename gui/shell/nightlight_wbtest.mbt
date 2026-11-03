// Wayland 夜温通道回归：只读侧（gsettings 可用性 / KDE ColorCorrect 读数），
// 写侧要动用户的 DE 配置/屏幕，不放进自动用例（真机清单归用户）。

///|
test "nightlight：GNOME schema 可用性探测（本机有则 true）" {
  // 本机（KDE 会话）也装了 gsd 的 color schema——读得到即算可用；
  // 没有 schema 的机器 false。两档都合法，不断言具体值。
  let avail = nl_gnome_available()
  if avail {
    // 读一次当前温度键（无副作用）
    match @sys.pr_run("gsettings", ["get", NL_GNOME_SCHEMA, NL_GNOME_KEY_TEMP], timeout_ms=3000) {
      Ok(out) => assert_true(out.stdout.length() > 0, msg="读到的温度键为空")
      Err(_) => fail("schema 可用但读不到温度键")
    }
  }
}

///|
test "nightlight：KDE ColorCorrect 读侧（KDE 会话给温度与运行态）" {
  match nl_kde_state() {
    None => println("nightlight: skip（非 KDE 或无 ColorCorrect）")
    Some((k, running)) => {
      // 色温 K 合理区间（夜灯 1000..6500）；运行态两档都合法
      assert_true(k >= 1000 && k <= 10000, msg="色温读数不合理: \{k}")
      let _ = running
    }
  }
}

///|
test "nightlight：KDE 写侧如实报不支持（读得到不等于写得进）" {
  // Plasma 5.27 的 ColorCorrect 属性全 read-only（实物核过）；Plasma 6 的
  // NightLight 写入口径未核——两档都不许假成功
  match nl_kde_set(50) {
    Err(@sys.NightlightError::Unsupported) => ()
    _ => fail("KDE 夜灯写侧应报 Unsupported")
  }
}
