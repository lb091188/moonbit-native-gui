// 代码生成器：模板树 → 生成函数体（script 原文 + 模板表达式），逐行携带
// 模板坐标产出 source map。生成行为契约见 proposals/native-template.md「Spike 契约」。

///|
priv struct Gen {
  lines : Array[String]
  map : Array[MapEntry]
  mut last : Pos
}

///|
fn g_emit(g : Gen, line : String, pos : Pos) -> Unit {
  let p = if pos.line == 0 {
    g.last
  } else {
    g.last = pos
    pos
  }
  g.lines.push(line)
  g.map.push({ gen_line: g.lines.length(), src_line: p.line, src_col: p.col })
}

///|
/// 内置组件表：ui-* 标签 → 调用路径 + 位置参数顺序。children=子元素数组、
/// child=单子元素、text=文本内容（:text 属性或元素文本）。
fn builtin_decl(tag : String) -> CompDecl? {
  match tag {
    "ui-text" => Some({ path: "@ui.text", positional: ["text"] })
    "ui-button" => Some({ path: "@ui.button", positional: ["text"] })
    "ui-input" => Some({ path: "@ui.input", positional: ["value"] })
    "ui-textarea" => Some({ path: "@ui.textarea", positional: ["value"] })
    "ui-stepper" => Some({ path: "@ui.stepper", positional: ["value"] })
    "ui-slider" => Some({ path: "@ui.slider", positional: ["value"] })
    "ui-rate" => Some({ path: "@ui.rate", positional: ["value"] })
    "ui-switch" => Some({ path: "@ui.switch", positional: ["value"] })
    "ui-checkbox" => Some({ path: "@ui.checkbox", positional: ["label", "value"] })
    "ui-radio-group" => Some({ path: "@ui.radio_group", positional: ["options", "value"] })
    "ui-select" => Some({ path: "@ui.select", positional: ["options", "value"] })
    "ui-form" => Some({ path: "@ui.form", positional: ["title", "children"] })
    "ui-form-item" => Some({ path: "@ui.form_item", positional: ["label", "child"] })
    "ui-col" => Some({ path: "@ui.col", positional: ["children"] })
    "ui-row" => Some({ path: "@ui.row", positional: ["children"] })
    "ui-view" => Some({ path: "@ui.view", positional: ["children"] })
    "ui-panel" => Some({ path: "@ui.panel", positional: ["title", "children"] })
    _ => None
  }
}

///|
priv struct Ctx {
  slots : Map[String, SlotKind]
  lets : Array[String]
  comps : Map[String, CompDecl]
}

///|
fn arr_contains(a : Array[String], s : String) -> Bool {
  for x in a {
    if x == s {
      return true
    }
  }
  false
}

///|
priv enum Piece {
  PLit(String)
  PExpr(String)
}

///|
/// 拆插值：`前缀{{ expr }}中缀` → [PLit, PExpr, PLit]；未闭合报错。
fn split_interp(raw : String, pos : Pos) -> Result[Array[Piece], String] {
  let a = chars_of(raw)
  let out : Array[Piece] = []
  let mut lit : Array[Char] = []
  let mut i = 0
  let n = a.length()
  while i < n {
    if i + 1 < n && a[i] == '{' && a[i + 1] == '{' {
      if lit.length() > 0 {
        out.push(PLit(lit.map(fn(c) { c.to_string() }).join("")))
        lit = []
      }
      let start = i + 2
      let mut j = start
      let mut closed = false
      while j + 1 < n {
        if a[j] == '}' && a[j + 1] == '}' {
          closed = true
          break
        }
        j += 1
      }
      if !closed {
        return Err("\{pos_str(pos)}：插值 {{ 未闭合")
      }
      out.push(PExpr(a[start:j].map(fn(c) { c.to_string() }).join("").trim().to_owned()))
      i = j + 2
    } else {
      lit.push(a[i])
      i += 1
    }
  }
  if lit.length() > 0 {
    out.push(PLit(lit.map(fn(c) { c.to_string() }).join("")))
  }
  Ok(out)
}

///|
/// 值语义表达式 → 字符串表达式 E（插值拼接 + 裸槽补 .get()）。
fn pieces_to_e(ctx : Ctx, pieces : Array[Piece]) -> String {
  let out : Array[String] = []
  for p in pieces {
    match p {
      PLit(s) => out.push(escape_mbt(s))
      PExpr(e) => out.push("\\{" + rewrite_value(e, ctx.slots) + "}")
    }
  }
  out.join("")
}

///|
/// 字符串字面量内容 → 完整字面量表达式。
fn q(content : String) -> String {
  "\"" + content + "\""
}

///|
/// 文本生成收口：按响应源数量选落点（0→text、1→bind_label/bind、多→computed+bind）。
fn finish_text(
  ctx : Ctx,
  e : String,
  srcs : Array[String],
  ind : Int,
  pos : Pos,
) -> Array[(String, Pos)] {
  let body = if srcs.length() == 0 {
    "@ui.text(" + e + ")"
  } else if srcs.length() == 1 {
    let id = srcs[0]
    let call = match ctx.slots.get(id) {
      Some(KSignal) => "@ui.bind"
      _ => "@ui.bind_label"
    }
    call + "(" + id + ", fn(_v) { " + e + " })"
  } else {
    "@ui.bind(@base.Signal::computed(fn() { " + e + " }), fn(s) { s })"
  }
  [(ind_str(ind) + body, pos)]
}

///|
/// 文本节点（含 {{ }}）→ 生成行。归一化先行：空白折叠、去首尾。
fn gen_text(ctx : Ctx, raw : String, pos : Pos, ind : Int) -> Result[Array[(String, Pos)], String] {
  let norm = normalize_text(raw)
  if norm.length() == 0 {
    return Ok([])
  }
  let pieces = match split_interp(norm, pos) {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let mut has_expr = false
  let srcs : Array[String] = []
  for p in pieces {
    match p {
      PExpr(e) => {
        has_expr = true
        for s in sources_of(e, ctx.slots) {
          if !arr_contains(srcs, s) {
            srcs.push(s)
          }
        }
      }
      _ => ()
    }
  }
  let e = q(
    if has_expr {
      pieces_to_e(ctx, pieces)
    } else {
      escape_mbt(norm)
    },
  )
  Ok(finish_text(ctx, e, srcs, ind, pos))
}

///|
/// :text 属性表达式（值语义）→ 生成行。
fn gen_text_expr(ctx : Ctx, expr : String, pos : Pos, ind : Int) -> Array[(String, Pos)] {
  let e = rewrite_value(expr, ctx.slots)
  finish_text(ctx, e, sources_of(expr, ctx.slots), ind, pos)
}

///|
/// 条件 → computed 信号表达式（值语义改写）。
fn cond_signal(ctx : Ctx, expr : String) -> String {
  "@base.Signal::computed(fn() { " + rewrite_value(expr, ctx.slots) + " })"
}

///|
/// v-if 链 → bind_node(computed(全链条件并集), if/else 链)。
/// branches: (条件?, 节点, 位置)，条件 None 即 v-else 收尾。
fn gen_chain(
  ctx : Ctx,
  branches : Array[(String?, TNode, Pos)],
  ind : Int,
) -> Result[Array[(String, Pos)], String] {
  let conds : Array[String] = []
  for b in branches {
    match b.0 {
      Some(c) => conds.push(c)
      None => ()
    }
  }
  if conds.length() == 0 {
    return Err("\{pos_str(branches[0].2)}：v-if 链缺少条件")
  }
  let union : Array[String] = []
  for c in conds {
    let rw = rewrite_value(c, ctx.slots)
    if !arr_contains(union, rw) {
      union.push(rw)
    }
  }
  let sig = "@base.Signal::computed(fn() { " + union.join(" || ") + " })"
  let out : Array[(String, Pos)] = []
  out.push((ind_str(ind) + "@widget.bind_node(" + sig + ", fn(_v) {", branches[0].2))
  for bi, b in branches {
    let (cond, node, pos) = b
    let head = match cond {
      Some(c) =>
        (if bi == 0 { "if " } else { "} else if " }) + rewrite_value(c, ctx.slots) + " {"
      None => "} else {"
    }
    out.push((ind_str(ind + 1) + head, pos))
    let body = match node {
      Elem(_, _, _, _) =>
        match gen_node(ctx, node, ind + 2) {
          Ok(v) => v
          Err(e) => return Err(e)
        }
      Text(raw, p) =>
        match gen_text(ctx, raw, p, ind + 2) {
          Ok(v) => v
          Err(e) => return Err(e)
        }
    }
    for l in body {
      out.push(l)
    }
  }
  if branches[branches.length() - 1].0 is Some(_) {
    out.push((ind_str(ind + 1) + "} else {", branches[0].2))
    out.push((ind_str(ind + 2) + "@ui.col([])", branches[0].2))
  }
  out.push((ind_str(ind + 1) + "}", branches[0].2))
  out.push((ind_str(ind) + "})", branches[0].2))
  Ok(out)
}

///|
/// 兄弟序列 → 表达式块列表（v-if 链合并为一个块；孤儿 v-else 报错）。
fn gen_blocks(
  ctx : Ctx,
  nodes : Array[TNode],
  ind : Int,
) -> Result[Array[Array[(String, Pos)]], String] {
  let out : Array[Array[(String, Pos)]] = []
  let mut i = 0
  let n = nodes.length()
  while i < n {
    let node = nodes[i]
    match node {
      Elem(tag, attrs, _, pos) => {
        let mut has_if = false
        let mut has_else = false
        for a in attrs {
          match a.kind {
            If => has_if = true
            ElseIf | Else => has_else = true
            For =>
              return Err("\{pos_str(a.pos)}：v-for 生成器 v1 收口未开放——列表先手写 ListStore keyed（gui/base/list_store.mbt）")
            _ => ()
          }
        }
        if has_if {
          let branches : Array[(String?, TNode, Pos)] = []
          let mut cond : String? = None
          for a in attrs {
            match a.kind {
              If => cond = Some(a.value)
              _ => ()
            }
          }
          branches.push((cond, node, pos))
          let mut j = i + 1
          while j < n {
            match nodes[j] {
              Elem(_, a2, _, p2) => {
                let mut kind2 : AttrKind = Plain
                let mut val2 = ""
                for a in a2 {
                  match a.kind {
                    ElseIf | Else | If => {
                      kind2 = a.kind
                      val2 = a.value
                    }
                    _ => ()
                  }
                }
                match kind2 {
                  ElseIf => {
                    branches.push((Some(val2), nodes[j], p2))
                    j += 1
                  }
                  Else => {
                    branches.push((None, nodes[j], p2))
                    j += 1
                    break
                  }
                  If =>
                    return Err("\{pos_str(p2)}：v-if 链中间不允许再起 v-if（应接 v-else-if）")
                  _ => break
                }
              }
              _ => break
            }
          }
          match gen_chain(ctx, branches, ind) {
            Ok(v) => out.push(v)
            Err(e) => return Err(e)
          }
          i = j
        } else {
          if has_else {
            return Err("\{pos_str(pos)}：v-else / v-else-if 需紧跟 v-if 链：<\{tag}>")
          }
          match gen_node(ctx, node, ind) {
            Ok(v) => out.push(v)
            Err(e) => return Err(e)
          }
          i += 1
        }
      }
      Text(raw, p) => {
        match gen_text(ctx, raw, p, ind) {
          Ok(v) => out.push(v)
          Err(e) => return Err(e)
        }
        i += 1
      }
    }
  }
  Ok(out)
}

///|
/// 节点 → 生成行（v-if 由 gen_blocks 消化；这里处理 v-show 包裹与其余）。
fn gen_node(
  ctx : Ctx,
  node : TNode,
  ind : Int,
) -> Result[Array[(String, Pos)], String] {
  match node {
    Text(raw, p) => gen_text(ctx, raw, p, ind)
    Elem(tag, attrs, children, p) => {
      let mut show : Attr? = None
      for a in attrs {
        match a.kind {
          Show => show = Some(a)
          // v-if / v-else-if / v-else 已被 gen_blocks 的链收集消化，到这里是正常残留
          If | ElseIf | Else => ()
          For =>
            return Err("\{pos_str(a.pos)}：v-for 生成器 v1 收口未开放——列表先手写 ListStore keyed（gui/base/list_store.mbt）")
          _ => ()
        }
      }
      let mut lines = match gen_elem_base(ctx, tag, attrs, children, p, ind) {
      Ok(v) => v
      Err(e) => return Err(e)
    }
      match show {
        Some(sa) => {
          if !sa.has_value {
            return Err("\{pos_str(sa.pos)}：v-show 需要表达式")
          }
          let sig = cond_signal(ctx, sa.value)
          lines = wrap_call("@ui.when_bool(" + sig + ", ", lines, ")", p, ind)
        }
        None => ()
      }
      Ok(lines)
    }
  }
}

///|
/// 前后缀包裹：首行接前缀、末行接后缀。
fn wrap_call(
  prefix : String,
  lines : Array[(String, Pos)],
  suffix : String,
  pos : Pos,
  ind : Int,
) -> Array[(String, Pos)] {
  let out : Array[(String, Pos)] = []
  for k, l in lines {
    let mut s = l.0
    if k == 0 {
      s = ind_str(ind) + prefix + s.trim().to_owned()
    }
    if k == lines.length() - 1 {
      s = s + suffix
    }
    out.push((s, if k == 0 { pos } else { l.1 }))
  }
  out
}

///|
/// 子元素数组部分：[ " [" ] + 各块（尾加逗号）+ [ " ]" ]；括号行用 0 哨兵位。
fn children_part(
  ctx : Ctx,
  children : Array[TNode],
  ind : Int,
) -> Result[Array[(String, Pos)], String] {
  let zero = { line: 0, col: 0 }
  let out : Array[(String, Pos)] = [("[", zero)]
  let blocks = match gen_blocks(ctx, children, ind + 1) {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  for b in blocks {
    let last = b.length() - 1
    b[last] = (b[last].0 + ",", b[last].1)
    for l in b {
      out.push(l)
    }
  }
  out.push((ind_str(ind) + "]", zero))
  Ok(out)
}

///|
/// 事件名 → 回调参数名；值必须是裸函数名。
fn event_labeled(a : Attr) -> Result[String, String] {
  let pname = match a.name {
    "click" => "on_click"
    "change" => "on_change"
    "enter" => "on_enter"
    other => return Err("\{pos_str(a.pos)}：@事件不支持「\{other}」（v1：click / change / enter）")
  }
  let v = a.value.trim().to_owned()
  let cs = chars_of(v)
  let mut ok = cs.length() > 0 && is_ident_start(cs[0])
  for c in cs {
    if !is_ident_char(c) {
      ok = false
    }
  }
  if !ok {
    return Err("\{pos_str(a.pos)}：@事件值需是 script 里的函数名")
  }
  Ok(pname + "=" + v)
}

///|
/// 元素本体 → 调用行（解析组件声明、填位置参数、拼标签参数）。
fn gen_elem_base(
  ctx : Ctx,
  tag : String,
  attrs : Array[Attr],
  children : Array[TNode],
  pos : Pos,
  ind : Int,
) -> Result[Array[(String, Pos)], String] {
  let decl : CompDecl = if tag.has_prefix("ui-") {
    match builtin_decl(tag) {
      Some(d) => d
      None =>
        return Err("\{pos_str(pos)}：组件 <\{tag}> 未登记内置表——用 script let 绑定 + // @mng 声明，或在 mngkit 登记新组件")
    }
  } else {
    let name = snake(tag)
    if !arr_contains(ctx.lets, name) {
      return Err("\{pos_str(pos)}：<\{tag}> 既不是 ui-* 组件，也不是 script 里的 let 绑定")
    }
    match ctx.comps.get(name) {
      Some(d) =>
        if d.path.has_prefix("@mng-error:") {
          return Err("\{pos_str(pos)}：\{d.path[11:].to_owned()}")
        } else {
          d
        }
      None =>
        return Err("\{pos_str(pos)}：组件 <\{tag}> 需要声明参数顺序——script 里加一行：// @mng <\{tag}> = <路径> positional(参数…)")
    }
  }
  let used2 : Array[Bool] = []
  for _a in attrs {
    used2.push(false)
  }
  let find_named = fn(spec : String) -> Attr? {
    for k, a in attrs {
      if used2[k] {
        continue
      }
      match a.kind {
        Dyn | Plain =>
          if a.name == spec {
            return Some(a)
          }
        _ => ()
      }
    }
    None
  }
  let mark_used = fn(a : Attr) -> Unit {
    for k, x in attrs {
      if x.pos.line == a.pos.line && x.pos.col == a.pos.col && x.name == a.name {
        used2[k] = true
      }
    }
  }
  let structural_only = fn() -> Bool {
    for k, a in attrs {
      if used2[k] {
        continue
      }
      match a.kind {
        Plain | Dyn | Event | Model => return false
        _ => ()
      }
    }
    true
  }
  // 动态 :text 整体替换：ui-text 的 :text 带响应源 → 直接出 bind 行
  if decl.path == "@ui.text" {
    for k, a in attrs {
      if a.kind is Dyn && a.name == "text" && sources_of(a.value, ctx.slots).length() > 0 {
        used2[k] = true
        if !structural_only() {
          return Err("\{pos_str(pos)}：动态 :text 暂不支持与其他属性同用（静态文本属性另写）")
        }
        return Ok(gen_text_expr(ctx, a.value, a.pos, ind))
      }
    }
  }
  let parts : Array[Array[(String, Pos)]] = []
  for spec in decl.positional {
    if spec == "children" {
      match children_part(ctx, children, ind) {
        Ok(v) => parts.push(v)
        Err(e) => return Err(e)
      }
    } else if spec == "child" {
      if children.length() != 1 {
        return Err("\{pos_str(pos)}：<\{tag}> 的 child 参数需要恰好一个子元素（现 \{children.length()}）")
      }
      match gen_node(ctx, children[0], ind + 1) {
        Ok(v) => {
          if v.length() > 0 {
            v[0] = (v[0].0.trim().to_owned(), v[0].1)
          }
          parts.push(v)
        }
        Err(e) => return Err(e)
      }
    } else if spec == "text" {
      let mut found : Attr? = None
      for k, a in attrs {
        if used2[k] {
          continue
        }
        match a.kind {
          Dyn | Plain =>
            if a.name == "text" {
              found = Some(a)
            }
          _ => ()
        }
      }
      match found {
        Some(a) => {
          mark_used(a)
          match a.kind {
            Dyn => parts.push([(a.value, a.pos)])
            _ => parts.push([(lit_of(a.value), a.pos)])
          }
        }
        None => {
          let mut raw = ""
          let mut tpos = pos
          let mut bad = false
          for c in children {
            match c {
              Text(s, p) => {
                raw = raw + s
                tpos = p
              }
              _ => bad = true
            }
          }
          if bad {
            return Err("\{pos_str(pos)}：<\{tag}> 的 text 参数混入了子元素（文本内容或 :text 二选一）")
          }
          let raw = normalize_text(raw)
          if raw.length() == 0 {
            return Err("\{pos_str(pos)}：<\{tag}> 缺文本内容（给 :text 或元素文本）")
          }
          let pieces = match split_interp(raw, tpos) {
            Ok(v) => v
            Err(e) => return Err(e)
          }
          let e = if has_interp(raw) {
            pieces_to_e(ctx, pieces)
          } else {
            escape_mbt(raw)
          }
          let srcs : Array[String] = []
          for p in pieces {
            match p {
              PExpr(x) =>
                for s in sources_of(x, ctx.slots) {
                  if !arr_contains(srcs, s) {
                    srcs.push(s)
                  }
                }
              _ => ()
            }
          }
          if srcs.length() > 0 && decl.path == "@ui.text" && structural_only() {
            return Ok(finish_text(ctx, q(e), srcs, ind, pos))
          }
          parts.push([(q(e), tpos)])
        }
      }
    } else {
      let mut found : Attr? = None
      if spec == "value" {
        for k, a in attrs {
          if used2[k] {
            continue
          }
          if a.kind is Model {
            found = Some(a)
          }
        }
      }
      match found {
        None => found = find_named(spec)
        Some(_) => ()
      }
      match found {
        Some(a) => {
          mark_used(a)
          match a.kind {
            Model => {
              let v = a.value.trim().to_owned()
              let cs = chars_of(v)
              let mut ok = cs.length() > 0 && is_ident_start(cs[0])
              for c in cs {
                if !is_ident_char(c) {
                  ok = false
                }
              }
              if !ok {
                return Err("\{pos_str(a.pos)}：v-model 需指向 script 里的 Store 绑定名")
              }
              parts.push([(v, a.pos)])
            }
            Dyn => parts.push([(a.value, a.pos)])
            _ => parts.push([(lit_of(a.value), a.pos)])
          }
        }
        None =>
          return Err("\{pos_str(pos)}：<\{tag}> 缺少参数「\{spec}」——给 :\{spec}（值参数给 v-model）")
      }
    }
  }
  let labeled : Array[(String, Pos)] = []
  for k, a in attrs {
    if used2[k] {
      continue
    }
    used2[k] = true
    match a.kind {
      Plain => {
        let v = if a.has_value {
          lit_of(a.value)
        } else {
          "true"
        }
        labeled.push((snake(a.name) + "=" + v, a.pos))
      }
      Dyn => labeled.push((snake(a.name) + "=" + a.value, a.pos))
      Event => {
        let ev = match event_labeled(a) {
          Ok(v) => v
          Err(e) => return Err(e)
        }
        labeled.push((ev, a.pos))
      }
      Model =>
        return Err("\{pos_str(a.pos)}：v-model 无对应值参数——<\{tag}> 的 positional 里要有 value")
      Key => ()
      If | ElseIf | Else | Show | For => ()
    }
  }
  Ok(join_call(decl.path, parts, labeled, ind, pos))
}

///|
/// 调用行拼装：path(p0, p1, …, name=v, …)——多行部分首行接在前一行、
/// 中间行原样缩进、末行回本层接后缀。
fn join_call(
  path : String,
  parts : Array[Array[(String, Pos)]],
  labeled : Array[(String, Pos)],
  ind : Int,
  pos : Pos,
) -> Array[(String, Pos)] {
  let all : Array[Array[(String, Pos)]] = []
  for p in parts {
    all.push(p)
  }
  for l in labeled {
    all.push([(l.0, l.1)])
  }
  let out : Array[(String, Pos)] = []
  if all.length() == 0 {
    out.push((ind_str(ind) + path + "()", pos))
    return out
  }
  let head_pos = if all[0][0].1.line == 0 { pos } else { all[0][0].1 }
  out.push((ind_str(ind) + path + "(" + all[0][0].0, head_pos))
  for k in 1..<all[0].length() {
    out.push(all[0][k])
  }
  for pi in 1..<all.length() {
    let p = all[pi]
    let last = out.length() - 1
    // 首段内联续接（单行参数同 行；多行部分首行如 "[" 也接在同一行）
    out[last] = (out[last].0 + ", " + p[0].0, out[last].1)
    for k in 1..<p.length() {
      out.push(p[k])
    }
  }
  let last = out.length() - 1
  out[last] = (out[last].0 + ")", out[last].1)
  out
}

///|
/// 文件名 → 生成函数名：取 basename、去首个扩展段、非法字符转下划线。
fn stem_of(filename : String) -> String {
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
  let mut out = ""
  for k in 0..<end {
    let c = b[k]
    out = out + (if is_ident_char(c) { c.to_string() } else { "_" })
  }
  if out.length() == 0 {
    return "page"
  }
  if is_digit(chars_of(out)[0]) {
    return "_" + out
  }
  out
}

///|
/// 编译入口：.mng 源码 → 生成 MoonBit + source map。
pub fn compile(src : String, filename : String) -> Result[GenOut, String] {
  let sfc = match parse_sfc(src) {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  if sfc.roots.length() != 1 {
    return Err("\{filename}：模板必须单根（v1），现 \{sfc.roots.length()} 个顶层节点")
  }
  let root = sfc.roots[0]
  let root_pos = match root {
    Elem(_, _, _, p) => p
    Text(_, p) => p
  }
  match root {
    Text(_, _) => return Err("\{filename}：模板根需是元素，不是文本")
    Elem(_, _, _, _) => ()
  }
  let info = analyze_script(sfc.script, sfc.script_line0)
  let ctx : Ctx = { slots: info.slots, lets: info.lets, comps: info.comps }
  let g : Gen = { lines: [], map: [], last: { line: 1, col: 1 } }
  let hp = { line: 1, col: 1 }
  g_emit(g, "// GENERATED by mngc（native-gui 模板编译器）。来源：" + filename + "。DO NOT EDIT。", hp)
  g_emit(g, "///|", hp)
  g_emit(g, "pub fn " + stem_of(filename) + "() -> @widget.Node {", hp)
  for k, l in info.lines {
    if l.length() > 0 {
      g_emit(g, "  " + l, { line: info.line0 + k, col: 1 })
    }
  }
  let block = match gen_blocks(ctx, [root], 1) {
    Ok(bs) =>
      if bs.length() == 1 {
        bs[0]
      } else {
        return Err("\{filename}：模板内部生成出 \{bs.length()} 个表达式块（应为一个）")
      }
    Err(e) => return Err(e)
  }
  for l in block {
    g_emit(g, l.0, l.1)
  }
  g_emit(g, "}", root_pos)
  let map_lines : Array[String] = ["# mng source map v1", "source " + filename]
  for m in g.map {
    map_lines.push("\{m.gen_line}\t\{m.src_line}\t\{m.src_col}")
  }
  Ok({ code: g.lines.join("\n") + "\n", map: map_lines.join("\n") + "\n" })
}
