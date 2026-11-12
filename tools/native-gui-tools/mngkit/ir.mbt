// IR 输出：模板编译器第二产物（dev 档热更新供给端）。结构是数据、行为按
// 键引用——结构补丁经单实例通道进应用，applier 查注册表原位重建。
// v1 边界：参数值三态（lit 字面量 / expr 动态串槽 / state 值槽目标）；动态
// 槽键用表达式内容哈希（t:<hash> / c:<hash>），结构增删挪不换键；节点可带
// class 名，补丁另带 classes（类定义数据）与 eval（新表达式 AST）；生成器
// 未覆盖的组件、applier v1 参数表外的参数与不支持槽型进 IR 即报（应用侧转 COLD）。

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
    Dyn => IExpr(bind_key("t", a.value.trim().to_owned()))
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
  ICol(Double, Array[IrNode], Array[String])
  IRow(Double, Array[IrNode], Array[String])
  IText(String) // 纯文本子节点
  IDynText(String) // 纯文本插值
  ITextEl(String, Array[String]) // <ui-text> 静态
  IDynTextEl(String, Array[String]) // <ui-text> 动态
  IIf(String, IrNode, IrNode)
  IComp(String, Array[(String, IrVal)], String?, Array[String]) // tag, 参数, click, class
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
        out.push(IDynText(bind_key("t", norm)))
      } else {
        out.push(IText(norm))
      }
      Ok(())
    }
    Elem(tag, attrs, children, pos) => {
      let mut show : Attr? = None
      let mut cond : Attr? = None
      let classes : Array[String] = []
      for a in attrs {
        match a.kind {
          Show => show = Some(a)
          If => cond = Some(a)
          For =>
            return Err(
              "\{pos_str(pos)}：v-for 不在 v1 补丁边界（应用侧转 COLD）",
            )
          Plain =>
            if a.name == "class" {
              for n in class_names_of(a.value) {
                classes.push(n)
              }
            }
          Dyn =>
            if a.name == "class" {
              return Err(
                "\{pos_str(a.pos)}：动态 class 不在 v1 补丁边界（应用侧转 COLD）",
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
      let cond_attr = match cond {
        Some(a) => Some(a)
        None => show
      }
      let cond_key = match cond_attr {
        Some(a) => bind_key("c", a.value.trim().to_owned())
        None => ""
      }
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
              } else if a.name != "class" {
                return Err(
                  "\{pos_str(a.pos)}：<\{tag}> 的参数 \{a.name} 不在 v1 补丁表（应用侧转 COLD）",
                )
              }
            Dyn =>
              return Err(
                "\{pos_str(a.pos)}：<\{tag}> 的动态参数 \{a.name} 不在 v1 补丁表（应用侧转 COLD）",
              )
            Event | Model =>
              return Err(
                "\{pos_str(a.pos)}：<\{tag}> 的事件/绑定不在 v1 补丁表（应用侧转 COLD）",
              )
            _ => ()
          }
        }
        if tag == "ui-col" {
          ICol(gap, kids, classes)
        } else {
          IRow(gap, kids, classes)
        }
      } else if tag == "ui-text" {
        // 文本内容：:text 动态 → expr 槽；静态 → 字面
        for a in attrs {
          match a.kind {
            Plain | Dyn =>
              if a.name != "text" && a.name != "class" {
                return Err(
                  "\{pos_str(a.pos)}：<ui-text> 的参数 \{a.name} 不在 v1 补丁表（应用侧转 COLD）",
                )
              }
            Event | Model =>
              return Err(
                "\{pos_str(a.pos)}：<ui-text> 的事件/绑定不在 v1 补丁表（应用侧转 COLD）",
              )
            _ => ()
          }
        }
        let mut found : Attr? = None
        for a in attrs {
          match a.kind {
            Dyn | Plain => if a.name == "text" { found = Some(a) }
            _ => ()
          }
        }
        match found {
          Some(a) =>
            match a.kind {
              Dyn =>
                IDynTextEl(bind_key("t", a.value.trim().to_owned()), classes)
              _ => ITextEl(text_of_lit(a), classes)
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
              return Err(
                "\{pos_str(pos)}：<ui-text> 的 text 混入子元素（v1 边界）",
              )
            }
        }
      } else {
        // 通用组件：位置参数 + 其余标签参数平铺；只收 applier v1 参数表
        let decl = match resolve_comp(tag, pos) {
          Ok(d) => d
          Err(e) => return Err(e)
        }
        if !hot_comp_tag(tag) {
          return Err(
            "\{pos_str(pos)}：组件 <\{tag}> 不在 v1 补丁表（应用侧转 COLD）",
          )
        }
        let args : Array[(String, IrVal)] = []
        for spec in decl.positional {
          match spec {
            "children" =>
              if kids.length() > 0 {
                return Err(
                  "\{pos_str(pos)}：组件 <\{tag}> 的 children 不在 v1 补丁边界（应用侧转 COLD）",
                )
              }
            "child" =>
              if kids.length() > 0 {
                return Err(
                  "\{pos_str(pos)}：组件 <\{tag}> 的 child 不在 v1 补丁边界（应用侧转 COLD）",
                )
              }
            "text" => {
              let mut found : Attr? = None
              for a in attrs {
                match a.kind {
                  Dyn | Plain => if a.name == "text" { found = Some(a) }
                  _ => ()
                }
              }
              match found {
                Some(a) => args.push(("text", ir_val_of(a)))
                None => {
                  // 元素文本内容：动态→expr 槽，静态→lit
                  let mut raw = ""
                  let mut bad = false
                  for c in children {
                    match c {
                      Text(x, _) => raw = raw + x
                      _ => bad = true
                    }
                  }
                  if bad {
                    return Err(
                      "\{pos_str(pos)}：<\{tag}> 的 text 混入子元素（v1 边界）",
                    )
                  }
                  let raw = normalize_text(raw)
                  if has_interp(raw) {
                    args.push(("text", IExpr(bind_key("t", raw))))
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
                    if a.name == spec || (a.kind is Model && spec == "value") {
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
        // 位置参之外的标签参数（max / min / placeholder …）
        for a in attrs {
          match a.kind {
            Plain | Dyn =>
              if a.name == "class" {
                ()
              } else if !hot_comp_arg(tag, a.name) {
                return Err(
                  "\{pos_str(a.pos)}：<\{tag}> 的参数 \{a.name} 不在 v1 补丁表（应用侧转 COLD）",
                )
              } else if args_has(args, a.name) {
                ()
              } else if a.kind is Dyn && !hot_comp_dyn_arg(tag, a.name) {
                return Err(
                  "\{pos_str(a.pos)}：<\{tag}> 的动态参数 \{a.name} 不在 v1 补丁表（应用侧转 COLD）",
                )
              } else {
                args.push((a.name, ir_val_of(a)))
              }
            Model => ()
            Event => ()
            _ => ()
          }
        }
        // 事件：v1 只认 button 的 click
        let mut click2 : String? = None
        for a in attrs {
          match a.kind {
            Event =>
              if tag == "ui-button" && a.name == "click" {
                click2 = Some(a.value.trim().to_owned())
              } else {
                return Err(
                  "\{pos_str(a.pos)}：<\{tag}> 的事件 @\{a.name} 不在 v1 补丁表（应用侧转 COLD）",
                )
              }
            _ => ()
          }
        }
        IComp(tag, args, click2, classes)
      }
      // v-show / v-if 包裹
      match cond_attr {
        Some(_) => out.push(IIf(cond_key, built, IText("")))
        None => out.push(built)
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
    Err(
      "\{pos_str(pos)}：自定义组件 <\{tag}> 不在 v1 补丁边界（应用侧转 COLD）",
    )
  }
}

///|
/// applier v1 表内的通用组件（col/row/text 另走专用分支）。
fn hot_comp_tag(tag : String) -> Bool {
  match tag {
    "ui-button" | "ui-checkbox" | "ui-switch" | "ui-stepper" | "ui-input" =>
      true
    _ => false
  }
}

///|
/// 各组件 v1 只认的参数名；表外参数一律转 COLD，避免补丁静默丢参。
fn hot_comp_arg(tag : String, name : String) -> Bool {
  match tag {
    "ui-button" =>
      match name {
        "text" => true
        _ => false
      }
    "ui-checkbox" =>
      match name {
        "label" | "value" => true
        _ => false
      }
    "ui-switch" =>
      match name {
        "value" => true
        _ => false
      }
    "ui-stepper" =>
      match name {
        "value" | "min" | "max" => true
        _ => false
      }
    "ui-input" =>
      match name {
        "value" | "placeholder" => true
        _ => false
      }
    _ => false
  }
}

///|
/// 动态参数只收 applier 能按表达式重取的：button 文本、checkbox 标签、
/// input 占位符（数值参数 min/max 只收字面量）。
fn hot_comp_dyn_arg(tag : String, name : String) -> Bool {
  match tag {
    "ui-button" =>
      match name {
        "text" => true
        _ => false
      }
    "ui-checkbox" =>
      match name {
        "label" => true
        _ => false
      }
    "ui-input" =>
      match name {
        "placeholder" => true
        _ => false
      }
    _ => false
  }
}

///|
fn args_has(args : Array[(String, IrVal)], name : String) -> Bool {
  let mut i = 0
  while i < args.length() {
    if args[i].0 == name {
      return true
    }
    i += 1
  }
  false
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
              return Err(
                "\{pos_str(pos)}：v-else-if 链不在 v1 补丁边界（应用侧转 COLD）",
              )
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
                    ICol(0.0, alt, [])
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
/// IR 协议代次（工具 ↔ applier 握手）：补丁带 `rev`，应用侧对不上即回 `stale`，
/// 工具据此走 COLD 重启回原页。加字段 / 换键语义时与 applier 同批 +1。
pub const IR_REV : String = "mng-ir-1"

///|
/// 键集摘要：排序后逐键喂双种子哈希（键间喂一个换行码），与 applier 侧
/// `mng_keys_digest` 逐字同算法——两侧不一致就永远判 stale。
fn ir_keys_digest(keys : Array[String]) -> String {
  let ks = keys.copy()
  ks.sort()
  let mut h1 = 5381
  let mut h2 = 52711
  for s in ks {
    h1 = ((h1 << 5) + h1 + 10) & 0x7FFF_FFFF
    h2 = ((h2 << 5) + h2 + 10) & 0x7FFF_FFFF
    for c in s.to_array() {
      h1 = ((h1 << 5) + h1 + c.to_int()) & 0x7FFF_FFFF
      h2 = ((h2 << 5) + h2 + c.to_int()) & 0x7FFF_FFFF
    }
  }
  hotkey_hex8(h1) + hotkey_hex8(h2)
}

///|
/// JSON 组装（应用侧 vsc_json_parse 读回）。exprs 收集动态槽键，states 收集
/// v-model 目标——应用侧注册表按清单登记，缺项由 applier 报错。
pub fn ir_of_with(
  src : String,
  filename : String,
  evals : Map[String, String],
  classes : String,
) -> Result[String, String] {
  let sfc = match parse_sfc(src) {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  if sfc.roots.length() != 1 {
    return Err(
      "\{filename}：模板必须单根（v1），现 \{sfc.roots.length()} 个顶层节点",
    )
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
    ICol(0.0, seq, [])
  }
  let exprs : Array[String] = []
  let states : Array[String] = []
  let handlers : Array[String] = []
  fn walk(nd : IrNode) -> Unit {
    match nd {
      IDynText(k) | IDynTextEl(k, _) => exprs.push(k)
      IIf(c, t, f) => {
        if c.length() > 0 {
          exprs.push(c)
        }
        walk(t)
        walk(f)
      }
      IComp(_, args, click, _) => {
        for a in args {
          match a.1 {
            IExpr(k) => exprs.push(k)
            IState(s) => states.push(s)
            _ => ()
          }
        }
        match click {
          Some(h) => if !arr_contains(handlers, h) { handlers.push(h) }
          None => ()
        }
      }
      ICol(_, kids, _) | IRow(_, kids, _) =>
        for k in kids {
          walk(k)
        }
      _ => ()
    }
  }

  walk(root)
  let stem = collect_stem(filename)
  // 握手用键集：requires（exprs ∪ states ∪ handlers）减去补丁自带 eval 键
  let need_keys : Array[String] = []
  for e in exprs {
    need_keys.push(e)
  }
  for st in states {
    need_keys.push(st)
  }
  for h in handlers {
    need_keys.push(h)
  }
  let parts : Array[String] = []
  parts.push("\"v\":1")
  parts.push("\"rev\":\"" + jstr(IR_REV) + "\"")
  parts.push("\"keys_digest\":\"" + ir_keys_digest(need_keys) + "\"")
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
  let ev : Array[String] = []
  for (k, j) in evals {
    ev.push("\"" + jstr(k) + "\":" + j)
  }
  parts.push("\"eval\":{" + ev.join(",") + "}")
  parts.push("\"classes\":" + classes)
  Ok("{" + parts.join(",") + "}\n")
}

///|
pub fn ir_of(src : String, filename : String) -> Result[String, String] {
  ir_of_with(src, filename, Map([]), "[]")
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
fn ir_class_json(names : Array[String]) -> String {
  if names.length() == 0 {
    return ""
  }
  let xs : Array[String] = []
  for n in names {
    xs.push("\"" + jstr(n) + "\"")
  }
  ",\"class\":[" + xs.join(",") + "]"
}

///|
fn ir_node_json(nd : IrNode) -> String {
  match nd {
    IText(s) => "{\"k\":\"text\",\"v\":\"" + jstr(s) + "\"}"
    ITextEl(s, cls) =>
      "{\"k\":\"text\",\"v\":\"" + jstr(s) + "\"" + ir_class_json(cls) + "}"
    IDynText(k) => "{\"k\":\"dyn\",\"key\":\"" + jstr(k) + "\"}"
    IDynTextEl(k, cls) =>
      "{\"k\":\"dyn\",\"key\":\"" + jstr(k) + "\"" + ir_class_json(cls) + "}"
    IIf(c, t, f) =>
      "{\"k\":\"if\",\"c\":\"" +
      jstr(c) +
      "\",\"t\":" +
      ir_node_json(t) +
      ",\"f\":" +
      ir_node_json(f) +
      "}"
    ICol(gap, kids, cls) =>
      "{\"k\":\"col\",\"gap\":\{gap},\"kids\":[" +
      ir_kids_json(kids) +
      "]" +
      ir_class_json(cls) +
      "}"
    IRow(gap, kids, cls) =>
      "{\"k\":\"row\",\"gap\":\{gap},\"kids\":[" +
      ir_kids_json(kids) +
      "]" +
      ir_class_json(cls) +
      "}"
    IComp(tag, args, click, cls) => {
      let parts : Array[String] = []
      let short = if tag.has_prefix("ui-") { tag[3:].to_owned() } else { tag }
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
      if cls.length() > 0 {
        let xs : Array[String] = []
        for n in cls {
          xs.push("\"" + jstr(n) + "\"")
        }
        parts.push("\"class\":[" + xs.join(",") + "]")
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
