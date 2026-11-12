// window_state 纯函数用例:JSON 往返、坏输入拒收、状态目录按平台拼装。

///|
test "wstate_text/parse:往返;键序无关" {
  let g : WinGeom = { x: 100, y: -40, w: 1280, h: 800, maximized: false, }
  let t = wstate_text(g)
  match wstate_parse(t) {
    Some(r) => {
      assert_eq(r.x, 100)
      assert_eq(r.y, -40)
      assert_eq(r.w, 1280)
      assert_eq(r.h, 800)
      assert_true(r.maximized == false)
    }
    None => abort("own output rejected")
  }
  // 键序任意、空白容忍(手写解析器对自家格式之外的宽容度就到这里)
  let t2 = "{ \"maximized\": true, \"h\": 600, \"w\": 900, \"y\": 12, \"x\": -8 }"
  match wstate_parse(t2) {
    Some(r) => {
      assert_eq(r.x, -8)
      assert_eq(r.y, 12)
      assert_true(r.maximized == true)
    }
    None => abort("reordered json rejected")
  }
}

///|
test "wstate_parse:缺字段/负尺寸/坏值给 None" {
  match
    wstate_parse(
      "{ \"x\": 1, \"y\": 2, \"w\": 0, \"h\": 3, \"maximized\": false }",
    ) {
    Some(_) => abort("zero width accepted")
    None => ()
  }
  match wstate_parse("{ \"x\": 1, \"y\": 2, \"w\": 10, \"h\": 3 }") {
    Some(_) => abort("missing maximized accepted")
    None => ()
  }
  match wstate_parse("not json at all") {
    Some(_) => abort("garbage accepted")
    None => ()
  }
  // 非整数(带小数点)不是合法值
  match
    wstate_parse(
      "{ \"x\": 1.5, \"y\": 2, \"w\": 10, \"h\": 3, \"maximized\": false }",
    ) {
    Some(_) => abort("float accepted")
    None => ()
  }
}

///|
test "wstate_dir:三平台目录拼装;空 id/空环境给 None" {
  // linux: XDG_STATE_HOME 优先,回退 ~/.local/state
  assert_eq(
    wstate_dir("linux", "/home/u", "", "/xdg/state", "com.ex.app"),
    Some("/xdg/state/com.ex.app"),
  )
  assert_eq(
    wstate_dir("linux", "/home/u", "", "", "com.ex.app"),
    Some("/home/u/.local/state/com.ex.app"),
  )
  // macos: Application Support
  assert_eq(
    wstate_dir("macos", "/Users/u", "", "", "com.ex.app"),
    Some("/Users/u/Library/Application Support/com.ex.app"),
  )
  // windows: %APPDATA% 反斜杠
  assert_eq(
    wstate_dir(
      "windows", "", "C:\\Users\\u\\AppData\\Roaming", "", "com.ex.app",
    ),
    Some("C:\\Users\\u\\AppData\\Roaming\\com.ex.app"),
  )
  // 空环境与空 id
  match wstate_dir("macos", "", "", "", "com.ex.app") {
    Some(_) => abort("empty home accepted")
    None => ()
  }
  match wstate_dir("linux", "/home/u", "", "", "") {
    Some(_) => abort("empty id accepted")
    None => ()
  }
}
