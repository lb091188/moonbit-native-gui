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
  assert_true(with_icon.contains("CFBundleDisplayName</key><string>My App</string>"))
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

test "basename_of:Windows 反斜杠与盘符（moon Artifacts 的原样形态）" {
  // `moon build` 在 Windows 打印的是反斜杠路径；只按 `/` 切会原样返回整条
  // 路径，拿去拼 `winroot/<整条路径>` 写文件必失败。
  let bs = "\\"
  assert_eq(
    basename_of("D:" + bs + "code" + bs + "app" + bs + "showcase.exe"),
    "showcase.exe",
  )
  assert_eq(basename_of("D:" + bs + "code" + bs + "assets" + bs), "assets")
  // 混用两种分隔符（拼出来的路径常见）
  assert_eq(basename_of("D:" + bs + "code/app" + bs + "x.exe"), "x.exe")
}

test "u16/u32 小端写读 roundtrip" {
  let b : FixedArray[Byte] = FixedArray::make(16, b'\x00')
  put_u16le(b, 0, 0x1234)
  put_u32le(b, 4, 0xdeadbeef)
  assert_eq(b[0].to_int(), 0x34)
  assert_eq(b[1].to_int(), 0x12)
  assert_eq(b[4].to_int(), 0xef)
  assert_eq(b[7].to_int(), 0xde)
}

test "get_be32:大端读" {
  let b : FixedArray[Byte] = FixedArray::make(8, b'\x00')
  b[0] = (0x01).to_byte()
  b[1] = (0x02).to_byte()
  b[2] = (0x03).to_byte()
  b[3] = (0x04).to_byte()
  assert_eq(get_be32(Bytes::from_array(b), 0), 0x01020304)
}

test "ico_of_png:头/目录项/载荷;宽高 ≥256 记 0;坏签名 None" {
  // 最小假 PNG:8B 签名 + 8B 长度/类型占位 + IHDR 宽高(16/20)+ 尾巴
  let raw : FixedArray[Byte] = FixedArray::make(40, b'\x41')
  let sig = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]
  let mut i = 0
  while i < 8 {
    raw[i] = (sig[i]).to_byte()
    i += 1
  }
  // 宽 256、高 128(大端)
  raw[16] = (0x00).to_byte()
  raw[17] = (0x00).to_byte()
  raw[18] = (0x01).to_byte()
  raw[19] = (0x00).to_byte()
  raw[20] = (0x00).to_byte()
  raw[21] = (0x00).to_byte()
  raw[22] = (0x00).to_byte()
  raw[23] = (0x80).to_byte()
  let png = Bytes::from_array(raw)
  match ico_of_png(png) {
    Some(ico) => {
      assert_eq(ico.length(), 22 + png.length())
      // ICONDIR:reserved 0 / type 1 / count 1
      assert_eq(ico[2].to_int(), 1)
      assert_eq(ico[4].to_int(), 1)
      assert_eq(ico[5].to_int(), 0)
      // 目录项:宽 256→0、高 128、bpp 32
      assert_eq(ico[6].to_int(), 0)
      assert_eq(ico[7].to_int(), 128)
      assert_eq(ico[12].to_int(), 32)
      assert_eq(ico[13].to_int(), 0)
      // size LE(40)与 offset 22
      assert_eq(ico[14].to_int(), 40)
      assert_eq(ico[18].to_int(), 22)
      // 载荷原样
      assert_eq(ico[22].to_int(), png[0].to_int())
      assert_eq(ico[22 + 39].to_int(), png[39].to_int())
    }
    None => abort("valid png rejected")
  }
  // 坏签名
  let bad = Bytes::from_array(FixedArray::make(40, b'\x00'))
  match ico_of_png(bad) {
    Some(_) => abort("bad signature accepted")
    None => ()
  }
  // 太短
  match ico_of_png(Bytes::from_array(FixedArray::make(10, b'\x00'))) {
    Some(_) => abort("short input accepted")
    None => ()
  }
}

test "esc_nsi:$ 转义为 $$" {
  assert_eq(esc_nsi("a$b"), "a$$b")
  assert_eq(esc_nsi("plain"), "plain")
}

test "to_win_path:正斜杠转反斜杠" {
  assert_eq(to_win_path(".mng/dist/winroot"), ".mng\\dist\\winroot")
  assert_eq(to_win_path("a/b\\c"), "a\\b\\c")
}

test "nsi_script:OutFile/InstallDir/快捷方式/卸载注册键齐全;File 排除自身" {
  let s = nsi_script(
      "com.ex.app",
      "My App",
      "mybin.exe",
      "1.2.0",
      "C:\\proj\\.mng\\dist\\winroot",
      "app",
      "C:\\proj\\.mng\\dist\\app-1.2.0-windows-x86_64.exe",
    )
  assert_true(s.contains("Unicode true"))
  assert_true(s.contains("OutFile \"C:\\proj\\.mng\\dist\\app-1.2.0-windows-x86_64.exe\""))
  assert_true(s.contains("InstallDir \"$LOCALAPPDATA\\Programs\\com.ex.app\""))
  assert_true(s.contains("RequestExecutionLevel user"))
  assert_true(s.contains("File /r /x installer.nsi \"C:\\proj\\.mng\\dist\\winroot\\*.*\""))
  assert_true(s.contains("CreateShortcut \"$SMPROGRAMS\\My App\\My App.lnk\" \"$INSTDIR\\mybin.exe\""))
  assert_true(s.contains("WriteUninstaller \"$INSTDIR\\uninstall.exe\""))
  assert_true(s.contains("Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\com.ex.app"))
  assert_true(s.contains("\"DisplayVersion\" \"1.2.0\""))
  assert_true(s.contains("DeleteRegKey"))
}

test "nsi_script:名字里的 $ 被转义" {
  let s = nsi_script("com.a.b", "A$B", "b.exe", "0.1.0", "C:\\s", "b", "C:\\o.exe")
  assert_true(s.contains("A$$B"))
  assert_false(s.contains("A$B"))
}

test "desktop_entry:字段齐全;categories 缺省 Utility、末尾补分号;comment 可空" {
  let d = desktop_entry("My App", "myapp", "mybin", [], "")
  assert_true(d.contains("[Desktop Entry]"))
  assert_true(d.contains("Name=My App"))
  assert_true(d.contains("Exec=mybin"))
  assert_true(d.contains("Icon=myapp"))
  assert_true(d.contains("Terminal=false"))
  assert_true(d.contains("Categories=Utility;"))
  assert_false(d.contains("Comment="))
  assert_true(d.contains("StartupWMClass=mybin"))
  let d2 = desktop_entry("N", "n", "b", ["Development", "Graphics"], "hello")
  assert_true(d2.contains("Categories=Development;Graphics;"))
  assert_true(d2.contains("Comment=hello"))
  assert_true(d2.contains("StartupWMClass=b"))
}

test "deb_control:Package/Version/Architecture 齐全;maintainer 缺省 unknown" {
  let c = deb_control("myapp", "My App", "1.2.0", "")
  assert_true(c.contains("Package: myapp"))
  assert_true(c.contains("Version: 1.2.0"))
  assert_true(c.contains("Architecture: amd64"))
  assert_true(c.contains("Description: My App"))
  assert_true(c.contains("Maintainer: unknown <>"))
  let c2 = deb_control("myapp", "My App", "1.2.0", "Noah <noah@example.com>")
  assert_true(c2.contains("Maintainer: Noah <noah@example.com>"))
}

test "apprun_script:exec 同树 usr/bin 的可执行" {
  let s = apprun_script("mybin")
  assert_true(s.contains("#!/bin/sh"))
  assert_true(s.contains("exec \"$HERE/usr/bin/mybin\" \"$@\""))
}

test "parse_package_toml:[package.linux] 节" {
  let toml = [
    "[package]",
    "id = \"com.a.b\"",
    "name = \"B\"",
    "version = \"1.0.0\"",
    "",
    "[package.linux]",
    "categories = [\"Development\", \"Utility\"]",
    "comment = \"工具\"",
  ].join("\n")
  let p = parse_package_toml(toml)
  assert_eq(p.linux_categories.length(), 2)
  assert_eq(p.linux_categories[0], "Development")
  assert_eq(p.linux_comment, "工具")
}
