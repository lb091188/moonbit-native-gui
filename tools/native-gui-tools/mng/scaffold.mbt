// `mng new <name>`（或显式 `mng new app <name>`）：生成可跑最小模板工程——
// moon.mod（gui/yoga 版本从 workspace 现读）、全套 import 的 moon.pkg、
// mng.toml、main.mbt、首页 .mng + dev 形态生成码（热更面在库包 @mngdev，
// 应用零复制）。与 `mng new page <路径>`（单页样板）、`mng init`（只写
// mng.toml）互补。

///|
/// 版本缺省：不在 native-gui workspace 内时用的兜底值（注释提醒用户改成
/// 自己锁定的版本）。
const SCAFFOLD_GUI_FALLBACK : String = "0.3.1"

///|
const SCAFFOLD_YOGA_FALLBACK : String = "0.1.1"

///|
/// 脚手架入口：在 `parent/<name>/` 生成工程。目录已存在拒绝（不覆盖）。
/// 返回 0 成功；非 0 失败并已打印原因。
fn scaffold_app_at(parent : String, raw_name : String) -> Int32 {
  let name = scaffold_mod_name(raw_name)
  if name.length() == 0 {
    println(
      tmsg(
        "工程名非法（字母/数字/下划线/连字符）：\{raw_name}",
        "Invalid project name (letters/digits/underscore/hyphen): \{raw_name}",
      ),
    )
    return 2
  }
  let dir = parent + "/" + name
  if @fs.path_exists(dir) {
    println(
      tmsg(
        "目录已存在，不覆盖：" + dir,
        "Directory already exists, not overwriting: " + dir,
      ),
    )
    return 1
  }
  if !mkdir_p(dir + "/pages") {
    println(
      tmsg(
        "建不出目录：" + dir + "/pages",
        "Cannot create directory: " + dir + "/pages",
      ),
    )
    return 1
  }
  let (gui_ver, yoga_ver) = scaffold_versions(parent)
  let mod_name = name
  let spit_ok = fn(p : String, body : String) -> Bool {
    spit(dir + "/" + p, body)
  }
  let ok = spit_ok("moon.mod", scaffold_moon_mod(mod_name, gui_ver, yoga_ver)) &&
    spit_ok("moon.pkg", scaffold_moon_pkg(mod_name)) &&
    spit_ok("pages/moon.pkg", scaffold_pages_pkg()) &&
    spit_ok("mng.toml", scaffold_mng_toml()) &&
    spit_ok("main.mbt", scaffold_main_mbt(mod_name)) &&
    spit_ok("pages/home.mng", scaffold_home_mng())
  if !ok {
    println(
      tmsg(
        "工程文件写失败（目录已删除）：" + dir,
        "Failed writing project files (directory removed): " + dir,
      ),
    )
    let _ = @fs.remove_dir(dir) catch { _ => () }
    return 1
  }
  // 首页生成码：dev 形态（热更面在 @mngdev，CI 对账与 mng dev 同形）
  match mng_compile_dev(scaffold_home_mng(), dir + "/pages/home.mng") {
    Err(e) => {
      println(
        tmsg(
          "首页模板编译失败（脚手架缺陷，请回报）：\{e}",
          "Home template compile failed (scaffold bug, please report): \{e}",
        ),
      )
      return 1
    }
    Ok(r) =>
      if !spit_ok("pages/home.gen.mbt", r.code) {
        println(
          tmsg(
            "生成码写失败：" + dir + "/pages/home.gen.mbt",
            "Failed writing generated code: " + dir + "/pages/home.gen.mbt",
          ),
        )
        return 1
      }
  }
  println("OK " + dir)
  println(
    tmsg(
      "下一步：cd \{name} && moon run .   （热更：mng dev）",
      "Next: cd \{name} && moon run .   (hot reload: mng dev)",
    ),
  )
  0
}

///|
/// 工程名合法化：字母/数字/下划线/连字符；首字符数字垫 _。
fn scaffold_mod_name(raw : String) -> String {
  let a = chars_of(raw)
  let out = StringBuilder()
  for c in a {
    if (c >= 'a' && c <= 'z') ||
      (c >= 'A' && c <= 'Z') ||
      (c >= '0' && c <= '9') ||
      c == '_' ||
      c == '-' {
      out.write_char(c)
    }
  }
  let s = out.to_string()
  if s.length() == 0 || is_digit_m(s.to_array()[0]) {
    "_" + s
  } else {
    s
  }
}

///|
/// 版本现读：向上找 moon.work → 读 gui/moon.mod 的 version 与 yoga import；
/// 不在仓库内给兜底值。
fn scaffold_versions(from : String) -> (String, String) {
  let mut cur = from
  let mut hops = 0
  while hops < 24 {
    if (match fs_read(cur + "/moon.work") {
        Some(_) => true
        None => false
      }) {
      let gmod = match fs_read(cur + "/gui/moon.mod") {
        Some(t) => t
        None => return (SCAFFOLD_GUI_FALLBACK, SCAFFOLD_YOGA_FALLBACK)
      }
      let gui_ver = match scaffold_line_value(gmod, "version") {
        Some(v) => v
        None => SCAFFOLD_GUI_FALLBACK
      }
      let yoga_ver = match scaffold_import_ver(gmod, "NoahLiu/yoga-mbt") {
        Some(v) => v
        None => SCAFFOLD_YOGA_FALLBACK
      }
      return (gui_ver, yoga_ver)
    }
    let up = dir_of_m(cur)
    if up == cur {
      break
    }
    cur = up
    hops += 1
  }
  (SCAFFOLD_GUI_FALLBACK, SCAFFOLD_YOGA_FALLBACK)
}

///|
/// moon.mod 顶层键取值：`version = "0.3.1"` → 0.3.1。
fn scaffold_line_value(text : String, key : String) -> String? {
  for line0 in text.split("\n") {
    let line = trim_spaces(line0.to_owned())
    if line.has_prefix(key + " ") || line.has_prefix(key + "=") {
      let rest = trim_spaces(line[key.length():].to_owned())
      if rest.has_prefix("=") {
        return Some(unquote(rest[1:].to_owned()))
      }
    }
  }
  None
}

///|
/// moon.mod import 块里 `"<pkg>@<ver>"` 的版本。
fn scaffold_import_ver(text : String, pkg : String) -> String? {
  for line0 in text.split("\n") {
    let line = trim_spaces(line0.to_owned())
    if line.has_prefix("\"" + pkg + "@") && line.has_suffix("\",") {
      let body = line[1:line.length() - 2].to_owned()
      let at = match index_of_char(body, '@') {
        Some(i) => i
        None => continue
      }
      return Some(body[at + 1:].to_owned())
    }
  }
  None
}

///|
fn dir_of_m(p : String) -> String {
  let a = chars_of(p)
  let mut last = -1
  for i, c in a {
    if c == '/' {
      last = i
    }
  }
  if last <= 0 {
    p
  } else {
    slice_path(a, 0, last)
  }
}

///|
fn scaffold_moon_mod(
  mod_name : String,
  gui_ver : String,
  yoga_ver : String,
) -> String {
  let head = "name = \"" +
    mod_name +
    "\"\n\nversion = \"0.1.0\"\n\npreferred_target = \"native\"\n\ndescription = \"native-gui 模板应用（.mng 单文件组件 + mng dev/build）\"\n\nlicense = \"MIT\"\n\nimport {\n  \"NoahLiu/native-gui@" +
    gui_ver +
    "\",\n  \"NoahLiu/yoga-mbt@" +
    yoga_ver +
    "\",\n}\n"
  if gui_ver == SCAFFOLD_GUI_FALLBACK {
    head +
    "\n// 版本是兜底值：不在 native-gui workspace 内生成时读不到现读版本，\n// 按你锁定的发布版改这两行。\n"
  } else {
    head
  }
}

///|
/// 主包配置：只 import main.mbt 用到的（moon 对未用 import 报 warning，
/// 门禁零警告）；页面生成码的别名集在 pages 包自己的 moon.pkg。
fn scaffold_moon_pkg(mod_name : String) -> String {
  "import {\n  \"NoahLiu/native-gui/ui\",\n  \"NoahLiu/native-gui/shell\" @shell,\n  \"" +
  mod_name +
  "/pages\" @pages,\n}\n\npkgtype(kind: \"executable\")\n\nsupported_targets = \"native\"\n"
}

///|
/// pages 包配置：生成码引用的别名（@yoga/@ui/@base/@style/@widget/@text/@mngdev）。
/// 没有 moon.pkg 的目录不成其为包，主包 import `<模块>/pages` 会解不出。
fn scaffold_pages_pkg() -> String {
  "import {\n  \"NoahLiu/yoga-mbt/src\" @yoga,\n  \"NoahLiu/native-gui/ui\",\n  \"NoahLiu/native-gui/base\" @base,\n  \"NoahLiu/native-gui/style\" @style,\n  \"NoahLiu/native-gui/widget\" @widget,\n  \"NoahLiu/native-gui/text\" @text,\n  \"NoahLiu/native-gui/mngdev\" @mngdev,\n}\n\nsupported_targets = \"native\"\n"
}

///|
fn scaffold_mng_toml() -> String {
  let dev = "# mng 工程配置（mng dev / mng build 无参时向上找到本文件）。\n[dev]\n\n# 递归扫 *.mng（跳过 _build / .mooncakes / 点目录）\ntemplates = [\".\"]\n\nbuild = \"moon build .\"\n\n# 留空 = 跑一次 build 后从 Artifacts 抓可执行路径\nrun = \"\"\n\n"
  dev + mng_toml_package_section() + "\n"
}

///|
fn scaffold_main_mbt(mod_name : String) -> String {
  let app_id = app_id_of_module(mod_name)
  let head = "// 模板应用入口：页面在 pages/home.mng（单文件组件），生成码 pages/home.gen.mbt\n"
  let head = head +
    "// 入口只有生产语义：单实例声称 + 挂窗。dev 三通道由 dev 形态生成码自装\n"
  let head = head +
    "// （生产构建换生产形态生成码后 dev 面整体不在包里），唤起泵在 ui 库内自排。\n\n///|\n"
  let head = head + "fn main {\n"
  let head = head + "  match @shell.instance_claim(\"" + app_id + "\") {\n"
  let head = head + "    Ok(@shell.Existing) => {\n"
  let head = head +
    "      let _ = @shell.instance_wake(\"" +
    app_id +
    "\", [])\n"
  let head = head +
    "      println(\"APP-INST: 已有实例，已唤起并退出\")\n"
  let head = head + "      return\n"
  let head = head + "    }\n"
  let head = head +
    "    Err(e) => println(\"APP-INST: 单实例降级：\" + e.to_string())\n"
  let head = head + "    Ok(@shell.Primary) => ()\n"
  let head = head + "  }\n"
  let head = head + "  let app = match @ui.mount_window(\n"
  let head = head + "    [@pages.home()],\n"
  let head = head + "    title=\"Template App\",\n"
  let head = head + "    width=420,\n"
  let head = head + "    height=360,\n"
  let head = head + "  ) {\n"
  let head = head + "    None => {\n"
  let head = head +
    "      println(\"APP-SKIP: 本平台没有窗口后端或没有显示服务\")\n"
  let head = head + "      return\n"
  let head = head + "    }\n"
  let head = head + "    Some(a) => a\n"
  let head = head + "  }\n"
  let head = head + "  app.run()\n"
  let head = head + "}\n"
  head
}

///|
fn scaffold_home_mng() -> String {
  "<script>\nlet count : @base.Store[Int] = @base.Store::new(0)\n</script>\n<template>\n  <ui-col class=\"page\">\n    <ui-text class=\"title\" text=\"Hello, .mng!\" />\n    <ui-text text=\"改本页保存：受限改动亚秒 HOT，script/行模板走 COLD 重启回本页。\" />\n    <ui-stepper v-model=\"count\" max=\"10\" />\n    计数: {{ count }}\n  </ui-col>\n</template>\n<style>\n  .page {\n    padding: 24px;\n    row-gap: 8px;\n    align-items: center;\n  }\n  .title {\n    font-size: 18px;\n    font-weight: bold;\n  }\n</style>\n"
}
