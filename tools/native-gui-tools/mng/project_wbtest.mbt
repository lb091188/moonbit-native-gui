// 项目级 dev 配置回归（无头）：mng.toml 解析、默认推导、多目录扫描、撞名聚合。
///|
/// 可写临时目录（跨平台）：Windows 没有 `/tmp`，硬写会让用例在 `abort` 上假红。
/// 依次取 `TMPDIR` / `TEMP` / `TMP`，都没有再回落 `/tmp`。
fn tmp_dir(sub : String) -> String {
  let mut base = ""
  for k in ["TMPDIR", "TEMP", "TMP"] {
    if base == "" {
      match @env.get_env_var(k) {
        Some(v) if v != "" => base = v
        _ => ()
      }
    }
  }
  if base == "" {
    base = "/tmp"
  }
  base + "/" + sub
}


///|
fn write_file_p(path : String, text : String) -> Unit {
  @fs.write_string_to_file(path, text) catch {
    _ => abort("写不出 " + path)
  }
}

///|
fn ensure_dir_p(path : String) -> Unit {
  @fs.create_dir(path) catch {
    _ => ()
  }
}

///|
test "mng.toml 解析：[dev] 段的模板目录/命令/app-id/轮询" {
  let text = [
    "# 注释",
    "[dev]",
    "templates = [\"src\", \"examples/app\"]",
    "build = \"moon build ./app\"",
    "run = \"\"",
    "app-id = \"com.example.demo\"",
    "poll-ms = 500",
    "",
    "[other]",
    "templates = [\"nope\"]",
  ].join("\n")
  let t = parse_dev_toml(text)
  assert_eq(t.templates.length(), 2)
  assert_eq(t.templates[0], "src")
  assert_eq(t.templates[1], "examples/app")
  assert_eq(t.build, "moon build ./app")
  assert_eq(t.app_id, "com.example.demo")
  assert_eq(t.poll_ms, Some(500))
}

///|
test "模块名 → app_id：小写、斜杠转点、非法字符转下划线" {
  assert_eq(
    app_id_of_module("NoahLiu/native-gui-examples-showcase"),
    "noahliu.native-gui-examples-showcase",
  )
  assert_eq(app_id_of_module("a b/c_d"), "a_b.c_d")
  // 裸名（无作者段）垫 local. 命名空间，否则 InvalidAppId 降级
  assert_eq(app_id_of_module("demo2"), "local.demo2")
  assert_eq(app_id_of_module("_9app"), "local._9app")
}

///|
test "默认推导：moon.mod 目录当模板根，app-id 由 name 派生" {
  let root = tmp_dir("mng_proj_conf")
  ensure_dir_p(root)
  write_file_p(root + "/moon.mod", "name = \"Acme/demo-app\"\n")
  let conf = match load_dev_conf("", "", "", None, root) {
    Ok(c) => c
    Err(e) => abort(e)
  }
  assert_eq(conf.dir, root)
  assert_eq(conf.templates.length(), 1)
  assert_eq(conf.templates[0], root)
  assert_eq(conf.build, "moon build .")
  assert_eq(conf.app_id, "acme.demo-app")
  assert_eq(conf.poll_ms, 300)
}

///|
test "mng.toml 优先：相对模板目录解析成配置根下的路径" {
  let root = tmp_dir("mng_proj_toml")
  ensure_dir_p(root)
  write_file_p(root + "/moon.mod", "name = \"Acme/toml-app\"\n")
  write_file_p(
    root + "/mng.toml",
    "[dev]\ntemplates = [\"pages\", \"examples/x\"]\nbuild = \"moon build x\"\napp-id = \"acme.toml\"\npoll-ms = 120\n",
  )
  let conf = match load_dev_conf("", "", "", None, root) {
    Ok(c) => c
    Err(e) => abort(e)
  }
  assert_eq(conf.templates.length(), 2)
  assert_eq(conf.templates[0], root + "/pages")
  assert_eq(conf.build, "moon build x")
  assert_eq(conf.app_id, "acme.toml")
  assert_eq(conf.poll_ms, 120)
  // CLI 覆盖优先
  let conf2 = match load_dev_conf("moon build y", "", "", Some(50), root) {
    Ok(c) => c
    Err(e) => abort(e)
  }
  assert_eq(conf2.build, "moon build y")
  assert_eq(conf2.poll_ms, 50)
}

///|
test "多目录递归扫描：跳过 _build/.mooncakes/点目录，结果去重排序" {
  let root = tmp_dir("mng_proj_scan")
  ensure_dir_p(root)
  ensure_dir_p(root + "/a")
  ensure_dir_p(root + "/a/_build")
  ensure_dir_p(root + "/b")
  write_file_p(root + "/a/one.mng", "<template />")
  write_file_p(root + "/a/_build/ignored.mng", "<template />")
  write_file_p(root + "/b/two.mng", "<template />")
  let files = scan_templates([root, root + "/a"])
  assert_eq(files.length(), 2)
  assert_true(arr_has_str(files, root + "/a/one.mng"))
  assert_true(arr_has_str(files, root + "/b/two.mng"))
}

///|
test "撞名聚合：同包同 stem 报，跨包同 stem 不报" {
  let same_pkg = ["/p/a/card.mng", "/p/a/card.old.mng"]
  match collision_msg(same_pkg) {
    Some(m) => assert_true(contains_sub_p(m, "同包撞名") && contains_sub_p(m, "card"))
    None => assert_true(false)
  }
  let cross_pkg = ["/p/a/card.mng", "/p/b/card.mng"]
  assert_true(
    match collision_msg(cross_pkg) {
      Some(_) => false
      None => true
    },
  )
}

///|
test "init 样板含 [dev] 段与关键字段" {
  let t = mng_toml_template()
  assert_true(contains_sub_p(t, "[dev]"))
  assert_true(contains_sub_p(t, "templates ="))
  assert_true(contains_sub_p(t, "build ="))
  assert_true(contains_sub_p(t, "app-id ="))
  assert_true(contains_sub_p(t, "poll-ms ="))
}

///|
fn contains_sub_p(s : String, sub : String) -> Bool {
  let a = s.to_array()
  let b = sub.to_array()
  let n = a.length()
  let m = b.length()
  if m == 0 || m > n {
    return m == 0
  }
  let mut i = 0
  while i + m <= n {
    let mut ok = true
    for k = 0; k < m; k = k + 1 {
      if a[i + k] != b[k] {
        ok = false
      }
    }
    if ok {
      return true
    }
    i = i + 1
  }
  false
}

///|
test "Artifacts 段解析：按模块名挑，别家模块的行不认（裸 workspace 构建的回归）" {
  let bin = tmp_dir("mng_proj_artifact.bin")
  let tool = tmp_dir("mng_proj_tool.bin")
  assert_true(is_abs_path("/a/b.exe"))
  assert_true(is_abs_path("C:\\Users\\a\\b.exe"))
  assert_true(is_abs_path("D:/build/app.exe"))
  assert_true(is_abs_path("\\\\server\\share\\app.exe"))
  assert_false(is_abs_path("build/app.exe"))
  assert_false(is_abs_path(""))
  assert_false(is_abs_path("C:app.exe"))
  write_file_p(bin, "x")
  write_file_p(tool, "x")
  // 裸 `moon build` 会列整个 workspace；本模块的行在中间，最后一条是别的模块
  let log = [
    "Artifacts:",
    "  NoahLiu/other  native  " + tool,
    "  Acme/app  native  " + bin,
    "  NoahLiu/native-gui-tools/mng  native  " + tool,
    "",
  ].join("\n")
  assert_eq(artifact_of_log(log, "Acme/app"), Some(bin))
  // 只有子包（cmd/main）也认
  let log2 = [
    "Artifacts:",
    "  Acme/app/cmd/main  native  " + bin,
    "  NoahLiu/other  native  " + tool,
  ].join("\n")
  assert_eq(artifact_of_log(log2, "Acme/app"), Some(bin))
  // 全不是本模块 → None（让调用方提示补 run，而不是乱起别的程序）
  assert_eq(artifact_of_log(log, "Acme/elsewhere"), None)
  assert_eq(artifact_of_log("no artifacts here", "Acme/app"), None)
}

///|
test "mng.toml：theme 键解析并落项目根相对路径" {
  let root = tmp_dir("mng_proj_theme")
  ensure_dir_p(root)
  write_file_p(root + "/moon.mod", "name = \"Acme/theme-app\"\n")
  write_file_p(
    root + "/mng.toml",
    "[dev]\ntheme = \"theme.json\"\n",
  )
  let conf = match load_dev_conf("", "", "", None, root) {
    Ok(c) => c
    Err(e) => abort(e)
  }
  assert_eq(conf.theme, root + "/theme.json")
  // 未配置给空串（dev 循环跳过主题盯梢）
  write_file_p(root + "/mng.toml", "[dev]\n")
  let conf2 = match load_dev_conf("", "", "", None, root) {
    Ok(c) => c
    Err(e) => abort(e)
  }
  assert_eq(conf2.theme, "")
}
