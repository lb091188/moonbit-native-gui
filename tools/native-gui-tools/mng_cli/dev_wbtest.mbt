// dev 循环产物落点回归（无头）：.mng/ 目录推导、相对包路径、文件名安全段、逐级建目录。

///|
test "safe_filename：app-id 里的非法字符转下划线" {
  assert_eq(safe_filename("noahliu.native-gui-examples-showcase"), "noahliu.native-gui-examples-showcase")
  assert_eq(safe_filename("comExample.App (dev)"), "comExample.App__dev_")
}

///|
test "rel_under：项目根下的相对包路径，根外退回目录名" {
  assert_eq(rel_under("/ws/app", "/ws/app/pages"), "pages")
  assert_eq(rel_under("/ws/app", "/ws/app/pages/sub"), "pages/sub")
  assert_eq(rel_under("/ws/app", "/elsewhere/pages"), "pages")
}

///|
test "dev_map_path：map 落 .mng/map/<相对包路径>/<stem>.gen.mbt.map" {
  assert_eq(
    dev_map_path("/ws/app/.mng", "/ws/app", "/ws/app/pages/dev_demo.mng"),
    "/ws/app/.mng/map/pages/dev_demo.gen.mbt.map",
  )
}

///|
test "mkdir_p：逐级建目录，已存在视为成功" {
  let root = "/tmp/mng_dev_mkdir_p/a/b/c"
  assert_true(mkdir_p(root))
  assert_true(@fs.is_dir(root) catch { _ => false })
  assert_true(mkdir_p(root))
  assert_true(mkdir_p("/tmp/mng_dev_mkdir_p"))
}
