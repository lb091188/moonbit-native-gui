// 项目级 dev：mng.toml（[dev] 段）解析、无配置时的默认推导、递归扫描与撞名聚合。
// 配置是 key=value 子集，不引依赖；路径相对 mng.toml 所在目录解析成绝对路径。

///|
/// dev 的工程配置（已解析成绝对路径）。
priv struct DevConf {
  dir : String
  templates : Array[String]
  build : String
  run : String
  app_id : String
  poll_ms : Int
  theme : String
}

///|
fn trim_spaces(s : String) -> String {
  s.trim().to_owned()
}

///|
/// 去掉行尾 `#` 注释（串里不含 `#` 的约定）。
fn strip_comment(line : String) -> String {
  let a = chars_of(line)
  let mut i = 0
  while i < a.length() {
    if a[i] == '#' {
      return slice_path(a, 0, i).trim_end().to_owned()
    }
    i += 1
  }
  line
}

///|
/// `"串"` → 内容（去引号）。
fn unquote(v : String) -> String {
  let s = trim_spaces(v)
  if s.length() >= 2 && s.has_prefix("\"") && s.has_suffix("\"") {
    s[1:s.length() - 1].to_owned()
  } else {
    s
  }
}

///|
/// `["a", "b"]` → 串数组（空数组给 []）。
fn parse_str_array(v : String) -> Array[String] {
  let out : Array[String] = []
  let s = trim_spaces(v)
  let a = chars_of(s)
  let mut i = 0
  while i < a.length() {
    if a[i] == '"' {
      let mut j = i + 1
      while j < a.length() && a[j] != '"' {
        j += 1
      }
      out.push(slice_path(a, i + 1, j))
      i = j + 1
    } else {
      i += 1
    }
  }
  out
}

///|
/// mng.toml 原文 → 覆盖项（缺省为空/None）。
priv struct TomlDev {
  mut templates : Array[String]
  mut build : String
  mut run : String
  mut app_id : String
  mut poll_ms : Int?
  mut theme : String
}

///|
fn parse_dev_toml(text : String) -> TomlDev {
  let t : TomlDev = { templates: [], build: "", run: "", app_id: "", poll_ms: None, theme: "" }
  let mut in_dev = false
  for raw in text.split("\n") {
    let line = trim_spaces(strip_comment(raw.to_owned()))
    if line.length() == 0 {
      continue
    }
    if line.has_prefix("[") && line.has_suffix("]") {
      in_dev = line[1:line.length() - 1].to_owned().trim().to_owned() == "dev"
      continue
    }
    if !in_dev {
      continue
    }
    let eq = match index_of_char(line, '=') {
      Some(i) => i
      None => continue
    }
    let key = trim_spaces(line[:eq].to_owned())
    let val = line[eq + 1:].to_owned()
    match key {
      "templates" => t.templates = parse_str_array(val)
      "build" => t.build = unquote(val)
      "run" => t.run = unquote(val)
      "app-id" | "app_id" => t.app_id = unquote(val)
      "theme" => t.theme = unquote(val)
      "poll-ms" | "poll_ms" =>
        match parse_uint(trim_spaces(val)) {
          Some(n) => t.poll_ms = Some(n)
          None => ()
        }
      _ => ()
    }
  }
  t
}

///|
fn index_of_char(s : String, c : Char) -> Int? {
  let a = chars_of(s)
  let mut i = 0
  while i < a.length() {
    if a[i] == c {
      return Some(i)
    }
    i += 1
  }
  None
}

///|
/// 目录部分（`a/b/c` → `a/b`；无分隔符 → `.`；绝对路径同规则）。
/// 分隔符认 `/` 与 `\` 两种：Windows 的 `TEMP` 天然是反斜杠，混进 `/`
/// 拼出的路径只认一种会让向上走在中途断掉。
fn parent_dir_of(p : String) -> String {
  let a = chars_of(p)
  let mut last = -1
  let mut i = 0
  while i < a.length() {
    if a[i] == '/' || a[i] == '\\' {
      last = i
    }
    i += 1
  }
  if last <= 0 {
    // 绝对路径的根要给 "/"（"/tmp" → "/"）：给 "." 会让向上走防线在
    // 文件系统根之后踩进 cwd 相对地带——find_project_root 记住的 mod_dir
    // 会被 cwd 里的 moon.mod 顶掉（绝对路径模板在项目外时踩过）。
    if a.length() > 0 && (a[0] == '/' || a[0] == '\\') {
      "/"
    } else if a.length() >= 2 && a[1] == ':' {
      // Windows 盘根（`c:` / `c:\`）：原样返回，向上走到此收口。
      // 这里给 "." 会同样踩进 cwd（`moon test` 的 cwd 里恰好有 moon.mod）。
      slice_path(a, 0, 2)
    } else {
      "."
    }
  } else {
    slice_path(a, 0, last)
  }
}

///|
/// 相对路径 → 以 base 为根的路径（已是绝对路径就原样）。
fn join_under(base : String, p : String) -> String {
  if p.has_prefix("/") || (p.length() > 1 && p[1:2].to_owned() == ":") {
    p
  } else if p == "." || p.length() == 0 {
    base
  } else if p.has_prefix("./") {
    join_under(base, p[2:].to_owned())
  } else if base == "." {
    p
  } else {
    base + "/" + p
  }
}

///|
/// 从 cwd 向上找配置文件：mng.toml → moon.mod → moon.work。
/// 返回 (目录, 种类)：种类 = "mng.toml" / "moon.mod" / "moon.work"。
fn find_project_root(start : String) -> (String, String)? {
  let mut cur = start
  let mut hops = 0
  let mut mod_dir = ""
  while hops < 32 {
    match fs_read(cur + "/mng.toml") {
      Some(_) => return Some((cur, "mng.toml"))
      None => ()
    }
    if mod_dir.length() == 0 {
      match fs_read(cur + "/moon.mod") {
        Some(_) => mod_dir = cur
        None => ()
      }
    }
    let up = parent_dir_of(cur)
    if up == cur {
      break
    }
    cur = up
    hops += 1
  }
  if mod_dir.length() > 0 {
    return Some((mod_dir, "moon.mod"))
  }
  // 没有 moon.mod 时退回工作区根（moon.work 在根）
  let mut cur = start
  let mut hops = 0
  while hops < 32 {
    match fs_read(cur + "/moon.work") {
      Some(_) => return Some((cur, "moon.work"))
      None => ()
    }
    let up = parent_dir_of(cur)
    if up == cur {
      break
    }
    cur = up
    hops += 1
  }
  None
}

///|
/// moon.mod 的 `name = "作者/工程"` → 模块名。
fn module_name_at(dir : String) -> String {
  match fs_read(dir + "/moon.mod") {
    Some(text) => {
      let mut name = ""
      for raw in text.split("\n") {
        if name.length() > 0 {
          break
        }
        let l = trim_spaces(raw.to_owned())
        if l.has_prefix("name") {
          let a = chars_of(l)
          let mut i = 0
          while i < a.length() && a[i] != '"' {
            i += 1
          }
          if i < a.length() {
            let mut j = i + 1
            while j < a.length() && a[j] != '"' {
              j += 1
            }
            name = slice_path(a, i + 1, j)
          }
        }
      }
      name
    }
    None => ""
  }
}

///|
/// 模块名 → 单实例 app_id：小写、`/` → `.`、其余非法字符 → `_`；
/// 派生结果无点分（裸名工程，无作者段）时垫 `local.` 命名空间——
/// 字法规格要 ≥2 个点分元素，裸名会让 instance_claim 给 InvalidAppId、
/// 单实例通道整个降级（mng dev 的 HOT 唤起与 COLD 回页全失效）。
fn app_id_of_module(name : String) -> String {
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

///|
/// 加载工程配置：CLI 覆盖项优先于 mng.toml，mng.toml 优先于默认推导。
fn load_dev_conf(
  build_override : String,
  run_override : String,
  app_id_override : String,
  poll_override : Int?,
  cwd : String,
) -> Result[DevConf, String] {
  let (root, kind) = match find_project_root(cwd) {
    Some(x) => x
    None =>
      return Err(
        tmsg(
          "找不到 mng.toml / moon.mod / moon.work——在项目里跑，或先 `mng init`",
          "mng.toml / moon.mod / moon.work not found — run inside a project, or `mng init` first",
        ),
      )
  }
  let templates : Array[String] = []
  let mut build = "moon build ."
  let mut run = ""
  let mut app_id = ""
  let mut poll_ms = 300
  let mut theme = ""
  if kind == "mng.toml" {
    let text = match fs_read(root + "/mng.toml") {
      Some(t) => t
      None => return Err(tmsg("读不到 " + root + "/mng.toml", "Cannot read " + root + "/mng.toml"))
    }
    let t = parse_dev_toml(text)
    for p in t.templates {
      templates.push(join_under(root, p))
    }
    if t.build.length() > 0 {
      build = t.build
    }
    if t.run.length() > 0 {
      run = t.run
    }
    if t.app_id.length() > 0 {
      app_id = t.app_id
    }
    if t.theme.length() > 0 {
      theme = join_under(root, t.theme)
    }
    match t.poll_ms {
      Some(n) => poll_ms = n
      None => ()
    }
  }
  if templates.length() == 0 {
    templates.push(root)
  }
  if build_override.length() > 0 {
    build = build_override
  }
  if run_override.length() > 0 {
    run = run_override
  }
  if app_id_override.length() > 0 {
    app_id = app_id_override
  }
  match poll_override {
    Some(n) => poll_ms = n
    None => ()
  }
  if app_id.length() == 0 {
    let mn = module_name_at(root)
    if mn.length() == 0 {
      return Err(
        tmsg(
          "配置里没有 app-id，且 " + root + "/moon.mod 没有 name——补 app-id",
          "no app-id in the config and " + root + "/moon.mod has no name — add app-id",
        ),
      )
    }
    app_id = app_id_of_module(mn)
  }
  Ok({ dir: root, templates, build, run, app_id, poll_ms, theme })
}

///|
/// 递归扫目录里的 *.mng（跳过 _build / .mooncakes / node_modules / target / 点目录）。
fn scan_templates(dirs : Array[String]) -> Array[String] {
  let out : Array[String] = []
  for d in dirs {
    scan_dir_mng(d, out)
  }
  out.sort()
  out
}

///|
fn scan_dir_mng(dir : String, out : Array[String]) -> Unit {
  let entries = fs_ls(dir)
  entries.sort()
  for name in entries {
    let p = if dir == "." { name } else { dir + "/" + name }
    if name == "_build" || name == ".mooncakes" || name == "node_modules" || name == "target" {
      continue
    }
    // 点目录先跳过——dev 产物目录 `.mng/` 名字恰以 .mng 结尾，后缀判断不能抢在它前面
    if name.has_prefix(".") {
      continue
    }
    if name.has_suffix(".mng") {
      if !arr_has_str(out, p) {
        out.push(p)
      }
      continue
    }
    let isdir = @fs.is_dir(p) catch {
      _ => false
    }
    if isdir {
      scan_dir_mng(p, out)
    }
  }
}

///|
fn arr_has_str(a : Array[String], s : String) -> Bool {
  for x in a {
    if x == s {
      return true
    }
  }
  false
}

///|
/// 撞名聚合：按包目录分组，同包内同 stem（生成函数名）即报；跨包同 stem 不报。
fn collision_msg(files : Array[String]) -> String? {
  let by_dir : Map[String, Map[String, String]] = Map([])
  let msgs : Array[String] = []
  for f in files {
    let dir = parent_dir_of(f)
    let stem = stem_of_file(f)
    let m = match by_dir.get(dir) {
      Some(m) => m
      None => {
        let m : Map[String, String] = Map([])
        let _ = by_dir.set(dir, m)
        m
      }
    }
    match m.get(stem) {
      Some(prev) =>
        msgs.push("同包撞名：" + prev + " 与 " + f + " 都生成 `" + stem + "`（" + dir + "）——改一个文件名")
      None => {
        let _ = m.set(stem, f)
      }
    }
  }
  if msgs.length() == 0 {
    None
  } else {
    Some(msgs.join("\n"))
  }
}

///|
/// `mng init` 的配置样板。
fn mng_toml_template() -> String {
  let lines = [
    "# mng dev 的工程配置（mng init 生成）",
    "# 命令与相对路径都以执行 mng dev 时的当前目录为准。",
    "",
    "[dev]",
    "# 递归扫 *.mng 的目录（相对本文件）；改任意模板都自动处理",
    "templates = [\".\"]",
    "",
    "# 构建命令",
    "build = \"moon build .\"",
    "",
    "# 启动命令；留空 = 跑一次 build 后从 Artifacts 输出抓可执行路径",
    "run = \"\"",
    "",
    "# 单实例唤起用；留空 = 由 moon.mod 的 name 派生（作者.工程名）",
    "app-id = \"\"",
    "",
    "# 文件轮询间隔（毫秒）",
    "poll-ms = 300",
    "",
    "# mng package 的打包声明（在项目根执行；本平台打本平台包）",
    "[package]",
    "# 反域名 id：mac bundle id / 产物短名同源",
    "id = \"\"",
    "# 显示名（.app / DMG 卷名 / 安装器标题）",
    "name = \"\"",
    "# 应用版本，三段数字；与 moon.mod 的模块版本无关",
    "version = \"0.1.0\"",
    "# 可执行名；留空 = 从构建产物抓",
    "bin = \"\"",
    "# 源图标：1024x1024 PNG，派生 icns/ico",
    "icon = \"\"",
    "# 随包资源（递归拷进 Contents/Resources / 安装目录）",
    "resources = []",
    "",
    "# 签名证书入口（全留空 = mac adhoc、win 不签）",
    "[package.sign]",
    "# codesign identity；如 \"Developer ID Application: NAME (TEAMID)\"",
    "mac_identity = \"\"",
    "# notarytool keychain profile；非空则公证 + staple",
    "notarize_profile = \"\"",
    "",
  ]
  lines.join("\n")
}
