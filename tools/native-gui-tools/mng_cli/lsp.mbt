// 语言服务（stdio JSON-RPC）。语义全部复用 mngkit：
//   诊断 = compile 错误（自带模板行列）；
//   补全 = 上下文分四档（标签 / 属性 / 表达式 / 类名）；
//   hover = 组件参数表；跳转 = 组件源码位置（Sigs::locate）或页内声明行。
// v1 不做：真实类型 hover（需桥 moon ide + source map 正向索引）、跨工程索引。

///|
/// 一条报文处理结果：回应（有 id 时）、附带通知（诊断）、是否退出。
priv struct LspOut {
  reply : String?
  notify : String?
  stop : Bool
}

///|
fn lsp_ok(reply : String) -> LspOut {
  { reply: Some(reply), notify: None, stop: false }
}

///|
fn lsp_send(payload : String) -> Unit {
  let body = @utf8.encode(payload)
  let head = @utf8.encode("Content-Length: \{body.length()}\r\n\r\n")
  let _ = @proc.write_stdout(head, head.length())
  let _ = @proc.write_stdout(body, body.length())
}

///|
/// 逐字节读一行（LSP 头是纯 ASCII）；EOF → None。
fn lsp_read_line() -> String? {
  let one = Bytes::new(1)
  let out = StringBuilder()
  let mut done = false
  let mut eof = false
  while !done {
    let n = @proc.read_stdin(one, 1)
    if n <= 0 {
      done = true
      eof = true
    } else {
      let c = match one[0].to_int().to_char() {
        Some(ch) => ch
        None => '?'
      }
      if c == '\n' {
        done = true
      } else if c != '\r' {
        out.write_char(c)
      }
    }
  }
  if eof && out.to_string().length() == 0 {
    None
  } else {
    Some(out.to_string())
  }
}

///|
/// 读一条 LSP 报文（头 + 按 Content-Length 取体）；EOF → None。
fn lsp_read_message() -> String? {
  let mut len = -1
  while true {
    let line = match lsp_read_line() {
      Some(l) => l
      None => return None
    }
    if line.length() == 0 {
      break
    }
    let lower = line.to_lower().to_string()
    if lower.has_prefix("content-length:") {
      let v = line[15:].trim().to_owned()
      match parse_uint(v) {
        Some(n) => len = n
        None => ()
      }
    }
  }
  if len < 0 {
    return None
  }
  let acc : Array[Byte] = []
  let chunk = Bytes::new(4096)
  while acc.length() < len {
    let want = if len - acc.length() > 4096 { 4096 } else { len - acc.length() }
    let got = @proc.read_stdin(chunk, want)
    if got <= 0 {
      return None
    }
    for i in 0..<got {
      acc.push(chunk[i])
    }
  }
  Some(@utf8.decode_lossy(Bytes::from_array(acc)))
}

///|
fn parse_uint(s : String) -> Int? {
  let a = chars_of_cli(s)
  if a.length() == 0 {
    return None
  }
  let mut v = 0
  for c in a {
    if c < '0' || c > '9' {
      return None
    }
    v = v * 10 + (c.to_int() - '0'.to_int())
  }
  Some(v)
}

///|
fn chars_of_cli(s : String) -> Array[Char] {
  let out : Array[Char] = []
  for c in s {
    out.push(c)
  }
  out
}

///|
fn slice_cli(a : Array[Char], lo : Int, hi : Int) -> String {
  if hi <= lo {
    ""
  } else {
    a[lo:hi].map(fn(c) { c.to_string() }).join("")
  }
}

///|
/// `file:///…` → 本地路径（只解 %20，够覆盖常见路径）。
fn uri_to_path(uri : String) -> String {
  let s = if uri.has_prefix("file://") {
    uri[7:].to_owned()
  } else {
    uri
  }
  let out = StringBuilder()
  let a = chars_of_cli(s)
  let mut i = 0
  while i < a.length() {
    if a[i] == '%' && i + 2 < a.length() {
      match parse_hex2(a[i + 1], a[i + 2]) {
        Some(v) => {
          match v.to_char() {
            Some(ch) => out.write_char(ch)
            None => ()
          }
          i += 3
        }
        None => {
          out.write_char(a[i])
          i += 1
        }
      }
    } else {
      out.write_char(a[i])
      i += 1
    }
  }
  out.to_string()
}

///|
fn parse_hex2(a : Char, b : Char) -> Int? {
  let h = fn(c : Char) -> Int? {
    if c >= '0' && c <= '9' {
      Some(c.to_int() - '0'.to_int())
    } else if c >= 'a' && c <= 'f' {
      Some(c.to_int() - 'a'.to_int() + 10)
    } else if c >= 'A' && c <= 'F' {
      Some(c.to_int() - 'A'.to_int() + 10)
    } else {
      None
    }
  }
  match (h(a), h(b)) {
    (Some(x), Some(y)) => Some(x * 16 + y)
    _ => None
  }
}

///|
/// 行/字符（0 基，字符按 UTF-16 单元）→ 文本内偏移。
fn offset_of(text : String, line : Int, ch : Int) -> Int {
  let a = chars_of_cli(text)
  let mut cur_line = 0
  let mut i = 0
  while i < a.length() && cur_line < line {
    if a[i] == '\n' {
      cur_line += 1
    }
    i += 1
  }
  let start = i
  let mut end = start
  while end < a.length() && a[end] != '\n' {
    end += 1
  }
  let stop = if start + ch < end { start + ch } else { end }
  stop
}

///|
/// `sub` 在 `a[0:stop]` 里最后一次出现的位置；没有返回 -1。
fn last_index_of(a : Array[Char], sub : String, stop : Int) -> Int {
  let b = chars_of_cli(sub)
  let n = if stop < a.length() { stop } else { a.length() }
  let mut last = -1
  let mut i = 0
  while i + b.length() <= n {
    let mut ok = true
    for k in 0..<b.length() {
      if a[i + k] != b[k] {
        ok = false
      }
    }
    if ok {
      last = i
      i += b.length()
    } else {
      i += 1
    }
  }
  last
}

///|
/// 光标是否在 `<script>` 段内（最后一个开标签在最后闭标签之后）。
fn in_script(a : Array[Char], stop : Int) -> Bool {
  last_index_of(a, "<script", stop) > last_index_of(a, "</script", stop)
}

///|
/// 光标前一个令牌（`@包.成员` / 标识符）。
fn token_before(a : Array[Char], stop : Int) -> String {
  let n = if stop < a.length() { stop } else { a.length() }
  let mut start = n
  while start > 0 &&
    (is_ident_char(a[start - 1]) ||
      a[start - 1] == '@' ||
      a[start - 1] == '.' ||
      a[start - 1] == ':') {
    start -= 1
  }
  slice_cli(a, start, n)
}

///|
/// 字符串里第一个 `.` 的位置。
fn dot_index_cli(s : String) -> Int? {
  let a = chars_of_cli(s)
  let mut i = 0
  while i < a.length() {
    if a[i] == '.' {
      return Some(i)
    }
    i += 1
  }
  None
}

///|
/// 令牌首段（`qty.set` → `qty`）；无分隔符返回 None。
fn first_seg(s : String) -> String? {
  let a = chars_of_cli(s)
  let mut i = 0
  while i < a.length() {
    if a[i] == '.' || a[i] == ':' {
      return Some(slice_cli(a, 0, i))
    }
    i += 1
  }
  None
}

///|
/// 以模板所在包为上下文的签名/跳转解析器。
fn sigs_for(uri : String) -> @mngkit.Sigs {
  let path = uri_to_path(uri)
  let dir = dir_of(path)
  @mngkit.sigs_new(ws_root(dir), dir, @mngkit.io_new(fs_read, fs_ls))
}

///|
/// 本地路径 → `file://` URI（空格、非 ASCII 走百分号编码）。
fn path_to_uri(p : String) -> String {
  let bytes = @utf8.encode(p)
  let out = StringBuilder()
  out.write_string("file://")
  for i in 0..<bytes.length() {
    let v = bytes[i].to_int()
    if (v >= 48 && v <= 57) ||
      (v >= 65 && v <= 90) ||
      (v >= 97 && v <= 122) ||
      v == 45 ||
      v == 46 ||
      v == 95 ||
      v == 126 ||
      v == 47 ||
      v == 58 {
      match v.to_char() {
        Some(c) => out.write_char(c)
        None => ()
      }
    } else {
      out.write_string("%" + hex2_of(v))
    }
  }
  out.to_string()
}

///|
fn hex2_of(v : Int) -> String {
  let digits = "0123456789ABCDEF"
  let hi = (v / 16) % 16
  let lo = v % 16
  digits[hi:hi + 1].to_owned() + digits[lo:lo + 1].to_owned()
}

///|
/// 补全上下文：("tag"|"attr"|"expr"|"class"|"script"|"none", 当前前缀, 所在标签名)。
fn lsp_context(text : String, off : Int) -> (String, String, String) {
  let a = chars_of_cli(text)
  let stop = if off < a.length() { off } else { a.length() }
  if in_script(a, stop) {
    return ("script", token_before(a, stop), "")
  }
  // 最近的 '<' 与 '>'
  let mut lt = -1
  let mut gt = -1
  let mut i = 0
  while i < stop {
    if a[i] == '<' {
      lt = i
    } else if a[i] == '>' {
      gt = i
    }
    i += 1
  }
  if lt > gt {
    // 开标签内：标签名段 or 属性段
    let seg = slice_cli(a, lt + 1, stop)
    let mut sp = -1
    let sa = chars_of_cli(seg)
    let mut k = 0
    while k < sa.length() {
      if sa[k] == ' ' || sa[k] == '\t' || sa[k] == '\n' || sa[k] == '\r' {
        sp = k
        break
      }
      k += 1
    }
    if sp < 0 {
      return ("tag", seg, seg)
    }
    let tag = slice_cli(sa, 0, sp)
    // 值内？找最后一个引号：若光标前的引号未闭合，则在值里
    let mut last_q = -1
    let mut q = 0
    let mut qi = 0
    while qi < sa.length() {
      if sa[qi] == '"' || sa[qi] == '\'' {
        last_q = qi
        q += 1
      }
      qi += 1
    }
    if q % 2 == 1 && last_q >= 0 {
      // 在值里：找属性名（引号前回退到 '=' 再回退到空白）
      let mut eq = last_q - 1
      while eq >= 0 && sa[eq] != '=' {
        eq -= 1
      }
      let mut ns = eq - 1
      while ns >= 0 && (sa[ns] != ' ' && sa[ns] != '\t' && sa[ns] != '\n') {
        ns -= 1
      }
      let attr = if eq > 0 { slice_cli(sa, ns + 1, eq) } else { "" }
      // 值内前缀：本 token 起点（空白后）
      let mut vs = last_q + 1
      let mut b = last_q + 1
      while b < sa.length() {
        let c = sa[b]
        if c == ' ' || c == '\t' || c == '\n' || c == ',' {
          vs = b + 1
        }
        b += 1
      }
      let partial = slice_cli(sa, vs, sa.length())
      if attr == "class" {
        return ("class", partial, tag)
      }
      return ("expr", partial, tag)
    }
    // 属性名位置：最后一段 token
    let mut ns = sp + 1
    let mut b = sp + 1
    while b < sa.length() {
      let c = sa[b]
      if c == ' ' || c == '\t' || c == '\n' {
        ns = b + 1
      }
      b += 1
    }
    return ("attr", slice_cli(sa, ns, sa.length()), tag)
  }
  // 标签外：{{ }} 内？
  let mut open_i = -1
  let mut j = 0
  while j + 1 < stop {
    if a[j] == '{' && a[j + 1] == '{' {
      open_i = j
    }
    j += 1
  }
  if open_i >= 0 {
    let mut close_i = -1
    let mut m = open_i + 2
    while m + 1 < stop {
      if a[m] == '}' && a[m + 1] == '}' {
        close_i = m
      }
      m += 1
    }
    if close_i < open_i {
      // 前缀取 { 之后最近的空白/标点后
      let mut vs = open_i + 2
      let mut b = open_i + 2
      while b < stop {
        let c = a[b]
        if c == ' ' || c == '\t' || c == '\n' || c == '(' || c == ',' || c == '=' {
          vs = b + 1
        }
        b += 1
      }
      return ("expr", slice_cli(a, vs, stop), "")
    }
  }
  ("none", "", "")
}

///|
/// 补全项 JSON。
fn completion_item(label : String, kind : Int) -> String {
  "{\"label\":" + jq(label) + ",\"kind\":" + kind.to_string() + "}"
}

///|
fn completion_list(items : Array[String], kind : Int) -> String {
  let parts : Array[String] = []
  for it in items {
    parts.push(completion_item(it, kind))
  }
  "{\"isIncomplete\":false,\"items\":[" + parts.join(",") + "]}"
}

///|
/// 从 script 原文里找 `let <名> = <路径>` 的路径（补全/跳转用）。
fn let_path_in(src : String, name : String) -> String? {
  for line in src.split("\n") {
    let l = line.trim().to_owned()
    if !l.has_prefix("let ") {
      continue
    }
    let a = chars_of_cli(l)
    let mut i = 4
    while i < a.length() && (a[i] == ' ' || a[i] == '\t') {
      i += 1
    }
    let mut j = i
    while j < a.length() && (is_ident_char(a[j]) || (a[j] >= '0' && a[j] <= '9')) {
      j += 1
    }
    let nm = slice_cli(a, i, j)
    if nm != name {
      continue
    }
    let mut e = j
    while e < a.length() && a[e] != '=' {
      e += 1
    }
    if e >= a.length() {
      continue
    }
    let rv = slice_cli(a, e + 1, a.length()).trim().to_owned()
    if rv.has_prefix("@") || (rv.length() > 0 && is_ident_char(chars_of_cli(rv)[0])) {
      let rc = chars_of_cli(rv)
      let mut k = if rc[0] == '@' { 1 } else { 0 }
      while k < rc.length() && (is_ident_char(rc[k]) || rc[k] == '.') {
        k += 1
      }
      return Some(slice_cli(rc, 0, k))
    }
  }
  None
}

///|
/// 组件标签 → 定义文件（同包裸名或 let 绑定的 `@包.名`）。
fn locate_tag(sigs : @mngkit.Sigs, text : String, tag : String) -> String? {
  let snake_name = snake_cli(tag)
  let target = match let_path_in(text, snake_name) {
    Some(p) => p
    None => snake_name
  }
  sigs.locate(target)
}

///|
fn snake_cli(s : String) -> String {
  let out = StringBuilder()
  for c in s {
    if c == '-' {
      out.write_char('_')
    } else {
      out.write_char(c)
    }
  }
  out.to_string()
}

///|
/// 声明行查找：`let [mut] 名` / `fn 名` / props 头参数 → 0 基行号。
fn decl_line_of(text : String, name : String) -> Int? {
  let lines = text.split("\n")
  let mut idx = 0
  for line in lines {
    let l = line.trim().to_owned()
    for kw in ["let ", "let mut ", "fn ", "pub fn ", "pub(all) fn "] {
      if l.has_prefix(kw) && ident_lead_cli(l[kw.length():].to_owned(), name) {
        return Some(idx)
      }
    }
    // props 头参数：fn 头里的 `名 :` / `名? :`
    if l.has_prefix("fn ") && (contains_sub_cli(l, name + " :") || contains_sub_cli(l, name + "? :")) {
      return Some(idx)
    }
    idx += 1
  }
  None
}

///|
/// `s` 是否以 `name` 开头且名字后断词（`qty` 不匹配 `qty2`）。
fn ident_lead_cli(s : String, name : String) -> Bool {
  if !s.has_prefix(name) {
    return false
  }
  if s.length() == name.length() {
    return true
  }
  let c = chars_of_cli(s)[name.length()]
  !(is_ident_char(c) || c == '-')
}

///|
fn contains_sub_cli(s : String, sub : String) -> Bool {
  let a = chars_of_cli(s)
  let b = chars_of_cli(sub)
  let n = a.length()
  let m = b.length()
  if m == 0 || m > n {
    return m == 0
  }
  let mut i = 0
  while i + m <= n {
    let mut ok = true
    for k in 0..<m {
      if a[i + k] != b[k] {
        ok = false
      }
    }
    if ok {
      return true
    }
    i += 1
  }
  false
}

///|
/// 诊断通知：编译错误 → publishDiagnostics（行列取自错误文本的「行 L 列 C」）。
fn lsp_diagnostics(uri : String, text : String) -> String {
  let diags : Array[String] = []
  match mng_compile(text, uri_to_path(uri)) {
    Ok(_) => ()
    Err(e) => {
      let (line, col) = err_pos_of(e)
      let msg = jq(e)
      let start = "{\"range\":{\"start\":{\"line\":" + line.to_string() + ",\"character\":" + col.to_string() + "}"
      let tail = ",\"end\":{\"line\":" + (line + 1).to_string() + ",\"character\":0}}"
      diags.push(start + tail + ",\"severity\":1,\"source\":\"mng\",\"message\":" + msg + "}")
    }
  }
  let head = "{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/publishDiagnostics\",\"params\":{"
  head + "\"uri\":" + jq(uri) + ",\"diagnostics\":[" + diags.join(",") + "]}}"
}

///|
/// 错误文本 → (0 基行, 0 基列)；无坐标给 (0,0)。
fn err_pos_of(e : String) -> (Int, Int) {
  let a = chars_of_cli(e)
  let mut line = 0
  let mut col = 0
  let mut i = 0
  while i < a.length() {
    if a[i] == '行' || a[i] == '列' {
      let mut k = i + 1
      while k < a.length() && (a[k] == ' ' || a[k] == '\t') {
        k += 1
      }
      let mut v = 0
      let mut digits = 0
      while k < a.length() && a[k] >= '0' && a[k] <= '9' {
        v = v * 10 + (a[k].to_int() - '0'.to_int())
        digits += 1
        k += 1
      }
      if digits > 0 {
        let z = if v > 0 { v - 1 } else { 0 }
        if a[i] == '行' {
          line = z
        } else {
          col = z
        }
        i = k
        continue
      }
    }
    i += 1
  }
  (line, col)
}

///|
fn lsp_completion(uri : String, text : String, line : Int, ch : Int) -> String {
  let off = offset_of(text, line, ch)
  let (ctx, partial, tag) = lsp_context(text, off)
  match ctx {
    "tag" => {
      let items : Array[String] = []
      for t in @mngkit.builtin_tags() {
        items.push(t)
      }
      for s in @mngkit.script_symbols(text) {
        let t = snake_cli(s)
        if !arr_has_cli(items, t) {
          items.push(t)
        }
      }
      completion_list(items, 9)
    }
    "attr" => {
      let items : Array[String] = ["class", "v-model", "v-if", "v-else-if", "v-else", "v-show", "v-for"]
      match @mngkit.builtin_params(tag) {
        Some(ps) =>
          for p in ps {
            if p != "children" && p != "child" && p != "text" && !arr_has_cli(items, p) {
              items.push(p)
            }
          }
        None => ()
      }
      items.push("@click")
      items.push("@change")
      items.push("@enter")
      completion_list(items, 5)
    }
    "expr" | "script" => lsp_expr_completion(uri, text, partial)
    "class" => completion_list(@mngkit.style_class_names(text), 7)
    _ => completion_list([], 1)
  }
}

///|
/// 表达式补全：`@别名.` 后给包内公开成员；`@` 后给 moon.pkg 别名表；否则页内符号。
fn lsp_expr_completion(uri : String, text : String, partial : String) -> String {
  let p = partial.trim().to_owned()
  let sigs = sigs_for(uri)
  let items : Array[String] = []
  if p.has_prefix("@") {
    match dot_index_cli(p) {
      Some(d) => {
        let al = p[1:d].to_owned()
        let prefix = p[d + 1:].to_owned()
        for m in sigs.members(al) {
          if prefix.length() == 0 || m.has_prefix(prefix) {
            items.push(completion_item(m, member_kind(m)))
          }
        }
      }
      None => {
        let lead = p[1:].to_owned()
        for al in sigs.pkg_aliases() {
          if lead.length() == 0 || al.has_prefix(lead) {
            items.push(completion_item("@" + al, 9))
          }
        }
      }
    }
  } else {
    for s in @mngkit.script_symbols(text) {
      items.push(completion_item(s, 6))
    }
    for al in sigs.pkg_aliases() {
      items.push(completion_item("@" + al, 9))
    }
  }
  "{\"isIncomplete\":false,\"items\":[" + items.join(",") + "]}"
}

///|
/// 补全项类型：`Type::method` 方法、大写开头类型、其余函数。
fn member_kind(name : String) -> Int {
  if contains_sub_cli(name, "::") {
    2
  } else {
    let a = chars_of_cli(name)
    if a.length() > 0 && a[0].to_int() >= 'A'.to_int() && a[0].to_int() <= 'Z'.to_int() {
      22
    } else {
      3
    }
  }
}

///|
fn arr_has_cli(a : Array[String], s : String) -> Bool {
  for x in a {
    if x == s {
      return true
    }
  }
  false
}

///|
fn lsp_hover(uri : String, text : String, line : Int, ch : Int) -> String {
  let off = offset_of(text, line, ch)
  let (ctx, partial, tag) = lsp_context(text, off)
  let content = match ctx {
    "attr" | "tag" => {
      let tag = expand_token(text, off, tag)
      if tag.length() > 0 {
        match @mngkit.builtin_params(tag) {
          Some(ps) => "`<" + tag + ">` 参数：" + ps.join(", ")
          None => "自定义组件 `<" + tag + ">`（参数见其 props 头）"
        }
      } else {
        ""
      }
    }
    "class" => "类 `" + partial + "`：由 `<style>` 摊平进命名类注册表"
    "expr" | "script" => hover_pkg_member(uri, text, off, partial)
    _ => ""
  }
  if content.length() == 0 {
    "null"
  } else {
    "{\"contents\":{\"kind\":\"markdown\",\"value\":" + jq(content) + "}}"
  }
}

///|
/// `@别名.成员` → 声明原文；`@别名` → 包目录。
fn hover_pkg_member(uri : String, text : String, off : Int, partial : String) -> String {
  let token = expand_token(text, off, partial)
  if !token.has_prefix("@") {
    return ""
  }
  let sigs = sigs_for(uri)
  match dot_index_cli(token) {
    Some(_) =>
      match sigs.decl_text(token) {
        Some(d) => "```moonbit\n" + d + "\n```"
        None => ""
      }
    None =>
      match sigs.alias_dir(token[1:].to_owned()) {
        Some(d) => "`" + token + "` → `" + d + "`"
        None => ""
      }
  }
}

///|
/// 光标处令牌扩到完整标识符（`ui-co|` → `ui-col`）；扩不到就原文返回。
fn expand_token(text : String, off : Int, tok : String) -> String {
  let a = chars_of_cli(text)
  let is_tok = fn(c : Char) -> Bool {
    is_ident_char(c) || c == '-' || c == '@' || c == ':' || c == '.'
  }
  let mut start = if off < a.length() { off } else { a.length() }
  while start > 0 && is_tok(a[start - 1]) {
    start -= 1
  }
  let mut end = if off < a.length() { off } else { a.length() }
  while end < a.length() && is_tok(a[end]) {
    end += 1
  }
  let t = slice_cli(a, start, end)
  if t.length() > 0 { t } else { tok }
}

///|
fn lsp_definition(uri : String, text : String, line : Int, ch : Int) -> String {
  let off = offset_of(text, line, ch)
  let (ctx, partial, tag) = lsp_context(text, off)
  let sigs = sigs_for(uri)
  let loc = if ctx == "tag" || ctx == "attr" {
    component_loc(sigs, text, off, tag)
  } else {
    symbol_loc(sigs, uri, text, off, partial)
  }
  match loc {
    Some(l) => "[" + loc_json(l) + "]"
    None => "[]"
  }
}

///|
/// 组件标签：内置表 → `@ui.<名>` 的源码；否则按 let 绑定 / 同包裸名找文件。
fn component_loc(
  sigs : @mngkit.Sigs,
  text : String,
  off : Int,
  tag : String,
) -> @mngkit.Loc? {
  let name = expand_token(text, off, tag)
  if name.length() == 0 {
    return None
  }
  if !name.has_prefix("ui-") {
    return match locate_tag(sigs, text, name) {
      Some(p) => Some(@mngkit.loc_new(p, 0))
      None => None
    }
  }
  match @mngkit.builtin_path(name) {
    Some(p) =>
      match sigs.locate_decl(p) {
        Some(l) => Some(l)
        None =>
          match locate_tag(sigs, text, name) {
            Some(f) => Some(@mngkit.loc_new(f, 0))
            None => None
          }
      }
    None => None
  }
}

///|
/// 表达式/脚本站位：`@包.成员` 走包解析；否则页内声明，再退同包函数。
fn symbol_loc(
  sigs : @mngkit.Sigs,
  uri : String,
  text : String,
  off : Int,
  partial : String,
) -> @mngkit.Loc? {
  let token = expand_token(text, off, partial)
  if token.length() == 0 {
    return None
  }
  if token.has_prefix("@") {
    return sigs.locate_decl(token)
  }
  let page = uri_to_path(uri)
  match decl_line_of(text, token) {
    Some(ln) => Some(@mngkit.loc_new(page, ln))
    None => {
      let page_decl = match first_seg(token) {
        Some(head) =>
          match decl_line_of(text, head) {
            Some(ln) => Some(@mngkit.loc_new(page, ln))
            None => None
          }
        None => None
      }
      match page_decl {
        Some(l) => Some(l)
        None => sigs.locate_decl(token)
      }
    }
  }
}

///|
fn loc_json(l : @mngkit.Loc) -> String {
  "{\"uri\":" + jq(path_to_uri(l.path)) + ",\"range\":{\"start\":{\"line\":" +
  l.line.to_string() + ",\"character\":0},\"end\":{\"line\":" + l.line.to_string() +
  ",\"character\":0}}}"
}

///|
/// 处理一条报文；docs 是 uri → 文本的缓存。
fn lsp_handle(docs : Map[String, String], body : String) -> LspOut {
  let parsed = match json_parse(body) {
    Ok(v) => v
    Err(_) => return { reply: None, notify: None, stop: false }
  }
  let meth = match jget(parsed, "method") {
    Some(x) => match json_str(x) {
      Some(m) => m
      None => ""
    }
    None => ""
  }
  let id_json = jget(parsed, "id")
  let id_part = match id_json {
    Some(x) => ",\"id\":" + json_raw(x)
    None => ""
  }
  let respond = fn(result : String) -> String {
    "{\"jsonrpc\":\"2.0\"" + id_part + ",\"result\":" + result + "}"
  }
  match meth {
    "initialize" => {
      let caps = "{\"capabilities\":{\"textDocumentSync\":1," + "\"completionProvider\":{\"triggerCharacters\":[\"<\",\":\",\"@\",\"{\",\" \",\"\\\"\",\".\",\"-\"]},"
      let caps2 = "\"hoverProvider\":true,\"definitionProvider\":true}," + "\"serverInfo\":{\"name\":\"mng_cli\",\"version\":\"0.1.0\"}}"
      lsp_ok(respond(caps + caps2))
    }
    "shutdown" => lsp_ok(respond("null"))
    "exit" => { reply: None, notify: None, stop: true }
    "textDocument/didOpen" => {
      let uri = doc_uri(parsed)
      let text = doc_text_at(parsed, "params/textDocument/text")
      match (uri, text) {
        (Some(u), Some(t)) => {
          let _ = docs.set(u, t)
          { reply: None, notify: Some(lsp_diagnostics(u, t)), stop: false }
        }
        _ => { reply: None, notify: None, stop: false }
      }
    }
    "textDocument/didChange" => {
      let uri = doc_uri(parsed)
      let text = doc_change_text(parsed)
      match (uri, text) {
        (Some(u), Some(t)) => {
          let _ = docs.set(u, t)
          { reply: None, notify: Some(lsp_diagnostics(u, t)), stop: false }
        }
        _ => { reply: None, notify: None, stop: false }
      }
    }
    "textDocument/completion" => {
      let uri = doc_uri(parsed)
      let line = num_path(parsed, "params/position/line")
      let ch = num_path(parsed, "params/position/character")
      match (uri, line, ch) {
        (Some(u), Some(l), Some(c)) => {
          let text = docs.get_or_default(u, "")
          lsp_ok(respond(lsp_completion(u, text, l, c)))
        }
        _ => lsp_ok(respond("{\"isIncomplete\":false,\"items\":[]}"))
      }
    }
    "textDocument/hover" => {
      let uri = doc_uri(parsed)
      let line = num_path(parsed, "params/position/line")
      let ch = num_path(parsed, "params/position/character")
      match (uri, line, ch) {
        (Some(u), Some(l), Some(c)) => {
          let text = docs.get_or_default(u, "")
          lsp_ok(respond(lsp_hover(u, text, l, c)))
        }
        _ => lsp_ok(respond("null"))
      }
    }
    "textDocument/definition" => {
      let uri = doc_uri(parsed)
      let line = num_path(parsed, "params/position/line")
      let ch = num_path(parsed, "params/position/character")
      match (uri, line, ch) {
        (Some(u), Some(l), Some(c)) => {
          let text = docs.get_or_default(u, "")
          lsp_ok(respond(lsp_definition(u, text, l, c)))
        }
        _ => lsp_ok(respond("[]"))
      }
    }
    _ =>
      match id_json {
        Some(_) => lsp_ok(respond("null"))
        None => { reply: None, notify: None, stop: false }
      }
  }
}

///|
fn json_raw(j : LJson) -> String {
  match j {
    LStr(s) => jq(s)
    LNum(v) => v.to_string()
    LBool(b) => if b { "true" } else { "false" }
    LNull => "null"
    LArr(a) => {
      let parts : Array[String] = []
      for x in a {
        parts.push(json_raw(x))
      }
      "[" + parts.join(",") + "]"
    }
    LObj(m) => {
      let parts : Array[String] = []
      for (k, v) in m {
        parts.push(jq(k) + ":" + json_raw(v))
      }
      "{" + parts.join(",") + "}"
    }
  }
}

///|
fn doc_uri(parsed : LJson) -> String? {
  match jpath(parsed, "params/textDocument/uri") {
    Some(x) => json_str(x)
    None => None
  }
}

///|
fn doc_text_at(parsed : LJson, path : String) -> String? {
  match jpath(parsed, path) {
    Some(x) => json_str(x)
    None => None
  }
}

///|
/// didChange（全量同步）：取 contentChanges 最后一条的 text。
fn doc_change_text(parsed : LJson) -> String? {
  match jpath(parsed, "params/contentChanges") {
    Some(arr_json) =>
      match json_arr(arr_json) {
        Some(arr) =>
          if arr.length() == 0 {
            None
          } else {
            match jget(arr[arr.length() - 1], "text") {
              Some(t) => json_str(t)
              None => None
            }
          }
        None => None
      }
    None => None
  }
}

///|
fn num_path(parsed : LJson, path : String) -> Int? {
  match jpath(parsed, path) {
    Some(x) => json_num(x)
    None => None
  }
}

///|
/// lsp 子命令：stdio 循环，直到 exit 或 stdin 关闭。
fn cmd_lsp(_args : Array[String]) -> Int {
  let docs : Map[String, String] = Map([])
  while true {
    let msg = match lsp_read_message() {
      Some(m) => m
      None => break
    }
    let out = lsp_handle(docs, msg)
    match out.reply {
      Some(r) => lsp_send(r)
      None => ()
    }
    match out.notify {
      Some(n) => lsp_send(n)
      None => ()
    }
    if out.stop {
      break
    }
  }
  0
}
