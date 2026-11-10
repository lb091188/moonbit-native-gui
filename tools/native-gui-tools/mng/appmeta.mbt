// appmeta:应用元信息单源。mng.toml [package] 的 id/name/version 生成叶子包
// <项目根>/appmeta/(appmeta.gen.mbt 三常量),应用侧(更新对话框「当前版本」、
// 单实例 app-id 等)从这里 import——不再手抄 mng.toml,免「改了配置忘改源码
// 常量」的双源漂移。mng dev 首轮与 mng build(全工程)都重生成;内容没变不写盘。
// id 或 version 缺省(没配打包的 dev-only 工程)不生成。

///|
/// appmeta 包的 moon.pkg(叶子包,无 import)。
const APPMETA_PKG : String = "// 应用元信息叶子包:内容全由 mng 从 mng.toml [package] 生成(appmeta.gen.mbt),不手改\n"

///|
/// appmeta.gen.mbt 文本;值过 JSON 同口径转义(引号/反斜杠/控制字符)。
fn appmeta_text(id : String, name : String, version : String) -> String {
  let lines = [
    "// 由 mng 从 mng.toml [package] 生成——勿手改;改 mng.toml 后跑 mng dev / mng build 同步",
    "",
    "///|",
    "/// 应用版本(mng.toml [package].version):更新链路「当前版本」的同源值。",
    "pub let app_version : String = \"" + pub_json_escape(version) + "\"",
    "",
    "///|",
    "/// 应用 id(mng.toml [package].id,反域名):单实例/托盘/通知的同源值。",
    "pub let app_id : String = \"" + pub_json_escape(id) + "\"",
    "",
    "///|",
    "/// 应用显示名(mng.toml [package].name):托盘/通知/桌面登记的同源值。",
    "pub let app_name : String = \"" + pub_json_escape(name) + "\"",
    "",
  ]
  lines.join("\n")
}

///|
/// 读 <root>/mng.toml 的 [package] 生成 appmeta 包:id 或 version 空(未配置
/// 打包)跳过给 Ok(false);生成内容与现存一致不写盘给 Ok(false);写了新内容
/// 给 Ok(true)。moon.pkg 缺则补。失败给 Err(带路径)。
fn sync_appmeta(root : String) -> Result[Bool, String] {
  let text = match fs_read(root + "/mng.toml") {
    Some(t) => t
    None => return Ok(false)
  }
  let p = parse_package_toml(text)
  if p.id.length() == 0 || p.version.length() == 0 {
    return Ok(false)
  }
  let dir = root + "/appmeta"
  if !mkdir_p(dir) {
    return Err("建不出目录：" + dir)
  }
  let pkg = dir + "/moon.pkg"
  match fs_read(pkg) {
    Some(_) => ()
    None =>
      if !spit(pkg, APPMETA_PKG) {
        return Err("写不出：" + pkg)
      }
  }
  let body = appmeta_text(p.id, p.name, p.version)
  let gp = dir + "/appmeta.gen.mbt"
  match fs_read(gp) {
    Some(old) =>
      if old == body {
        return Ok(false)
      }
    None => ()
  }
  if !spit(gp, body) {
    return Err("写不出：" + gp)
  }
  Ok(true)
}
