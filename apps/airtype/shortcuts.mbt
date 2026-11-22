// 快捷指令：桌面端配置的手机快捷按钮（发预置文本 + 可带回车），TSV 文本
// 持久化。行格式三种：`文本`（标签同文本、带回车）、`文本|no`（不带回车）、
// `标签|文本|yes/no`。`#` 开头的行是注释。

///|
struct ShortCut {
  label : String
  text : String
  enter : Bool
}

///|
let g_shortcuts_cfg : Ref[String] = Ref("")

///|
fn shortcuts_path() -> String? {
  match @sys.sys_platform() {
    "windows" =>
      match @sys.sys_getenv("APPDATA") {
        Some(base) => Some(base + "\\airtype\\shortcuts.tsv")
        None => None
      }
    _ =>
      match @sys.sys_getenv("HOME") {
        Some(home) => Some(home + "/.config/airtype/shortcuts.tsv")
        None => None
      }
  }
}

///|
const SHORTCUTS_DEFAULT : String = "继续\n"

///|
/// 去掉会破坏行格式的字符：换行清掉、超长截断。
fn sanitize_field(s : String) -> String {
  let mut out = ""
  for ch in s {
    if ch != '\n' && ch != '\r' {
      out = out + ch.to_string()
    }
  }
  let t = out.trim().to_owned()
  if t.length() > 200 {
    t[:200].to_owned()
  } else {
    t
  }
}

///|
fn parse_shortcuts(text : String) -> Array[ShortCut] {
  let out : Array[ShortCut] = []
  for line0 in text.split("\n") {
    let line = line0.to_owned().trim().to_owned()
    if line.length() == 0 || line.has_prefix("#") {
      continue
    }
    let parts : Array[String] = []
    for p in line.split("|") {
      parts.push(p.to_owned())
    }
    // 尾段是 yes/no 时按回车开关消费
    let mut enter = true
    let mut keep = parts.length()
    if keep >= 2 {
      let last = parts[keep - 1].trim().to_owned()
      if last == "yes" {
        keep = keep - 1
      } else if last == "no" {
        enter = false
        keep = keep - 1
      }
    }
    if keep == 0 {
      continue
    }
    let (label, body) : (String, String) = if keep >= 2 {
      let mut t = ""
      for i in 1..<keep {
        if i > 1 {
          t = t + "|"
        }
        t = t + parts[i]
      }
      (sanitize_field(parts[0]), sanitize_field(t))
    } else {
      let t = sanitize_field(parts[0])
      (t, t)
    }
    if label.length() > 0 && body.length() > 0 {
      out.push({ label, text: body, enter })
    }
  }
  out
}

///|
fn json_escape(s : String) -> String {
  let mut out = ""
  for ch in s {
    match ch {
      '"' => out = out + "\\\""
      '\\' => out = out + "\\\\"
      _ => out = out + ch.to_string()
    }
  }
  out
}

///|
/// 手机页 `/cfg` 的载荷：紧凑 JSON 数组。
fn shortcuts_json() -> String {
  let list = parse_shortcuts(g_shortcuts_cfg.val)
  let mut out = "["
  for i, sc in list {
    if i > 0 {
      out = out + ","
    }
    out = out + "{\"l\":\"" + json_escape(sc.label)
    out = out + "\",\"t\":\"" + json_escape(sc.text)
    out = out + "\",\"e\":" + (if sc.enter { "true" } else { "false" }) + "}"
  }
  out + "]"
}

///|
/// 启动加载：文件缺失或读失败给默认配置；文件在则以其为准。
fn load_shortcuts() -> String {
  let text = match shortcuts_path() {
    Some(path) =>
      match @sys.sys_read_text_file(path) {
        Some(t) => t
        None => SHORTCUTS_DEFAULT
      }
    None => SHORTCUTS_DEFAULT
  }
  g_shortcuts_cfg.val = text
  text
}

///|
/// 配置变更（桌面编辑）：更新全局并落盘，落盘失败不阻断（内存生效）。
fn apply_shortcuts(text : String) -> Unit {
  g_shortcuts_cfg.val = text
  match shortcuts_path() {
    Some(path) => {
      let dir = match path.rev_find("/") {
        Some(i) => path[:i].to_owned()
        None => ""
      }
      if dir.length() > 0 {
        let _ = @sys.sys_make_dirs(dir)
      }
      let _ = @sys.sys_write_text_file(path, text)
    }
    None => ()
  }
}
