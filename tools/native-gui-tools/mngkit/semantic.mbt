// 语义着色分词器：给 LSP semanticTokens 供数据（VSIX 转发，颜色由编辑器主题按
// 语义档给出）。只分「标识符类」档：类型/变量/参数/函数/方法/属性/命名空间；
// 关键字、字面量、标点、注释不发——那些区间维持 TextMate 着色，LSP 降级时整体退回。
// 符号表复用 parse_sfc + analyze_script（props 参数、let 绑定、函数名）。
// 坐标按 UTF-16 码元与 LSP 列对齐：遍历用字符数组 + 平行码元偏移表。

///|
/// 语义令牌：全文码元区间 + legend 下标 + 修饰位。
pub struct SemTok {
  start : Int // 全文 UTF-16 码元偏移
  len : Int
  ty : Int    // tokenTypes 标准序下标
  mods : Int  // tokenModifiers 位掩码
}

// tokenTypes 标准序（与 extension.js 的 SEMANTIC_TYPES 同序拷贝）：
// 0 namespace  1 type       2 class      3 enum       4 interface  5 struct
// 6 typeParameter  7 parameter  8 variable   9 property  10 enumMember
// 11 event     12 function  13 method    14 macro     15 label     16 comment
// 17 string    18 number    19 regexp    20 operator  21 keyword
const SEM_TY_NAMESPACE = 0
const SEM_TY_TYPE = 1
const SEM_TY_PARAMETER = 7
const SEM_TY_VARIABLE = 8
const SEM_TY_PROPERTY = 9
const SEM_TY_FUNCTION = 12
const SEM_TY_METHOD = 13

// tokenModifiers 位（标准序）：declaration=0 readonly=2
const SEM_MD_DECL = 1
const SEM_MD_READONLY = 4

///|
priv struct SemScan {
  cs : Array[Char] // 全文字符
  u16 : Array[Int] // u16[k] = 第 k 个字符的码元偏移
  mut i : Int      // 字符下标
  endi : Int       // 区域终点（不含）
  toks : Array[SemTok]
  // 页面符号表
  lets : Map[String, Bool]
  muts : Map[String, Bool]
  fns : Map[String, Bool]
  params : Map[String, Bool] // props 参数（模板表达式里可见）
  // 上下文机
  mut cur_params : Map[String, Bool] // 当前 fn 签名参数（体内引用按参数发色）
  mut collect_sig : Bool // 正在 fn 签名里收参数
  mut sig_paren : Int    // 签名括号层深
  mut sig_arm : Bool     // 刚过 fn 名（下个 ( 开签名）
  mut paren : Int
  mut brace : Int
  mut let_pending : Bool // 刚见 let（下个标识符是绑定名）
  mut let_mut : Bool
  mut prev_dot : Bool
  mut prev_colon2 : Bool
  mut prev_word : String
  tmpl : Bool // 模板表达式模式（无 let/fn 上下文）
}

///|
/// 全文语义令牌（按区域顺序，未排序；编码侧按位置排序）。
pub fn semantic_tokens(src : String) -> Array[SemTok] {
  let cs = chars_of(src)
  let u16 = sem_u16(cs)
  let toks : Array[SemTok] = []
  let syms = sem_syms_of(src)
  let (s0, s1) = sem_find_region(cs, "script")
  if s1 > s0 {
    let sc : SemScan = {
      cs,
      u16,
      i: s0,
      endi: s1,
      toks,
      lets: syms.lets,
      muts: syms.muts,
      fns: syms.fns,
      params: syms.params,
      cur_params: Map([]),
      collect_sig: false,
      sig_paren: 0,
      sig_arm: false,
      paren: 0,
      brace: 0,
      let_pending: false,
      let_mut: false,
      prev_dot: false,
      prev_colon2: false,
      prev_word: "",
      tmpl: false,
    }
    sem_scan_script(sc)
  }
  let (t0, t1) = sem_find_region(cs, "template")
  if t1 > t0 {
    let sc : SemScan = {
      cs,
      u16,
      i: t0,
      endi: t1,
      toks,
      lets: syms.lets,
      muts: syms.muts,
      fns: syms.fns,
      params: syms.params,
      cur_params: Map([]),
      collect_sig: false,
      sig_paren: 0,
      sig_arm: false,
      paren: 0,
      brace: 0,
      let_pending: false,
      let_mut: false,
      prev_dot: false,
      prev_colon2: false,
      prev_word: "",
      tmpl: true,
    }
    sem_scan_template(sc)
  }
  toks
}

///|
/// 每个字符的码元偏移（星面字符宽 2，保证与 LSP UTF-16 列对齐）。
fn sem_u16(cs : Array[Char]) -> Array[Int] {
  let out : Array[Int] = []
  let mut u = 0
  for c in cs {
    out.push(u)
    u += if c.to_int() >= 0x10000 { 2 } else { 1 }
  }
  out
}

///|
priv struct SemSyms {
  lets : Map[String, Bool]
  muts : Map[String, Bool]
  fns : Map[String, Bool]
  params : Map[String, Bool]
}

///|
/// 页面符号表：props 参数、let 绑定（含 let mut）、函数名。
/// 模板解析失败（编辑中常态）就给空表——词法档（类型/成员）仍可用。
fn sem_syms_of(src : String) -> SemSyms {
  let lets : Map[String, Bool] = Map([])
  let muts : Map[String, Bool] = Map([])
  let fns : Map[String, Bool] = Map([])
  let params : Map[String, Bool] = Map([])
  match parse_sfc(src) {
    Ok(sfc) => {
      let info = analyze_script(sfc.script, sfc.script_line0)
      for p in info.params {
        let _ = params.set(p.name, true)
      }
      // analyze_script 不识别 let mut（会把 "mut" 当绑定名），这里补正
      for x in info.lets {
        if x != "mut" {
          let _ = lets.set(x, true)
        }
      }
      for l in info.lines {
        let t = l.trim().to_owned()
        if t.has_prefix("let mut ") {
          let a = chars_of(t)
          let mut k = 8
          while k < a.length() && is_ident_char(a[k]) {
            k += 1
          }
          if k > 8 {
            let nm = slice_str(a, 8, k)
            let _ = lets.set(nm, true)
            let _ = muts.set(nm, true)
          }
        } else if t.has_prefix("fn ") || t.has_prefix("pub fn ") {
          let a = chars_of(t)
          let mut k = if t.has_prefix("pub ") { 7 } else { 3 }
          while k < a.length() && (a[k] == ' ' || a[k] == '\t') {
            k += 1
          }
          let mut j = k
          while j < a.length() && is_ident_char(a[j]) {
            j += 1
          }
          if j > k {
            let _ = fns.set(slice_str(a, k, j), true)
          }
        }
      }
    }
    Err(_) => ()
  }
  { lets, muts, fns, params }
}

///|
/// 顶层区域内容界：`<tag …>` 到配平的 `</tag>`（字符下标，不含标签本身）。
fn sem_find_region(cs : Array[Char], tag : String) -> (Int, Int) {
  let n = cs.length()
  let tag_cs = chars_of(tag)
  let m = tag_cs.length()
  let mut i = 0
  while i < n {
    if cs[i] == '<' && i + 1 < n && is_ident_start(cs[i + 1]) {
      // 标签名
      let mut k = i + 1
      while k < n && (is_ident_char(cs[k]) || cs[k] == '-') {
        k += 1
      }
      if k - (i + 1) == m {
        let mut ok = true
        for d in 0..<m {
          if cs[i + 1 + d] != tag_cs[d] {
            ok = false
          }
        }
        if ok {
          // 吃属性到 '>'（引号内不截断）
          let mut j = k
          let mut quote = ' '
          let mut in_q = false
          while j < n {
            let c = cs[j]
            if in_q {
              if c == quote {
                in_q = false
              }
            } else if c == '"' || c == '\'' {
              in_q = true
              quote = c
            } else if c == '>' {
              break
            }
            j += 1
          }
          if j >= n {
            return (-1, -1)
          }
          // 自闭合无内容
          if j > 0 && cs[j - 1] == '/' {
            return (-1, -1)
          }
          let start = j + 1
          // 找配平的 </tag>
          let mut depth = 1
          let mut p = start
          while p < n {
            if cs[p] == '<' && p + 1 < n {
              if cs[p + 1] == '/' && p + 1 + m + 1 < n {
                let mut ok = true
                for d in 0..<m {
                  if cs[p + 2 + d] != tag_cs[d] {
                    ok = false
                  }
                }
                if ok {
                  depth -= 1
                  if depth == 0 {
                    return (start, p)
                  }
                }
              } else if is_ident_start(cs[p + 1]) {
                // 嵌套同名开标签（template 槽）才加深
                let mut k2 = p + 1
                while k2 < n && (is_ident_char(cs[k2]) || cs[k2] == '-') {
                  k2 += 1
                }
                if k2 - (p + 1) == m {
                  let mut ok2 = true
                  for d in 0..<m {
                    if cs[p + 1 + d] != tag_cs[d] {
                      ok2 = false
                    }
                  }
                  if ok2 {
                    depth += 1
                  }
                }
              }
            }
            p += 1
          }
          return (-1, -1)
        }
      }
      i = k
      continue
    }
    i += 1
  }
  (-1, -1)
}

///|
fn sem_scan_script(sc : SemScan) -> Unit {
  while sc.i < sc.endi {
    sem_expr_token(sc, true)
  }
}

///|
/// 表达式层分发一个 token（script 段与模板表达式槽共用）。
/// comments = 是否把 `//` `/*` 当注释（模板表达式里不认，防吃掉剩余槽）。
fn sem_expr_token(sc : SemScan, comments : Bool) -> Unit {
  sem_skip_ws(sc)
  if sc.i >= sc.endi {
    return
  }
  let c = sc.cs[sc.i]
  if comments && c == '/' && sc.i + 1 < sc.endi {
    let d = sc.cs[sc.i + 1]
    if d == '/' {
      sc.i += 2
      while sc.i < sc.endi && sc.cs[sc.i] != '\n' {
        sc.i += 1
      }
      return
    }
    if d == '*' {
      sc.i += 2
      while sc.i + 1 < sc.endi &&
      !(sc.cs[sc.i] == '*' && sc.cs[sc.i + 1] == '/') {
        sc.i += 1
      }
      sc.i = if sc.i + 1 < sc.endi { sc.i + 2 } else { sc.endi }
      return
    }
  }
  if c == '"' {
    sem_string_lit(sc)
    return
  }
  if c == '\'' {
    sem_char_lit(sc)
    return
  }
  if c == '@' && sc.i + 1 < sc.endi && is_ident_start(sc.cs[sc.i + 1]) {
    let s = sc.i
    sc.i += 1
    while sc.i < sc.endi && is_ident_char(sc.cs[sc.i]) {
      sc.i += 1
    }
    sem_emit(sc, s, sc.i - s, SEM_TY_NAMESPACE, 0)
    sem_clear_flags(sc)
    sc.prev_word = "@"
    return
  }
  if is_ident_start(c) {
    sem_ident(sc)
    return
  }
  if is_digit(c) {
    sem_number(sc)
    sem_clear_flags(sc)
    sc.prev_word = ""
    return
  }
  // 标点
  if c == ':' && sc.i + 1 < sc.endi && sc.cs[sc.i + 1] == ':' {
    sc.i += 2
    sc.prev_dot = false
    sc.prev_colon2 = true
    return
  }
  if c == '.' {
    sc.i += 1
    sc.prev_colon2 = false
    sc.prev_dot = true
    return
  }
  if c == '(' {
    sc.paren += 1
    if sc.sig_arm && !sc.tmpl {
      sc.collect_sig = true
      sc.sig_paren = sc.paren
    }
    sc.sig_arm = false
    sem_clear_flags(sc)
    sc.prev_word = ""
    sc.i += 1
    return
  }
  if c == ')' {
    if sc.collect_sig && sc.paren <= sc.sig_paren {
      sc.collect_sig = false
    }
    if sc.paren > 0 {
      sc.paren -= 1
    }
    sem_clear_flags(sc)
    sc.prev_word = ""
    sc.i += 1
    return
  }
  if c == '{' {
    sc.brace += 1
    sem_clear_flags(sc)
    sc.prev_word = ""
    sc.i += 1
    return
  }
  if c == '}' {
    if sc.brace > 0 {
      sc.brace -= 1
    }
    if sc.brace == 0 {
      sc.cur_params = Map([])
      sc.collect_sig = false
    }
    sem_clear_flags(sc)
    sc.prev_word = ""
    sc.i += 1
    return
  }
  sem_clear_flags(sc)
  sc.prev_word = ""
  sc.i += 1
}

///|
fn sem_clear_flags(sc : SemScan) -> Unit {
  sc.prev_dot = false
  sc.prev_colon2 = false
}

///|
/// 标识符分发（含 let/fn 声明名、签名参数、成员与符号表分档）。
fn sem_ident(sc : SemScan) -> Unit {
  let s = sc.i
  while sc.i < sc.endi && is_ident_char(sc.cs[sc.i]) {
    sc.i += 1
  }
  let text = slice_str(sc.cs, s, sc.i)
  let was_dot = sc.prev_dot
  let was_c2 = sc.prev_colon2
  sem_clear_flags(sc)
  sem_classify(sc, s, sc.i, text, was_dot, was_c2)
}

///|
fn sem_classify(
  sc : SemScan,
  s : Int,
  e : Int,
  text : String,
  was_dot : Bool,
  was_c2 : Bool,
) -> Unit {
  let upper = is_upper_start(sc.cs[s])
  if sem_is_kw(text) {
    match text {
      "let" if !sc.tmpl => {
        sc.let_pending = true
        sc.let_mut = false
        if sc.brace == 0 {
          sc.cur_params = Map([])
        }
      }
      "mut" if !sc.tmpl && sc.let_pending => sc.let_mut = true
      "fn" if !sc.tmpl => {
        sc.cur_params = Map([])
        sc.collect_sig = false
      }
      _ => ()
    }
    sc.prev_word = text
    return
  }
  // let 绑定名声明
  if !sc.tmpl && sc.let_pending {
    sc.let_pending = false
    let mods = if sc.let_mut {
      SEM_MD_DECL
    } else {
      SEM_MD_DECL + SEM_MD_READONLY
    }
    let _ = sc.lets.set(text, true)
    if sc.let_mut {
      let _ = sc.muts.set(text, true)
    }
    sem_emit(sc, s, e - s, SEM_TY_VARIABLE, mods)
    sc.prev_word = text
    return
  }
  // fn 名声明
  if !sc.tmpl && sc.prev_word == "fn" {
    let _ = sc.fns.set(text, true)
    sc.sig_arm = true
    sem_emit(sc, s, e - s, SEM_TY_FUNCTION, SEM_MD_DECL)
    sc.prev_word = text
    return
  }
  // fn 签名内：小写是参数声明，大写是类型
  if sc.collect_sig {
    if upper {
      sem_emit(sc, s, e - s, SEM_TY_TYPE, 0)
    } else {
      let _ = sc.cur_params.set(text, true)
      sem_emit(sc, s, e - s, SEM_TY_PARAMETER, SEM_MD_DECL)
    }
    sc.prev_word = text
    return
  }
  // 成员访问
  if was_dot {
    if upper {
      sem_emit(sc, s, e - s, SEM_TY_TYPE, 0)
    } else if sem_next_is_call(sc) {
      sem_emit(sc, s, e - s, SEM_TY_METHOD, 0)
    } else {
      sem_emit(sc, s, e - s, SEM_TY_PROPERTY, 0)
    }
    sc.prev_word = text
    return
  }
  if was_c2 {
    sem_emit(sc, s, e - s, SEM_TY_FUNCTION, 0)
    sc.prev_word = text
    return
  }
  if upper {
    sem_emit(sc, s, e - s, SEM_TY_TYPE, 0)
    sc.prev_word = text
    return
  }
  // 调用形态
  if sem_next_is_call(sc) {
    sem_emit(sc, s, e - s, SEM_TY_FUNCTION, 0)
    sc.prev_word = text
    return
  }
  // 符号表分档
  if sc.lets.contains(text) {
    let mods = if sc.muts.contains(text) { 0 } else { SEM_MD_READONLY }
    sem_emit(sc, s, e - s, SEM_TY_VARIABLE, mods)
    sc.prev_word = text
    return
  }
  if sc.brace > 0 && sc.cur_params.contains(text) {
    sem_emit(sc, s, e - s, SEM_TY_PARAMETER, 0)
    sc.prev_word = text
    return
  }
  if sc.params.contains(text) {
    sem_emit(sc, s, e - s, SEM_TY_PARAMETER, 0)
    sc.prev_word = text
    return
  }
  if sc.fns.contains(text) {
    sem_emit(sc, s, e - s, SEM_TY_FUNCTION, 0)
    sc.prev_word = text
    return
  }
  sc.prev_word = text
}

///|
fn is_upper_start(c : Char) -> Bool {
  c >= 'A' && c <= 'Z'
}

///|
fn sem_next_is_call(sc : SemScan) -> Bool {
  let mut k = sc.i
  while k < sc.endi && (sc.cs[k] == ' ' || sc.cs[k] == '\t') {
    k += 1
  }
  k < sc.endi && sc.cs[k] == '('
}

///|
fn sem_is_kw(w : String) -> Bool {
  match w {
    "let"
    | "fn"
    | "pub"
    | "priv"
    | "mut"
    | "struct"
    | "enum"
    | "trait"
    | "typealias"
    | "type"
    | "const"
    | "impl"
    | "if"
    | "else"
    | "match"
    | "loop"
    | "while"
    | "for"
    | "in"
    | "return"
    | "break"
    | "continue"
    | "true"
    | "false"
    | "self"
    | "is"
    | "as"
    | "guard"
    | "try"
    | "catch"
    | "raise"
    | "extern"
    | "async"
    | "where" => true
    _ => false
  }
}

///|
fn sem_skip_ws(sc : SemScan) -> Unit {
  while sc.i < sc.endi {
    let c = sc.cs[sc.i]
    if c == ' ' || c == '\t' || c == '\n' || c == '\r' {
      sc.i += 1
    } else {
      break
    }
  }
}

///|
/// 字符串字面量：转义跳过，`\{ … }` 插值内部按表达式分档。
fn sem_string_lit(sc : SemScan) -> Unit {
  sc.i += 1
  while sc.i < sc.endi {
    let c = sc.cs[sc.i]
    if c == '"' {
      sc.i += 1
      return
    }
    if c == '\\' {
      sc.i += 1
      if sc.i < sc.endi {
        if sc.cs[sc.i] == '{' {
          sem_interp(sc)
        } else {
          sc.i += 1
        }
      }
      continue
    }
    sc.i += 1
  }
}

///|
/// 插值表达式（已越过 `\{`）：配平到 `}`，内容按表达式规则分档。
fn sem_interp(sc : SemScan) -> Unit {
  let mut depth = 1
  sc.i += 1
  while depth > 0 && sc.i < sc.endi {
    let c = sc.cs[sc.i]
    if c == '"' {
      sem_string_lit(sc)
      continue
    }
    if c == '\'' {
      sem_char_lit(sc)
      continue
    }
    if is_ident_start(c) {
      sem_ident(sc)
      continue
    }
    if c == '{' {
      depth += 1
      sc.i += 1
      continue
    }
    if c == '}' {
      depth -= 1
      sc.i += 1
      continue
    }
    if c == '.' {
      sc.prev_dot = true
      sc.i += 1
      continue
    }
    sc.i += 1
  }
  sem_clear_flags(sc)
}

///|
fn sem_char_lit(sc : SemScan) -> Unit {
  sc.i += 1
  while sc.i < sc.endi {
    let c = sc.cs[sc.i]
    if c == '\\' {
      sc.i += 2
      continue
    }
    if c == '\'' {
      sc.i += 1
      return
    }
    sc.i += 1
  }
}

///|
fn sem_number(sc : SemScan) -> Unit {
  if sc.cs[sc.i] == '0' && sc.i + 1 < sc.endi && (sc.cs[sc.i + 1] == 'x' || sc.cs[sc.i + 1] == 'X') {
    sc.i += 2
    while sc.i < sc.endi && is_ident_char(sc.cs[sc.i]) {
      sc.i += 1
    }
    return
  }
  while sc.i < sc.endi && is_digit(sc.cs[sc.i]) {
    sc.i += 1
  }
  if sc.i + 1 < sc.endi && sc.cs[sc.i] == '.' && is_digit(sc.cs[sc.i + 1]) {
    sc.i += 1
    while sc.i < sc.endi && is_digit(sc.cs[sc.i]) {
      sc.i += 1
    }
  }
  if sc.i < sc.endi && (sc.cs[sc.i] == 'e' || sc.cs[sc.i] == 'E') {
    let mut k = sc.i + 1
    if k < sc.endi && (sc.cs[k] == '+' || sc.cs[k] == '-') {
      k += 1
    }
    if k < sc.endi && is_digit(sc.cs[k]) {
      sc.i = k
      while sc.i < sc.endi && is_digit(sc.cs[sc.i]) {
        sc.i += 1
      }
    }
  }
}

///|
fn sem_emit(sc : SemScan, s : Int, len : Int, ty : Int, mods : Int) -> Unit {
  // 标识符全 ASCII：码元长 == 字符长
  if s < sc.u16.length() {
    sc.toks.push({ start: sc.u16[s], len, ty, mods })
  }
}

///|
/// 模板段：HTML 层扫描，只进表达式槽（`:attr`/`@事件`/`v-*`/`{{ }}`）。
fn sem_scan_template(sc : SemScan) -> Unit {
  while sc.i < sc.endi {
    let c = sc.cs[sc.i]
    if c == '<' && sc.i + 3 < sc.endi && sc.cs[sc.i + 1] == '!' && sc.cs[sc.i + 2] == '-' && sc.cs[sc.i + 3] == '-' {
      sc.i += 4
      while sc.i + 2 < sc.endi &&
      !(sc.cs[sc.i] == '-' && sc.cs[sc.i + 1] == '-' && sc.cs[sc.i + 2] == '>') {
        sc.i += 1
      }
      sc.i = if sc.i + 2 < sc.endi { sc.i + 3 } else { sc.endi }
      continue
    }
    if c == '{' && sc.i + 1 < sc.endi && sc.cs[sc.i + 1] == '{' {
      sc.i += 2
      sem_expr_until(sc, '}', true)
      // 吃掉 }}
      while sc.i < sc.endi && sc.cs[sc.i] == '}' {
        sc.i += 1
      }
      continue
    }
    if c == '<' && sc.i + 1 < sc.endi && is_ident_start(sc.cs[sc.i + 1]) {
      sem_tag(sc)
      continue
    }
    sc.i += 1
  }
}

///|
/// 表达式槽扫描：到 stopch 为止（`\stopch` 不算界）。
/// 双花括号模式见任意 `}` 即返回（单个 `}` 当界），调用方吞掉连续 `}`——
/// 不能把 `}` 交给通用标点分发，否则 `}}` 停止模式永远配不齐、扫描会跑穿文档。
fn sem_expr_until(sc : SemScan, stopch : Char, double_brace : Bool) -> Unit {
  while sc.i < sc.endi {
    let c = sc.cs[sc.i]
    if double_brace {
      if c == '}' {
        return
      }
    } else if c == stopch {
      return
    }
    sem_expr_token(sc, false)
  }
}

///|
fn sem_skip_attr_value(sc : SemScan, quote : Char) -> Unit {
  while sc.i < sc.endi {
    let c = sc.cs[sc.i]
    if c == '\\' {
      sc.i += 2
      continue
    }
    if c == quote {
      return
    }
    sc.i += 1
  }
}

///|
/// 标签扫描：读标签名与属性，表达式槽进分词器，其余略过。
fn sem_tag(sc : SemScan) -> Unit {
  sc.i += 1 // '<'
  while sc.i < sc.endi && (is_ident_char(sc.cs[sc.i]) || sc.cs[sc.i] == '-') {
    sc.i += 1
  }
  while sc.i < sc.endi {
    sem_skip_ws(sc)
    if sc.i >= sc.endi {
      return
    }
    let c = sc.cs[sc.i]
    if c == '>' {
      sc.i += 1
      return
    }
    if c == '/' && sc.i + 1 < sc.endi && sc.cs[sc.i + 1] == '>' {
      sc.i += 2
      return
    }
    if !is_ident_start(c) && c != ':' && c != '@' {
      sc.i += 1
      continue
    }
    // 属性名（标识符 + : @ -）
    let ns = sc.i
    while sc.i < sc.endi &&
    (is_ident_char(sc.cs[sc.i]) || sc.cs[sc.i] == ':' || sc.cs[sc.i] == '@' || sc.cs[sc.i] == '-') {
      sc.i += 1
    }
    let name = slice_str(sc.cs, ns, sc.i)
    sem_skip_ws(sc)
    if sc.i < sc.endi && sc.cs[sc.i] == '=' {
      sc.i += 1
      sem_skip_ws(sc)
      if sc.i < sc.endi && (sc.cs[sc.i] == '"' || sc.cs[sc.i] == '\'') {
        let q = sc.cs[sc.i]
        sc.i += 1
        if sem_is_expr_attr(name) {
          sem_clear_flags(sc)
          sc.prev_word = ""
          sem_expr_until(sc, q, false)
        } else {
          sem_skip_attr_value(sc, q)
        }
        if sc.i < sc.endi && sc.cs[sc.i] == q {
          sc.i += 1
        }
      }
    }
  }
}

///|
fn sem_is_expr_attr(name : String) -> Bool {
  name.has_prefix(":") ||
  name.has_prefix("@") ||
  name == "v-model" ||
  name == "v-if" ||
  name == "v-else-if" ||
  name == "v-show" ||
  name == "v-for"
}
