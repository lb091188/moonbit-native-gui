// mng 编译 CLI。子命令：
//   build <input.mng> -o <out.mbt>   编译出生成码 + <out.mbt>.map（source map）
//   map-errors --map <out.mbt.map> <log>  把 moon check 日志里的生成码行列映射回模板
//
// DX 生死线（proposals/native-template.md）：错误回映射。用法——
//   moon run tools/native-gui-tools/mng -- build page.mng -o page.mbt
//   moon check > check.log 2>&1; moon run tools/native-gui-tools/mng -- map-errors --map page.mbt.map check.log

fn usage() -> Unit {
  println("用法：moon run tools/native-gui-tools/mng -- <子命令> ...")
  println("  build <input.mng> -o <out.mbt>    编译模板：产出 out.mbt 与 out.mbt.map")
  println("  build（无参）                           按 mng.toml 生成全工程生产形态（会覆盖 dev 形态生成码）")
  println("  gen <input.mng> -o <out.mbt>      dev 形态编译（CI 生成物对账用，无 map）")
  println("  map-errors --map <out.mbt.map> <log>   把日志中 <gen>.mbt:行:列 映射回模板行列")
  println("  ir <input.mng>                    打印模板的 IR 补丁（调试与注册表校准）")
  println("  new <name>                             生成可跑最小模板工程（moon.mod/moon.pkg/mng.toml/main/首页+dev 生成码）")
  println("  new app <name>                         同 new <name>，显式写法")
  println("  new page <路径>                        生成单页 .mng 样板（可带路径，如 pages/about）")
  println("  lsp                                    语言服务（stdio JSON-RPC：诊断/补全/hover/跳转）")
  println("  init                                   在模块根写 mng.toml 样板（dev 的项目级配置）")
  println("  --version                              版本与 mng-schema 位（插件握手用）")
  println("  dev ...                                watch + 契约分类 + 回退编排（dev 无参看细目）")
}

///|
fn slurp(p : String) -> String? {
  let s = @fs.read_file_to_string(p) catch {
    _ => return None
  }
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
const MNG_VERSION : String = "0.2.2"

///|
/// --version：版本与 mng-schema 位（编辑器插件启动时握手，对不上则补全降级）。
fn cmd_version() -> Int {
  println("mng \{MNG_VERSION}")
  println("mng-schema 1")
  0
}

///|
/// build 子命令：读模板 → 编译 → 写 .mbt 与 .map。
fn cmd_build(args : Array[String]) -> Int {
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
    println("build 需要输入文件与 -o 输出路径（或无参跑项目级生成）")
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
      println("读不到文件：" + input)
      return 1
    }
  }
  match mng_compile(src, input) {
    Err(e) => {
      println(input + " 编译失败：")
      println(e)
      return 1
    }
    Ok(r) => {
      if !spit(out, r.code) {
        println("写不出文件：" + out)
        return 1
      }
      if !spit(out + ".map", r.map + "gen " + basename(out) + "\n") {
        println("写不出文件：" + out + ".map")
        return 1
      }
      println("OK " + out + "（+ .map）")
      return 0
    }
  }
}

///|
/// gen 子命令：dev 形态编译单个模板（生成码写 -o，不写 map）。与 dev 循环
/// 的首轮编译同一形态——CI 生成物新鲜度对账用：重生成后与提交的
/// `<stem>.gen.mbt` diff，不一致即「手改生成码或忘重新生成」。
fn cmd_gen(args : Array[String]) -> Int {
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
    println("gen 需要输入文件与 -o 输出路径")
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
      println("读不到文件：" + input)
      return 1
    }
  }
  match mng_compile_dev(src, input) {
    Err(e) => {
      println(input + " 编译失败：")
      println(e)
      return 1
    }
    Ok(r) => {
      if !spit(out, r.code) {
        println("写不出文件：" + out)
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
  entries : Array[(Int, Int, Int)] // (gen_line, src_line, src_col)，按 gen_line 升序
}

///|
fn load_map(p : String) -> Mapped? {
  let text = match slurp(p) {
    Some(t) => t
    None => return None
  }
  let mut source = ""
  let mut gen = ""
  let entries : Array[(Int, Int, Int)] = []
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
  Some({ source, gen, entries })
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
fn parse_int(s : String) -> Int? {
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
fn map_lookup(m : Mapped, line : Int) -> (Int, Int)? {
  let mut best : (Int, Int)? = None
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
fn scan_num(a : Array[Char], i : Int) -> (Int?, Int) {
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
fn cmd_map_errors(args : Array[String]) -> Int {
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
    println("map-errors 需要 --map <out.mbt.map> 与日志文件")
    return 2
  }
  let m = match load_map(map_path) {
    Some(mm) => mm
    None => {
      println("读不到 map：" + map_path)
      return 1
    }
  }
  let log = match slurp(log_path) {
    Some(l) => l
    None => {
      println("读不到日志：" + log_path)
      return 1
    }
  }
  // 生成码文件名（basename），匹配 `name:L:C` 且 name 前不是标识符字符
  if m.gen.length() == 0 {
    println("map 缺 gen 行（build 时生成）")
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
      if i + gl.length() <= n && a[i] == gl[0] && (i == 0 || !(is_ident_char(a[i - 1]) || a[i - 1] == '.')) {
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
  let raw = @env.args()
  let args : Array[String] = []
  let mut k = 1
  while k < raw.length() {
    args.push(raw[k])
    k += 1
  }
  if args.length() == 0 {
    usage()
    @sys.exit(2)
  }
  let cmd = args[0]
  let rest : Array[String] = []
  let mut j = 1
  while j < args.length() {
    rest.push(args[j])
    j += 1
  }
  let code = if cmd == "--version" || cmd == "-V" || cmd == "version" {
    cmd_version()
  } else if cmd == "build" {
    cmd_build(rest)
  } else if cmd == "gen" {
    cmd_gen(rest)
  } else if cmd == "map-errors" {
    cmd_map_errors(rest)
  } else if cmd == "dev" {
    cmd_dev(rest)
  } else if cmd == "ir" {
    cmd_ir(rest)
  } else if cmd == "new" {
    cmd_new(rest)
  } else if cmd == "lsp" {
    cmd_lsp(rest)
  } else if cmd == "init" {
    cmd_init(rest)
  } else {
    usage()
    2
  }
  if code != 0 {
    @sys.exit(code)
  }
}
