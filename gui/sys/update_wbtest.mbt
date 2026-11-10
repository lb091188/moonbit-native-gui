// update.mbt 纯函数用例:semver、target id、清单解析、SHA256 提取、URL/路径助手。

test "update_version_cmp:三段逐级比较;非法输入字符串兜底" {
  assert_eq(update_version_cmp("1.0.0", "1.0.0"), 0)
  assert_eq(update_version_cmp("1.2.0", "1.10.0"), -1)
  assert_eq(update_version_cmp("2.0.0", "1.99.99"), 1)
  assert_eq(update_version_cmp("1.0.1", "1.0.0"), 1)
  assert_eq(update_version_cmp("0.2.3", "0.2.10"), -1)
  // 非法(非数字段):不相等按「可比为大」——宁可提示更新
  assert_eq(update_version_cmp("x.y.z", "1.0.0"), 1)
  assert_eq(update_version_cmp("x.y.z", "x.y.z"), 0)
}

test "update_is_newer:严格大于" {
  assert_true(update_is_newer("0.2.0", "0.1.9"))
  assert_false(update_is_newer("0.1.9", "0.2.0"))
  assert_false(update_is_newer("1.0.0", "1.0.0"))
}

test "update_target_id:与 sys_platform 映射一致" {
  let expect = match sys_platform() {
    "macos" => "darwin-aarch64"
    "windows" => "windows-x86_64"
    _ => "linux-x86_64"
  }
  assert_eq(update_target_id(), expect)
}

test "update_parse_manifest:完整清单含预留字段忽略" {
  let text = [
    "{",
    "  \"version\": \"1.2.0\",",
    "  \"notes\": \"修复若干\",",
    "  \"pub_date\": \"2026-11-08T00:00:00Z\",",
    "  \"platforms\": {",
    "    \"darwin-aarch64\": {\"url\": \"https://x/a.zip\", \"size\": 12345, \"sha256\": \"abc\"},",
    "    \"linux-x86_64\": {\"url\": \"https://x/a.AppImage\", \"size\": 999, \"sha256\": \"def\"}",
    "  },",
    "  \"signature\": null,",
    "  \"sig_alg\": null,",
    "  \"deltas\": null",
    "}",
  ].join("\n")
  let m = match update_parse_manifest(text) {
    Some(m) => m
    None => abort("valid manifest rejected")
  }
  assert_eq(m.version, "1.2.0")
  assert_eq(m.notes, "修复若干")
  assert_eq(m.assets.length(), 2)
  let a = match update_manifest_asset(m, "linux-x86_64") {
    Some(a) => a
    None => abort("linux asset missing")
  }
  assert_eq(a.url, "https://x/a.AppImage")
  assert_eq(a.size, 999L)
  assert_eq(a.sha256, "def")
  // 不存在的平台
  match update_manifest_asset(m, "windows-x86_64") {
    Some(_) => abort("unexpected windows asset")
    None => ()
  }
}

test "update_parse_manifest:缺 version / 坏 JSON 给 None" {
  let no_ver = "{\"platforms\": {}}"
  match update_parse_manifest(no_ver) {
    Some(_) => abort("manifest without version accepted")
    None => ()
  }
  match update_parse_manifest("not json at all {") {
    Some(_) => abort("garbage accepted")
    None => ()
  }
}

test "upd_extract_sha256:posix 行与 certutil 块都吃;无 64 段给 None" {
  let hex64 = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
  // posix:sha256sum 输出
  assert_eq(upd_extract_sha256("\{hex64}  /tmp/x.zip\n"), Some(hex64))
  // certutil:多行块(头行含中文、空行、hex、CertUtil 行)
  let ct = "SHA256 的 C:\\x.zip 哈希:\n\n\{hex64}\nCertUtil: -hashfile 命令成功完成。\n"
  assert_eq(upd_extract_sha256(ct), Some(hex64))
  // 大写不认(本端统一小写;certutil 输出为小写)
  match upd_extract_sha256("ABCDEF") {
    Some(_) => abort("uppercase hex accepted")
    None => ()
  }
  // 没有 64 长的段
  match upd_extract_sha256("deadbeef  file\n") {
    Some(_) => abort("short hex accepted")
    None => ()
  }
}

test "upd_basename_of_url:末段去查询串;空回退" {
  assert_eq(
    upd_basename_of_url("https://gh/releases/download/app-v1/a-1.0.0-darwin-aarch64.zip?token=x"),
    "a-1.0.0-darwin-aarch64.zip",
  )
  assert_eq(upd_basename_of_url("https://x/y.AppImage"), "y.AppImage")
  assert_eq(upd_basename_of_url("https://x/"), "update-download")
}

test "upd_dirname:posix / windows / 无分隔" {
  assert_eq(upd_dirname("/a/b/c.zip"), "/a/b")
  assert_eq(upd_dirname("C:\\Apps\\x.exe"), "C:\\Apps")
  assert_eq(upd_dirname("x.exe"), ".")
  assert_eq(upd_dirname("/x"), "/")
}

test "update_check:http 默认拒;allow_http 越过前缀检查(本地服务口)" {
  // 默认:明文清单直接拒,不触网(前缀检查在任何 IO 之前)
  let r = update_check("http://127.0.0.1:8765/update.json", "0.1.0")
  match r {
    Err(e) => assert_true(e.contains("HTTPS"))
    Ok(_) => fail("http:// 清单默认应被拒")
  }
  // 显式放行:越过前缀检查走进拉取(本地无服务时落「拉取失败」,非 HTTPS 拒绝)
  let r2 = update_check(
    "http://127.0.0.1:1/update.json",
    "0.1.0",
    timeout_ms=2000,
    allow_http=true,
  )
  match r2 {
    Err(e) => assert_false(e.contains("HTTPS"))
    Ok(_) => ()
  }
}

test "upd_linux_target:无 $APPIMAGE 环境(测试环境即此)落回自身路径" {
  assert_eq(
    upd_linux_target("/tmp/.mount_x/usr/bin/a.exe"),
    "/tmp/.mount_x/usr/bin/a.exe",
  )
}
