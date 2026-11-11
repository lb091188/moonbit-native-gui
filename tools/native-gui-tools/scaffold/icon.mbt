// 图标步：把用户给的 PNG 收进工程并接线 mng.toml 的 [package].icon。
// icns/ico 各档派生归 `mng package` 打包时做，这里只落源文件与声明。

///|
/// 拷 `<png>` 到 `<dir>/assets/icon.png` 并把 mng.toml 的 `icon = ""` 改指向它。
/// 返回工程内相对路径；源不存在 / 拷贝或写声明失败给 Err。
pub fn icon_step(dir~ : String, png~ : String) -> Result[String, String] {
  if png.length() == 0 {
    return Err("图标路径为空")
  }
  if !@fs.path_exists(png) {
    return Err("图标文件不存在：" + png)
  }
  let bytes = @fs.read_file_to_bytes(png) catch {
    _ => return Err("图标读不出来：" + png)
  }
  if !mkdir_p(dir + "/assets") {
    return Err("建不出目录：" + dir + "/assets")
  }
  let rel = "assets/icon.png"
  @fs.write_bytes_to_file(dir + "/" + rel, bytes) catch {
    _ => return Err("图标拷不进工程：" + dir + "/" + rel)
  }
  let toml_path = dir + "/mng.toml"
  let toml = @fs.read_file_to_string(toml_path) catch {
    _ => return Err("读不到 " + toml_path + "——先建工程再设图标")
  }
  let patched = replace_icon_line(toml, rel)
  if !spit(toml_path, patched) {
    return Err("写不回 " + toml_path)
  }
  Ok(rel)
}

///|
/// mng.toml 文本里 `icon = "…"` 一行的替换（只替第一处 [package] 段内的；
/// 纯函数，wbtest 钉口径）。
fn replace_icon_line(toml : String, rel : String) -> String {
  let out = StringBuilder()
  let mut replaced = false
  for line0 in toml.split("\n") {
    let line = line0.to_owned()
    if !replaced && line.has_prefix("icon = ") {
      out.write_string("icon = \"" + rel + "\"")
      replaced = true
    } else {
      out.write_string(line)
    }
    out.write_char('\n')
  }
  // 原文若以 \n 结尾，上面逐行补 \n 会多一个——去尾对齐
  let s = out.to_string()
  if toml.has_suffix("\n") {
    if s.has_suffix("\n\n") {
      s[:s.length() - 1].to_owned()
    } else {
      s
    }
  } else if s.has_suffix("\n") {
    s[:s.length() - 1].to_owned()
  } else {
    s
  }
}
