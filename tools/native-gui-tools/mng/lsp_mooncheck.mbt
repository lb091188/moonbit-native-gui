// didSave 诊断联动（moon check 回投）：保存 .mng 时跑一次 `moon -C <root> check`，
// 把输出里 `<stem>.gen.mbt:行:列` 的类型错误经 dev source map（`.mng/map/`）
// 反查回模板行列，与模板结构诊断合并进 publishDiagnostics。
// 节奏：client 在 didSave 后连发 `$/mng/checkTick` 通知（proc 层无时钟，轮询
// 与 25 tick 上限都在 client 侧）；进行中的 check 不重入；诊断基于磁盘生成码
// ——保存动作正是把编辑器内容落到磁盘的口子，dev 循环负责生成码新鲜。
// 解析不了的日志行跳过不猜；`moon check` 本体报错（非生成码位置）不回投。

///|
let check_running : Ref[Bool] = Ref(false)
let check_pid : Ref[Int] = Ref(0)
let check_uri : Ref[String] = Ref("")
let check_root : Ref[String] = Ref("")
let check_ticks : Ref[Int] = Ref(0)

///|
/// moon check 命中的诊断缓存：uri → [(模板行 0 基, 列 0 基, message)]。
let check_diags : Ref[Map[String, Array[(Int, Int, String)]]] = Ref(Map([]))

///|
/// didSave 入口：起一次 moon check（进行中不重入）。
fn check_kickoff(uri : String) -> Unit {
  if check_running.val {
    return
  }
  let path = uri_to_path(uri)
  let dir = dir_name_of_lsp(path)
  let root = match find_project_root(dir) {
    Some((r, _)) => r
    None => return
  }
  let mng_dir = root + "/.mng"
  let _ = mkdir_p(mng_dir)
  let log = mng_dir + "/mooncheck.log"
  let _ = @fs.remove_file(log) catch {
    _ => ()
  }
  match @proc.spawn("moon", ["-C", root, "check"], log) {
    Ok(pid) => {
      check_running.val = true
      check_pid.val = pid
      check_uri.val = uri
      check_root.val = root
      check_ticks.val = 0
    }
    Err(_) => ()
  }
}

///|
/// $/mng/checkTick：轮询一次。进程退出则解析回投；25 tick 上限强杀。
fn check_tick(docs : Map[String, String]) -> Unit {
  if !check_running.val {
    return
  }
  if @proc.alive(check_pid.val) {
    check_ticks.val += 1
    if check_ticks.val > 25 {
      let _ = @proc.kill(check_pid.val)
      check_running.val = false
    }
    return
  }
  check_running.val = false
  let uri = check_uri.val
  let root = check_root.val
  let log = match fs_read(root + "/.mng/mooncheck.log") {
    Some(t) => t
    None => ""
  }
  let items = check_items_from_log(log, root, uri)
  let _ = check_diags.val.set(uri, items)
  match docs.get(uri) {
    Some(t) => lsp_send(lsp_diagnostics(uri, t))
    None => ()
  }
}

///|
/// 日志 + dev map → 模板诊断项（生成码位置反查不到的跳过）。
fn check_items_from_log(
  log : String,
  root : String,
  uri : String,
) -> Array[(Int, Int, String)] {
  let path = uri_to_path(uri)
  let stem = stem_of_path(path)
  let hits = parse_mooncheck_errors(log, stem + ".gen.mbt")
  if hits.length() == 0 {
    return []
  }
  let map_text = match fs_read(check_map_path(root, path)) {
    Some(t) => t
    None => return []
  }
  let out : Array[(Int, Int, String)] = []
  for h in hits {
    match lsp_map_lookup(map_text, h.0) {
      Some((sl, sc)) => out.push((sl - 1, sc - 1, h.2))
      None => ()
    }
  }
  out
}

///|
/// dev source map 落点（与 dev 循环的 dev_map_path 同式）：`.mng/map/<模板
/// 相对项目根的包路径>/<stem>.gen.mbt.map`。
fn check_map_path(root : String, mng_path : String) -> String {
  let dir = dir_name_of_lsp(mng_path)
  let rel = if dir.has_prefix(root + "/") {
    dir[root.length() + 1:].to_owned()
  } else {
    // 根外（无法定位项目布局）：map 反查不到就跳过，不猜路径
    ""
  }
  if rel.length() == 0 {
    root + "/.mng/map/" + stem_of_path(mng_path) + ".gen.mbt.map"
  } else {
    root + "/.mng/map/" + rel + "/" + stem_of_path(mng_path) + ".gen.mbt.map"
  }
}

///|
/// 文件路径 → 目录部分（无斜杠给 "."）。
fn dir_name_of_lsp(p : String) -> String {
  let a = normalize_path(p).to_array()
  let mut last = -1
  for i, c in a {
    if c == '/' {
      last = i
    }
  }
  if last <= 0 {
    "."
  } else {
    slice_cli(a, 0, last)
  }
}

///|
/// 文件路径 → stem（basename 去首个扩展段，与生成函数名同规则）。
fn stem_of_path(p : String) -> String {
  let a = normalize_path(p).to_array()
  let mut start = 0
  for i, c in a {
    if c == '/' {
      start = i + 1
    }
  }
  let base = slice_cli(a, start, a.length())
  let b = base.to_array()
  let mut end = b.length()
  for i, c in b {
    if c == '.' {
      end = i
      break
    }
  }
  if end == 0 {
    base
  } else {
    slice_cli(b, 0, end)
  }
}

///|
/// moon check 日志 → 生成码位置命中：逐行找 `<gen_file>:L:C`（moon check 的
/// 框式输出 `╭─[ 路径:行:列 ]`），message 收集随后至下一个命中前的 `╰──` 行。
/// 其他文件 / 解析不了的行跳过。
fn parse_mooncheck_errors(
  log : String,
  gen_file : String,
) -> Array[(Int, Int, String)] {
  let out : Array[(Int, Int, String)] = []
  let lines : Array[String] = []
  for line0 in log.split("\n") {
    lines.push(line0.to_owned())
  }
  let mut i = 0
  let n = lines.length()
  while i < n {
    let line = lines[i]
    match line_ref_of(line, gen_file) {
      Some((l, c)) => {
        // 收集到下一个命中/错误边界为止的 `╰──` 说明行
        let msg_parts : Array[String] = []
        let mut j = i + 1
        while j < n && j <= i + 8 {
          let t = lines[j]
          if line_ref_of(t, gen_file) is Some(_) || contains_sub_cli(t, "Error") || contains_sub_cli(t, "Warning") {
            break
          }
          if contains_sub_cli(t, "╰──") {
            msg_parts.push(trim_cli(t))
          }
          j += 1
        }
        out.push((l, c, msg_parts.join(" ")))
        i = j
      }
      None => i += 1
    }
  }
  out
}

///|
/// 一行里提取 `<gen_file>:L:C`（前缘不是标识符字符，避免吃更长的文件名）。
fn line_ref_of(line : String, gen_file : String) -> (Int, Int)? {
  let a = line.to_array()
  let g = gen_file.to_array()
  let n = a.length()
  let m = g.length()
  if m == 0 || m > n {
    return None
  }
  let mut i = 0
  while i + m < n {
    let mut ok = true
    for k in 0..<m {
      if a[i + k] != g[k] {
        ok = false
        break
      }
    }
    if ok && a[i + m] == ':' && (i == 0 || !is_ident_char_lsp(a[i - 1])) {
      // L
      let mut j = i + m + 1
      let mut l = 0
      let mut got_l = false
      while j < n && a[j] >= '0' && a[j] <= '9' {
        l = l * 10 + (a[j].to_int() - '0'.to_int())
        got_l = true
        j += 1
      }
      if got_l && j < n && a[j] == ':' {
        let mut k2 = j + 1
        let mut c = 0
        let mut got_c = false
        while k2 < n && a[k2] >= '0' && a[k2] <= '9' {
          c = c * 10 + (a[k2].to_int() - '0'.to_int())
          got_c = true
          k2 += 1
        }
        if got_c {
          return Some((l, c))
        }
      }
    }
    i += 1
  }
  None
}

///|
fn is_ident_char_lsp(c : Char) -> Bool {
  (c >= 'a' && c <= 'z') ||
  (c >= 'A' && c <= 'Z') ||
  (c >= '0' && c <= '9') ||
  c == '_' || c == '.'
}

///|
/// dev source map 反查：gen_line ≤ 目标的最靠后条目（map 文件三列
/// `gen\tsrc_line\tsrc_col`，头行 `source`/`gen`/`#` 跳过）。
fn lsp_map_lookup(map_text : String, gen_line : Int) -> (Int, Int)? {
  let mut best : (Int, Int)? = None
  for line0 in map_text.split("\n") {
    let line = line0.trim(chars=" \t\r").to_owned()
    if line.length() == 0 || line.has_prefix("#") || line.has_prefix("source") || line.has_prefix("gen ") {
      continue
    }
    let parts = line.split("\t").to_array()
    if parts.length() < 3 {
      continue
    }
    let g = atoi_lsp(parts[0].to_owned())
    let sl = atoi_lsp(parts[1].to_owned())
    let sc = atoi_lsp(parts[2].to_owned())
    match (g, sl, sc) {
      (Some(gv), Some(sv), Some(cv)) =>
        if gv <= gen_line {
          best = Some((sv, cv))
        }
      _ => ()
    }
  }
  best
}

///|
fn atoi_lsp(s : String) -> Int? {
  let a = s.to_array()
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
fn trim_cli(t : String) -> String {
  let a = t.to_array()
  let mut lo = 0
  let mut hi = a.length()
  while lo < hi && (a[lo] == ' ' || a[lo] == '\t' || a[lo] == '\r' || a[lo] == '│') {
    lo += 1
  }
  while hi > lo && (a[hi - 1] == ' ' || a[hi - 1] == '\t' || a[hi - 1] == '\r' || a[hi - 1] == '│') {
    hi -= 1
  }
  slice_cli(a, lo, hi)
}
