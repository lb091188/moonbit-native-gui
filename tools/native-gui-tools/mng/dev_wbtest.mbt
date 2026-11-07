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
  let root = tmp_dir("mng_dev_mkdir_p") + "/a/b/c"
  assert_true(mkdir_p(root))
  assert_true(@fs.is_dir(root) catch { _ => false })
  assert_true(mkdir_p(root))
  assert_true(mkdir_p(tmp_dir("mng_dev_mkdir_p")))
}

///|
test "build_project_at：按 mng.toml 扫全工程产生产形态生成码 + map，幂等" {
  // 去尾斜杠：macOS 的 TMPDIR 带尾斜杠，双斜杠会干扰 rel_under 的相对路径推导
  let root = tmp_dir("mng_build_proj")
  let root = if root.has_suffix("/") {
    root[:root.length() - 1].to_owned()
  } else {
    root
  }
  ensure_dir_p(root)
  write_file_p(root + "/moon.mod", "name = \"noahliu.build_proj\"\nversion = \"0.0.1\"\n")
  write_file_p(
    root + "/mng.toml",
    "[dev]\ntemplates = [\".\"]\nbuild = \"true\"\n",
  )
  write_file_p(
    root + "/page.mng",
    "<template>\n  <ui-text text=\"hello\" />\n</template>",
  )
  assert_eq(build_project_at(root), 0)
  let gen = @fs.read_file_to_string(root + "/page.gen.mbt") catch {
    _ => abort("生成码没落包内")
  }
  assert_true(contains_sub_cli(gen, "pub fn page() -> @widget.Node"))
  // 生产形态：无 dev 注册表痕迹
  assert_false(contains_sub_cli(gen, "mng_dev_page"))
  // map 落 .mng/map/ 下（根级模板的相对包路径会退回目录名，子路径不钉死）
  let map_dir = root + "/.mng/map"
  assert_true(@fs.is_dir(map_dir) catch { _ => false })
  let has_map = Ref(false)
  let dirs = Ref([map_dir])
  while dirs.val.length() > 0 {
    let dir = dirs.val[dirs.val.length() - 1]
    let _ = dirs.val.remove(dirs.val.length() - 1)
    let entries = @fs.read_dir(dir) catch { _ => [] }
    for e in entries {
      let p = dir + "/" + e.to_string()
      let isdir = @fs.is_dir(p) catch { _ => false }
      if isdir {
        dirs.val.push(p)
      } else if e.to_string().has_suffix(".map") {
        has_map.val = true
      }
    }
  }
  assert_true(has_map.val)
  // 幂等：再跑一遍仍 0 且内容不变
  let again = @fs.read_file_to_string(root + "/page.gen.mbt") catch {
    _ => abort("生成码读不回")
  }
  assert_eq(build_project_at(root), 0)
  assert_eq(
    @fs.read_file_to_string(root + "/page.gen.mbt") catch { _ => "" },
    again,
  )
}

///|
test "build_project_at：模板编译失败非零退出" {
  let root = tmp_dir("mng_build_proj_bad")
  let root = if root.has_suffix("/") {
    root[:root.length() - 1].to_owned()
  } else {
    root
  }
  ensure_dir_p(root)
  write_file_p(root + "/moon.mod", "name = \"noahliu.build_proj_bad\"\nversion = \"0.0.1\"\n")
  write_file_p(
    root + "/bad.mng",
    "<template>\n  <ui-col>\n    <ui-text v-else text=\"x\" />\n  </ui-col>\n</template>",
  )
  assert_eq(build_project_at(root), 1)
}

///|
test "scan_source_files：收 .mbt（排 .gen.mbt）与工程清单，跳产物目录" {
  let root = tmp_dir("mng_scan_src")
  ensure_dir_p(root)
  ensure_dir_p(root + "/sub")
  ensure_dir_p(root + "/_build")
  ensure_dir_p(root + "/.mng")
  write_file_p(root + "/a.mbt", "fn a {}")
  write_file_p(root + "/a.gen.mbt", "// GENERATED")
  write_file_p(root + "/moon.pkg", "{}")
  write_file_p(root + "/sub/b.mbt", "fn b {}")
  write_file_p(root + "/_build/c.mbt", "fn c {}")
  write_file_p(root + "/.mng/d.mbt", "fn d {}")
  let got = scan_source_files(root)
  assert_true(arr_has_cli(got, root + "/a.mbt"))
  assert_true(arr_has_cli(got, root + "/moon.pkg"))
  assert_true(arr_has_cli(got, root + "/sub/b.mbt"))
  assert_false(arr_has_cli(got, root + "/a.gen.mbt"))
  assert_false(arr_has_cli(got, root + "/_build/c.mbt"))
  assert_false(arr_has_cli(got, root + "/.mng/d.mbt"))
}

///|
test "diff_file_sets：新增/删除各自成列，共有的不动" {
  let (added, removed) = diff_file_sets(["/a.mng", "/b.mng"], ["/b.mng", "/c.mng"])
  assert_eq(added, ["/c.mng"])
  assert_eq(removed, ["/a.mng"])
  let (added2, removed2) = diff_file_sets([], [])
  assert_eq(added2, [])
  assert_eq(removed2, [])
}

///|
test "scaffold_app_at：workspace 内现读版本，文件齐全，dev 生成码带 @mngdev" {
  let root = tmp_dir("mng_scaffold_ws")
  ensure_dir_p(root)
  ensure_dir_p(root + "/gui")
  write_file_p(root + "/moon.work", "members = [\n  \"gui\",\n]\n")
  write_file_p(
    root + "/gui/moon.mod",
    "name = \"NoahLiu/native-gui\"\n\nversion = \"0.9.9\"\n\nimport {\n  \"NoahLiu/yoga-mbt@0.7.7\",\n}\n",
  )
  assert_eq(scaffold_app_at(root, "my_app"), 0)
  let gmod = @fs.read_file_to_string(root + "/my_app/moon.mod") catch { _ => abort("moon.mod 缺") }
  assert_true(contains_sub_cli(gmod, "NoahLiu/native-gui@0.9.9"))
  assert_true(contains_sub_cli(gmod, "NoahLiu/yoga-mbt@0.7.7"))
  let pkg = @fs.read_file_to_string(root + "/my_app/moon.pkg") catch { _ => abort("moon.pkg 缺") }
  assert_true(contains_sub_cli(pkg, "mngdev\" @mngdev"))
  assert_true(contains_sub_cli(pkg, "noahliu.my_app/pages\" @pages"))
  let gen = @fs.read_file_to_string(root + "/my_app/pages/home.gen.mbt") catch { _ => abort("生成码缺") }
  assert_true(contains_sub_cli(gen, "@mngdev.mng_dev_page(\"home\""))
  assert_true(contains_sub_cli(gen, "pub fn home() -> @widget.Node"))
  // 目录已存在拒绝
  assert_eq(scaffold_app_at(root, "my_app"), 1)
}

///|
test "scaffold_app_at：非法名净化与 workspace 外兜底版本注释" {
  let root = tmp_dir("mng_scaffold_raw")
  ensure_dir_p(root)
  assert_eq(scaffold_app_at(root, "9app"), 0)
  let gmod = @fs.read_file_to_string(root + "/_9app/moon.mod") catch { _ => abort("moon.mod 缺") }
  assert_true(contains_sub_cli(gmod, "name = \"noahliu._9app\""))
  assert_true(contains_sub_cli(gmod, "版本是兜底值"))
}
