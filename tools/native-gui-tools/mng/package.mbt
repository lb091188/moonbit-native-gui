// mng package:应用打包。本平台打本平台包(D1);平台分腿——
// mac 腿:.app 组装 + icns 派生 + DMG + 更新载体 zip + 签名/公证档;
// win 腿:NSIS setup 安装器 + ICO 派生 + 更新载体 zip + signtool 档;
// linux 腿:deb + AppImage(AppImage 兼作更新载体)。
// 配置在 mng.toml [package] / [package.sign] / [package.linux];方案见
// proposals/package-update.md。产物落 <项目根>/.mng/dist/,不进源码树。
// 约定在项目根执行(与 mng dev 同口径)。

///|
/// mng.toml [package] / [package.sign] / [package.linux] 原文 → 打包配置(缺省为空)。
priv struct PkgConf {
  mut id : String
  mut name : String
  mut version : String
  mut bin : String
  mut icon : String
  mut resources : Array[String]
  mut targets : Array[String]
  mut sign_mac : String // codesign identity;空 = adhoc("-")
  mut notarize_profile : String // notarytool keychain profile;空 = 不公证
  mut win_cert : String // win 腿消费
  mut win_cert_pw_env : String
  mut linux_categories : Array[String] // desktop entry Categories;缺省 Utility
  mut linux_comment : String // desktop entry Comment;可空
  mut maintainer : String // 「名 <邮箱>」形态;deb control Maintainer 用,缺省 unknown <>
}

///|
fn pkg_conf_default() -> PkgConf {
  {
    id: "",
    name: "",
    version: "",
    bin: "",
    icon: "",
    resources: [],
    targets: [],
    sign_mac: "",
    notarize_profile: "",
    win_cert: "",
    win_cert_pw_env: "",
    linux_categories: [],
    linux_comment: "",
    maintainer: "",
  }
}

///|
/// [package] 与 [package.sign] 两节;其他节忽略。行级口径同 parse_dev_toml。
fn parse_package_toml(text : String) -> PkgConf {
  let t = pkg_conf_default()
  let mut section = ""
  for raw in text.split("\n") {
    let line = trim_spaces(strip_comment(raw.to_owned()))
    if line.length() == 0 {
      continue
    }
    if line.has_prefix("[") && line.has_suffix("]") {
      section = line[1:line.length() - 1].to_owned().trim().to_owned()
      continue
    }
    let eq = match index_of_char(line, '=') {
      Some(i) => i
      None => continue
    }
    let key = trim_spaces(line[:eq].to_owned())
    let val = line[eq + 1:].to_owned()
    if section == "package" {
      match key {
        "id" => t.id = unquote(val)
        "name" => t.name = unquote(val)
        "version" => t.version = unquote(val)
        "bin" => t.bin = unquote(val)
        "icon" => t.icon = unquote(val)
        "resources" => t.resources = parse_str_array(val)
        "targets" => t.targets = parse_str_array(val)
        "maintainer" => t.maintainer = unquote(val)
        _ => ()
      }
    } else if section == "package.sign" {
      match key {
        "mac_identity" => t.sign_mac = unquote(val)
        "notarize_profile" => t.notarize_profile = unquote(val)
        "win_cert" => t.win_cert = unquote(val)
        "win_cert_pw_env" => t.win_cert_pw_env = unquote(val)
        _ => ()
      }
    } else if section == "package.linux" {
      match key {
        "categories" => t.linux_categories = parse_str_array(val)
        "comment" => t.linux_comment = unquote(val)
        _ => ()
      }
    }
  }
  t
}

///|
/// semver 三段(a.b.c,每段纯数字)。
fn semver_ok(v : String) -> Bool {
  let parts = collect_array_dev(v.split(".").map(fn(x) { x.to_owned() }))
  if parts.length() != 3 {
    return false
  }
  for p in parts {
    if p.length() == 0 {
      return false
    }
    for c in p {
      if c < '0' || c > '9' {
        return false
      }
    }
  }
  true
}

///|
/// 打包前置校验:id 反域名(至少一个点)、version 三段、name 非空、targets 拼写、
/// win 证书密码环境变量配套;返回错误文案。
fn pkg_validate(p : PkgConf) -> String? {
  if p.id.length() == 0 {
    return Some("[package] id 未配置")
  }
  let mut has_dot = false
  for c in p.id {
    if c == '.' {
      has_dot = true
      break
    }
  }
  if !has_dot {
    return Some(
      "[package] id 须为反域名(至少一个点),如 com.example.myapp",
    )
  }
  if p.name.length() == 0 {
    return Some("[package] name 未配置")
  }
  if !semver_ok(p.version) {
    return Some(
      "[package] version 须为三段数字,如 1.2.0(当前:\{p.version})",
    )
  }
  for t in p.targets {
    if !(t == "dmg" || t == "setup" || t == "deb" || t == "appimage") {
      return Some(
        "[package] targets 只认 dmg/setup/deb/appimage(不识:\{t})",
      )
    }
  }
  if p.win_cert.length() > 0 && p.win_cert_pw_env.length() == 0 {
    return Some(
      "[package.sign] 配了 win_cert 就要配 win_cert_pw_env(证书密码的环境变量名)",
    )
  }
  None
}

///|
/// id 末段当产物短名(com.example.myapp → myapp)。
fn slug_of(id : String) -> String {
  let mut last = id
  for raw in id.split(".") {
    let s = raw.to_owned()
    if s.length() > 0 {
      last = s
    }
  }
  last
}

///|
fn esc_xml(s : String) -> String {
  let out = StringBuilder()
  for c in s {
    if c == '&' {
      out.write_string("&amp;")
    } else if c == '<' {
      out.write_string("&lt;")
    } else if c == '>' {
      out.write_string("&gt;")
    } else {
      out.write_char(c)
    }
  }
  out.to_string()
}

///|
/// Info.plist(icns 有则带 CFBundleIconFile;字段口径沿 release-bin 的 CI 版)。
fn info_plist_xml(
  id : String,
  name : String,
  bin : String,
  version : String,
  icns : String,
) -> String {
  let icon_key = if icns.length() > 0 {
    "  <key>CFBundleIconFile</key><string>\{icns}</string>\n"
  } else {
    ""
  }
  "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n<plist version=\"1.0\">\n<dict>\n  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>\n  <key>CFBundlePackageType</key><string>APPL</string>\n  <key>CFBundleName</key><string>\{esc_xml(name)}</string>\n  <key>CFBundleDisplayName</key><string>\{esc_xml(name)}</string>\n  <key>CFBundleExecutable</key><string>\{esc_xml(bin)}</string>\n  <key>CFBundleIdentifier</key><string>\{esc_xml(id)}</string>\n  <key>CFBundleShortVersionString</key><string>\{esc_xml(version)}</string>\n  <key>CFBundleVersion</key><string>\{esc_xml(version)}</string>\n\{icon_key}  <key>NSHighResolutionCapable</key><true/>\n  <key>LSMinimumSystemVersion</key><string>11.0</string>\n</dict>\n</plist>\n"
}

///|
/// iconset 尺寸表(文件名,边长):Apple 标准十档。
let iconset_sizes : Array[(String, Int32)] = [
  ("icon_16x16.png", 16),
  ("icon_16x16@2x.png", 32),
  ("icon_32x32.png", 32),
  ("icon_32x32@2x.png", 64),
  ("icon_128x128.png", 128),
  ("icon_128x128@2x.png", 256),
  ("icon_256x256.png", 256),
  ("icon_256x256@2x.png", 512),
  ("icon_512x512.png", 512),
  ("icon_512x512@2x.png", 1024),
]

///|
/// 单引号包路径,给 sh -c 的命令行用。
fn sq(p : String) -> String {
  "'" + p + "'"
}

///|
/// 跑一条 shell 命令,stdout/stderr 落 log;非零退出码时把日志尾部打出来。
/// 依赖 `sh -c`,只在 POSIX 腿用;Windows 腿用 run_tool(spawn + 轮询)。
fn run_logged(
  cmdline : String,
  log : String,
  timeout_ms : Int32,
) -> Result[Unit, String] {
  let full = cmdline + " > " + sq(log) + " 2>&1"
  match @proc.run_wait("sh", ["-c", full], timeout_ms) {
    Err(e) => Err(e)
    Ok(0) => Ok(())
    Ok(code) => {
      print_log_tail(log)
      Err("命令退出码 \{code}:\{cmdline}")
    }
  }
}

///|
/// 打印日志尾部(默认 15 行);供执行器失败时给用户看原因。
fn print_log_tail(log : String) -> Unit {
  match slurp(log) {
    Some(t) => {
      let lines = collect_array_dev(t.split("\n").map(fn(x) { x.to_owned() }))
      let n = lines.length()
      let from = if n > 15 { n - 15 } else { 0 }
      let b = StringBuilder()
      let mut i = from
      while i < n {
        b.write_string(lines[i])
        b.write_char('\n')
        i += 1
      }
      let tail = b.to_string()
      if tail.length() > 0 {
        eprintln(tail)
      }
    }
    None => ()
  }
}

///|
/// 跨平台命令执行:起子进程、stdout/stderr 落 log、等退出并取退出码;
/// 非 0 即 Err(先印日志尾,带日志路径),超时杀进程组。
fn run_tool(
  file : String,
  args : Array[String],
  log : String,
  timeout_ms : Int32,
) -> Result[Unit, String] {
  match @proc.spawn_wait(file, args, log, timeout_ms) {
    Err(e) => Err(e)
    Ok(0) => Ok(())
    Ok(code) => {
      print_log_tail(log)
      Err("\{file} 退出码 \{code}（日志：\{log}）")
    }
  }
}

///|
/// 宿主平台判定:Windows 环境变量 OS=Windows_NT;mac 认工具链存在;
/// 其余(POSIX 且非 mac)按 linux 腿走。
fn host_pkg() -> String {
  match @env.get_env_var("OS") {
    Some("Windows_NT") => return "win"
    _ => ()
  }
  if @fs.path_exists("/usr/bin/iconutil") && @fs.path_exists("/usr/bin/hdiutil") {
    return "mac"
  }
  "linux"
}

///|
fn put_u16le(b : FixedArray[Byte], off : Int32, v : Int32) -> Unit {
  b[off] = (v & 0xff).to_byte()
  b[off + 1] = ((v >> 8) & 0xff).to_byte()
}

///|
fn put_u32le(b : FixedArray[Byte], off : Int32, v : Int32) -> Unit {
  b[off] = (v & 0xff).to_byte()
  b[off + 1] = ((v >> 8) & 0xff).to_byte()
  b[off + 2] = ((v >> 16) & 0xff).to_byte()
  b[off + 3] = ((v >> 24) & 0xff).to_byte()
}

///|
fn get_be32(b : Bytes, off : Int32) -> Int32 {
  (b[off].to_int() << 24) |
  (b[off + 1].to_int() << 16) |
  (b[off + 2].to_int() << 8) |
  b[off + 3].to_int()
}

///|
/// PNG bytes → 单帧 ICO(Vista+ 支持 ICO 内嵌 PNG 帧):读 IHDR 宽高写目录项,
/// ≥256 的边写 0(ICO 约定);载荷原样。多帧多尺寸档后续按观感反馈再扩。
fn ico_of_png(png : Bytes) -> Bytes? {
  if png.length() < 24 {
    return None
  }
  // PNG 签名:89 50 4E 47 0D 0A 1A 0A
  let sig = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]
  let mut i = 0
  while i < 8 {
    if png[i].to_int() != sig[i] {
      return None
    }
    i += 1
  }
  let w = get_be32(png, 16)
  let h = get_be32(png, 20)
  if w <= 0 || h <= 0 || w > 65535 || h > 65535 {
    return None
  }
  let out : FixedArray[Byte] = FixedArray::make(22 + png.length(), b'\x00')
  // ICONDIR:reserved 0,type 1(icon),count 1
  put_u16le(out, 2, 1)
  put_u16le(out, 4, 1)
  // ICONDIRENTRY:宽高(256 记 0)、色深 0、保留 0、planes 1、bpp 32
  out[6] = (if w >= 256 { 0 } else { w }).to_byte()
  out[7] = (if h >= 256 { 0 } else { h }).to_byte()
  out[8] = b'\x00'
  out[9] = b'\x00'
  put_u16le(out, 10, 1)
  put_u16le(out, 12, 32)
  put_u32le(out, 14, png.length())
  put_u32le(out, 18, 22)
  let mut k = 0
  while k < png.length() {
    out[22 + k] = png[k]
    k += 1
  }
  Some(Bytes::from_array(out))
}

///|
/// NSI 字符串转义:`$` → `$$`(nsi 变量前缀)。
fn esc_nsi(s : String) -> String {
  let out = StringBuilder()
  for c in s {
    if c == '$' {
      out.write_string("$$")
    } else {
      out.write_char(c)
    }
  }
  out.to_string()
}

///|
/// NSIS 安装脚本(MUI2;per-user 装法为自动更新铺路):路径全绝对,
/// 不依赖 makensis 的 cwd 语义;File /x 排除脚本自身。
fn nsi_script(
  id : String,
  name : String,
  bin_exe : String,
  version : String,
  stage : String,
  slug : String,
  setup : String,
) -> String {
  let e_id = esc_nsi(id)
  let e_name = esc_nsi(name)
  let icon = stage + "\\" + slug + ".ico"
  let uninst_key = "Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\" +
    e_id
  "Unicode true\n" +
  "OutFile \"" +
  esc_nsi(setup) +
  "\"\n" +
  "Name \"" +
  e_name +
  "\"\n" +
  "Icon \"" +
  icon +
  "\"\n" +
  "UninstallIcon \"" +
  icon +
  "\"\n" +
  "InstallDir \"$LOCALAPPDATA\\Programs\\" +
  e_id +
  "\"\n" +
  "RequestExecutionLevel user\n" +
  "SetCompressor /solid lzma\n" +
  "!include \"MUI2.nsh\"\n" +
  "!insertmacro MUI_PAGE_DIRECTORY\n" +
  "!insertmacro MUI_PAGE_INSTFILES\n" +
  "!insertmacro MUI_LANGUAGE \"SimpChinese\"\n" +
  "!insertmacro MUI_LANGUAGE \"English\"\n" +
  "Section \"install\"\n" +
  "  SetOutPath \"$INSTDIR\"\n" +
  "  File /r /x installer.nsi \"" +
  stage +
  "\\*.*\"\n" +
  "  CreateDirectory \"$SMPROGRAMS\\" +
  e_name +
  "\"\n" +
  "  CreateShortcut \"$SMPROGRAMS\\" +
  e_name +
  "\\" +
  e_name +
  ".lnk\" \"$INSTDIR\\" +
  esc_nsi(bin_exe) +
  "\"\n" +
  "  CreateShortcut \"$SMPROGRAMS\\" +
  e_name +
  "\\Uninstall " +
  e_name +
  ".lnk\" \"$INSTDIR\\uninstall.exe\"\n" +
  "  WriteUninstaller \"$INSTDIR\\uninstall.exe\"\n" +
  "  WriteRegStr HKCU \"" +
  uninst_key +
  "\" \"DisplayName\" \"" +
  e_name +
  "\"\n" +
  "  WriteRegStr HKCU \"" +
  uninst_key +
  "\" \"DisplayVersion\" \"" +
  esc_nsi(version) +
  "\"\n" +
  "  WriteRegStr HKCU \"" +
  uninst_key +
  "\" \"UninstallString\" \"$\\\"$INSTDIR\\uninstall.exe$\\\"\"\n" +
  "  WriteRegStr HKCU \"" +
  uninst_key +
  "\" \"InstallLocation\" \"$INSTDIR\"\n" +
  "SectionEnd\n" +
  "Section \"Uninstall\"\n" +
  "  Delete \"$SMPROGRAMS\\" +
  e_name +
  "\\" +
  e_name +
  ".lnk\"\n" +
  "  Delete \"$SMPROGRAMS\\" +
  e_name +
  "\\Uninstall " +
  e_name +
  ".lnk\"\n" +
  "  RMDir \"$SMPROGRAMS\\" +
  e_name +
  "\"\n" +
  "  RMDir /r \"$INSTDIR\"\n" +
  "  DeleteRegKey HKCU \"" +
  uninst_key +
  "\"\n" +
  "SectionEnd\n"
}

///|
/// makensis 探测:PATH → NSIS 默认安装位;探测动作 = 跑 /VERSION 落 log。
fn find_makensis() -> String? {
  let cands = [
    "makensis", "C:\\Program Files (x86)\\NSIS\\makensis.exe", "C:\\Program Files\\NSIS\\makensis.exe",
  ]
  let log = match @env.get_env_var("TEMP") {
    Some(t) if t != "" => t + "\\mng-makensis-probe.log"
    _ => "/tmp/mng-makensis-probe.log"
  }
  for c in cands {
    match run_tool(c, ["/VERSION"], log, 10000) {
      Ok(_) =>
        match slurp(log) {
          Some(t) if t.trim().to_owned().length() > 0 => {
            ignore(@fs.remove_file(log) catch { _ => () })
            return Some(c)
          }
          _ => ()
        }
      Err(_) => ()
    }
  }
  None
}

///|
/// desktop entry(AppImage 的放 AppDir 根、deb 的放 usr/share/applications)。
/// Categories 缺省 Utility;分号分隔、末尾补分号(freedesktop 口径)。
fn desktop_entry(
  name : String,
  slug : String,
  bin : String,
  categories : Array[String],
  comment : String,
) -> String {
  let cats = if categories.length() > 0 {
    categories.join(";") + ";"
  } else {
    "Utility;"
  }
  let cmt = if comment.length() > 0 { "Comment=" + comment + "\n" } else { "" }
  // StartupWMClass 让 dock/任务栏把窗口归到本菜单项(值=可执行名,与 GTK 窗口
  // class 的缺省来源一致);不写时部分桌面按 WM_NAME 猜,图标对不上号
  "[Desktop Entry]\nType=Application\nName=" +
  name +
  "\nExec=" +
  bin +
  "\nIcon=" +
  slug +
  "\nTerminal=false\n" +
  cmt +
  "Categories=" +
  cats +
  "\nStartupWMClass=" +
  bin +
  "\n"
}

///|
/// deb 的 DEBIAN/control(架构钉 amd64 = linux-x86_64 支持面);Maintainer 可由
/// [package] maintainer 配,缺省 unknown <>。
fn deb_control(
  slug : String,
  name : String,
  version : String,
  maintainer : String,
) -> String {
  let who = if maintainer.length() > 0 { maintainer } else { "unknown <>" }
  "Package: " +
  slug +
  "\nVersion: " +
  version +
  "\nSection: utils\nPriority: optional\nArchitecture: amd64\nMaintainer: " +
  who +
  "\nDescription: " +
  name +
  " (packaged by mng)\n"
}

///|
/// AppImage 的 AppRun:解析真实路径后 exec 同树 usr/bin 下的可执行。
fn apprun_script(bin : String) -> String {
  "#!/bin/sh\nHERE=\"$(dirname \"$(readlink -f \"$0\")\")\"\nexec \"$HERE/usr/bin/" +
  bin +
  "\" \"$@\"\n"
}

///|
/// 拷完可执行补可执行位(copy_file 走字节读写不保权限位);win 无 chmod 不调。
fn ensure_exec(path : String, dist : String) -> Bool {
  if host_pkg() == "win" {
    return true
  }
  match run_logged("chmod +x " + sq(path), dist + "/chmod.log", 10000) {
    Ok(_) => true
    Err(_) => false
  }
}

///|
/// 递归删目录（remove_dir 只删得动空目录；dist 清场、DMG 卷目录残骸用）。
/// 先按文件删、失败才当目录递归：is_dir 会跟随符号链接（DMG 卷里的
/// Applications → /Applications），按文件删对链接只摘链接本身，不会进目标。
fn rm_rf(root : String) -> Unit {
  if !@fs.path_exists(root) {
    return
  }
  if !(@fs.is_dir(root) catch { _ => false }) {
    ignore(@fs.remove_file(root) catch { _ => () })
    return
  }
  let entries = @fs.read_dir(root) catch { _ => return }
  for name in entries {
    let p = root + "/" + name
    let gone = try {
      @fs.remove_file(p)
      true
    } catch {
      _ => false
    }
    if !gone {
      rm_rf(p)
    }
  }
  ignore(@fs.remove_dir(root) catch { _ => () })
}

///|
/// appimagetool 探测与自取:PATH → ~/.mng/tools/appimagetool.AppImage;
/// 缺失从 AppImageKit continuous 下载(curl -L)并 chmod +x。continuous
/// 无可钉 sha,校验靠功能探测(--version 落 log);跑法恒带
/// --appimage-extract-and-run(FUSE 缺失环境也能出包,CI 容器必需)。
fn find_or_fetch_appimagetool(dist : String) -> String? {
  let ver_args = ["--appimage-extract-and-run", "--version"]
  // 1) PATH
  let probe = "/tmp/mng-appimagetool-probe.log"
  match run_tool("appimagetool", ver_args, probe, 60000) {
    Ok(_) =>
      match slurp(probe) {
        Some(t) if t.trim().to_owned().length() > 0 =>
          return Some("appimagetool")
        _ => ()
      }
    Err(_) => ()
  }
  // 2) 用户级缓存 ~/.mng/tools/
  let home = match @env.get_env_var("HOME") {
    Some(h) if h != "" => h
    _ => return None
  }
  let tool = home + "/.mng/tools/appimagetool.AppImage"
  let tool_ok = @fs.is_file(tool) catch { _ => false }
  if !tool_ok {
    println(
      tmsg(
        "下载 appimagetool(首次)…", "downloading appimagetool (first run)…",
      ),
    )
    if !mkdir_p(home + "/.mng/tools") {
      return None
    }
    match
      run_tool(
        "curl",
        [
          // -f:HTTP 错误码当失败,不把错误页写进目标文件留半截缓存
          "-fL", "--retry", "3", "-o", tool, "https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-x86_64.AppImage",
        ],
        dist + "/appimagetool-dl.log",
        300000,
      ) {
      Ok(_) => ()
      Err(_) => {
        let _ = @fs.remove_file(tool) catch { _ => () }
        print_log_tail(dist + "/appimagetool-dl.log")
        return None
      }
    }
    if !ensure_exec(tool, dist) {
      let _ = @fs.remove_file(tool) catch { _ => () }
      return None
    }
  }
  // 功能探测:缓存的文件跑不起来(断网期留下的半截文件等)就删掉,
  // 下次运行重新下载——否则坏缓存会永远占位
  match run_tool(tool, ver_args, dist + "/appimagetool-probe.log", 60000) {
    Ok(_) =>
      match slurp(dist + "/appimagetool-probe.log") {
        Some(t) if t.trim().to_owned().length() > 0 => return Some(tool)
        _ => {
          let _ = @fs.remove_file(tool) catch { _ => () }
          None
        }
      }
    Err(_) => {
      let _ = @fs.remove_file(tool) catch { _ => () }
      None
    }
  }
}

///|
fn copy_file(src : String, dst : String) -> Bool {
  try {
    let b = @fs.read_file_to_bytes(src)
    @fs.write_bytes_to_file(dst, b)
    true
  } catch {
    _ => false
  }
}

///|
/// 递归拷目录;文件直传。目标父目录须已存在。
fn copy_tree(src : String, dst : String) -> Bool {
  let isd = @fs.is_dir(src) catch { _ => false }
  if !isd {
    return copy_file(src, dst)
  }
  if !mkdir_p(dst) {
    return false
  }
  let entries = @fs.read_dir(src) catch { _ => return false }
  for name in entries {
    let s = src + "/" + name
    let d = dst + "/" + name
    if !copy_tree(s, d) {
      return false
    }
  }
  true
}

///|
/// 路径分隔符转 Windows 形态(给 nsi 脚本里的绝对路径用)。
fn to_win_path(p : String) -> String {
  let out = StringBuilder()
  for c in p {
    if c == '/' {
      out.write_char('\\')
    } else {
      out.write_char(c)
    }
  }
  out.to_string()
}

///|
/// mac 腿:.app 组装 + icns + 签名 + DMG + 更新 zip(+公证)。返回产物路径列表。
fn package_mac(
  conf : PkgConf,
  exe : String,
  bin_name : String,
  slug : String,
  dist : String,
) -> Result[Array[String], String] {
  // .app 目录树
  let app = dist + "/" + conf.name + ".app"
  let macdir = app + "/Contents/MacOS"
  let resdir = app + "/Contents/Resources"
  if !(mkdir_p(macdir) && mkdir_p(resdir)) {
    return Err(tmsg("建不了 .app 目录", "cannot create .app dirs"))
  }
  // mac bundle 内可执行名不带 .exe（moon 原生产物全平台带后缀；Finder/
  // LaunchServices 对 .exe 名不可靠），CFBundleExecutable 与拷入名同源
  let mac_bin = if bin_name.has_suffix(".exe") {
    bin_name[:bin_name.length() - 4].to_owned()
  } else {
    bin_name
  }
  if !copy_file(exe, macdir + "/" + mac_bin) {
    return Err(tmsg("拷可执行失败:", "copy executable failed: ") + exe)
  }
  if !ensure_exec(macdir + "/" + mac_bin, dist) {
    return Err("chmod +x failed: " + mac_bin)
  }
  for r in conf.resources {
    if !copy_tree(r, resdir + "/" + basename_of(r)) {
      return Err(tmsg("拷资源失败:", "copy resource failed: ") + r)
    }
  }
  // icns:源 png → sips 十档 → iconutil
  let icns_name = slug + ".icns"
  if conf.icon.length() > 0 {
    if !(@fs.is_file(conf.icon) catch { _ => false }) {
      return Err(tmsg("icon 不存在:", "icon not found: ") + conf.icon)
    }
    let iconset = dist + "/" + slug + ".iconset"
    if !mkdir_p(iconset) {
      return Err("mkdir iconset failed")
    }
    for pair in iconset_sizes {
      let (fname, n) = pair
      let dim = n.to_string()
      match
        run_logged(
          "sips -z \{dim} \{dim} " +
          sq(conf.icon) +
          " --out " +
          sq(iconset + "/" + fname),
          dist + "/sips.log",
          60000,
        ) {
        Ok(_) => ()
        Err(e) =>
          return Err(
            tmsg("icns 派生失败(sips):", "icns derivation failed (sips): ") +
            e,
          )
      }
    }
    match
      run_logged(
        "iconutil -c icns " +
        sq(iconset) +
        " -o " +
        sq(resdir + "/" + icns_name),
        dist + "/iconutil.log",
        60000,
      ) {
      Ok(_) => ()
      Err(e) =>
        return Err(
          tmsg("icns 合成失败(iconutil):", "icns build failed (iconutil): ") +
          e,
        )
    }
  }
  // Info.plist(配置面没给 icon 就不带 IconFile 键)
  if !spit(
      app + "/Contents/Info.plist",
      info_plist_xml(
        conf.id,
        conf.name,
        mac_bin,
        conf.version,
        if conf.icon.length() > 0 {
          icns_name
        } else {
          ""
        },
      ),
    ) {
    return Err("write Info.plist failed")
  }
  // 签名:identity 空则 adhoc;要公证时补 hardened runtime
  let identity = if conf.sign_mac.length() > 0 { conf.sign_mac } else { "-" }
  let mut sign_cmd = "codesign --force --sign " + sq(identity)
  if conf.notarize_profile.length() > 0 {
    sign_cmd = sign_cmd + " --options runtime"
  }
  match run_logged(sign_cmd + " " + sq(app), dist + "/codesign.log", 120000) {
    Ok(_) => ()
    Err(e) => return Err(tmsg("签名失败:", "codesign failed: ") + e)
  }
  // DMG:卷内 .app + Applications 链接
  println(tmsg("出 DMG…", "creating DMG…"))
  let dmgroot = dist + "/dmgroot"
  if !(mkdir_p(dmgroot) && copy_tree(app, dmgroot + "/" + conf.name + ".app")) {
    return Err(tmsg("组 DMG 卷目录失败", "cannot stage DMG root"))
  }
  // copy_tree 走字节读写不保执行位：卷内主二进制补 chmod +x（拖装副本
  // 没有它 LaunchServices 双击/聚焦即「无法打开」，dist 内副本因有上道
  // ensure_exec 而能跑，现场表象正好一正一反）
  if !ensure_exec(
      dmgroot + "/" + conf.name + ".app/Contents/MacOS/" + mac_bin,
      dist,
    ) {
    return Err("chmod +x failed (dmgroot): " + mac_bin)
  }
  match
    run_logged(
      "ln -s /Applications " + sq(dmgroot + "/Applications"),
      dist + "/ln.log",
      10000,
    ) {
    Ok(_) => ()
    Err(e) => return Err(e)
  }
  let dmg = dist + "/\{slug}-\{conf.version}-darwin-aarch64.dmg"
  match
    run_logged(
      "hdiutil create -volname " +
      sq(conf.name) +
      " -srcfolder " +
      sq(dmgroot) +
      " -format UDZO " +
      sq(dmg),
      dist + "/hdiutil.log",
      300000,
    ) {
    Ok(_) => ()
    Err(e) => return Err(tmsg("DMG 生成失败:", "DMG creation failed: ") + e)
  }
  rm_rf(dmgroot)
  // 更新载体 zip(ditto 保元数据;D2:更新不走安装器)
  let zip = dist + "/\{slug}-\{conf.version}-darwin-aarch64.zip"
  match
    run_logged(
      "ditto -c -k --keepParent " + sq(app) + " " + sq(zip),
      dist + "/ditto.log",
      300000,
    ) {
    Ok(_) => ()
    Err(e) =>
      return Err(tmsg("更新 zip 生成失败:", "update zip failed: ") + e)
  }
  // 公证(配置了才走;失败报错不撤产物)
  if conf.notarize_profile.length() > 0 {
    println(
      tmsg(
        "公证 DMG(等待 Apple)…", "notarizing DMG (waiting on Apple)…",
      ),
    )
    match
      run_logged(
        "xcrun notarytool submit " +
        sq(dmg) +
        " --keychain-profile " +
        sq(conf.notarize_profile) +
        " --wait",
        dist + "/notarytool.log",
        1800000,
      ) {
      Ok(_) => ()
      Err(e) => return Err(tmsg("公证失败:", "notarization failed: ") + e)
    }
    match
      run_logged(
        "xcrun stapler staple " + sq(dmg),
        dist + "/stapler.log",
        300000,
      ) {
      Ok(_) => ()
      Err(e) => return Err(tmsg("staple 失败:", "staple failed: ") + e)
    }
  } else if conf.sign_mac.length() > 0 {
    println(
      tmsg(
        "已用证书签名;未配 notarize_profile,跳过公证", "signed with identity; notarize_profile unset, skipping notarization",
      ),
    )
  }
  Ok([app, dmg, zip])
}

///|
/// win 腿:stage(exe/资源/ico)→ NSIS setup + 更新载体 zip(+signtool 档)。
/// 返回产物路径列表。
fn package_win(
  conf : PkgConf,
  exe : String,
  bin_name : String,
  slug : String,
  dist : String,
) -> Result[Array[String], String] {
  let bin_exe = if bin_name.has_suffix(".exe") {
    bin_name
  } else {
    bin_name + ".exe"
  }
  let stage = dist + "/winroot"
  if !mkdir_p(stage) {
    return Err("mkdir winroot failed")
  }
  if !copy_file(exe, stage + "/" + bin_exe) {
    return Err(tmsg("拷可执行失败:", "copy executable failed: ") + exe)
  }
  for r in conf.resources {
    if !copy_tree(r, stage + "/" + basename_of(r)) {
      return Err(tmsg("拷资源失败:", "copy resource failed: ") + r)
    }
  }
  // ICO:源 png 单帧直嵌(Vista+);多帧档后续按观感反馈再扩
  if conf.icon.length() > 0 {
    let png = @fs.read_file_to_bytes(conf.icon) catch {
      _ =>
        return Err(
          tmsg("icon 读不了(须 PNG):", "icon unreadable (PNG required): ") +
          conf.icon,
        )
    }
    match ico_of_png(png) {
      Some(ico) =>
        @fs.write_bytes_to_file(stage + "/" + slug + ".ico", ico) catch {
          _ => return Err("write .ico failed")
        }
      None =>
        return Err(
          tmsg("icon 不是合法 PNG:", "icon is not a valid PNG: ") +
          conf.icon,
        )
    }
  }
  // 更新载体 zip:系统自带 bsdtar 按扩展名出 zip(Win10+)
  let zip = dist + "/\{slug}-\{conf.version}-windows-x86_64.zip"
  match
    run_tool(
      "tar",
      ["-a", "-c", "-f", zip, "-C", stage, "."],
      dist + "/tar.log",
      300000,
    ) {
    Ok(_) => ()
    Err(e) => {
      print_log_tail(dist + "/tar.log")
      return Err(
        tmsg("更新 zip 生成失败(tar):", "update zip failed (tar): ") + e,
      )
    }
  }
  let zip_ok = @fs.is_file(zip) catch { _ => false }
  if !zip_ok {
    print_log_tail(dist + "/tar.log")
    return Err(tmsg("更新 zip 没落地:", "update zip missing: ") + zip)
  }
  // NSIS setup
  println(tmsg("出 setup(NSIS)…", "creating setup (NSIS)…"))
  let makensis = match find_makensis() {
    Some(m) => m
    None =>
      return Err(
        tmsg(
          "没找到 makensis——装 NSIS 后重跑(winget install NSIS.NSIS 或 choco install nsis)",
          "makensis not found — install NSIS and retry (winget install NSIS.NSIS or choco install nsis)",
        ),
      )
  }
  let setup = dist + "/\{slug}-\{conf.version}-windows-x86_64.exe"
  let nsi = stage + "/installer.nsi"
  if !spit(
      nsi,
      nsi_script(
        conf.id,
        conf.name,
        bin_exe,
        conf.version,
        to_win_path(stage),
        slug,
        to_win_path(setup),
      ),
    ) {
    return Err("write installer.nsi failed")
  }
  match run_tool(makensis, [nsi], dist + "/makensis.log", 600000) {
    Ok(_) => ()
    Err(e) => {
      print_log_tail(dist + "/makensis.log")
      return Err(tmsg("NSIS 打包失败:", "NSIS build failed: ") + e)
    }
  }
  let setup_ok = @fs.is_file(setup) catch { _ => false }
  if !setup_ok {
    print_log_tail(dist + "/makensis.log")
    return Err(tmsg("setup 没落地:", "setup missing: ") + setup)
  }
  // signtool 档([package.sign] win_cert)
  if conf.win_cert.length() > 0 {
    let pw = match @env.get_env_var(conf.win_cert_pw_env) {
      Some(v) if v != "" => v
      _ =>
        return Err(
          tmsg(
            "环境变量 \{conf.win_cert_pw_env} 没设(win_cert 密码)",
            "env var \{conf.win_cert_pw_env} unset (win_cert password)",
          ),
        )
    }
    match
      run_tool(
        "signtool",
        [
          "sign",
          "/fd",
          "SHA256",
          "/f",
          conf.win_cert,
          "/p",
          pw,
          stage + "/" + bin_exe,
          setup,
        ],
        dist + "/signtool.log",
        300000,
      ) {
      Ok(_) => println(tmsg("已签名(exe + setup)", "signed (exe + setup)"))
      Err(e) => {
        print_log_tail(dist + "/signtool.log")
        return Err(
          tmsg(
            "签名失败(signtool;需 Windows SDK):", "signing failed (signtool; Windows SDK required): ",
          ) +
          e,
        )
      }
    }
  }
  Ok([setup, zip])
}

///|
/// linux 腿:AppImage(AppDir + appimagetool,兼作更新载体)+ deb。
/// 架构钉 x86_64(与产物名/CI 矩阵一致);deb 腿需 dpkg-deb(deb 系自带)。
fn package_linux(
  conf : PkgConf,
  exe : String,
  bin_name : String,
  slug : String,
  dist : String,
) -> Result[Array[String], String] {
  // 宿主架构判定(arm64 宿主打 x86_64 包是名不符实,如实报)
  match run_tool("uname", ["-m"], dist + "/uname.log", 10000) {
    Ok(_) =>
      match slurp(dist + "/uname.log") {
        Some(m) if m.trim().to_owned() != "x86_64" =>
          return Err(
            tmsg(
              "linux 腿当前只出 x86_64(宿主是 \{m.trim().to_owned()})",
              "linux packaging targets x86_64 only (host is \{m.trim().to_owned()})",
            ),
          )
        _ => ()
      }
    Err(e) => return Err("uname failed: " + e)
  }
  // ---- AppImage:AppDir 组装 ----
  let appdir = dist + "/" + slug + ".AppDir"
  let bindir = appdir + "/usr/bin"
  if !mkdir_p(bindir) {
    return Err("mkdir AppDir failed")
  }
  if !copy_file(exe, bindir + "/" + bin_name) {
    return Err(tmsg("拷可执行失败:", "copy executable failed: ") + exe)
  }
  if !ensure_exec(bindir + "/" + bin_name, dist) {
    return Err("chmod +x failed: " + bin_name)
  }
  if !spit(
      appdir + "/" + slug + ".desktop",
      desktop_entry(
        conf.name,
        slug,
        bin_name,
        conf.linux_categories,
        conf.linux_comment,
      ),
    ) {
    return Err("write desktop entry failed")
  }
  if !spit(appdir + "/AppRun", apprun_script(bin_name)) {
    return Err("write AppRun failed")
  }
  if !ensure_exec(appdir + "/AppRun", dist) {
    return Err("chmod +x AppRun failed")
  }
  let icon_ok = if conf.icon.length() > 0 {
    copy_file(conf.icon, appdir + "/" + slug + ".png")
  } else {
    true
  }
  if !icon_ok {
    return Err(tmsg("icon 拷贝失败:", "icon copy failed: ") + conf.icon)
  }
  let sharedir = appdir + "/usr/share/" + slug
  if !mkdir_p(sharedir) {
    return Err("mkdir AppDir usr/share failed")
  }
  for r in conf.resources {
    if !copy_tree(r, sharedir + "/" + basename_of(r)) {
      return Err(tmsg("拷资源失败:", "copy resource failed: ") + r)
    }
  }
  // appimagetool(探测/自取;恒 extract-and-run 免 FUSE 依赖)
  println(tmsg("出 AppImage…", "creating AppImage…"))
  let tool = match find_or_fetch_appimagetool(dist) {
    Some(t) => t
    None =>
      return Err(
        tmsg(
          "appimagetool 不可用(PATH/下载均失败)——手动装或检查网络后重试",
          "appimagetool unavailable (PATH/download both failed) — install manually or check network",
        ),
      )
  }
  let appimage = dist + "/\{slug}-\{conf.version}-linux-x86_64.AppImage"
  match
    run_tool(
      tool,
      ["--appimage-extract-and-run", appdir, appimage],
      dist + "/appimagetool.log",
      300000,
    ) {
    Ok(_) => ()
    Err(e) => {
      print_log_tail(dist + "/appimagetool.log")
      return Err(tmsg("AppImage 打包失败:", "AppImage build failed: ") + e)
    }
  }
  let appimage_ok = @fs.is_file(appimage) catch { _ => false }
  if !appimage_ok {
    print_log_tail(dist + "/appimagetool.log")
    return Err(tmsg("AppImage 没落地:", "AppImage missing: ") + appimage)
  }
  if !ensure_exec(appimage, dist) {
    return Err("chmod +x AppImage failed")
  }
  // ---- deb:目录树 + control/md5sums + dpkg-deb ----
  println(tmsg("出 deb…", "creating deb…"))
  let debroot = dist + "/debroot"
  let deb_bin = debroot + "/usr/bin"
  let deb_share = debroot + "/usr/share/" + slug
  let deb_apps = debroot + "/usr/share/applications"
  let deb_icons = debroot + "/usr/share/icons/hicolor/512x512/apps"
  if !(mkdir_p(deb_bin) &&
    mkdir_p(deb_share) &&
    mkdir_p(deb_apps) &&
    mkdir_p(deb_icons) &&
    mkdir_p(debroot + "/DEBIAN")) {
    return Err("mkdir debroot failed")
  }
  if !spit(
      debroot + "/DEBIAN/control",
      deb_control(slug, conf.name, conf.version, conf.maintainer),
    ) {
    return Err("write control failed")
  }
  if !copy_file(exe, deb_bin + "/" + bin_name) {
    return Err("copy exe for deb failed")
  }
  if !ensure_exec(deb_bin + "/" + bin_name, dist) {
    return Err("chmod +x failed (deb): " + bin_name)
  }
  if !spit(
      deb_apps + "/" + slug + ".desktop",
      desktop_entry(
        conf.name,
        slug,
        bin_name,
        conf.linux_categories,
        conf.linux_comment,
      ),
    ) {
    return Err("write desktop entry (deb) failed")
  }
  let deb_icon_ok = if conf.icon.length() > 0 {
    copy_file(conf.icon, deb_icons + "/" + slug + ".png")
  } else {
    true
  }
  if !deb_icon_ok {
    return Err("icon copy failed (deb)")
  }
  for r in conf.resources {
    if !copy_tree(r, deb_share + "/" + basename_of(r)) {
      return Err(
        tmsg("拷资源失败(deb):", "copy resource failed (deb): ") + r,
      )
    }
  }
  // md5sums:数据区全量文件(DEBIAN 自身除外),相对 debroot 根的路径
  match
    run_logged(
      "cd " +
      sq(debroot) +
      " && find . -type f -not -path './DEBIAN/*' -exec md5sum {} + > DEBIAN/md5sums",
      dist + "/md5sums.log",
      60000,
    ) {
    Ok(_) => ()
    Err(e) => return Err("md5sums failed: " + e)
  }
  let deb = dist + "/\{slug}-\{conf.version}-linux-x86_64.deb"
  match
    run_logged(
      "dpkg-deb --root-owner-group --build " + sq(debroot) + " " + sq(deb),
      dist + "/dpkg-deb.log",
      300000,
    ) {
    Ok(_) => ()
    Err(e) => {
      print_log_tail(dist + "/dpkg-deb.log")
      return Err(
        tmsg(
          "deb 打包失败(需 dpkg-deb,deb 系自带;Arch/Fedora 宿主没它):",
          "deb build failed (needs dpkg-deb, present on deb distros; not on Arch/Fedora): ",
        ) +
        e,
      )
    }
  }
  let deb_ok = @fs.is_file(deb) catch { _ => false }
  if !deb_ok {
    print_log_tail(dist + "/dpkg-deb.log")
    return Err(tmsg("deb 没落地:", "deb missing: ") + deb)
  }
  Ok([appimage, deb])
}

///|
/// `mng package` 入口:公共前置(配置校验/构建/抓可执行)后按宿主平台分腿。
fn cmd_package(_args : Array[String]) -> Int32 {
  let cwd = match @env.current_dir() {
    Some(d) => d
    None => "."
  }
  let (root, kind) = match find_project_root(cwd) {
    Some(x) => x
    None =>
      return fail_pkg(
        tmsg(
          "没找到 mng.toml(向上找过了)——先 mng init", "mng.toml not found (walked up) — run mng init first",
        ),
      )
  }
  if kind != "mng.toml" {
    return fail_pkg(
      tmsg(
        "项目根是按 moon.mod 定位的,没有 mng.toml——先 mng init", "project root is a moon.mod without mng.toml — run mng init first",
      ),
    )
  }
  let text = match fs_read(root + "/mng.toml") {
    Some(t) => t
    None => return fail_pkg("mng.toml unreadable")
  }
  let conf = parse_package_toml(text)
  match pkg_validate(conf) {
    Some(e) => return fail_pkg(e)
    None => ()
  }
  // appmeta 强制同步:版本常量由生成码进二进制,打包前不同步会出现
  // 「载体文件名是新版本、应用自报旧版本」的错位(更新完成版本不变)
  match sync_appmeta(root) {
    Err(e) => return fail_pkg(tmsg("appmeta：", "appmeta: ") + e)
    Ok(_) => ()
  }
  // 平台分派(D1:本平台打本平台包)
  let host = host_pkg()
  let target_name = if host == "mac" {
    "darwin-aarch64"
  } else if host == "win" {
    "windows-x86_64"
  } else {
    "linux-x86_64"
  }
  let slug = slug_of(conf.id)
  let dist = root + "/.mng/dist"
  rm_rf(dist)
  if !mkdir_p(dist) {
    return fail_pkg(
      tmsg("建不了产物目录 ", "cannot create dist dir ") + dist,
    )
  }
  // release 构建 + 从 Artifacts 抓本模块可执行(win 走 spawn 直调,POSIX 走 sh -c)
  println(tmsg("构建(release)…", "building (release)…"))
  let build_log = dist + "/build.log"
  let build_res = if host == "win" {
    run_tool(
      "moon",
      ["build", ".", "--target", "native", "--release", "--strip"],
      build_log,
      600000,
    )
  } else {
    run_logged(
      "moon build . --target native --release --strip", build_log, 600000,
    )
  }
  match build_res {
    Ok(_) => ()
    Err(e) =>
      return fail_pkg(
        tmsg("release 构建失败:", "release build failed: ") + e,
      )
  }
  let module_name = module_name_at(root)
  let build_text = match slurp(build_log) {
    Some(t) => t
    None => ""
  }
  let exe = match artifact_of_log(build_text, module_name) {
    Some(p) => p
    None => {
      // 日志为空 = 子进程输出根本没落盘（Windows 上 spawn 重定向句柄不可继承的典型症状，
      // 只回 pid 的 spawn 无从发现）；有日志但没有 Artifacts 段才是 mng.toml/bin 的问题。
      // 两种分开报，免得照着「检查 mng.toml」白查一轮。
      if build_text.length() == 0 {
        return fail_pkg(
          tmsg(
            "构建日志为空(\{build_log})——子进程输出没落盘，多半是 mng 自身过旧，先重装 `moon install ./tools/native-gui-tools/mng`",
            "build log is empty (\{build_log}) — child output was not captured, likely an outdated mng; reinstall: moon install ./tools/native-gui-tools/mng",
          ),
        )
      }
      return fail_pkg(
        tmsg(
          "Artifacts 里没抓到本模块(\{module_name})的可执行——检查 mng.toml 或显式配 bin",
          "no executable for module \{module_name} in Artifacts — check mng.toml or set bin explicitly",
        ),
      )
    }
  }
  let bin_name = if conf.bin.length() > 0 { conf.bin } else { basename_of(exe) }
  let artifacts = match host {
    "mac" => package_mac(conf, exe, bin_name, slug, dist)
    "win" => package_win(conf, exe, bin_name, slug, dist)
    _ => package_linux(conf, exe, bin_name, slug, dist)
  }
  match artifacts {
    Err(e) => return fail_pkg(e)
    Ok(list) => {
      println(tmsg("产物:", "artifacts:"))
      for p in list {
        println("  " + p)
      }
      println(
        tmsg(
          "完成 \{conf.name} \{conf.version}(\{target_name})",
          "done \{conf.name} \{conf.version} (\{target_name})",
        ),
      )
      0
    }
  }
}

///|
fn fail_pkg(msg : String) -> Int32 {
  eprintln(tmsg("打包失败:", "package failed:") + " " + msg)
  1
}

///|
/// 路径末段(exe 名 / 资源目录名)。
///
/// **两个分隔符都要认**:`moon build` 打印的 Artifacts 路径在 Windows 上是
/// `D:\…\app.exe` 形态,只按 `/` 切会原样返回整条路径——拿它拼产物目录名
/// （`winroot/<整条路径>`）写文件必然失败,而报错只说得清「拷可执行失败」。
fn basename_of(p : String) -> String {
  let a = chars_of(p)
  // 先剥尾部分隔符（`assets/` 的末段是 assets，不是空串）
  let mut end = a.length()
  while end > 0 && (a[end - 1] == '/' || a[end - 1] == '\\') {
    end -= 1
  }
  if end == 0 {
    return p
  }
  let mut start = 0
  let mut i = 0
  while i < end {
    if a[i] == '/' || a[i] == '\\' {
      start = i + 1
    }
    i += 1
  }
  slice_path(a, start, end)
}
