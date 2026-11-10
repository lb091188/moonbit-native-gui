// LSP semantic tokens：mngkit 语义令牌 → textDocument/semanticTokens/full 报文。
// legend 标准序，与 tools/vscode-mng/extension.js 的 SEMANTIC_TYPES/MODIFIERS 同序拷贝。

///|
fn sem_legend_types() -> Array[String] {
  [
    "namespace", "type", "class", "enum", "interface", "struct", "typeParameter",
    "parameter", "variable", "property", "enumMember", "event", "function", "method",
    "macro", "label", "comment", "string", "number", "regexp", "operator", "keyword",
  ]
}

///|
fn sem_legend_mods() -> Array[String] {
  [
    "declaration", "definition", "readonly", "static", "deprecated", "abstract",
    "async", "modification", "documentation", "defaultLibrary",
  ]
}

///|
fn sem_str_arr_json(a : Array[String]) -> String {
  let parts : Array[String] = []
  for s in a {
    parts.push(jq(s))
  }
  "[" + parts.join(",") + "]"
}

///|
fn sem_legend_json() -> String {
  "{\"tokenTypes\":" +
  sem_str_arr_json(sem_legend_types()) +
  ",\"tokenModifiers\":" +
  sem_str_arr_json(sem_legend_mods()) +
  "}"
}

///|
/// 每行行首的码元偏移（0 基行）。
fn sem_line_starts(text : String) -> Array[Int32] {
  let starts : Array[Int32] = [0]
  let mut u = 0
  for c in text {
    let w = if c.to_int() >= 0x10000 { 2 } else { 1 }
    if c == '\n' {
      starts.push(u + w)
    }
    u += w
  }
  starts
}

///|
/// 令牌数组 → LSP delta 编码 data 数组（相对前一令牌的行/列增量 + 长/档/修饰）。
fn sem_encode(text : String, toks : Array[@mngkit.SemTok]) -> String {
  toks.sort_by(fn(a, b) { a.start - b.start })
  let starts = sem_line_starts(text)
  let parts : Array[String] = []
  let mut li = 0
  let mut pl = 0
  let mut pc = 0
  for t in toks {
    while li + 1 < starts.length() && starts[li + 1] <= t.start {
      li += 1
    }
    let line = li
    let col = t.start - starts[li]
    // LSP 契约：每令牌恒 5 个数；首令牌相对 (0,0)，deltaLine=0 也要显式给
    let dl = line - pl
    let dc = if line == pl { col - pc } else { col }
    parts.push(dl.to_string())
    parts.push(dc.to_string())
    parts.push(t.len.to_string())
    parts.push(t.ty.to_string())
    parts.push(t.mods.to_string())
    pl = line
    pc = col
  }
  "[" + parts.join(",") + "]"
}
