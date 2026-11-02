// script 段分析：组件签名头（props）、槽名与种类（Store/Signal/普通）、
// let 绑定的组件路径、`// @mng` 覆盖声明。纯词法，不解析 MoonBit 语义。

///|
priv struct ScriptInfo {
  slots : Map[String, SlotKind]
  lets : Array[String]
  // let 名 → 右值组件路径（`let sh_section = @shared.section`）
  let_paths : Map[String, String]
  // let 名 → script 内 0 基行号（被当组件消费且无引用时，生成体里丢该行）
  let_lines : Map[String, Int]
  comps : Map[String, CompDecl]
  // props 头：原文行（空数组 = 未声明，退回 `fn <stem>() -> @widget.Node`）与参数表
  head : Array[String]
  head_line : Int
  head_ret : String
  params : Array[Param]
  // 槽名 → 元素类型原文（`Store[Int]` → `Int`；dev 档按类型登记 state）
  slot_tys : Map[String, String]
  line0 : Int
  lines : Array[String]
}

///|
/// 签名头识别：script 段第一个 `fn` 声明，括号配平后**不含**顶层 `{`（含即为页内辅助函数）。
fn find_head(lines : Array[String]) -> (Array[String], Int) {
  let n = lines.length()
  let mut i = 0
  while i < n {
    let t = lines[i].trim().to_owned()
    if t.has_prefix("fn ") || t.has_prefix("pub fn ") || t == "fn" {
      let block : Array[String] = []
      let mut depth = 0
      let mut opened = false
      let mut j = i
      while j < n {
        let l = lines[j].trim().to_owned()
        block.push(lines[j])
        let cs = chars_of(l)
        for c in cs {
          if c == '(' {
            depth += 1
            opened = true
          } else if c == ')' {
            depth -= 1
          } else if c == '{' && opened && depth == 0 {
            // 带函数体：页内辅助函数，不是组件签名头
            return ([], -1)
          }
        }
        if opened && depth <= 0 {
          return (block, i)
        }
        j += 1
      }
      return ([], -1)
    }
    i += 1
  }
  ([], -1)
}

///|
/// 右值 → 组件路径：`@包.名`（点分段全为标识符、无空格）或同包裸名 `名`；其余返回 None。
fn path_of_rv(rv : String) -> String? {
  let s = strip_line_comment(rv.trim().to_owned())
  if s.length() == 0 {
    return None
  }
  let a = chars_of(s)
  let n = a.length()
  let bare = is_ident_start(a[0])
  let start = if a[0] == '@' { 1 } else if bare { 0 } else { return None }
  let mut seg = 0
  let mut i = start
  while i < n {
    let c = a[i]
    if c == '.' {
      if seg == 0 || bare {
        return None
      }
      seg = 0
    } else if is_ident_char(c) {
      seg += 1
    } else {
      return None
    }
    i += 1
  }
  if seg == 0 {
    None
  } else {
    Some(s)
  }
}

///|
/// 去掉行尾 `//` 注释（不处理串里的 //，声明行右值够用）。
fn strip_line_comment(s : String) -> String {
  let a = chars_of(s)
  let n = a.length()
  let mut i = 0
  while i + 1 < n {
    if a[i] == '/' && a[i + 1] == '/' {
      return s[:i].trim_end().to_owned()
    }
    i += 1
  }
  s
}

///|
/// 声明行识别：`let <名> [: <类型>] = <右值>` 按类型注解（Store[ / Signal[）与右值形态分档。
fn analyze_script(script : String, line0 : Int) -> ScriptInfo {
  let slots : Map[String, SlotKind] = Map([])
  let lets : Array[String] = []
  let let_paths : Map[String, String] = Map([])
  let let_lines : Map[String, Int] = Map([])
  let comps : Map[String, CompDecl] = Map([])
  let slot_tys : Map[String, String] = Map([])
  let lines = split_arr(script, "\n")
  let (head0, head_line0) = find_head(lines)
  let params : Array[Param] = []
  let mut head = head0
  let mut head_line = head_line0
  let mut head_ret = ""
  if head.length() > 0 {
    match parse_fn_sig(head.join("\n")) {
      Some(sig) => {
        head_ret = sig.ret
        for p in sig.params {
          params.push(p)
          let _ = slots.set(p.name, kind_of_ty(p.ty))
          match elem_ty_of(p.ty) {
            Some(t) => {
              let _ = slot_tys.set(p.name, t)
            }
            None => ()
          }
        }
      }
      None => {
        // 解析不了就不当头：原文留在函数体里，交 moon check 报错回映射
        head = []
        head_line = -1
      }
    }
  }
  for k, raw in lines {
    let l = raw.trim().to_owned()
    if l.has_prefix("// @mng ") {
      match parse_mng_decl(l) {
        Ok((tag, d)) => {
          // 模板标签按 kebab 书写，查表按 snake——存时归一
          let _ = comps.set(snake(tag), d)
        }
        Err(e) => {
          // 坏格式声明：记一个 @mng-error 前缀路径，该标签被用到时报错并带原因
          let body = l[8:].to_owned()
          let toks = split_arr(body, " ")
          if toks.length() > 0 && toks[0].length() > 0 {
            let _ = comps.set(snake(toks[0]), { path: "@mng-error:" + e, positional: [] })
          }
        }
      }
      continue
    }
    if k >= head_line && head_line >= 0 && k < head_line + head.length() {
      continue
    }
    if l.has_prefix("let ") {
      let rest = l[4:].to_owned()
      let a = chars_of(rest)
      let mut i = 0
      while i < a.length() && is_ident_char(a[i]) {
        i += 1
      }
      if i > 0 {
        let name = a[0:i].map(fn(c) { c.to_string() }).join("")
        lets.push(name)
        let _ = let_lines.set(name, k)
        let mut j = i
        while j < a.length() && (a[j] == ' ' || a[j] == '\t') {
          j += 1
        }
        if j < a.length() && a[j] == ':' {
          let mut e = j
          while e < a.length() && a[e] != '=' {
            e += 1
          }
          let ty = a[j:e].map(fn(c) { c.to_string() }).join("")
          let _ = slots.set(name, kind_of_ty(ty))
          match elem_ty_of(ty) {
            Some(t) => {
              let _ = slot_tys.set(name, t)
            }
            None => ()
          }
          // 右值：`=` 之后到行尾（去注释），`@包.名` 形态即可作组件路径
          if e < a.length() && a[e] == '=' {
            let rv = a[e + 1:].map(fn(c) { c.to_string() }).join("")
            match path_of_rv(rv) {
              Some(p) => {
                let _ = let_paths.set(name, p)
              }
              None => ()
            }
          }
        } else {
          let _ = slots.set(name, KPlain)
          let mut e = j
          while e < a.length() && a[e] != '=' {
            e += 1
          }
          if e < a.length() && a[e] == '=' {
            let rv = a[e + 1:].map(fn(c) { c.to_string() }).join("")
            match path_of_rv(rv) {
              Some(p) => {
                let _ = let_paths.set(name, p)
              }
              None => ()
            }
          }
        }
      }
    }
  }
  {
    slots,
    lets,
    let_paths,
    let_lines,
    comps,
    head,
    head_line,
    head_ret,
    params,
    slot_tys,
    line0,
    lines,
  }
}

///|
/// `// @mng <tag> = <path> positional(a, b, children)` → CompDecl（覆盖参数顺序/落点）。
fn parse_mng_decl(l : String) -> Result[(String, CompDecl), String] {
  let body = l[8:].to_owned()
  let parts = split_arr(body, " ")
  let nonempty : Array[String] = []
  for p in parts {
    if p.length() > 0 {
      nonempty.push(p)
    }
  }
  if nonempty.length() < 2 || nonempty[1] != "=" {
    return Err("@mng 声明格式：// @mng <标签> = <路径> positional(参数…)")
  }
  let tag = nonempty[0]
  let path = if nonempty.length() > 2 {
    nonempty[2]
  } else {
    ""
  }
  let positional : Array[String] = []
  let mut joined = ""
  for k in 3..<nonempty.length() {
    joined += nonempty[k]
  }
  if joined.has_prefix("positional(") && joined.has_suffix(")") {
    let inner = joined[11:joined.length() - 1].to_owned()
    for seg0 in inner.split(",") {
      let seg = seg0.trim().to_owned()
      if seg.length() > 0 {
        positional.push(seg)
      }
    }
  }
  Ok((tag, { path, positional }))
}

///|
/// `@base.Store[Int]` / `Signal[Bool]` → 方括号内的元素类型文本；非容器返回 None。
fn elem_ty_of(ty : String) -> String? {
  let a = chars_of(ty)
  let mut lo = -1
  let mut hi = -1
  let mut depth = 0
  let mut i = 0
  while i < a.length() {
    if a[i] == '[' {
      if depth == 0 && lo < 0 {
        lo = i + 1
      }
      depth += 1
    } else if a[i] == ']' {
      depth -= 1
      if depth == 0 && lo >= 0 && hi < 0 {
        hi = i
      }
    }
    i += 1
  }
  if lo < 0 || hi <= lo {
    return None
  }
  if !contains_sub(ty, "Store[") && !contains_sub(ty, "Signal[") {
    return None
  }
  Some(slice_str(a, lo, hi).trim().to_owned())
}

///|
/// script 段里可作为表达式补全的符号：props 参数 + let 绑定 + 函数名（按首现序）。
pub fn script_symbols(src : String) -> Array[String] {
  let sfc = match parse_sfc(src) {
    Ok(v) => v
    Err(_) => return []
  }
  let info = analyze_script(sfc.script, sfc.script_line0)
  let out : Array[String] = []
  for p in info.params {
    out.push(p.name)
  }
  for x in info.lets {
    out.push(x)
  }
  for l in info.lines {
    let t = l.trim().to_owned()
    if t.has_prefix("fn ") {
      let a = chars_of(t)
      let mut i = 3
      while i < a.length() && (a[i] == ' ' || a[i] == '\t') {
        i += 1
      }
      let mut j = i
      while j < a.length() && is_ident_char(a[j]) {
        j += 1
      }
      let nm = slice_str(a, i, j)
      if nm.length() > 0 && !arr_contains(out, nm) {
        out.push(nm)
      }
    }
  }
  out
}

///|
/// `<style>` 段里定义的类名（去重、按首现序）。
pub fn style_class_names(src : String) -> Array[String] {
  let sfc = match parse_sfc(src) {
    Ok(v) => v
    Err(_) => return []
  }
  let rules = match parse_style(sfc.style) {
    Ok(r) => r
    Err(_) => return []
  }
  let out : Array[String] = []
  for r in rules {
    if !arr_contains(out, r.class) {
      out.push(r.class)
    }
  }
  out
}
