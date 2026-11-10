// appmeta.mbt 用例:生成文本、跳过口径、写盘幂等。

///|
test "appmeta_text:三常量与转义" {
  let t = appmeta_text("com.ex.my\"app", "My App", "1.2.3")
  assert_true(t.contains("pub let app_version : String = \"1.2.3\""))
  assert_true(t.contains("pub let app_id : String = \"com.ex.my\\\"app\""))
  assert_true(t.contains("pub let app_name : String = \"My App\""))
  // 同输入幂等(CI 重生成与提交文件 diff 对账的前提)
  assert_eq(t, appmeta_text("com.ex.my\"app", "My App", "1.2.3"))
}

///|
test "sync_appmeta:没 mng.toml / 没配 id-version 都跳过" {
  ignore(mkdir_p("/tmp/mng_appmeta/none"))
  match sync_appmeta("/tmp/mng_appmeta/none") {
    Ok(false) => ()
    _ => abort("无 mng.toml 应跳过 Ok(false)")
  }
  ignore(mkdir_p("/tmp/mng_appmeta/noid"))
  let _ = spit(
    "/tmp/mng_appmeta/noid/mng.toml",
    "[package]\nversion = \"1.0.0\"\n",
  )
  match sync_appmeta("/tmp/mng_appmeta/noid") {
    Ok(false) => ()
    _ => abort("id 缺省应跳过 Ok(false)")
  }
}

///|
test "sync_appmeta:配置齐了就写盘,再跑内容一致不重写" {
  ignore(mkdir_p("/tmp/mng_appmeta/ok"))
  let _ = spit(
    "/tmp/mng_appmeta/ok/mng.toml",
    "[package]\nid = \"com.ex.demo\"\nname = \"Demo\"\nversion = \"1.2.3\"\n",
  )
  match sync_appmeta("/tmp/mng_appmeta/ok") {
    Ok(true) => ()
    _ => abort("首次生成应写盘 Ok(true)")
  }
  let body = match fs_read("/tmp/mng_appmeta/ok/appmeta/appmeta.gen.mbt") {
    Some(t) => t
    None => abort("生成码应在")
  }
  assert_true(body.contains("pub let app_version : String = \"1.2.3\""))
  assert_true(body.contains("pub let app_id : String = \"com.ex.demo\""))
  // moon.pkg 缺则补
  assert_true(fs_read("/tmp/mng_appmeta/ok/appmeta/moon.pkg") is Some(_))
  // 内容一致:不重写
  match sync_appmeta("/tmp/mng_appmeta/ok") {
    Ok(false) => ()
    _ => abort("内容一致应 Ok(false) 不写盘")
  }
  // 版本改了:重新写盘
  let _ = spit(
    "/tmp/mng_appmeta/ok/mng.toml",
    "[package]\nid = \"com.ex.demo\"\nname = \"Demo\"\nversion = \"2.0.0\"\n",
  )
  match sync_appmeta("/tmp/mng_appmeta/ok") {
    Ok(true) => ()
    _ => abort("版本变更应重写 Ok(true)")
  }
  match fs_read("/tmp/mng_appmeta/ok/appmeta/appmeta.gen.mbt") {
    Some(t) => assert_true(t.contains("pub let app_version : String = \"2.0.0\""))
    None => abort("生成码应在")
  }
}
