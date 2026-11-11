// mng 编译 CLI。子命令：
//   build <input.mng> -o <out.mbt>   编译出生成码 + <out.mbt>.map（source map）
//   map-errors --map <out.mbt.map> <log>  把 moon check 日志里的生成码行列映射回模板
//
// DX 生死线（proposals/native-template.md）：错误回映射。用法——
//   moon run tools/native-gui-tools/mng -- build page.mng -o page.mbt
//   moon check > check.log 2>&1; moon run tools/native-gui-tools/mng -- map-errors --map page.mbt.map check.log

///|
/// CLI 文案语言：LC_ALL / LC_MESSAGES / LANG 依次取，zh 前缀或全缺省走中文。
/// 只覆盖命令面提示与错误；dev 运行期 watch 日志与编译器诊断不在其列。
let cli_zh : Array[Bool] = [true]

///|
fn cli_lang_init() -> Unit {
  for k in ["LC_ALL", "LC_MESSAGES", "LANG"] {
    match @env.get_env_var(k) {
      Some(v) if v.length() > 0 => {
        cli_zh[0] = v.has_prefix("zh")
        return
      }
      _ => ()
    }
  }
  // 环境变量缺席（Windows 原生 shell 常态）：读系统 UI 语言主 ID，
  // 0x04 = 中文；仍未知（POSIX 恒 0）则缺省中文
  let l = @proc.ui_lang()
  cli_zh[0] = l == 0 || l == 0x04
}

///|
/// 调用形态前缀：argv[0] 在 _build 里 = `moon run`（开发环境），否则是安装好的 mng。
/// usage 与各 help 首行按此给出可复制的调用形式；moon 产物在 mac 上也叫 *.exe，
/// 只能看路径不能看文件名。
let inv_prefix : Array[String] = ["moon run tools/native-gui-tools/mng --"]

///|
fn inv_prefix_init(argv0 : String) -> Unit {
  if !argv0.contains("_build") {
    inv_prefix[0] = "mng"
  }
}

///|
fn tmsg(zh : String, en : String) -> String {
  if cli_zh[0] {
    zh
  } else {
    en
  }
}

///|
/// usage 行：命令列统一补齐到 42 显示列再接解释，保住间距。
/// 宽度按终端显示列算：非 ASCII 字符一律计 2（如 <路径> 的 CJK）。
fn usage_line(cmd : String, zh : String, en : String) -> Unit {
  let mut w = 0
  for c in cmd {
    w += if c.to_int() > 0x7f { 2 } else { 1 }
  }
  let gap = if w + 2 > 42 { 2 } else { 42 - w }
  let s = StringBuilder()
  s.write_string(cmd)
  let mut k = 0
  while k < gap {
    s.write_char(' ')
    k += 1
  }
  s.write_string(tmsg(zh, en))
  println(s.to_string())
}

///|
fn usage() -> Unit {
  println(
    tmsg(
      "用法：\{inv_prefix[0]} <子命令> ...",
      "Usage: \{inv_prefix[0]} <subcommand> ...",
    ),
  )
  usage_line(
    "  build <input.mng> -o <out.mbt>", "编译模板：产出 out.mbt 与 out.mbt.map；无参跑全工程生产形态",
    "Compile template: writes out.mbt and out.mbt.map; no args runs whole-project production generation",
  )
  usage_line(
    "  gen <input.mng> -o <out.mbt>", "dev 形态编译单个模板", "Dev-form compile of a single template",
  )
  usage_line(
    "  map-errors --map <out.mbt.map> <log>", "把日志中 <gen>.mbt:行:列 映射回模板行列",
    "Map <gen>.mbt:line:col in the log back to template line:col",
  )
  usage_line(
    "  ir <input.mng>", "打印模板的 IR 补丁", "Print the template IR patch",
  )
  usage_line(
    "  new <name>", "生成可跑最小模板工程", "Generate a runnable minimal template project",
  )
  usage_line(
    "  new app <name>", "同 new <name>，显式写法", "Same as new <name>, explicit form",
  )
  usage_line(
    "  new page <路径>", "生成单页 .mng 样板", "Generate a single-page .mng sample",
  )
  usage_line("  lsp", "语言服务", "Language server")
  usage_line(
    "  init", "在模块根写 mng.toml 样板", "Write an mng.toml sample at module root",
  )
  usage_line(
    "  doctor [-f]", "环境体检（moon/Python/编译器/GTK）；全绿写 ~/.mng/ready，-f 强制重检",
    "Environment health check (moon/Python/compilers/GTK); writes ~/.mng/ready when green, -f forces re-check",
  )
  usage_line(
    "  --version", "版本与 mng-schema 位", "Version and mng-schema bit",
  )
  usage_line("  -v", "版本与 mng-schema 位", "Version and mng-schema bit")
  usage_line("  -V", "版本与 mng-schema 位", "Version and mng-schema bit")
  usage_line(
    "  dev ...", "watch + 契约分类 + 回退编排；-h 看细目", "Watch + contract classification + rebuild orchestration; -h for details",
  )
  usage_line(
    "  package", "打包本平台应用产物（mac：.app+DMG+zip；win：setup+zip；linux：deb+AppImage）；-h 看细目",
    "Package platform-native app artifacts (mac: .app+DMG+zip; win: setup+zip; linux: deb+AppImage); -h for details",
  )
  usage_line(
    "  publish", "扫 .mng/dist/ 生成 update.json 并经 gh 上传 draft Release；-h 看细目",
    "Generate update.json from .mng/dist/ and upload a draft Release via gh; -h for details",
  )
  println(
    tmsg(
      "子命令加 -h 看详细说明。", "Add -h to a subcommand for details.",
    ),
  )
}

///|
/// `mng doctor -h`：环境体检说明。
fn help_doctor() -> Unit {
  println(
    tmsg(
      "用法：\{inv_prefix[0]} doctor [-f]",
      "Usage: \{inv_prefix[0]} doctor [-f]",
    ),
  )
  println(
    tmsg(
      "  探测 moon / Python 3 / C·C++ 编译器 /（Linux）GTK 开发包，可选项（WebView、媒体库）只提示",
      "  Probes moon / Python 3 / C & C++ compilers / (Linux) GTK dev packages; optional items (WebView, media libs) only warn",
    ),
  )
  println(
    tmsg(
      "  必选项全过即写 ~/.mng/ready（内容为 mng 版本行，mng 升级后自动重检）；裸 mng 首跑会自动走一轮",
      "  All required checks green writes ~/.mng/ready (an mng version line, re-checked after mng upgrades); bare mng runs it on first use",
    ),
  )
}

///|
/// `mng package -h`：打包说明。
fn help_package() -> Unit {
  println(
    tmsg("用法：\{inv_prefix[0]} package", "Usage: \{inv_prefix[0]} package"),
  )
  println(
    tmsg(
      "  在项目根执行（与 dev 同口径）；读 mng.toml [package] 节",
      "  Run at project root (same convention as dev); reads the [package] section of mng.toml",
    ),
  )
  println(
    tmsg(
      "  本平台打本平台包——mac 出 .app + DMG + 更新载体 zip；win 出 NSIS setup + 更新 zip；linux 出 deb + AppImage（AppImage 兼作更新载体）",
      "  Builds for the host platform only — mac emits .app + DMG + update zip; win emits NSIS setup + update zip; linux emits deb + AppImage (the AppImage doubles as the update carrier)",
    ),
  )
  println(
    tmsg(
      "  win 需 NSIS（winget install NSIS.NSIS）；linux 的 deb 需 dpkg-deb（deb 系自带）、appimagetool 缺失自动下载",
      "  win needs NSIS (winget install NSIS.NSIS); linux deb needs dpkg-deb (present on deb distros), appimagetool auto-downloads when missing",
    ),
  )
  println(
    tmsg(
      "  产物落 <项目根>/.mng/dist/，不进源码树", "  Artifacts land in <project root>/.mng/dist/, out of the source tree",
    ),
  )
  println(
    tmsg(
      "  签名：[package.sign] mac_identity 空 = adhoc；notarize_profile 非空则公证 + staple；win_cert 走 signtool",
      "  Signing: empty [package.sign] mac_identity = adhoc; set notarize_profile to notarize + staple; win_cert goes through signtool",
    ),
  )
}

///|
/// `mng publish -h`：发布说明。
fn help_publish() -> Unit {
  println(
    tmsg(
      "用法：\{inv_prefix[0]} publish [--tag <tag>] [--repo <owner/name>] [--notes <文本>] [--no-upload]",
      "Usage: \{inv_prefix[0]} publish [--tag <tag>] [--repo <owner/name>] [--notes <text>] [--no-upload]",
    ),
  )
  println(
    tmsg(
      "  在项目根执行（package 之后）；扫 .mng/dist/ 产物算 SHA256/体积，生成 update.json（更新载体进 platforms，安装包只随 Release 分发）",
      "  Run at project root (after package); hashes artifacts in .mng/dist/, writes update.json (carriers go into platforms, installers ship with the Release only)",
    ),
  )
  println(
    tmsg(
      "  经 gh 上传到 draft Release（存在则补传 --clobber）；--tag 默认 app-v<版本>，--repo 默认 gh 探测",
      "  Uploads via gh to a draft Release (appends with --clobber when it exists); --tag defaults to app-v<version>, --repo is resolved by gh",
    ),
  )
  println(
    tmsg(
      "  跨平台拼清单：把别处出的产物拷进 .mng/dist/ 一起发（按文件名解析全收）；--no-upload 只生成清单",
      "  To compose a cross-platform manifest, drop other platforms' artifacts into .mng/dist/ before publishing (all parsed by name); --no-upload writes the manifest only",
    ),
  )
}

///|
/// 各子命令详细帮助（`mng <cmd> -h`）。
fn help_build() -> Unit {
  println(
    tmsg(
      "用法：\{inv_prefix[0]} build [<input.mng> -o <out.mbt>]",
      "Usage: \{inv_prefix[0]} build [<input.mng> -o <out.mbt>]",
    ),
  )
  println(
    tmsg(
      "  单文件：读模板 → 编译 → 写出生成码 out.mbt 与 source map out.mbt.map",
      "  Single file: read template -> compile -> write generated code out.mbt and source map out.mbt.map",
    ),
  )
  println(
    tmsg(
      "  无参：按 mng.toml 生成全工程生产形态，生成码落模板同包——会覆盖 dev 形态生成码",
      "  No args: whole-project production generation per mng.toml, code lands next to each template — overwrites dev-form generated code",
    ),
  )
  println(
    tmsg(
      "  错误里的 <gen>.mbt:行:列 用 `mng map-errors` 映射回模板行列",
      "  Map <gen>.mbt:line:col in errors back to template line:col with `mng map-errors`",
    ),
  )
}

///|
fn help_gen() -> Unit {
  println(
    tmsg(
      "用法：\{inv_prefix[0]} gen <input.mng> -o <out.mbt>",
      "Usage: \{inv_prefix[0]} gen <input.mng> -o <out.mbt>",
    ),
  )
  println(
    tmsg(
      "  dev 形态编译单个模板，生成码写 -o，不产 source map", "  Dev-form compile of one template; generated code goes to -o, no source map",
    ),
  )
  println(
    tmsg(
      "  与 `mng dev` 首轮编译同一形态：CI 重生成后与提交的 <stem>.gen.mbt diff 对账",
      "  Same form as `mng dev` first pass: regenerate in CI and diff against the committed <stem>.gen.mbt",
    ),
  )
}

///|
fn help_map_errors() -> Unit {
  println(
    tmsg(
      "用法：\{inv_prefix[0]} map-errors --map <out.mbt.map> <log>",
      "Usage: \{inv_prefix[0]} map-errors --map <out.mbt.map> <log>",
    ),
  )
  println(
    tmsg(
      "  把日志里 <gen>.mbt:行:列 经 source map 映射回 <source>:行:列，结果打到 stdout",
      "  Rewrite <gen>.mbt:line:col positions in the log via the source map to <source>:line:col, result on stdout",
    ),
  )
  println(
    tmsg("  map 由 `mng build` 生成", "  The map is written by `mng build`"),
  )
}

///|
fn help_ir() -> Unit {
  println(
    tmsg(
      "用法：\{inv_prefix[0]} ir <input.mng>",
      "Usage: \{inv_prefix[0]} ir <input.mng>",
    ),
  )
  println(
    tmsg(
      "  打印模板的 IR 补丁 JSON——调试与注册表键校准用", "  Print the template's IR patch JSON — for debugging and registry-key calibration",
    ),
  )
}

///|
fn help_new() -> Unit {
  println(
    tmsg(
      "用法：\{inv_prefix[0]} new <工程名> | \{inv_prefix[0]} new app <工程名> | \{inv_prefix[0]} new page <页路径>",
      "Usage: \{inv_prefix[0]} new <name> | \{inv_prefix[0]} new app <name> | \{inv_prefix[0]} new page <path>",
    ),
  )
  println(
    tmsg(
      "  new <名>：在 ./<名>/ 生成可跑最小模板工程——moon.mod（gui/yoga 版本仓内现读、仓外兜底值）、",
      "  new <name>: generate a runnable minimal project in ./<name>/ — moon.mod (gui/yoga versions read live inside this workspace, fallback outside),",
    ),
  )
  println(
    tmsg(
      "    全套 import 的 moon.pkg、mng.toml、main.mbt（单实例 + 三条 dev 通道 + 唤起泵）、pages/home.mng 与 dev 形态生成码",
      "    a moon.pkg with the full import set, mng.toml, main.mbt (single instance + three dev channels + wake pump), pages/home.mng and dev-form generated code",
    ),
  )
  println(
    tmsg(
      "  new app <名>：同 new <名>，显式写法", "  new app <name>: same as new <name>, explicit form",
    ),
  )
  println(
    tmsg(
      "  new page <路径>：生成单页 .mng 样板；路径可带目录（如 pages/about），父目录现建，.mng 后缀可省",
      "  new page <path>: generate a single-page .mng sample; path may include dirs (e.g. pages/about), parent dirs are created, the .mng suffix is optional",
    ),
  )
  println(
    tmsg(
      "  工程名合法化：字母/数字/下划线/连字符，数字开头垫 _；目录已存在拒绝，不覆盖",
      "  Name normalization: letters/digits/underscore/hyphen, leading digit gets a _ prefix; an existing directory is refused, never overwritten",
    ),
  )
}

///|
fn help_lsp() -> Unit {
  println(tmsg("用法：\{inv_prefix[0]} lsp", "Usage: \{inv_prefix[0]} lsp"))
  println(
    tmsg(
      "  stdio JSON-RPC 语言服务：模板结构实时诊断、保存时 moon check 回投、补全/hover/跳转、语义令牌",
      "  stdio JSON-RPC language server: live template-structure diagnostics, moon check feedback on save, completion/hover/goto, semantic tokens",
    ),
  )
  println(
    tmsg(
      "  握手：编辑器先读 `mng --version` 的 mng-schema 位，不一致则补全降级",
      "  Handshake: the editor reads the mng-schema bit from `mng --version`; on mismatch completion degrades",
    ),
  )
}

///|
fn help_init() -> Unit {
  println(
    tmsg("用法：\{inv_prefix[0]} init", "Usage: \{inv_prefix[0]} init"),
  )
  println(
    tmsg(
      "  向上找模块根（moon.mod / moon.work），写一份带注释的 mng.toml 样板（dev 的项目级配置）",
      "  Walk up to the module root (moon.mod / moon.work) and write a commented mng.toml sample (project-level dev config)",
    ),
  )
  println(
    tmsg(
      "  已有 mng.toml 时不覆盖", "  An existing mng.toml is left untouched",
    ),
  )
}

///|
fn help_version() -> Unit {
  println(
    tmsg(
      "用法：\{inv_prefix[0]} -v | -V | --version",
      "Usage: \{inv_prefix[0]} -v | -V | --version",
    ),
  )
  println(
    tmsg(
      "  打印 mng 版本与 mng-schema 位；编辑器插件启动握手用", "  Print the mng version and the mng-schema bit; used for the editor plugin handshake",
    ),
  )
}

///|

///|
fn slurp(p : String) -> String? {
  let s = @fs.read_file_to_string(p) catch { _ => return None }
  Some(s)
}

///|
fn spit(p : String, s : String) -> Bool {
  @fs.write_string_to_file(p, s) catch {
    _ => return false
  }
  true
}

///|
fn basename(p : String) -> String {
  let a = chars_of(p)
  let mut start = 0
  for k, c in a {
    if c == '/' {
      start = k + 1
    }
  }
  a[start:].map(fn(c) { c.to_string() }).join("")
}

///|
/// 工具版本：每落地一批改动 +1（用户重装后凭 --version 区分新旧二进制）。
/// lsp serverInfo 同源取此常量。
const MNG_VERSION : String = "0.2.11"

///|
/// --version：版本与 mng-schema 位（编辑器插件启动时握手，对不上则补全降级）。
fn cmd_version() -> Int32 {
  println("mng \{MNG_VERSION}")
  println("mng-schema 1")
  0
}

///|
/// build 子命令：读模板 → 编译 → 写 .mbt 与 .map。
fn cmd_build(args : Array[String]) -> Int32 {
  let mut input = ""
  let mut out = ""
  let mut k = 0
  while k < args.length() {
    if args[k] == "-o" && k + 1 < args.length() {
      out = args[k + 1]
      k += 2
    } else {
      input = args[k]
      k += 1
    }
  }
  if input.length() == 0 && out.length() == 0 {
    // 无参：项目模式——按 mng.toml 生成全工程生产形态
    return cmd_build_project()
  }
  if input.length() == 0 || out.length() == 0 {
    println(
      tmsg(
        "build 需要输入文件与 -o 输出路径（或无参跑项目级生成）",
        "build needs an input file and an -o output path (or run with no args for project-level generation)",
      ),
    )
    return 2
  }
  match stem_conflict_msg(input) {
    Some(m) => {
      println(m)
      return 1
    }
    None => ()
  }
  let src = match slurp(input) {
    Some(s) => s
    None => {
      println(tmsg("读不到文件：" + input, "Cannot read file: " + input))
      return 1
    }
  }
  match mng_compile(src, input) {
    Err(e) => {
      println(tmsg(input + " 编译失败：", input + " compile failed:"))
      println(e)
      return 1
    }
    Ok(r) => {
      if !spit(out, r.code) {
        println(tmsg("写不出文件：" + out, "Cannot write file: " + out))
        return 1
      }
      if !spit(out + ".map", r.map + "gen " + basename(out) + "\n") {
        println(
          tmsg(
            "写不出文件：" + out + ".map",
            "Cannot write file: " + out + ".map",
          ),
        )
        return 1
      }
      println("OK " + out + tmsg("（+ .map）", " (+ .map)"))
      return 0
    }
  }
}

///|
/// gen 子命令：dev 形态编译单个模板（生成码写 -o，不写 map）。与 dev 循环
/// 的首轮编译同一形态——CI 生成物新鲜度对账用：重生成后与提交的
/// `<stem>.gen.mbt` diff，不一致即「手改生成码或忘重新生成」。
fn cmd_gen(args : Array[String]) -> Int32 {
  let mut input = ""
  let mut out = ""
  let mut k = 0
  while k < args.length() {
    if args[k] == "-o" && k + 1 < args.length() {
      out = args[k + 1]
      k += 2
    } else {
      input = args[k]
      k += 1
    }
  }
  if input.length() == 0 || out.length() == 0 {
    println(
      tmsg(
        "gen 需要输入文件与 -o 输出路径", "gen needs an input file and an -o output path",
      ),
    )
    return 2
  }
  match stem_conflict_msg(input) {
    Some(m) => {
      println(m)
      return 1
    }
    None => ()
  }
  let src = match slurp(input) {
    Some(s) => s
    None => {
      println(tmsg("读不到文件：" + input, "Cannot read file: " + input))
      return 1
    }
  }
  match mng_compile_dev(src, input) {
    Err(e) => {
      println(tmsg(input + " 编译失败：", input + " compile failed:"))
      println(e)
      return 1
    }
    Ok(r) => {
      if !spit(out, r.code) {
        println(tmsg("写不出文件：" + out, "Cannot write file: " + out))
        return 1
      }
      println("OK " + out)
      return 0
    }
  }
}

///|
/// source map 装载：头两行 source/gen，其后 `gen行\t源行\t源列`。
priv struct Mapped {
  source : String
  gen : String
  entries : Array[(Int32, Int32, Int32)] // (gen_line, src_line, src_col)，按 gen_line 升序
}

///|
fn load_map(p : String) -> Mapped? {
  let text = match slurp(p) {
    Some(t) => t
    None => return None
  }
  let mut source = ""
  let mut gen = ""
  let entries : Array[(Int32, Int32, Int32)] = []
  for line0 in text.split("\n") {
    let line = line0.trim().to_owned()
    if line.has_prefix("source ") {
      source = line[7:].to_owned()
    } else if line.has_prefix("gen ") {
      gen = line[4:].to_owned()
    } else if line.has_prefix("#") || line.length() == 0 {
      continue
    } else {
      let segs : Array[String] = []
      for x in line.split("\t") {
        segs.push(x.trim().to_owned())
      }
      if segs.length() == 3 {
        match (parse_int(segs[0]), parse_int(segs[1]), parse_int(segs[2])) {
          (Some(a), Some(b), Some(cc)) => entries.push((a, b, cc))
          _ => ()
        }
      }
    }
  }
  Some({ source, gen, entries, })
}

///|
fn is_ident_char(c : Char) -> Bool {
  ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_') ||
  (c >= '0' && c <= '9')
}

///|
fn chars_of(s : String) -> Array[Char] {
  let a : Array[Char] = []
  for c in s {
    a.push(c)
  }
  a
}

///|
fn parse_int(s : String) -> Int32? {
  let a = chars_of(s)
  if a.length() == 0 {
    return None
  }
  let mut v = 0
  for c in a {
    if c < '0' || c > '9' {
      return None
    }
    v = v * 10 + (c.to_int() - '0'.to_int())
  }
  Some(v)
}

///|
/// 查映射：gen_line ≤ line 的最近条目。
fn map_lookup(m : Mapped, line : Int32) -> (Int32, Int32)? {
  let mut best : (Int32, Int32)? = None
  for e in m.entries {
    if e.0 <= line {
      best = Some((e.1, e.2))
    } else {
      break
    }
  }
  best
}

///|
/// 数字串消费：从 i 起读最长数字 run，返回 (值, 下一位置)。
fn scan_num(a : Array[Char], i : Int32) -> (Int32?, Int32) {
  let start = i
  let mut k = i
  while k < a.length() && a[k] >= '0' && a[k] <= '9' {
    k += 1
  }
  if k == start {
    return (None, i)
  }
  let seg = a[start:k].map(fn(c) { c.to_string() }).join("")
  match parse_int(seg) {
    Some(v) => (Some(v), k)
    None => (None, i)
  }
}

///|
/// map-errors：把日志里 `<gen>:L:C` 全部替换为 `<source>:L':C'`。
fn cmd_map_errors(args : Array[String]) -> Int32 {
  let mut map_path = ""
  let mut log_path = ""
  let mut k = 0
  while k < args.length() {
    if args[k] == "--map" && k + 1 < args.length() {
      map_path = args[k + 1]
      k += 2
    } else {
      log_path = args[k]
      k += 1
    }
  }
  if map_path.length() == 0 || log_path.length() == 0 {
    println(
      tmsg(
        "map-errors 需要 --map <out.mbt.map> 与日志文件", "map-errors needs --map <out.mbt.map> and a log file",
      ),
    )
    return 2
  }
  let m = match load_map(map_path) {
    Some(mm) => mm
    None => {
      println(
        tmsg("读不到 map：" + map_path, "Cannot read map: " + map_path),
      )
      return 1
    }
  }
  let log = match slurp(log_path) {
    Some(l) => l
    None => {
      println(
        tmsg("读不到日志：" + log_path, "Cannot read log: " + log_path),
      )
      return 1
    }
  }
  // 生成码文件名（basename），匹配 `name:L:C` 且 name 前不是标识符字符
  if m.gen.length() == 0 {
    println(
      tmsg(
        "map 缺 gen 行（build 时生成）", "map lacks the gen line (written by build)",
      ),
    )
    return 1
  }
  let gen_a = chars_of(m.gen)
  let mut gstart = 0
  for k2, c in gen_a {
    if c == '/' {
      gstart = k2 + 1
    }
  }
  let gname = gen_a[gstart:].map(fn(c) { c.to_string() }).join("")
  let src_a = chars_of(m.source)
  let mut sstart = 0
  for k2, c in src_a {
    if c == '/' {
      sstart = k2 + 1
    }
  }
  let sname = src_a[sstart:].map(fn(c) { c.to_string() }).join("")
  for line0 in log.split("\n") {
    let line = line0.to_owned()
    let a = chars_of(line)
    let out : Array[String] = []
    let mut i = 0
    let n = a.length()
    let gl = chars_of(gname)
    while i < n {
      // 尝试在此位置匹配 gname
      if i + gl.length() <= n &&
        a[i] == gl[0] &&
        (i == 0 || !(is_ident_char(a[i - 1]) || a[i - 1] == '.')) {
        let mut ok = true
        for q in 0..<gl.length() {
          if a[i + q] != gl[q] {
            ok = false
          }
        }
        if ok && i + gl.length() < n && a[i + gl.length()] == ':' {
          let (l1, j1) = scan_num(a, i + gl.length() + 1)
          match l1 {
            Some(line_no) =>
              if j1 < n && a[j1] == ':' {
                let (c1, j2) = scan_num(a, j1 + 1)
                if c1 is Some(_) {
                  match map_lookup(m, line_no) {
                    Some((sl, sc)) => {
                      out.push(sname + ":\{sl}:\{sc}")
                      i = j2
                      continue
                    }
                    None => ()
                  }
                }
              }
            None => ()
          }
        }
      }
      out.push(a[i].to_string())
      i += 1
    }
    println(out.join(""))
  }
  return 0
}

///|
fn main {
  cli_lang_init()
  let raw = @env.args()
  if raw.length() > 0 {
    inv_prefix_init(raw[0])
  }
  let args : Array[String] = []
  let mut k = 1
  while k < raw.length() {
    args.push(raw[k])
    k += 1
  }
  if args.length() == 0 {
    // 裸 mng 状态机：ready 缺失先跑一轮体检（全绿写 ready），之后照旧 usage；
    // 体检有红项直接以退出码 1 结束。ready 只门这条交互入口，子命令与 CI 不受影响。
    let home = @doctor.home_dir()
    let path = @doctor.ready_path(home~)
    if !@doctor.ready_valid(path~, version=MNG_VERSION) {
      let code = cmd_doctor(force=true)
      if code != 0 {
        @sys.exit(code)
      }
    }
    usage()
    @sys.exit(2)
  }
  let cmd = args[0]
  let rest : Array[String] = []
  let mut j = 1
  let mut wants_help = false
  while j < args.length() {
    if args[j] == "-h" || args[j] == "--help" {
      wants_help = true
    }
    rest.push(args[j])
    j += 1
  }
  let code = if cmd == "-h" || cmd == "--help" {
    usage()
    0
  } else if wants_help {
    if cmd == "build" {
      help_build()
    } else if cmd == "gen" {
      help_gen()
    } else if cmd == "map-errors" {
      help_map_errors()
    } else if cmd == "ir" {
      help_ir()
    } else if cmd == "new" {
      help_new()
    } else if cmd == "lsp" {
      help_lsp()
    } else if cmd == "init" {
      help_init()
    } else if cmd == "doctor" {
      help_doctor()
    } else if cmd == "dev" {
      usage_dev()
    } else if cmd == "package" {
      help_package()
    } else if cmd == "publish" {
      help_publish()
    } else if cmd == "--version" ||
      cmd == "-v" ||
      cmd == "-V" ||
      cmd == "version" {
      help_version()
    } else {
      usage()
    }
    0
  } else if cmd == "--version" || cmd == "-v" || cmd == "-V" || cmd == "version" {
    cmd_version()
  } else if cmd == "build" {
    cmd_build(rest)
  } else if cmd == "gen" {
    cmd_gen(rest)
  } else if cmd == "map-errors" {
    cmd_map_errors(rest)
  } else if cmd == "dev" {
    cmd_dev(rest)
  } else if cmd == "package" {
    cmd_package(rest)
  } else if cmd == "publish" {
    cmd_publish(rest)
  } else if cmd == "ir" {
    cmd_ir(rest)
  } else if cmd == "new" {
    cmd_new(rest)
  } else if cmd == "lsp" {
    cmd_lsp(rest)
  } else if cmd == "init" {
    cmd_init(rest)
  } else if cmd == "doctor" {
    cmd_doctor(force=rest.contains("-f") || rest.contains("--force"))
  } else {
    usage()
    2
  }
  if code != 0 {
    @sys.exit(code)
  }
}
