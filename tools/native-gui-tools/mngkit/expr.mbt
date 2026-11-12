// 受限表达式文法（dev v2a-1）：字面量、状态名、.get()/.to_string()、
// 算术/比较/逻辑、if 表达式、已登记函数调用。文法和类型检查通过才可热更；
// 其余表达式转 COLD。

///|
priv enum EType {
  TInt
  TDouble
  TBool
  TStr
}

///|
priv enum ENode {
  NInt(Int32)
  NDouble(Double)
  NBool(Bool)
  NStr(String)
  NId(String)
  NGet(ENode)
  NToStr(ENode)
  NNot(ENode)
  NNeg(ENode)
  NBin(String, ENode, ENode)
  NIf(ENode, ENode, ENode)
  NCall(String, Array[ENode])
}

///|
priv struct EP {
  cs : Array[Char]
  mut i : Int32
}

///|
priv suberror ExprRaise {
  ExprRaise(String)
}

///|
fn[A] need(r : Result[A, String]) -> A raise ExprRaise {
  match r {
    Ok(v) => v
    Err(e) => raise ExprRaise(e)
  }
}

///|
fn ep_new(s : String) -> EP {
  { cs: chars_of(s), i: 0, }
}

///|
fn ep_ws(p : EP) -> Unit {
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
fn ep_eof(p : EP) -> Bool {
  ep_ws(p)
  p.i >= p.cs.length()
}

///|
fn ep_accept(p : EP, c : Char) -> Bool {
  ep_ws(p)
  if p.i < p.cs.length() && p.cs[p.i] == c {
    p.i += 1
    true
  } else {
    false
  }
}

///|
fn ep_accept_str(p : EP, s : String) -> Bool {
  ep_ws(p)
  let a = chars_of(s)
  if p.i + a.length() <= p.cs.length() {
    let mut ok = true
    for k in 0..<a.length() {
      if p.cs[p.i + k] != a[k] {
        ok = false
      }
    }
    if ok {
      p.i += a.length()
      return true
    }
  }
  false
}

///|
fn ep_expect(p : EP, c : Char) -> Result[Unit, String] {
  if ep_accept(p, c) {
    Ok(())
  } else {
    Err("表达式：期待「\{c}」")
  }
}

///|
fn ep_ident(p : EP) -> String {
  ep_ws(p)
  let mut s = ""
  if p.i < p.cs.length() && (is_ident_start(p.cs[p.i]) || p.cs[p.i] == '@') {
    s = s + p.cs[p.i].to_string()
    p.i += 1
    while p.i < p.cs.length() && is_ident_char(p.cs[p.i]) {
      s = s + p.cs[p.i].to_string()
      p.i += 1
    }
  }
  s
}

///|
fn ep_path(p : EP) -> String {
  let mut s = ep_ident(p)
  while ep_accept(p, '.') {
    s = s + "." + ep_ident(p)
  }
  s
}

///|
fn ep_string(p : EP) -> Result[ENode, String] raise ExprRaise {
  let _ = need(ep_expect(p, '"'))
  let parts : Array[ENode] = []
  let mut lit = StringBuilder()
  while p.i < p.cs.length() {
    let c = p.cs[p.i]
    if c == '"' {
      p.i += 1
      if lit.to_string().length() > 0 {
        parts.push(NStr(lit.to_string()))
      }
      if parts.length() == 0 {
        return Ok(NStr(""))
      }
      let mut n = parts[0]
      let mut k = 1
      while k < parts.length() {
        n = NBin("+", n, parts[k])
        k += 1
      }
      return Ok(n)
    }
    if c == '\\' {
      if p.i + 1 >= p.cs.length() {
        return Err("表达式：字符串未闭合")
      }
      let e = p.cs[p.i + 1]
      p.i += 2
      if e == '"' {
        lit.write_char('"')
      } else if e == '\\' {
        lit.write_char('\\')
      } else if e == 'n' {
        lit.write_char('\n')
      } else if e == 't' {
        lit.write_char('\t')
      } else if e == 'r' {
        lit.write_char('\r')
      } else if e == '{' {
        if lit.to_string().length() > 0 {
          parts.push(NStr(lit.to_string()))
          lit = StringBuilder()
        }
        let inner = need(parse_expr(p))
        let _ = need(ep_expect(p, '}'))
        parts.push(NToStr(inner))
      } else {
        return Err("表达式：不支持的字符串转义 \\" + e.to_string())
      }
    } else {
      lit.write_char(c)
      p.i += 1
    }
  }
  Err("表达式：字符串未闭合")
}

///|
fn ep_number(p : EP) -> Result[ENode, String] {
  ep_ws(p)
  let start = p.i
  while p.i < p.cs.length() && is_digit(p.cs[p.i]) {
    p.i += 1
  }
  if p.i == start {
    return Err("表达式：缺数字")
  }
  let mut is_double = false
  if p.i + 1 < p.cs.length() && p.cs[p.i] == '.' && is_digit(p.cs[p.i + 1]) {
    is_double = true
    p.i += 1
    while p.i < p.cs.length() && is_digit(p.cs[p.i]) {
      p.i += 1
    }
  }
  let text = p.cs[start:p.i].map(fn(c) { c.to_string() }).join("")
  if is_double {
    Ok(NDouble(parse_double(text)))
  } else {
    let mut v = 0
    for c in chars_of(text) {
      v = v * 10 + (c.to_int() - '0'.to_int())
    }
    Ok(NInt(v))
  }
}

///|
fn parse_primary(p : EP) -> Result[ENode, String] raise ExprRaise {
  ep_ws(p)
  if ep_eof(p) {
    return Err("表达式：意外结束")
  }
  let c = p.cs[p.i]
  if c == '"' {
    return ep_string(p)
  }
  if is_digit(c) {
    return ep_number(p)
  }
  if c == '(' {
    p.i += 1
    let n = need(parse_expr(p))
    let _ = need(ep_expect(p, ')'))
    return Ok(n)
  }
  if c == '@' {
    let name = ep_path(p)
    let _ = need(ep_expect(p, '('))
    let args : Array[ENode] = []
    if !ep_accept(p, ')') {
      while true {
        args.push(need(parse_expr(p)))
        if ep_accept(p, ')') {
          break
        }
        let _ = need(ep_expect(p, ','))
      }
    }
    return Ok(NCall(name, args))
  }
  if is_ident_start(c) {
    let name = ep_ident(p)
    if name == "true" {
      return Ok(NBool(true))
    }
    if name == "false" {
      return Ok(NBool(false))
    }
    if name == "if" {
      let cond = need(parse_expr(p))
      let _ = need(ep_expect(p, '{'))
      let then = need(parse_expr(p))
      let _ = need(ep_expect(p, '}'))
      ep_ws(p)
      let kw = ep_ident(p)
      if kw != "else" {
        return Err("表达式：if 需要 else 分支")
      }
      let _ = need(ep_expect(p, '{'))
      let els = need(parse_expr(p))
      let _ = need(ep_expect(p, '}'))
      return Ok(NIf(cond, then, els))
    }
    if ep_accept(p, '(') {
      let args : Array[ENode] = []
      if !ep_accept(p, ')') {
        while true {
          args.push(need(parse_expr(p)))
          if ep_accept(p, ')') {
            break
          }
          let _ = need(ep_expect(p, ','))
        }
      }
      return Ok(NCall(name, args))
    }
    return Ok(NId(name))
  }
  Err("表达式：无法识别的字符「\{c}」")
}

///|
fn parse_postfix(p : EP) -> Result[ENode, String] raise ExprRaise {
  let mut n = need(parse_primary(p))
  while true {
    if !ep_accept(p, '.') {
      break
    }
    let name = ep_ident(p)
    if name == "get" {
      let _ = need(ep_expect(p, '('))
      let _ = need(ep_expect(p, ')'))
      n = NGet(n)
    } else if name == "to_string" {
      let _ = need(ep_expect(p, '('))
      let _ = need(ep_expect(p, ')'))
      n = NToStr(n)
    } else {
      return Err("表达式：方法 .\{name}() 不在热更文法")
    }
  }
  Ok(n)
}

///|
fn parse_unary(p : EP) -> Result[ENode, String] raise ExprRaise {
  if ep_accept(p, '!') {
    Ok(NNot(need(parse_unary(p))))
  } else if ep_accept(p, '-') {
    Ok(NNeg(need(parse_unary(p))))
  } else {
    parse_postfix(p)
  }
}

///|
fn parse_mul(p : EP) -> Result[ENode, String] raise ExprRaise {
  let mut n = need(parse_unary(p))
  while true {
    let op = if ep_accept(p, '*') {
      "*"
    } else if ep_accept(p, '/') {
      "/"
    } else if ep_accept(p, '%') {
      "%"
    } else {
      break
    }
    n = NBin(op, n, need(parse_unary(p)))
  }
  Ok(n)
}

///|
fn parse_add(p : EP) -> Result[ENode, String] raise ExprRaise {
  let mut n = need(parse_mul(p))
  while true {
    let op = if ep_accept(p, '+') {
      "+"
    } else if ep_accept(p, '-') {
      "-"
    } else {
      break
    }
    n = NBin(op, n, need(parse_mul(p)))
  }
  Ok(n)
}

///|
fn parse_cmp(p : EP) -> Result[ENode, String] raise ExprRaise {
  let mut n = need(parse_add(p))
  while true {
    let op = if ep_accept_str(p, "==") {
      "=="
    } else if ep_accept_str(p, "!=") {
      "!="
    } else if ep_accept_str(p, "<=") {
      "<="
    } else if ep_accept_str(p, ">=") {
      ">="
    } else if ep_accept(p, '<') {
      "<"
    } else if ep_accept(p, '>') {
      ">"
    } else {
      break
    }
    n = NBin(op, n, need(parse_add(p)))
  }
  Ok(n)
}

///|
fn parse_and(p : EP) -> Result[ENode, String] raise ExprRaise {
  let mut n = need(parse_cmp(p))
  while ep_accept_str(p, "&&") {
    n = NBin("&&", n, need(parse_cmp(p)))
  }
  Ok(n)
}

///|
fn parse_expr(p : EP) -> Result[ENode, String] raise ExprRaise {
  let mut n = need(parse_and(p))
  while ep_accept_str(p, "||") {
    n = NBin("||", n, need(parse_and(p)))
  }
  Ok(n)
}

///|
fn etype_eq(a : EType, b : EType) -> Bool {
  match (a, b) {
    (TInt, TInt) | (TDouble, TDouble) | (TBool, TBool) | (TStr, TStr) => true
    _ => false
  }
}

///|
fn etype_of(
  n : ENode,
  syms : Map[String, EType],
) -> Result[EType, String] raise ExprRaise {
  match n {
    NInt(_) => Ok(TInt)
    NDouble(_) => Ok(TDouble)
    NBool(_) => Ok(TBool)
    NStr(_) => Ok(TStr)
    NId(name) =>
      match syms.get(name) {
        Some(t) => Ok(t)
        None => Err("表达式符号「\{name}」未登记为顶层 Store")
      }
    NGet(a) =>
      match a {
        NId(name) =>
          match syms.get(name) {
            Some(t) => Ok(t)
            None => Err("表达式符号「\{name}」未登记为顶层 Store")
          }
        _ => Err("表达式：.get() 只能接状态名")
      }
    NToStr(a) => {
      let _ = need(etype_of(a, syms))
      Ok(TStr)
    }
    NNot(a) =>
      match need(etype_of(a, syms)) {
        TBool => Ok(TBool)
        _ => Err("表达式：! 需要 Bool")
      }
    NNeg(a) =>
      match need(etype_of(a, syms)) {
        TInt | TDouble => etype_of(a, syms)
        _ => Err("表达式：- 需要数值")
      }
    NBin(op, l, r) => {
      let lt = need(etype_of(l, syms))
      let rt = need(etype_of(r, syms))
      match op {
        "+" =>
          match (lt, rt) {
            (TInt, TInt) | (TDouble, TDouble) | (TStr, TStr) => Ok(lt)
            _ => Err("表达式：+ 两侧类型不一致")
          }
        "-" | "*" | "/" =>
          match (lt, rt) {
            (TInt, TInt) | (TDouble, TDouble) => Ok(lt)
            _ => Err("表达式：算术需要同类型数值")
          }
        "%" =>
          match (lt, rt) {
            (TInt, TInt) => Ok(TInt)
            _ => Err("表达式：% 只收 Int")
          }
        "==" | "!=" =>
          if etype_eq(lt, rt) {
            Ok(TBool)
          } else {
            Err("表达式：比较两侧类型不一致")
          }
        "<" | "<=" | ">" | ">=" =>
          match (lt, rt) {
            (TInt, TInt) | (TDouble, TDouble) => Ok(TBool)
            _ => Err("表达式：大小比较需要同类型数值")
          }
        "&&" | "||" =>
          match (lt, rt) {
            (TBool, TBool) => Ok(TBool)
            _ => Err("表达式：逻辑运算需要 Bool")
          }
        _ => Err("表达式：未知运算符 " + op)
      }
    }
    NIf(c, t, f) => {
      match need(etype_of(c, syms)) {
        TBool => ()
        _ => return Err("表达式：if 条件需要 Bool")
      }
      let tt = need(etype_of(t, syms))
      let ft = need(etype_of(f, syms))
      if etype_eq(tt, ft) {
        Ok(tt)
      } else {
        Err("表达式：if 两分支类型不一致")
      }
    }
    NCall(name, args) => {
      let tys : Array[EType] = []
      for a in args {
        tys.push(need(etype_of(a, syms)))
      }
      match name {
        "@shared.tx" =>
          if tys.length() == 1 && etype_eq(tys[0], TStr) {
            Ok(TStr)
          } else {
            Err("表达式：@shared.tx 需要 1 个字符串")
          }
        "@shared.tr" =>
          if tys.length() == 2 &&
            etype_eq(tys[0], TStr) &&
            etype_eq(tys[1], TStr) {
            Ok(TStr)
          } else {
            Err("表达式：@shared.tr 需要 2 个字符串")
          }
        _ => Err("表达式：函数 \{name} 不在热更白名单")
      }
    }
  }
}

///|
fn enode_json(n : ENode) -> String {
  match n {
    NInt(v) => "{\"k\":\"int\",\"v\":" + v.to_string() + "}"
    NDouble(v) => "{\"k\":\"dbl\",\"v\":" + v.to_string() + "}"
    NBool(v) =>
      "{\"k\":\"bool\",\"v\":" + (if v { "true" } else { "false" }) + "}"
    NStr(v) => "{\"k\":\"str\",\"v\":\"" + jstr(v) + "\"}"
    NId(v) => "{\"k\":\"id\",\"v\":\"" + jstr(v) + "\"}"
    NGet(a) => "{\"k\":\"get\",\"a\":" + enode_json(a) + "}"
    NToStr(a) => "{\"k\":\"tostr\",\"a\":" + enode_json(a) + "}"
    NNot(a) => "{\"k\":\"not\",\"a\":" + enode_json(a) + "}"
    NNeg(a) => "{\"k\":\"neg\",\"a\":" + enode_json(a) + "}"
    NBin(op, l, r) =>
      "{\"k\":\"bin\",\"op\":\"" +
      jstr(op) +
      "\",\"l\":" +
      enode_json(l) +
      ",\"r\":" +
      enode_json(r) +
      "}"
    NIf(c, t, f) =>
      "{\"k\":\"if\",\"c\":" +
      enode_json(c) +
      ",\"t\":" +
      enode_json(t) +
      ",\"f\":" +
      enode_json(f) +
      "}"
    NCall(name, args) => {
      let xs : Array[String] = []
      for a in args {
        xs.push(enode_json(a))
      }
      "{\"k\":\"call\",\"f\":\"" +
      jstr(name) +
      "\",\"a\":[" +
      xs.join(",") +
      "]}"
    }
  }
}

///|
/// 表达式文本 → AST JSON；文法/类型不过就报原因（调用方转 COLD）。
/// `want` = "t" 表示文本槽（结果 String），"c" 表示条件槽（结果 Bool）。
fn parse_eval_expr(
  expr : String,
  syms : Map[String, EType],
  want : String,
) -> Result[String, String] {
  try {
    let p = ep_new(expr)
    let n = need(parse_expr(p))
    if !ep_eof(p) {
      Err("表达式：尾部还有未解析内容")
    } else {
      let t = need(etype_of(n, syms))
      if want == "c" {
        match t {
          TBool => Ok(enode_json(n))
          _ => Err("表达式：条件槽需要 Bool")
        }
      } else {
        match t {
          TStr => Ok(enode_json(n))
          _ => Err("表达式：文本槽需要 String")
        }
      }
    }
  } catch {
    ExprRaise(e) => Err(e)
  }
}
