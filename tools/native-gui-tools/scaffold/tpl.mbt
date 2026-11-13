// 脚手架模板构造：moon.mod / moon.pkg / mng.toml / main.mbt / 首页与单页样板。

///|
/// 版本缺省：不在 native-gui workspace 内时用的兜底值（注释提醒用户改成
/// 自己锁定的版本）。
const SCAFFOLD_GUI_FALLBACK : String = "0.3.3"

///|
const SCAFFOLD_YOGA_FALLBACK : String = "0.1.1"

///|
fn moon_mod_tpl(
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
fn moon_pkg_tpl(mod_name : String) -> String {
  "import {\n  \"NoahLiu/native-gui/ui\",\n  \"NoahLiu/native-gui/shell\" @shell,\n  \"" +
  mod_name +
  "/pages\" @pages,\n}\n\npkgtype(kind: \"executable\")\n\nsupported_targets = \"native\"\n"
}

///|
/// pages 包配置：生成码引用的别名（@yoga/@ui/@base/@style/@widget/@text/@mngdev）。
/// 没有 moon.pkg 的目录不成其为包，主包 import `<模块>/pages` 会解不出。
fn pages_pkg_tpl() -> String {
  "import {\n  \"NoahLiu/yoga-mbt/src\" @yoga,\n  \"NoahLiu/native-gui/ui\",\n  \"NoahLiu/native-gui/base\" @base,\n  \"NoahLiu/native-gui/style\" @style,\n  \"NoahLiu/native-gui/widget\" @widget,\n  \"NoahLiu/native-gui/text\" @text,\n  \"NoahLiu/native-gui/mngdev\" @mngdev,\n}\n\nsupported_targets = \"native\"\n"
}

///|
fn mng_toml_tpl() -> String {
  let dev = "# mng 工程配置（mng dev / mng build 无参时向上找到本文件）。\n[dev]\n\n# 递归扫 *.mng（跳过 _build / .mooncakes / 点目录）\ntemplates = [\".\"]\n\nbuild = \"moon build .\"\n\n# 留空 = 跑一次 build 后从 Artifacts 抓可执行路径\nrun = \"\"\n\n"
  dev + package_section() + "\n"
}

///|
/// mng.toml 的 [package] / [package.sign] 样板段（init 与 `mng new` 脚手架
/// 共用——脚手架此前只写 [dev]，新工程打首个包必撞「id 未配置」）。
pub fn package_section() -> String {
  let lines = [
    "# mng package 的打包声明（在项目根执行；本平台打本平台包）",
    "[package]", "# 反域名 id：mac bundle id / 产物短名同源", "id = \"\"",
    "# 显示名（.app / DMG 卷名 / 安装器标题）", "name = \"\"", "# 应用版本，三段数字；与 moon.mod 的模块版本无关",
    "version = \"0.1.0\"", "# 可执行名；留空 = 从构建产物抓", "bin = \"\"",
    "# 源图标：1024x1024 PNG，派生 icns/ico", "icon = \"\"", "# 随包资源（递归拷进 Contents/Resources / 安装目录）",
    "resources = []", "# deb control 的 Maintainer（\"名 <邮箱>\"）；留空 = unknown <>",
    "maintainer = \"\"", "", "# 签名证书入口（全留空 = mac adhoc、win 不签）",
    "[package.sign]", "# codesign identity；如 \"Developer ID Application: NAME (TEAMID)\"",
    "mac_identity = \"\"", "# notarytool keychain profile；非空则公证 + staple",
    "notarize_profile = \"\"",
  ]
  lines.join("\n")
}

///|
fn main_mbt_tpl(mod_name : String) -> String {
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
fn home_mng_tpl() -> String {
  "<script>\nlet count : @base.Store[Int32] = @base.Store::new(0)\n</script>\n<template>\n  <ui-col class=\"page\">\n    <ui-text class=\"title\" text=\"Hello, .mng!\" />\n    <ui-text text=\"改本页保存：受限改动亚秒 HOT，script/行模板走 COLD 重启回本页。\" />\n    <ui-stepper v-model=\"count\" max=\"10\" />\n    计数: {{ count }}\n  </ui-col>\n</template>\n<style>\n  .page {\n    padding: 24px;\n    row-gap: 8px;\n    align-items: center;\n  }\n  .title {\n    font-size: 18px;\n    font-weight: bold;\n  }\n</style>\n"
}

///|
/// 模块名 → 单实例 app_id：小写、`/` → `.`、其余非法字符 → `_`；
/// 派生结果无点分（裸名工程，无作者段）时垫 `local.` 命名空间——
/// 字法规格要 ≥2 个点分元素，裸名会让 instance_claim 给 InvalidAppId、
/// 单实例通道整个降级（mng dev 的 HOT 唤起与 COLD 回页全失效）。
pub fn app_id_of_module(name : String) -> String {
  let out = StringBuilder()
  for c in name {
    if (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '-' || c == '_' {
      out.write_char(c)
    } else if c >= 'A' && c <= 'Z' {
      match (c.to_int() + 32).to_char() {
        Some(x) => out.write_char(x)
        None => ()
      }
    } else if c == '/' {
      out.write_char('.')
    } else {
      out.write_char('_')
    }
  }
  let s = out.to_string()
  let mut has_dot = false
  for c in s {
    if c == '.' {
      has_dot = true
      break
    }
  }
  if has_dot {
    s
  } else {
    "local." + s
  }
}
