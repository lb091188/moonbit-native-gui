// publish.mbt 纯函数用例:产物名解析、载体判定、清单文本、SHA 提取、转义。

///|
test "pub_parse_artifact:五件产物与坏名字" {
  // mac 三件
  let a = match pub_parse_artifact("showcase-0.1.0-darwin-aarch64.dmg") {
    Some(x) => x
    None => abort("dmg rejected")
  }
  assert_eq(a.slug, "showcase")
  assert_eq(a.version, "0.1.0")
  assert_eq(a.target, "darwin-aarch64")
  assert_eq(a.ext, "dmg")
  // win / linux
  assert_true(
    match pub_parse_artifact("my-app-1.2.3-windows-x86_64.exe") {
      Some(x) => x.ext == "exe" && x.slug == "my-app"
      None => false
    },
  )
  assert_true(
    match pub_parse_artifact("my-app-1.2.3-linux-x86_64.AppImage") {
      Some(x) => x.target == "linux-x86_64"
      None => false
    },
  )
  // slug 里可以带连字符
  assert_true(
    match pub_parse_artifact("native-gui-showcase-0.2.0-darwin-aarch64.zip") {
      Some(x) => x.slug == "native-gui-showcase" && x.version == "0.2.0"
      None => false
    },
  )
  // 坏名字:非 semver / 缺 target / 未知后缀 / 没点
  match pub_parse_artifact("showcase-0.1-darwin-aarch64.dmg") {
    Some(_) => abort("non-semver accepted")
    None => ()
  }
  match pub_parse_artifact("showcase-0.1.0-darwin-x86_64.dmg") {
    Some(_) => abort("unknown target accepted")
    None => ()
  }
  match pub_parse_artifact("showcase-0.1.0-darwin-aarch64.tar.gz") {
    Some(_) => abort("unknown ext accepted")
    None => ()
  }
  match pub_parse_artifact("no-dot-name") {
    Some(_) => abort("dotless accepted")
    None => ()
  }
}

///|
test "pub_is_carrier:zip/zip/AppImage;安装包不是载体" {
  assert_true(pub_is_carrier("darwin-aarch64", "zip"))
  assert_true(pub_is_carrier("windows-x86_64", "zip"))
  assert_true(pub_is_carrier("linux-x86_64", "AppImage"))
  assert_false(pub_is_carrier("darwin-aarch64", "dmg"))
  assert_false(pub_is_carrier("windows-x86_64", "exe"))
  assert_false(pub_is_carrier("linux-x86_64", "deb"))
  assert_false(pub_is_carrier("linux-x86_64", "zip"))
}

///|
test "pub_manifest_text:载体条目与预留位" {
  let carriers : Array[PubArt] = [
    {
      file: "showcase-0.1.0-darwin-aarch64.zip",
      slug: "showcase",
      version: "0.1.0",
      target: "darwin-aarch64",
      ext: "zip",
    },
    {
      file: "showcase-0.1.0-linux-x86_64.AppImage",
      slug: "showcase",
      version: "0.1.0",
      target: "linux-x86_64",
      ext: "AppImage",
    },
  ]
  let t = pub_manifest_text(
    "0.1.0",
    "首版 \"发布\" 与\\回退",
    "owner/repo",
    "app-v0.1.0",
    carriers,
    ["a".repeat(64), "b".repeat(64)],
    [123L, 456L],
  )
  assert_true(t.contains("\"version\": \"0.1.0\""))
  assert_true(t.contains("首版 \\\"发布\\\" 与\\\\回退"))
  assert_true(
    t.contains(
      "\"url\": \"https://github.com/owner/repo/releases/download/app-v0.1.0/showcase-0.1.0-darwin-aarch64.zip\"",
    ),
  )
  assert_true(t.contains("\"size\": 123"))
  assert_true(t.contains("\"pub_date\": \"\""))
  assert_true(t.contains("\"signature\": null"))
  assert_true(t.contains("\"deltas\": null"))
  // 库侧解析器口径:gui/sys/update_parse_manifest 吃得下(结构由文本形态保证)
}

///|
test "pub_manifest_text:无载体时 platforms 空" {
  let t = pub_manifest_text("0.1.0", "n", "o/r", "app-v0.1.0", [], [], [])
  assert_true(t.contains("\"platforms\": {}"))
}

///|
test "pub_extract_sha:posix 行与 certutil 块" {
  let hex64 = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
  assert_eq(pub_extract_sha("\{hex64}  /x.zip\n"), Some(hex64))
  assert_true(
    match pub_extract_sha("头\n\n\{hex64}\nCertUtil: 成功。\n") {
      Some(h) => h == hex64
      None => false
    },
  )
  match pub_extract_sha("short") {
    Some(_) => abort("short accepted")
    None => ()
  }
}

///|
test "pub_json_escape:引号反斜杠控制字符" {
  assert_eq(pub_json_escape("a\"b\\c\nd"), "a\\\"b\\\\c\\nd")
  assert_eq(pub_json_escape("平文"), "平文")
}
