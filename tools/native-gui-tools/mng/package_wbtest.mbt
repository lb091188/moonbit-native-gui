// package.mbt 纯函数用例:[package] 解析、前置校验、plist、iconset 表。

test "parse_package_toml:两节字段与缺省" {
  let toml = [
    "[dev]",
    "build = \"moon build .\"",
    "",
    "[package]",
    "id = \"com.example.myapp\"",
    "name = \"My App\"",
    "version = \"1.2.0\"",
    "icon = \"assets/icon.png\"",
    "resources = [\"assets/\", \"data\"]",
    "",
    "[package.sign]",
    "mac_identity = \"Developer ID Application: NAME (TEAMID)\"",
    "notarize_profile = \"prof\"",
    "win_cert = \"cert.pfx\"",
    "win_cert_pw_env = \"SIGN_PW\"",
  ].join("\n")
  let p = parse_package_toml(toml)
  assert_eq(p.id, "com.example.myapp")
  assert_eq(p.name, "My App")
  assert_eq(p.version, "1.2.0")
  assert_eq(p.icon, "assets/icon.png")
  assert_eq(p.resources.length(), 2)
  assert_eq(p.resources[0], "assets/")
  assert_eq(p.sign_mac, "Developer ID Application: NAME (TEAMID)")
  assert_eq(p.notarize_profile, "prof")
  assert_eq(p.win_cert, "cert.pfx")
  assert_eq(p.win_cert_pw_env, "SIGN_PW")
  // 未配置的字段保持缺省
  assert_eq(p.bin, "")
}

test "parse_package_toml:无 [package] 节全空" {
  let p = parse_package_toml("[dev]\nbuild = \"moon build .\"\n")
  assert_eq(p.id, "")
  assert_eq(p.version, "")
  assert_eq(p.resources.length(), 0)
}

test "pkg_validate:id 无点 / version 非三段 / name 空 / targets 拼写 / win 证书配套 / 通过" {
  let bad_id = pkg_conf_default()
  bad_id.id = "myapp"
  bad_id.name = "My"
  bad_id.version = "1.0.0"
  match pkg_validate(bad_id) {
    Some(_) => ()
    None => abort("expected error for id without dot")
  }
  let bad_ver = pkg_conf_default()
  bad_ver.id = "com.a.b"
  bad_ver.name = "My"
  bad_ver.version = "1.0"
  match pkg_validate(bad_ver) {
    Some(_) => ()
    None => abort("expected error for two-segment version")
  }
  let bad_name = pkg_conf_default()
  bad_name.id = "com.a.b"
  bad_name.name = ""
  bad_name.version = "1.0.0"
  match pkg_validate(bad_name) {
    Some(_) => ()
    None => abort("expected error for empty name")
  }
  let bad_target = pkg_conf_default()
  bad_target.id = "com.a.b"
  bad_target.name = "My"
  bad_target.version = "1.0.0"
  bad_target.targets = ["dmz"]
  match pkg_validate(bad_target) {
    Some(_) => ()
    None => abort("expected error for unknown target")
  }
  let bad_win = pkg_conf_default()
  bad_win.id = "com.a.b"
  bad_win.name = "My"
  bad_win.version = "1.0.0"
  bad_win.win_cert = "cert.pfx"
  match pkg_validate(bad_win) {
    Some(_) => ()
    None => abort("expected error for win_cert without pw env")
  }
  let ok = pkg_conf_default()
  ok.id = "com.a.b"
  ok.name = "My"
  ok.version = "0.1.0"
  match pkg_validate(ok) {
    None => ()
    Some(e) => abort("unexpected error: " + e)
  }
}

test "semver_ok:三段数字才过" {
  assert_true(semver_ok("0.1.0"))
  assert_true(semver_ok("10.20.30"))
  assert_false(semver_ok("1.0"))
  assert_false(semver_ok("1.0.0.0"))
  assert_false(semver_ok("1.0.x"))
  assert_false(semver_ok(""))
}

test "slug_of:id 末段" {
  assert_eq(slug_of("com.example.myapp"), "myapp")
  assert_eq(slug_of("a.b"), "b")
}

test "esc_xml:三个敏感字符" {
  assert_eq(esc_xml("a<b&c>d"), "a&lt;b&amp;c&gt;d")
}

test "info_plist_xml:键齐全;icon 空则无 IconFile" {
  let with_icon = info_plist_xml("com.ex.app", "My App", "mybin", "1.2.0", "app.icns")
  assert_true(with_icon.contains("CFBundleIdentifier</key><string>com.ex.app</string>"))
  assert_true(with_icon.contains("CFBundleExecutable</key><string>mybin</string>"))
  assert_true(with_icon.contains("CFBundleShortVersionString</key><string>1.2.0</string>"))
  assert_true(with_icon.contains("CFBundleIconFile</key><string>app.icns</string>"))
  assert_true(with_icon.contains("NSHighResolutionCapable"))
  let no_icon = info_plist_xml("com.ex.app", "N", "b", "0.1.0", "")
  assert_false(no_icon.contains("CFBundleIconFile"))
}

test "info_plist_xml:显示名转义" {
  let x = info_plist_xml("com.ex.app", "A&B", "b", "0.1.0", "")
  assert_true(x.contains("A&amp;B"))
}

test "iconset_sizes:Apple 标准十档、含 @2x 五档、上限 1024" {
  assert_eq(iconset_sizes.length(), 10)
  let mut has_1024 = false
  let mut at2x = 0
  for pair in iconset_sizes {
    let name = pair.0
    let n = pair.1
    assert_true(n > 0 && n <= 1024)
    if n == 1024 {
      has_1024 = true
    }
    if name.contains("@2x") {
      at2x += 1
    }
  }
  assert_true(has_1024)
  assert_eq(at2x, 5)
}

test "basename_of:末段非空" {
  assert_eq(basename_of("/a/b/showcase.exe"), "showcase.exe")
  assert_eq(basename_of("assets/"), "assets")
  assert_eq(basename_of("x"), "x")
}
