// mng package:应用打包。本平台打本平台包(D1);本文件是 mac 腿——
// .app 组装 + icns 派生 + DMG + 更新载体 zip + 签名/公证档。
// 配置在 mng.toml [package] / [package.sign];方案见 proposals/package-update.md。
// 产物落 <项目根>/.mng/dist/,不进源码树。约定在项目根执行(与 mng dev 同口径)。

///|
/// mng.toml [package] / [package.sign] 原文 → 打包配置(缺省为空)。
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
    return Some("[package] id 须为反域名(至少一个点),如 com.example.myapp")
  }
  if p.name.length() == 0 {
    return Some("[package] name 未配置")
  }
  if !semver_ok(p.version) {
    return Some("[package] version 须为三段数字,如 1.2.0(当前:\{p.version})")
  }
  for t in p.targets {
    if !(t == "dmg" || t == "setup" || t == "deb" || t == "appimage") {
      return Some("[package] targets 只认 dmg/setup/deb/appimage(不识:\{t})")
    }
  }
  if p.win_cert.length() > 0 && p.win_cert_pw_env.length() == 0 {
    return Some("[package.sign] 配了 win_cert 就要配 win_cert_pw_env(证书密码的环境变量名)")
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
fn info_plist_xml(id : String, name : String, bin : String, version : String, icns : String) -> String {
  let icon_key = if icns.length() > 0 {
      "  <key>CFBundleIconFile</key><string>\{icns}</string>\n"
    } else {
      ""
    }
  "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n<plist version=\"1.0\">\n<dict>\n  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>\n  <key>CFBundlePackageType</key><string>APPL</string>\n  <key>CFBundleName</key><string>\{esc_xml(name)}</string>\n  <key>CFBundleExecutable</key><string>\{esc_xml(bin)}</string>\n  <key>CFBundleIdentifier</key><string>\{esc_xml(id)}</string>\n  <key>CFBundleShortVersionString</key><string>\{esc_xml(version)}</string>\n  <key>CFBundleVersion</key><string>\{esc_xml(version)}</string>\n\{icon_key}  <key>NSHighResolutionCapable</key><true/>\n  <key>LSMinimumSystemVersion</key><string>11.0</string>\n</dict>\n</plist>\n"
}

///|
/// iconset 尺寸表(文件名,边长):Apple 标准十档。
let iconset_sizes : Array[(String, Int)] = [
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
fn run_logged(cmdline : String, log : String, timeout_ms : Int) -> Result[Unit, String] {
  let full = cmdline + " > " + sq(log) + " 2>&1"
  match @proc.run_wait("sh", ["-c", full], timeout_ms) {
    Err(e) => Err(e)
    Ok(0) => Ok(())
    Ok(code) => {
      let mut tail = ""
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
          tail = b.to_string()
        }
        None => ()
      }
      if tail.length() > 0 {
        eprintln(tail)
      }
      Err("命令退出码 \{code}:\{cmdline}")
    }
  }
}

///|
/// 拷单个文件(字节直拷)。
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
  let isd = @fs.is_dir(src) catch {
    _ => false
  }
  if !isd {
    return copy_file(src, dst)
  }
  if !mkdir_p(dst) {
    return false
  }
  let entries = @fs.read_dir(src) catch {
    _ => return false
  }
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
/// `mng package` 入口:本平台打本平台包(mac 腿 = .app + DMG + 更新 zip)。
fn cmd_package(_args : Array[String]) -> Int {
  let cwd = match @env.current_dir() {
    Some(d) => d
    None => "."
  }
  let (root, kind) = match find_project_root(cwd) {
    Some(x) => x
    None =>
      return fail_pkg(tmsg("没找到 mng.toml(向上找过了)——先 mng init", "mng.toml not found (walked up) — run mng init first"))
  }
  if kind != "mng.toml" {
    return fail_pkg(tmsg("项目根是按 moon.mod 定位的,没有 mng.toml——先 mng init", "project root is a moon.mod without mng.toml — run mng init first"))
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
  // 本平台腿判定:mac 工具链在不在(D1:其余平台腿在后批)
  if !(@fs.path_exists("/usr/bin/iconutil") && @fs.path_exists("/usr/bin/hdiutil")) {
    return fail_pkg(tmsg("此平台的 package 腿在后批——mac 在 mac 上打,win/linux 各在各自平台", "package for this platform comes in a later batch — build mac on mac, win/linux on their own"))
  }
  let slug = slug_of(conf.id)
  let dist = root + "/.mng/dist"
  ignore(@fs.remove_dir(dist) catch {
    _ => ()
  })
  if !mkdir_p(dist) {
    return fail_pkg(tmsg("建不了产物目录 ", "cannot create dist dir ") + dist)
  }
  // 1) release 构建 + 从 Artifacts 抓本模块可执行
  println(tmsg("构建(release)…", "building (release)…"))
  let build_log = dist + "/build.log"
  match run_logged("moon build . --target native --release --strip", build_log, 600000) {
    Ok(_) => ()
    Err(e) => return fail_pkg(tmsg("release 构建失败:", "release build failed: ") + e)
  }
  let module_name = module_name_at(root)
  let build_text = match slurp(build_log) {
    Some(t) => t
    None => ""
  }
  let exe = match artifact_of_log(build_text, module_name) {
    Some(p) => p
    None =>
      return fail_pkg(
        tmsg(
          "Artifacts 里没抓到本模块(\{module_name})的可执行——检查 mng.toml 或显式配 bin",
          "no executable for module \{module_name} in Artifacts — check mng.toml or set bin explicitly",
        ),
      )
  }
  let bin_name = if conf.bin.length() > 0 {
      conf.bin
    } else {
      basename_of(exe)
    }
  // 2) .app 目录树
  let app = dist + "/" + conf.name + ".app"
  let macdir = app + "/Contents/MacOS"
  let resdir = app + "/Contents/Resources"
  if !(mkdir_p(macdir) && mkdir_p(resdir)) {
    return fail_pkg(tmsg("建不了 .app 目录", "cannot create .app dirs"))
  }
  if !copy_file(exe, macdir + "/" + bin_name) {
    return fail_pkg(tmsg("拷可执行失败:", "copy executable failed: ") + exe)
  }
  for r in conf.resources {
    if !copy_tree(r, resdir + "/" + basename_of(r)) {
      return fail_pkg(tmsg("拷资源失败:", "copy resource failed: ") + r)
    }
  }
  // 3) icns:源 png → sips 十档 → iconutil
  let icns_name = slug + ".icns"
  if conf.icon.length() > 0 {
    if !(@fs.is_file(conf.icon) catch {
          _ => false
        }) {
      return fail_pkg(tmsg("icon 不存在:", "icon not found: ") + conf.icon)
    }
    let iconset = dist + "/" + slug + ".iconset"
    if !mkdir_p(iconset) {
      return fail_pkg("mkdir iconset failed")
    }
    for pair in iconset_sizes {
      let (fname, n) = pair
      let dim = n.to_string()
      match run_logged(
        "sips -z \{dim} \{dim} " + sq(conf.icon) + " --out " + sq(iconset + "/" + fname),
        dist + "/sips.log",
        60000,
      ) {
        Ok(_) => ()
        Err(e) => return fail_pkg(tmsg("icns 派生失败(sips):", "icns derivation failed (sips): ") + e)
      }
    }
    match run_logged(
      "iconutil -c icns " + sq(iconset) + " -o " + sq(resdir + "/" + icns_name),
      dist + "/iconutil.log",
      60000,
    ) {
      Ok(_) => ()
      Err(e) => return fail_pkg(tmsg("icns 合成失败(iconutil):", "icns build failed (iconutil): ") + e)
    }
  }
  // 4) Info.plist(配置面没给 icon 就不带 IconFile 键)
  if !spit(app + "/Contents/Info.plist", info_plist_xml(conf.id, conf.name, bin_name, conf.version, if conf.icon.length() > 0 { icns_name } else { "" })) {
    return fail_pkg("write Info.plist failed")
  }
  // 5) 签名:identity 空则 adhoc;要公证时补 hardened runtime
  let identity = if conf.sign_mac.length() > 0 {
      conf.sign_mac
    } else {
      "-"
    }
  let mut sign_cmd = "codesign --force --sign " + sq(identity)
  if conf.notarize_profile.length() > 0 {
    sign_cmd = sign_cmd + " --options runtime"
  }
  match run_logged(sign_cmd + " " + sq(app), dist + "/codesign.log", 120000) {
    Ok(_) => ()
    Err(e) => return fail_pkg(tmsg("签名失败:", "codesign failed: ") + e)
  }
  // 6) DMG:卷内 .app + Applications 链接
  println(tmsg("出 DMG…", "creating DMG…"))
  let dmgroot = dist + "/dmgroot"
  if !(mkdir_p(dmgroot) && copy_tree(app, dmgroot + "/" + conf.name + ".app")) {
    return fail_pkg(tmsg("组 DMG 卷目录失败", "cannot stage DMG root"))
  }
  match run_logged("ln -s /Applications " + sq(dmgroot + "/Applications"), dist + "/ln.log", 10000) {
    Ok(_) => ()
    Err(e) => return fail_pkg(e)
  }
  let dmg = dist + "/\{slug}-\{conf.version}-darwin-aarch64.dmg"
  match run_logged(
    "hdiutil create -volname " + sq(conf.name) + " -srcfolder " + sq(dmgroot) + " -format UDZO -o " + sq(dmg),
    dist + "/hdiutil.log",
    300000,
  ) {
    Ok(_) => ()
    Err(e) => return fail_pkg(tmsg("DMG 生成失败:", "DMG creation failed: ") + e)
  }
  ignore(@fs.remove_dir(dmgroot) catch {
    _ => ()
  })
  // 7) 更新载体 zip(ditto 保元数据;D2:更新不走安装器)
  let zip = dist + "/\{slug}-\{conf.version}-darwin-aarch64.zip"
  match run_logged(
    "ditto -c -k --keepParent " + sq(app) + " " + sq(zip),
    dist + "/ditto.log",
    300000,
  ) {
    Ok(_) => ()
    Err(e) => return fail_pkg(tmsg("更新 zip 生成失败:", "update zip failed: ") + e)
  }
  // 8) 公证(配置了才走;失败报错不撤产物)
  if conf.notarize_profile.length() > 0 {
    println(tmsg("公证 DMG(等待 Apple)…", "notarizing DMG (waiting on Apple)…"))
    match run_logged(
      "xcrun notarytool submit " + sq(dmg) + " --keychain-profile " + sq(conf.notarize_profile) + " --wait",
      dist + "/notarytool.log",
      1800000,
    ) {
      Ok(_) => ()
      Err(e) => return fail_pkg(tmsg("公证失败:", "notarization failed: ") + e)
    }
    match run_logged("xcrun stapler staple " + sq(dmg), dist + "/stapler.log", 300000) {
      Ok(_) => ()
      Err(e) => return fail_pkg(tmsg("staple 失败:", "staple failed: ") + e)
    }
  } else if conf.sign_mac.length() > 0 {
    println(tmsg("已用证书签名;未配 notarize_profile,跳过公证", "signed with identity; notarize_profile unset, skipping notarization"))
  }
  println(tmsg("产物:", "artifacts:"))
  println("  " + app)
  println("  " + dmg)
  println("  " + zip)
  println(tmsg("完成 \{conf.name} \{conf.version}(darwin-aarch64)", "done \{conf.name} \{conf.version} (darwin-aarch64)"))
  0
}

///|
fn fail_pkg(msg : String) -> Int {
  eprintln(tmsg("打包失败:", "package failed:") + " " + msg)
  1
}

///|
/// 路径末段(exe 名 / 资源目录名)。
fn basename_of(p : String) -> String {
  let mut last = p
  for raw in p.split("/") {
    let s = raw.to_owned()
    if s.length() > 0 {
      last = s
    }
  }
  last
}
