// LSP 自用的极简 JSON：对象/数组/串/数/布尔/null 的解析与拼装。
// 只服务 stdio JSON-RPC 报文，够用即止（不做转义之外的诊断友好性）。

///|
priv enum LJson {
  LObj(Map[String, LJson])
  LArr(Array[LJson])
  LStr(String)
  LNum(Double)
  LBool(Bool)
  LNull
}

///|
priv struct JParse {
  cs : Array[Char]
  mut i : Int32
}

///|
fn jp_ws(p : JParse) -> Unit {
  while p.i < p.cs.length() {
    let c = p.cs[p.i]
    if c == ' ' || c == '\t' || c == '\n' || c == '\r' {
      p.i += 1
    } else {
      break
    }
  }
}

///|
fn jp_value(p : JParse) -> Result[LJson, String] {
  jp_ws(p)
  if p.i >= p.cs.length() {
    return Err("JSON 提前结束")
  }
  let c = p.cs[p.i]
  if c == '{' {
    p.i += 1
    let m : Map[String, LJson] = Map([])
    jp_ws(p)
    if p.i < p.cs.length() && p.cs[p.i] == '}' {
      p.i += 1
      return Ok(LObj(m))
    }
    while true {
      jp_ws(p)
      let key = match jp_value(p) {
        Ok(LStr(s)) => s
        _ => return Err("JSON 对象键需为串")
      }
      jp_ws(p)
      if p.i >= p.cs.length() || p.cs[p.i] != ':' {
        return Err("JSON 对象缺冒号")
      }
      p.i += 1
      let v = match jp_value(p) {
        Ok(v) => v
        Err(e) => return Err(e)
      }
      let _ = m.set(key, v)
      jp_ws(p)
      if p.i >= p.cs.length() {
        return Err("JSON 对象未闭合")
      }
      if p.cs[p.i] == ',' {
        p.i += 1
        continue
      }
      if p.cs[p.i] == '}' {
        p.i += 1
        return Ok(LObj(m))
      }
      return Err("JSON 对象缺逗号或右括号")
    }
    abort("unreachable")
  } else if c == '[' {
    p.i += 1
    let arr : Array[LJson] = []
    jp_ws(p)
    if p.i < p.cs.length() && p.cs[p.i] == ']' {
      p.i += 1
      return Ok(LArr(arr))
    }
    while true {
      let v = match jp_value(p) {
        Ok(v) => v
        Err(e) => return Err(e)
      }
      arr.push(v)
      jp_ws(p)
      if p.i >= p.cs.length() {
        return Err("JSON 数组未闭合")
      }
      if p.cs[p.i] == ',' {
        p.i += 1
        continue
      }
      if p.cs[p.i] == ']' {
        p.i += 1
        return Ok(LArr(arr))
      }
      return Err("JSON 数组缺逗号或右括号")
    }
    abort("unreachable")
  } else if c == '"' {
    p.i += 1
    let out = StringBuilder()
    while p.i < p.cs.length() && p.cs[p.i] != '"' {
      let ch = p.cs[p.i]
      if ch == '\\' && p.i + 1 < p.cs.length() {
        let nx = p.cs[p.i + 1]
        if nx == 'n' {
          out.write_char('\n')
        } else if nx == 't' {
          out.write_char('\t')
        } else if nx == 'r' {
          out.write_char('\r')
        } else if nx == 'u' && p.i + 5 < p.cs.length() {
          // \uXXXX：只处理 BMP 常见区（LSP 报文里的中文路径不常走这口）
          let hex = StringBuilder()
          for k in 2..<6 {
            hex.write_char(p.cs[p.i + k])
          }
          match parse_hex4(hex.to_string()) {
            Some(cp) => out.write_char(cp.unsafe_to_char())
            None => out.write_char('?')
          }
          p.i += 4
        } else {
          out.write_char(nx)
        }
        p.i += 2
      } else {
        out.write_char(ch)
        p.i += 1
      }
    }
    if p.i >= p.cs.length() {
      return Err("JSON 串未闭合")
    }
    p.i += 1
    Ok(LStr(out.to_string()))
  } else if c == 't' {
    if jp_lit(p, "true") {
      Ok(LBool(true))
    } else {
      Err("JSON 字面量非法")
    }
  } else if c == 'f' {
    if jp_lit(p, "false") {
      Ok(LBool(false))
    } else {
      Err("JSON 字面量非法")
    }
  } else if c == 'n' {
    if jp_lit(p, "null") {
      Ok(LNull)
    } else {
      Err("JSON 字面量非法")
    }
  } else {
    let start = p.i
    while p.i < p.cs.length() {
      let d = p.cs[p.i]
      if (d >= '0' && d <= '9') ||
        d == '-' ||
        d == '+' ||
        d == '.' ||
        d == 'e' ||
        d == 'E' {
        p.i += 1
      } else {
        break
      }
    }
    let seg = slice_str_js(p.cs, start, p.i)
    match num_of(seg) {
      Some(v) => Ok(LNum(v))
      None => Err("JSON 数字非法：" + seg)
    }
  }
}

///|
fn jp_lit(p : JParse, lit : String) -> Bool {
  let a = chars_of_js(lit)
  if p.i + a.length() > p.cs.length() {
    return false
  }
  for k in 0..<a.length() {
    if p.cs[p.i + k] != a[k] {
      return false
    }
  }
  p.i += a.length()
  true
}

///|
fn parse_hex4(s : String) -> Int32? {
  let a = chars_of_js(s)
  if a.length() != 4 {
    return None
  }
  let mut v = 0
  for c in a {
    let d = if c >= '0' && c <= '9' {
      c.to_int() - '0'.to_int()
    } else if c >= 'a' && c <= 'f' {
      c.to_int() - 'a'.to_int() + 10
    } else if c >= 'A' && c <= 'F' {
      c.to_int() - 'A'.to_int() + 10
    } else {
      return None
    }
    v = v * 16 + d
  }
  Some(v)
}

///|
fn num_of(s : String) -> Double? {
  let a = chars_of_js(s)
  if a.length() == 0 {
    return None
  }
  let mut neg = false
  let mut i = 0
  if a[0] == '-' {
    neg = true
    i = 1
  }
  let mut int_part = 0.0
  let mut digits = 0
  while i < a.length() && a[i] >= '0' && a[i] <= '9' {
    int_part = int_part * 10.0 + (a[i].to_int() - '0'.to_int()).to_double()
    digits += 1
    i += 1
  }
  let mut frac = 0.0
  let mut scale = 0.1
  if i < a.length() && a[i] == '.' {
    i += 1
    while i < a.length() && a[i] >= '0' && a[i] <= '9' {
      frac += (a[i].to_int() - '0'.to_int()).to_double() * scale
      scale = scale * 0.1
      digits += 1
      i += 1
    }
  }
  if digits == 0 {
    return None
  }
  let v = int_part + frac
  Some(if neg { -v } else { v })
}

///|
fn chars_of_js(s : String) -> Array[Char] {
  let out : Array[Char] = []
  for c in s {
    out.push(c)
  }
  out
}

///|
fn slice_str_js(a : Array[Char], lo : Int32, hi : Int32) -> String {
  if hi <= lo {
    ""
  } else {
    a[lo:hi].map(fn(c) { c.to_string() }).join("")
  }
}

///|
/// 报文串 → JSON。
fn json_parse(s : String) -> Result[LJson, String] {
  let p = { cs: chars_of_js(s), i: 0, }
  let v = match jp_value(p) {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  jp_ws(p)
  Ok(v)
}

///|
fn json_str(j : LJson) -> String? {
  match j {
    LStr(s) => Some(s)
    _ => None
  }
}

///|
fn json_num(j : LJson) -> Int32? {
  match j {
    LNum(v) => Some(v.to_int())
    _ => None
  }
}

///|
fn json_arr(j : LJson) -> Array[LJson]? {
  match j {
    LArr(a) => Some(a)
    _ => None
  }
}

///|
/// 对象取键（非对象或键缺失给 None）。
fn jget(j : LJson, key : String) -> LJson? {
  match j {
    LObj(m) => m.get(key)
    _ => None
  }
}

///|
/// 路径取值：`a/b/c` 逐层取对象键。
fn jpath(j : LJson, path : String) -> LJson? {
  let mut cur = Some(j)
  for seg in split_path(path) {
    cur = match cur {
      Some(x) => jget(x, seg)
      None => None
    }
  }
  cur
}

///|
fn split_path(p : String) -> Array[String] {
  let out : Array[String] = []
  let a = chars_of_js(p)
  let mut start = 0
  let mut i = 0
  while i <= a.length() {
    if i == a.length() || a[i] == '/' {
      if i > start {
        out.push(slice_str_js(a, start, i))
      }
      start = i + 1
    }
    i += 1
  }
  out
}

///|
/// 串 → JSON 串字面量（带引号与转义）。
fn jq(s : String) -> String {
  let out = StringBuilder()
  out.write_char('"')
  for c in s {
    if c == '"' {
      out.write_string("\\\"")
    } else if c == '\\' {
      out.write_string("\\\\")
    } else if c == '\n' {
      out.write_string("\\n")
    } else if c == '\r' {
      out.write_string("\\r")
    } else if c == '\t' {
      out.write_string("\\t")
    } else if c.to_int() < 32 {
      out.write_string("\\u")
    } else {
      out.write_char(c)
    }
  }
  out.write_char('"')
  out.to_string()
}
