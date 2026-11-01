// script 段分析：槽名与种类（Store/Signal/普通）、@mng 组件声明。纯词法，不解析 MoonBit。

///|
priv struct ScriptInfo {
  slots : Map[String, SlotKind]
  lets : Array[String]
  comps : Map[String, CompDecl]
  line0 : Int
  lines : Array[String]
}

///|
/// 声明行识别：`let <名> : <类型>` 按类型前缀分档（Store[ / Signal[），无注解按普通值。
fn analyze_script(script : String, line0 : Int) -> ScriptInfo {
  let slots : Map[String, SlotKind] = Map([])
  let lets : Array[String] = []
  let comps : Map[String, CompDecl] = Map([])
  let lines = split_arr(script, "\n")
  for raw in lines {
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
          let kind = if contains_sub(ty, "Store[") {
            KStore
          } else if contains_sub(ty, "Signal[") {
            KSignal
          } else {
            KPlain
          }
          let _ = slots.set(name, kind)
        } else {
          let _ = slots.set(name, KPlain)
        }
      }
    }
  }
  { slots, lets, comps, line0, lines }
}

///|
/// `// @mng <tag> = <path> positional(a, b, children)` → CompDecl。
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
