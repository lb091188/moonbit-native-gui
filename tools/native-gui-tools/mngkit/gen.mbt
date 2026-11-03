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
  // let 名 → 右值路径（消 `// @mng` 冗余用）
  let_paths : Map[String, String]
  comps : Map[String, CompDecl]
  // 外部签名解析器：`@包.名` → 该函数签名原文；None = 解析不到（走 @mng 逃生口）
  resolve : (String) -> String?
  cache : Map[String, CompDecl]
  // 路径 → 该函数全部参数名（自定义组件的 @事件 回调落点查表用）
  sigs : Map[String, Array[String]]
  // 本文件 `<style>` 摊平出的规则（class → class_of、深色档选取用）
  style_rules : Array[StyleRule]
  // 被当组件消费的 let 名（生成体里按需丢弃）
  used_lets : Array[String]
}

///|
/// 类型原文 → 归一（去空白，比对 children/child 落点用）。
fn norm_ty(ty : String) -> String {
  chars_of(ty).filter(fn(c) { c != ' ' && c != '\t' && c != '\n' && c != '\r' })
    .map(fn(c) { c.to_string() })
    .join("")
}

///|
/// 签名 → 组件声明：未标 `?` 的参数按声明序进 positional；类型为子节点数组/单节点的
/// 槽位记成 children / child（模板子元素落点）；`?` 参数由剩余属性按名填。
fn decl_of_sig(path : String, sig : FnSig) -> CompDecl {
  let positional : Array[String] = []
  let mut got_children = false
  let mut got_child = false
  for p in sig.params {
    if p.labelled {
      continue
    }
    let t = norm_ty(p.ty)
    if t == "Array[@widget.Node]" && !got_children {
      got_children = true
      positional.push("children")
    } else if t == "@widget.Node" && !got_child {
      got_child = true
      positional.push("child")
    } else {
      positional.push(p.name)
    }
  }
  { path, positional }
}

///|
/// `@包.名` → 末段函数名。
fn fn_of_path(path : String) -> String {
  let a = chars_of(path)
  let mut last = if a.length() > 0 && a[0] == '@' { 1 } else { 0 }
  let mut i = last
  while i < a.length() {
    if a[i] == '.' {
      last = i + 1
    }
    i += 1
  }
  let mut out = ""
  while last < a.length() && is_ident_char(a[last]) {
    out = out + a[last].to_string()
    last += 1
  }
  out
}

///|
/// 组件路径 → 声明：先查缓存，再问解析器。解析不到报错并指路 `// @mng`。
fn decl_of_path(ctx : Ctx, tag : String, path : String, pos : Pos) -> Result[CompDecl, String] {
  match ctx.cache.get(path) {
    Some(d) => Ok(d)
    None =>
      match (ctx.resolve)(path) {
        Some(text) =>
          match parse_fn_sig(text) {
            Some(sig) =>
              if sig.name != fn_of_path(path) {
                Err(
                  "\{pos_str(pos)}：<\{tag}> 的 `\{path}` 解析到 `\{sig.name}` 的签名——解析器错位，用 // @mng \{tag} = \{path} positional(…) 覆盖",
                )
              } else {
                let d = decl_of_sig(path, sig)
                let names : Array[String] = []
                for p in sig.params {
                  names.push(p.name)
                }
                let _ = ctx.sigs.set(path, names)
                let _ = ctx.cache.set(path, d)
                Ok(d)
              }
            None =>
              Err(
                "\{pos_str(pos)}：<\{tag}> 的绑定路径 `\{path}` 签名解析失败——用 // @mng \{tag} = \{path} positional(…) 覆盖",
              )
          }
        None =>
          Err(
            "\{pos_str(pos)}：<\{tag}> 绑定的 `\{path}` 找不到源码签名（依赖未装或跨发布单元）——用 // @mng \{tag} = \{path} positional(…) 声明参数顺序",
          )
      }
  }
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
      let expr = a[start:j].map(fn(c) { c.to_string() }).join("").trim().to_owned()
      out.push(PExpr(requote_expr(expr)))
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
/// 裸标识符判定（@事件 / v-model 的值形态）。
fn is_bare_ident(v : String) -> Bool {
  let cs = chars_of(v)
  if cs.length() == 0 || !is_ident_start(cs[0]) {
    return false
  }
  let mut ok = true
  for c in cs {
    if !is_ident_char(c) {
      ok = false
    }
  }
  ok
}

///|
/// 自定义组件的 @事件：回调 prop 名按 `<事件>` / `on_<事件>` 在目标参数里查；
/// 都查不到按属性名直传（与静态属性同形）。
fn event_on_comp(ctx : Ctx, decl : CompDecl, a : Attr) -> Result[String, String] {
  let v = a.value.trim().to_owned()
  if !is_bare_ident(v) {
    return Err("\{pos_str(a.pos)}：@事件值需是 script 里的函数名")
  }
  let n = snake(a.name)
  let names = match ctx.sigs.get(decl.path) {
    Some(x) => x
    None => []
  }
  let mut picked = n
  for cand in [n, "on_" + n] {
    if arr_contains(names, cand) {
      picked = cand
      break
    }
  }
  Ok(picked + "=" + v)
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
  if !is_bare_ident(v) {
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
    match ctx.comps.get(name) {
      Some(d) =>
        if d.path.has_prefix("@mng-error:") {
          return Err("\{pos_str(pos)}：\{d.path[11:].to_owned()}")
        } else {
          if arr_contains(ctx.lets, name) {
            ctx.used_lets.push(name)
          }
          d
        }
      None =>
        match ctx.let_paths.get(name) {
          Some(path) => {
            ctx.used_lets.push(name)
            match decl_of_path(ctx, tag, path, pos) {
              Ok(d) => d
              Err(e) => return Err(e)
            }
          }
          None =>
            match decl_of_path(ctx, tag, name, pos) {
              Ok(d) => d
              Err(_) =>
                return Err(
                  "\{pos_str(pos)}：<\{tag}> 不是 ui-* 组件，script 里没有 `let \{name} = @包.名`，同包也没有 `fn \{name}`——补其一，或写 // @mng \{tag} = <路径> positional(…)",
                )
            }
        }
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
        Event => {
          // 回调型位置参数（如 `on_reset : () -> Unit`）用 `@reset` 填
          let en = snake(a.name)
          if en == spec || "on_" + en == spec {
            return Some(a)
          }
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
              if !is_bare_ident(v) {
                return Err("\{pos_str(a.pos)}：v-model 需指向 script 里的 Store 绑定名")
              }
              parts.push([(v, a.pos)])
            }
            Dyn => parts.push([(a.value, a.pos)])
            Event => parts.push([(a.value.trim().to_owned(), a.pos)])
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
        let key = snake(a.name)
        if key == "class" {
          if !a.has_value {
            return Err("\{pos_str(a.pos)}：class 需要类名（class=\"a b\"）")
          }
          let ce = class_expr(ctx.style_rules, class_names_of(a.value))
          labeled.push(("class=" + ce, a.pos))
        } else if arr_contains(themed_props(), key) {
          return Err(
            "\{pos_str(a.pos)}：样式字面量 `\{key}` 不写在模板上——进 <style> 的类，用 class=\"名\" 引用（值随主题热）",
          )
        } else {
          let v = if a.has_value {
            lit_of(a.value)
          } else {
            "true"
          }
          labeled.push((key + "=" + v, a.pos))
        }
      }
      Dyn => labeled.push((snake(a.name) + "=" + a.value, a.pos))
      Event => {
        let ev = if tag.has_prefix("ui-") {
          match event_labeled(a) {
            Ok(v) => v
            Err(e) => return Err(e)
          }
        } else {
          match event_on_comp(ctx, decl, a) {
            Ok(v) => v
            Err(e) => return Err(e)
          }
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
/// 路径 → basename（末段斜杠之后）。生成码头注与 source map 的「来源」用它：
/// 绝对路径每台机器（与 CI runner）都不同，会把「重生成后与提交版 diff」的
/// 新鲜度门禁永远判成过期。
fn base_of(filename : String) -> String {
  let a = chars_of(filename)
  let mut start = 0
  for k, c in a {
    if c == '/' {
      start = k + 1
    }
  }
  a[start:].map(fn(c) { c.to_string() }).join("")
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
fn map_has(m : Map[Int, Bool], k : Int) -> Bool {
  match m.get(k) {
    Some(_) => true
    None => false
  }
}

///|
/// 行号 → 该行的 let 绑定名（无则空串）。
fn let_at(info : ScriptInfo, k : Int) -> String {
  for (name, line) in info.let_lines {
    if line == k {
      return name
    }
  }
  ""
}

///|
/// 编译内核：`dev=false` 产生产形态；`dev=true` 追加页面注册表与 holder 落点。
fn compile_impl(
  src : String,
  filename : String,
  resolve : (String) -> String?,
  dev : Bool,
) -> Result[GenOut, String] {
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
  match check_expr_quotes(sfc.roots, filename) {
    Ok(_) => ()
    Err(e) => return Err(e)
  }
  let info = analyze_script(sfc.script, sfc.script_line0)
  let style_rules = if sfc.style.trim().to_owned().length() > 0 {
    match parse_style(sfc.style, sfc.style_line0) {
      Ok(r) => r
      Err(e) => return Err(e)
    }
  } else {
    []
  }
  let ctx : Ctx = {
    slots: info.slots,
    lets: info.lets,
    let_paths: info.let_paths,
    comps: info.comps,
    resolve,
    cache: Map([]),
    sigs: Map([]),
    style_rules,
    used_lets: [],
  }
  // ① 先生成模板树：其间登记被消费的组件 let 与解析到的签名
  let block = match gen_blocks(ctx, [root], if dev { 2 } else { 1 }) {
    Ok(bs) =>
      if bs.length() == 1 {
        bs[0]
      } else {
        return Err("\{filename}：模板内部生成出 \{bs.length()} 个表达式块（应为一个）")
      }
    Err(e) => return Err(e)
  }
  // ② 引用集：script 正文（去签名头、去纯组件绑定的 let 行）+ 模板表达式——
  // 决定 props 的消警告垫片，以及只作声明用的 let 是否留在生成体里
  let head_lines : Map[Int, Bool] = Map([])
  if info.head_line >= 0 {
    for k in 0..<info.head.length() {
      let _ = head_lines.set(info.head_line + k, true)
    }
  }
  let comp_lines : Map[Int, Bool] = Map([])
  for name in ctx.used_lets {
    match info.let_lines.get(name) {
      Some(k) => {
        let _ = comp_lines.set(k, true)
      }
      None => ()
    }
  }
  let exprs : Array[String] = []
  collect_exprs(sfc.roots, exprs, Map([]))
  let mut body_text = ""
  for k, l in info.lines {
    if !map_has(head_lines, k) && !map_has(comp_lines, k) {
      body_text = body_text + l + " "
    }
  }
  let used = idents_in(body_text + " " + exprs.join(" "))
  let g : Gen = { lines: [], map: [], last: { line: 1, col: 1 } }
  let hp = { line: 1, col: 1 }
  g_emit(g, "// GENERATED by mngc（native-gui 模板编译器）。来源：" + base_of(filename) + "。DO NOT EDIT。", hp)
  g_emit(g, "///|", hp)
  if info.head.length() > 0 {
    if info.head_ret.length() == 0 {
      return Err(
        "\{filename}：props 头需要返回类型（如 fn 名(…) -> @widget.Node）",
      )
    }
    let hpos = { line: info.line0 + info.head_line, col: 1 }
    let hs : Array[String] = []
    for l in info.head {
      let t = l.trim().to_owned()
      let one = if t.has_prefix("pub ") {
        t[4:].to_owned()
      } else {
        t
      }
      hs.push(one)
    }
    for k, l in hs {
      let head_part = if k == 0 { "pub " } else { "" }
      let tail = if k == hs.length() - 1 { " {" } else { "" }
      g_emit(g, head_part + l + tail, hpos)
    }
  } else {
    g_emit(g, "pub fn " + stem_of(filename) + "() -> @widget.Node {", hp)
  }
  for p in info.params {
    if !arr_contains(used, p.name) {
      g_emit(
        g,
        "  let _ = " + p.name,
        { line: info.line0 + (if info.head_line >= 0 { info.head_line } else { 0 }), col: 1 },
      )
    }
  }
  // `<style>` 摊平：注册命名类（先于任何 class_of 引用执行）
  for stmt in style_defs(ctx.style_rules) {
    g_emit(g, stmt, { line: sfc.style_line0, col: 1 })
  }
  for k, l in info.lines {
    let drop = map_has(head_lines, k) || (map_has(comp_lines, k) && !arr_contains(used, let_at(info, k)))
    if l.length() > 0 && !drop {
      g_emit(g, "  " + l, { line: info.line0 + k, col: 1 })
    }
  }
  if dev {
    let regs = match dev_collect(sfc.roots, ctx, info.slot_tys) {
      Ok(r) => r
      Err(e) => return Err(e)
    }
    // 受限表达式求值器要按名取状态：把 script 顶层 Store 全登记，
    // 不只模板里 v-model 用到的那些。
    for p in info.params {
      match kind_of_ty(p.ty) {
        KStore =>
          match elem_ty_of(p.ty) {
            Some(t) =>
              match state_kind_of(t) {
                Some(kd) => dev_push_state(regs.states, p.name, kd, hp)
                None => ()
              }
            None => ()
          }
        _ => ()
      }
    }
    for (n, line) in info.let_lines {
      if line >= 0 && line < info.lines.length() &&
        (info.lines[line].has_prefix("let ") ||
          info.lines[line].has_prefix("pub let ")) {
        match info.slots.get(n) {
          Some(KStore) =>
            match info.slot_tys.get(n) {
              Some(t) =>
                match state_kind_of(t) {
                  Some(kd) => dev_push_state(regs.states, n, kd, hp)
                  None => ()
                }
              None => ()
            }
          _ => ()
        }
      }
    }
    g_emit(g, "  let reg = @shared.mng_reg_new()", hp)
    g_emit(g, "  @shared.mng_reg_builtins(reg)", hp)
    for (k, e, p) in regs.exprs {
      g_emit(g, "  reg.expr(" + q(k) + ", fn() { " + e + " })", p)
    }
    for (k, e, p) in regs.conds {
      g_emit(g, "  reg.cond(" + q(k) + ", fn() { " + e + " })", p)
    }
    for (h, p) in regs.handlers {
      g_emit(g, "  reg.handler(" + q(h) + ", " + h + ")", p)
    }
    for (n, kd, p) in regs.states {
      g_emit(g, "  reg." + kd + "(" + q(n) + ", " + n + ")", p)
    }
    g_emit(g, "  @shared.mng_dev_page(" + q(stem_of(filename)) + ", reg, fn() {", hp)
    for l in block {
      g_emit(g, l.0, l.1)
    }
    g_emit(g, "  })", root_pos)
  } else {
    for l in block {
      g_emit(g, l.0, l.1)
    }
  }
  g_emit(g, "}", root_pos)
  let map_lines : Array[String] = ["# mng source map v1", "source " + base_of(filename)]
  for m in g.map {
    map_lines.push("\{m.gen_line}\t\{m.src_line}\t\{m.src_col}")
  }
  Ok({ code: g.lines.join("\n") + "\n", map: map_lines.join("\n") + "\n" })
}

///|
/// 模板表达式/条件/事件/状态的键清单（dev 登记与热更检查共用）。
priv struct DevBindings {
  exprs : Array[(String, String)]
  conds : Array[(String, String)]
  handlers : Array[String]
  states : Array[String]
}

///|
fn dev_bindings(src : String, filename : String) -> Result[DevBindings, String] {
  let sfc = match parse_sfc(src) {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let info = analyze_script(sfc.script, sfc.script_line0)
  let ctx : Ctx = {
    slots: info.slots,
    lets: info.lets,
    let_paths: info.let_paths,
    comps: info.comps,
    resolve: fn(_path : String) -> String? { None },
    cache: Map([]),
    sigs: Map([]),
    style_rules: [],
    used_lets: [],
  }
  let regs = match dev_collect(sfc.roots, ctx, info.slot_tys) {
    Ok(r) => r
    Err(e) => return Err(e)
  }
  let exprs : Array[(String, String)] = []
  for (k, e, _) in regs.exprs {
    exprs.push((k, e))
  }
  let conds : Array[(String, String)] = []
  for (k, e, _) in regs.conds {
    conds.push((k, e))
  }
  let handlers : Array[String] = []
  for (h, _) in regs.handlers {
    handlers.push(h)
  }
  let states : Array[String] = []
  for (n, _, _) in regs.states {
    states.push(n)
  }
  let _ = filename
  Ok({ exprs, conds, handlers, states })
}

///|
fn etype_of_store(t : String) -> EType? {
  match t {
    "Int" => Some(TInt)
    "Bool" => Some(TBool)
    "String" => Some(TStr)
    _ => None
  }
}

///|
/// script 顶层 Store 名 → 值类型（与 dev 生成码的 state 登记同口径）。
fn script_store_types(script : String, line0 : Int) -> Map[String, EType] {
  let out : Map[String, EType] = Map([])
  let info = analyze_script(script, line0)
  for p in info.params {
    match kind_of_ty(p.ty) {
      KStore =>
        match elem_ty_of(p.ty) {
          Some(t) =>
            match etype_of_store(t) {
              Some(et) => {
                let _ = out.set(p.name, et)
              }
              None => ()
            }
          None => ()
        }
      _ => ()
    }
  }
  for (n, line) in info.let_lines {
    if line >= 0 && line < info.lines.length() &&
      (info.lines[line].has_prefix("let ") ||
        info.lines[line].has_prefix("pub let ")) {
      match info.slots.get(n) {
        Some(KStore) =>
          match info.slot_tys.get(n) {
            Some(t) =>
              match etype_of_store(t) {
                Some(et) => {
                  let _ = out.set(n, et)
                }
                None => ()
              }
            None => ()
          }
        _ => ()
      }
    }
  }
  out
}

///|
/// 热更检查：script / `<style>` 未变；新出现的表达式都在受限文法内且只引用
/// 顶层 Store 与内置函数；新事件函数必须已在旧模板里。通过则返回带 eval 的 IR。
pub fn hot_ir(new_src : String, base_src : String, filename : String) -> Result[String, String] {
  let n = match parse_sfc(new_src) {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let b = match parse_sfc(base_src) {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  if n.script != b.script {
    return Err("script 段改动")
  }
  let nb = match dev_bindings(new_src, filename) {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let bb = match dev_bindings(base_src, filename) {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  for h in nb.handlers {
    if !arr_contains(bb.handlers, h) {
      return Err("新事件函数「" + h + "」不在启动注册表")
    }
  }
  let stores = script_store_types(n.script, n.script_line0)
  for s in nb.states {
    match stores.get(s) {
      Some(_) => ()
      None => return Err("状态「" + s + "」不是顶层 Store")
    }
  }
  let base_keys : Map[String, Bool] = Map([])
  for (k, _) in bb.exprs {
    let _ = base_keys.set(k, true)
  }
  for (k, _) in bb.conds {
    let _ = base_keys.set(k, true)
  }
  let evals : Map[String, String] = Map([])
  for (k, e) in nb.exprs {
    if !base_keys.get_or_default(k, false) {
      let want = if k.has_prefix("c:") { "c" } else { "t" }
      let ast = match parse_eval_expr(e, stores, want) {
        Ok(v) => v
        Err(err) => return Err("表达式热更不支持：" + err)
      }
      let _ = evals.set(k, ast)
    }
  }
  for (k, e) in nb.conds {
    if !base_keys.get_or_default(k, false) {
      let ast = match parse_eval_expr(e, stores, "c") {
        Ok(v) => v
        Err(err) => return Err("条件热更不支持：" + err)
      }
      let _ = evals.set(k, ast)
    }
  }
  let classes = match style_classes_json(n.style, n.style_line0) {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  ir_of_with(new_src, filename, evals, classes)
}

///|
/// 生产形态编译（带签名解析器）。
pub fn compile_with(
  src : String,
  filename : String,
  resolve : (String) -> String?,
) -> Result[GenOut, String] {
  compile_impl(src, filename, resolve, false)
}

///|
/// dev 形态编译：script 段外层建状态，树进 build 闭包，登记表随页生成。
pub fn compile_dev(
  src : String,
  filename : String,
  resolve : (String) -> String?,
) -> Result[GenOut, String] {
  compile_impl(src, filename, resolve, true)
}

///|
/// 编译入口（无签名解析器）：非 ui-* 组件只认 `// @mng` 声明。
pub fn compile(src : String, filename : String) -> Result[GenOut, String] {
  compile_with(src, filename, fn(_path) { None })
}

///|
/// 内置组件标签表（编辑器补全用）：`ui-*` 标签名。
pub fn builtin_tags() -> Array[String] {
  [
    "ui-text",
    "ui-button",
    "ui-input",
    "ui-textarea",
    "ui-stepper",
    "ui-slider",
    "ui-rate",
    "ui-switch",
    "ui-checkbox",
    "ui-radio-group",
    "ui-select",
    "ui-form",
    "ui-form-item",
    "ui-col",
    "ui-row",
    "ui-view",
    "ui-panel",
  ]
}

///|
/// 内置组件的参数名（位置参数序 + `class` 等通用项由调用方另补）。
pub fn builtin_params(tag : String) -> Array[String]? {
  match builtin_decl(tag) {
    Some(d) => Some(d.positional)
    None => None
  }
}

///|
/// 内置组件标签 → 生成码里的构造函数路径（编辑器跳转用）。
pub fn builtin_path(tag : String) -> String? {
  match builtin_decl(tag) {
    Some(d) => Some(d.path)
    None => None
  }
}

///|
/// 模板里的动态表达式原文（script 引用面统计用）。
fn collect_exprs(
  nodes : Array[TNode],
  out : Array[String],
  seen : Map[String, Bool],
) -> Unit {
  fn push(e : String) -> Unit {
    if e.length() > 0 && !seen.get_or_default(e, false) {
      let _ = seen.set(e, true)
      out.push(e)
    }
  }
  for n in nodes {
    match n {
      Elem(_, attrs, kids, _) => {
        for a in attrs {
          match a.kind {
            Dyn | Event | Model | If | ElseIf | Show =>
              if a.has_value {
                push(a.value)
              }
            _ => ()
          }
        }
        collect_exprs(kids, out, seen)
      }
      Text(raw, pos) =>
        match split_interp(raw, pos) {
          Ok(pieces) =>
            for p in pieces {
              match p {
                PExpr(e) => push(e)
                _ => ()
              }
            }
          Err(_) => ()
        }
    }
  }
}
