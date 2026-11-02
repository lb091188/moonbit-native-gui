// IR 输出：模板编译器第二产物（dev 档热更新供给端）。结构是数据、行为按
// 键引用——结构补丁经单实例通道进应用，applier 查注册表原位重建。
// v1 边界：参数值三态（lit 字面量 / expr 动态串槽 / state 值槽目标）；动态
// 槽键用模板坐标（t:行:列 / c:行:列），应用侧手写注册表按坐标登记；
// 生成器未覆盖的组件与不支持槽型进 IR 即报（应用侧转 COLD）。

///|
priv enum IrVal {
  ILitStr(String)
  ILitNum(String)
  ILitBool(String)
  IExpr(String)
  IState(String)
}

///|
fn ir_val_of(a : Attr) -> IrVal {
  match a.kind {
    Model => IState(a.value.trim().to_owned())
    Dyn => IExpr("t:\{a.pos.line}:\{a.pos.col}")
    _ => {
      // 静态：数字 / 布尔 / 字符串字面量（单引号=MoonBit 串，双引号=串）/ 裸串
      let v = a.value.trim().to_owned()
      let cs = chars_of(v)
      let n = cs.length()
      if n >= 2 && cs[0] == '\'' && cs[n - 1] == '\'' {
        ILitStr(v[1:n - 1].to_owned())
      } else if n >= 2 && cs[0] == '"' && cs[n - 1] == '"' {
        ILitStr(v[1:n - 1].to_owned())
      } else if v == "true" || v == "false" {
        ILitBool(v)
      } else {
        let mut digits = 0
        let mut dots = 0
        let mut num = n > 0
        let mut i = if n > 0 && cs[0] == '-' { 1 } else { 0 }
        while i < n {
          let c = cs[i]
          if is_digit(c) {
            digits += 1
          } else if c == '.' {
            dots += 1
          } else {
            num = false
          }
          i += 1
        }
        if num && digits > 0 && dots <= 1 {
          ILitNum(v)
        } else {
          ILitStr(v)
        }
      }
    }
  }
}

///|
fn ir_val_json(v : IrVal) -> String {
  match v {
    ILitStr(s) => "{\"lit\":\"" + jstr(s) + "\"}"
    ILitNum(x) => "{\"lit\":" + x + "}"
    ILitBool(b) => "{\"lit\":\"" + b + "\"}"
    IExpr(e) => "{\"expr\":\"" + jstr(e) + "\"}"
    IState(s) => "{\"state\":\"" + jstr(s) + "\"}"
  }
}

///|
priv enum IrNode {
  ICol(Double, Array[IrNode])
  IRow(Double, Array[IrNode])
  IText(String)
  IDynText(String)
  IIf(String, IrNode, IrNode)
  IComp(String, Array[(String, IrVal)], String?) // tag, (参数名, 值), click handler
}

///|
/// 极简 JSON 字符串转义（IR 输出用；应用侧 vsc_json_parse 读回）。
fn jstr(s : String) -> String {
  let out : Array[String] = []
  for c in s {
    if c == '"' {
      out.push("\\\"")
    } else if c == '\\' {
      out.push("\\\\")
    } else if c == '\n' {
      out.push("\\n")
    } else if c == '\t' {
      out.push("\\t")
    } else if c == '\r' {
      out.push("\\r")
    } else {
      out.push(c.to_string())
    }
  }
  out.join("")
}

///|
/// 模板树 → IR 节点。返回 Err 即该节点超出 v1 补丁边界（应用侧转 COLD）。
fn ir_of_node(node : TNode, out : Array[IrNode]) -> Result[Unit, String] {
  match node {
    Text(raw, pos) => {
      let norm = normalize_text(raw)
      if norm.length() == 0 {
        return Ok(())
      }
      let pieces = match split_interp(norm, pos) {
        Ok(p) => p
        Err(e) => return Err(e)
      }
      let mut has_expr = false
      for p in pieces {
        match p {
          PExpr(_) => has_expr = true
          _ => ()
        }
      }
      if has_expr {
        out.push(IDynText("t:\{pos.line}:\{pos.col}"))
      } else {
        out.push(IText(norm))
      }
      Ok(())
    }
    Elem(tag, attrs, children, pos) => {
      let mut show : Attr? = None
      let mut cond : String? = None
      for a in attrs {
        match a.kind {
          Show => show = Some(a)
          If => cond = Some(a.value)
          For =>
            return Err("\{pos_str(pos)}：v-for 不在 v1 补丁边界（应用侧转 COLD）")
          Plain | Dyn =>
            if a.name == "class" {
              return Err(
                "\{pos_str(a.pos)}：class 不在 v1 补丁边界（应用侧转 COLD）",
              )
            }
          _ => ()
        }
      }
      // 递归子节点（含 v-else 回填）
      let kids : Array[IrNode] = []
      match ir_seq(children, kids) {
        Ok(_) => ()
        Err(e) => return Err(e)
      }
      let cond_key = "c:\{pos.line}:\{pos.col}"
      let built : IrNode = if tag == "ui-col" || tag == "ui-row" {
        let mut gap = 0.0
        for a in attrs {
          match a.kind {
            Plain =>
              if a.name == "row_gap" || a.name == "column_gap" {
                match ir_val_of(a) {
                  ILitNum(x) => gap = parse_double(x)
                  _ => ()
                }
              }
            _ => ()
          }
        }
        if tag == "ui-col" {
          ICol(gap, kids)
        } else {
          IRow(gap, kids)
        }
      } else if tag == "ui-text" {
        // 文本内容：:text 动态 → expr 槽；静态 → 字面
        let mut found : Attr? = None
        for a in attrs {
          match a.kind {
            Dyn | Plain =>
              if a.name == "text" {
                found = Some(a)
              }
            _ => ()
          }
        }
        match found {
          Some(a) =>
            match a.kind {
              Dyn => IDynText("t:\{pos.line}:\{pos.col}")
              _ => IText(text_of_lit(a))
            }
          None =>
            if kids.length() == 1 {
              match kids[0] {
                IText(s) => IText(s)
                IDynText(k) => IDynText(k)
                _ => IText("")
              }
            } else if kids.length() == 0 {
              IText("")
            } else {
              return Err("\{pos_str(pos)}：<ui-text> 的 text 混入子元素（v1 边界）")
            }
        }
      } else {
        // 通用组件：位置/标签参数平铺（positional spec 展开成参数名对）
        let decl = match resolve_comp(tag, pos) {
          Ok(d) => d
          Err(e) => return Err(e)
        }
        let args : Array[(String, IrVal)] = []
        let click : String? = None
        for spec in decl.positional {
          match spec {
            "children" =>
              if kids.length() > 0 {
                return Err("\{pos_str(pos)}：组件 <\{tag}> 的 children 不在 v1 补丁边界（应用侧转 COLD）")
              }
            "child" =>
              if kids.length() > 0 {
                return Err("\{pos_str(pos)}：组件 <\{tag}> 的 child 不在 v1 补丁边界（应用侧转 COLD）")
              }
            "text" => {
              let mut found : Attr? = None
              for a in attrs {
                match a.kind {
                  Dyn | Plain =>
                    if a.name == "text" {
                      found = Some(a)
                    }
                  _ => ()
                }
              }
              match found {
                Some(a) => args.push(("text", ir_val_of(a)))
                None => {
                  // 元素文本内容：动态→expr 槽，静态→lit
                  let mut raw = ""
                  let mut tpos = pos
                  let mut bad = false
                  for c in children {
                    match c {
                      Text(x, q) => {
                        raw = raw + x
                        tpos = q
                      }
                      _ => bad = true
                    }
                  }
                  if bad {
                    return Err("\{pos_str(pos)}：<\{tag}> 的 text 混入子元素（v1 边界）")
                  }
                  let raw = normalize_text(raw)
                  if has_interp(raw) {
                    args.push(("text", IExpr("t:\{tpos.line}:\{tpos.col}")))
                  } else if raw.length() > 0 {
                    args.push(("text", ILitStr(raw)))
                  }
                }
              }
            }
            _ => {
              // 按 spec 找参数
              let mut found : Attr? = None
              for a in attrs {
                match a.kind {
                  Dyn | Plain | Model =>
                    if (a.name == spec) || (a.kind is Model && spec == "value") {
                      found = Some(a)
                    }
                  _ => ()
                }
              }
              match found {
                Some(a) => args.push((spec, ir_val_of(a)))
                None => ()
              }
            }
          }
        }
        let mut click2 : String? = None
        for a in attrs {
          match a.kind {
            Event =>
              if a.name == "click" {
                click2 = Some(a.value.trim().to_owned())
              }
            _ => ()
          }
        }
        let _ = click
        IComp(tag, args, click2)
      }
      // v-show / v-if 包裹
      match show {
        Some(_) =>
          match built {
            IText(s) =>
              // 静态文本 + v-show → 直接丢给 if 包裹（条件动态）
              match cond {
                Some(_) => out.push(IIf(cond_key, IText(s), IText("")))
                None => out.push(IText(s))
              }
            _ =>
              match cond {
                Some(_) =>
                  out.push(IIf(cond_key, built, IText("")))
                None => out.push(built)
              }
          }
        None =>
          match cond {
            Some(_) => out.push(IIf(cond_key, built, IText("")))
            None => out.push(built)
          }
      }
      Ok(())
    }
  }
}

///|
fn text_of_lit(a : Attr) -> String {
  match ir_val_of(a) {
    ILitStr(s) => s
    _ => a.value.trim().to_owned()
  }
}

///|
///|
/// 手写定点的 double 解析（IR 里的字面量数字；格式在 ir_val_of 已验证）。
fn parse_double(s : String) -> Double {
  let cs = chars_of(s)
  let mut neg = false
  let mut i = 0
  if i < cs.length() && cs[i] == '-' {
    neg = true
    i += 1
  }
  let mut int_part = 0.0
  while i < cs.length() && is_digit(cs[i]) {
    int_part = int_part * 10.0 + (cs[i].to_int() - '0'.to_int()).to_double()
    i += 1
  }
  let mut frac = 0.0
  let mut scale = 0.1
  if i < cs.length() && cs[i] == '.' {
    i += 1
    while i < cs.length() && is_digit(cs[i]) {
      frac += (cs[i].to_int() - '0'.to_int()).to_double() * scale
      scale = scale * 0.1
      i += 1
    }
  }
  let v = int_part + frac
  if neg {
    -v
  } else {
    v
  }
}

///|
fn resolve_comp(tag : String, pos : Pos) -> Result[CompDecl, String] {
  if tag.has_prefix("ui-") {
    match builtin_decl(tag) {
      Some(d) => Ok(d)
      None => Err("\{pos_str(pos)}：组件 <\{tag}> 未登记内置表")
    }
  } else {
    // let 绑定组件在补丁里按黑盒处理（v1 不跨补丁重建自定义组件）
    Err("\{pos_str(pos)}：自定义组件 <\{tag}> 不在 v1 补丁边界（应用侧转 COLD）")
  }
}

///|
/// 兄弟序列 → IR：逐节点转换 + v-else 回填最近未填的 IIf；v-else-if 报边界。
fn ir_seq(nodes : Array[TNode], out : Array[IrNode]) -> Result[Unit, String] {
  for node in nodes {
    match node {
      Elem(_, attrs, _, pos) => {
        let mut has_else = false
        for a in attrs {
          match a.kind {
            Else => has_else = true
            ElseIf =>
              return Err("\{pos_str(pos)}：v-else-if 链不在 v1 补丁边界（应用侧转 COLD）")
            _ => ()
          }
        }
        if has_else {
          let mut done = false
          let mut k = out.length()
          while k > 0 {
            match out[k - 1] {
              IIf(c, t, IText(s2)) =>
                if s2 == "" {
                  let _ = out.remove(k - 1)
                  let alt : Array[IrNode] = []
                  match ir_of_node(node, alt) {
                    Ok(_) => ()
                    Err(e) => return Err(e)
                  }
                  let f = if alt.length() == 1 {
                    alt[0]
                  } else if alt.length() == 0 {
                    IText("")
                  } else {
                    ICol(0.0, alt)
                  }
                  out.push(IIf(c, t, f))
                  done = true
                  break
                }
              _ => ()
            }
            k -= 1
          }
          if !done {
            return Err("\{pos_str(pos)}：孤儿 v-else")
          }
        } else {
          match ir_of_node(node, out) {
            Ok(_) => ()
            Err(e) => return Err(e)
          }
        }
      }
      Text(_, _) =>
        match ir_of_node(node, out) {
          Ok(_) => ()
          Err(e) => return Err(e)
        }
    }
  }
  Ok(())
}

///|
/// JSON 组装（应用侧 vsc_json_parse 读回）。exprs 收集动态槽键，states 收集
/// v-model 目标——应用侧注册表按清单登记，缺项由 applier 报错。
pub fn ir_of(src : String, filename : String) -> Result[String, String] {
  let sfc = match parse_sfc(src) {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  if sfc.roots.length() != 1 {
    return Err("\{filename}：模板必须单根（v1），现 \{sfc.roots.length()} 个顶层节点")
  }
  let seq : Array[IrNode] = []
  match ir_seq(sfc.roots, seq) {
    Ok(_) => ()
    Err(e) => return Err(e)
  }
  let root = if seq.length() == 1 {
    seq[0]
  } else if seq.length() == 0 {
    IText("")
  } else {
    ICol(0.0, seq)
  }
  let exprs : Array[String] = []
  let states : Array[String] = []
  let handlers : Array[String] = []
  fn walk(nd : IrNode) -> Unit {
    match nd {
      IDynText(k) => exprs.push(k)
      IIf(c, t, f) => {
        if c.length() > 0 {
          exprs.push(c)
        }
        walk(t)
        walk(f)
      }
      IComp(_, args, click) => {
        for a in args {
          match a.1 {
            IExpr(k) => exprs.push(k)
            IState(s) => states.push(s)
            _ => ()
          }
        }
        match click {
          Some(h) =>
            if !arr_contains(handlers, h) {
              handlers.push(h)
            }
          None => ()
        }
      }
      ICol(_, kids) | IRow(_, kids) =>
        for k in kids {
          walk(k)
        }
      _ => ()
    }
  }

  walk(root)
  let stem = collect_stem(filename)
  let parts : Array[String] = []
  parts.push("\"v\":1")
  parts.push("\"page\":\"" + jstr(stem) + "\"")
  parts.push("\"root\":" + ir_node_json(root))
  let ea : Array[String] = []
  for e in exprs {
    ea.push("\"" + jstr(e) + "\"")
  }
  parts.push("\"exprs\":[" + ea.join(",") + "]")
  let sa : Array[String] = []
  for st in states {
    sa.push("\"" + jstr(st) + "\"")
  }
  parts.push("\"states\":[" + sa.join(",") + "]")
  let ha : Array[String] = []
  for h in handlers {
    ha.push("\"" + jstr(h) + "\"")
  }
  parts.push("\"handlers\":[" + ha.join(",") + "]")
  Ok("{" + parts.join(",") + "}\n")
}

///|
fn collect_stem(filename : String) -> String {
  let a = chars_of(filename)
  let mut start = 0
  for k, c in a {
    if c == '/' {
      start = k + 1
    }
  }
  let base = a[start:].map(fn(c) { c.to_string() }).join("")
  let b = chars_of(base)
  let mut end = b.length()
  for k, c in b {
    if c == '.' {
      end = k
      break
    }
  }
  b[0:end].map(fn(c) { c.to_string() }).join("")
}

///|
fn ir_node_json(nd : IrNode) -> String {
  match nd {
    IText(s) => "{\"k\":\"text\",\"v\":\"" + jstr(s) + "\"}"
    IDynText(k) => "{\"k\":\"dyn\",\"key\":\"" + jstr(k) + "\"}"
    IIf(c, t, f) =>
      "{\"k\":\"if\",\"c\":\"" + jstr(c) + "\",\"t\":" + ir_node_json(t) +
        ",\"f\":" + ir_node_json(f) + "}"
    ICol(gap, kids) => "{\"k\":\"col\",\"gap\":\{gap},\"kids\":[" + ir_kids_json(kids) + "]}"
    IRow(gap, kids) => "{\"k\":\"row\",\"gap\":\{gap},\"kids\":[" + ir_kids_json(kids) + "]}"
    IComp(tag, args, click) => {
      let parts : Array[String] = []
      let short = if tag.has_prefix("ui-") {
        tag[3:].to_owned()
      } else {
        tag
      }
      parts.push("\"k\":\"" + jstr(short) + "\"")
      let aa : Array[String] = []
      for a in args {
        aa.push("\"" + jstr(a.0) + "\":" + ir_val_json(a.1))
      }
      parts.push("\"args\":{" + aa.join(",") + "}")
      match click {
        Some(h) => parts.push("\"click\":\"" + jstr(h) + "\"")
        None => ()
      }
      "{" + parts.join(",") + "}"
    }
  }
}

///|
fn ir_kids_json(kids : Array[IrNode]) -> String {
  let out : Array[String] = []
  for k in kids {
    out.push(ir_node_json(k))
  }
  out.join(",")
}
