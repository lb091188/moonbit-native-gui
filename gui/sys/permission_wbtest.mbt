// 权限族白盒：平台分支的契约形状（探针与引导在 mac 真机验，不锁具体读数——
// 授权状态随机器与用户操作变，锁了就是 flaky）。Windows / Linux 的
// NotNeeded 分支在非 mac 宿主的 CI 上才会真实走到，这里用「平台断言双态」
// 写法保证两个宿主都各自验到自己的那半。

///|
test "permission_supported 按平台" {
  if sys_platform() == "macos" {
    assert_eq(permission_supported(), true)
  } else {
    assert_eq(permission_supported(), false)
  }
}

///|
test "probe 契约：mac 给两态之一，非 mac 恒 NotNeeded" {
  match permission_probe(PermAccessibility) {
    Ok(PermGranted) => assert_true(sys_platform() == "macos")
    Ok(PermNotGranted) => assert_true(sys_platform() == "macos")
    Ok(PermNotNeeded) => assert_true(sys_platform() != "macos")
    Err(e) => abort("\{e}")
  }
  match permission_probe(PermScreenRecording) {
    Ok(PermGranted) => assert_true(sys_platform() == "macos")
    Ok(PermNotGranted) => assert_true(sys_platform() == "macos")
    Ok(PermNotNeeded) => assert_true(sys_platform() != "macos")
    Err(e) => abort("\{e}")
  }
}

///|
test "request 契约：不炸、非 mac 是空操作" {
  match permission_request(PermAccessibility) {
    Ok(_) => ()
    Err(e) => abort("\{e}")
  }
  match permission_request(PermScreenRecording) {
    Ok(_) => ()
    Err(e) => abort("\{e}")
  }
}

///|
test "状态 Show 形状" {
  assert_eq(
    PermNotNeeded.to_string(),
    "PermNotNeeded"
  )
  assert_eq(PermGranted.to_string(), "PermGranted")
  assert_eq(PermNotGranted.to_string(), "PermNotGranted")
}
