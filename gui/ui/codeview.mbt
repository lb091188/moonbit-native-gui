// 代码高亮：多语言分词（tokenize_lang / tokenize_moonbit）与 code_view
// 组件（代码块，逐 token 着色自绘）。构造期逐 token 测宽预排版，on_draw
// 现画；颜色按角色（TokenRole）在绘制期从 `CodeTheme` 现取——默认跟
// `theme_current()`（深浅基底各一套映射），`code_theme` 显式传参可钉死。

///|
/// 代码 token 的着色角色（颜色在绘制期按 `CodeTheme` 现算，随主题走）。
pub(all) enum TokenRole {
  Fg // 普通文本/标点/运算符
  Keyword
  Ty // 类型/构造器（大写开头）
  Call // 函数调用（后随 '('）
  StrLit // 字符串字面量
  NumLit // 数字
  Comment
  LineNo // 行号列（布局内部用，分词不产出）
}

///|
/// 代码高亮的着色单元。`byte_start` / `byte_len` 是它在**本行原文**里的 UTF-8
/// 字节区间（与 `@input.Editor` / `@input.TextLayout` 同口径）：token 连续覆盖
/// 整行（空格、标点各自成词），所以出口按累加回填一次，分词内部不各自计数。
pub(all) struct Token {
  text : String
  role : TokenRole
  mut byte_start : Int32
  mut byte_len : Int32
}

///|
fn tok(text : String, role : TokenRole) -> Token {
  { text, role, byte_start: 0, byte_len: 0, }
}

///|
/// 一行扫描的**行首状态**（跨行构造）：块注释带嵌套深度（rust 允许嵌套，C 系恒 1）、
/// 三引号串带定界符原文（三个双引号或三个单引号）、heredoc 带结束标记。
/// `scan_line` 逐行传播它；未闭合就一路挂到行尾，下一行接着吃——code_editor 的
/// 增量重扫按「行首状态是否与缓存一致」决定收敛停。
pub(all) enum ScanState {
  SNormal
  SBlockComment(Int32)
  STriple(String)
  SHeredoc(String)
}

///|
/// 逐行扫描一行：吃进行首状态，吐出这一行的 token（字节区间已回填）与
/// **下一行的行首状态**。
pub fn scan_line(
  line : String,
  lang : String,
  state : ScanState,
) -> (Array[Token], ScanState) {
  let out : Array[Token] = []
  let next = scan_into(line, lang, state, out)
  let mut b = 0
  for t in out {
    let bl = @utf8.encode(t.text).length()
    t.byte_start = b
    t.byte_len = bl
    b += bl
  }
  (out, next)
}

///|
/// 代码块配色（角色 → 色值）。色值写语义 token 名以外的直接色值也合法
/// （刻意钉死的场景）；默认由 `code_theme_of` 从 `Theme` 派生。
pub(all) struct CodeTheme {
  bg : String
  text : String
  keyword : String
  ty : String
  call : String
  str_lit : String
  num_lit : String
  comment : String
  line_no : String
}

///|
/// 从主题派生代码配色：按 `bg_panel` 亮度判深浅基底，两套映射——
/// 深：底=面板底、亮字；浅：底=斑马纹（比面板沉一档的代码面板底）。
/// 角色→token：关键字=主色、调用=主色悬停、类型=警示、字符串=成功、
/// 数字=危险、注释/行号=次要文字；普通文本=主要文字。
pub fn code_theme_of(t : @theme.Theme) -> CodeTheme {
  let dark = match @theme.parse_hex(t.bg_panel) {
    Some((r, g, b)) =>
      (0.299 * r.to_double() + 0.587 * g.to_double() + 0.114 * b.to_double()) /
      255.0 <
      0.5
    None => false
  }
  {
    bg: if dark {
      t.bg_panel
    } else {
      t.fill_zebra
    },
    text: t.text_primary,
    keyword: t.primary,
    ty: t.warning,
    call: t.primary_hover,
    str_lit: t.success,
    num_lit: t.danger,
    comment: t.text_secondary,
    line_no: t.text_secondary,
  }
}

///|
/// 当前主题的代码配色（绘制期现取的默认源）。
pub fn code_theme_current() -> CodeTheme {
  code_theme_of(@theme.theme_current())
}

///|
/// 角色 → 色值。
fn role_color(ct : CodeTheme, role : TokenRole) -> String {
  match role {
    Fg => ct.text
    Keyword => ct.keyword
    Ty => ct.ty
    Call => ct.call
    StrLit => ct.str_lit
    NumLit => ct.num_lit
    Comment => ct.comment
    LineNo => ct.line_no
  }
}

///|
/// ASCII 小写(关键字大小写不敏感比较用)。
fn ascii_lower(s : String) -> String {
  let out = Ref(StringBuilder())
  for ch in s {
    let c = ch.to_int()
    if c >= 65 && c <= 90 {
      out.val.write_char((c + 32).unsafe_to_char())
    } else {
      out.val.write_char(ch)
    }
  }
  out.val.to_string()
}

///|
/// 语言关键字集与行注释前缀(代码高亮通用参数表)。
fn lang_keywords(lang : String) -> (Array[String], String) {
  match lang {
    "js" | "ts" =>
      (
        [
          "function", "const", "let", "var", "if", "else", "return", "class", "extends",
          "import", "export", "new", "typeof", "await", "async", "for", "while",
          "switch", "case", "break", "default", "try", "catch", "throw", "this",
          "super", "null", "undefined", "true", "false", "static", "get", "set",
          "of", "in", "yield", "delete", "void",
        ],
        "//",
      )
    "python" =>
      (
        [
          "def", "class", "import", "from", "if", "elif", "else", "for", "while",
          "in", "not", "and", "or", "lambda", "return", "None", "True", "False",
          "self", "pass", "with", "as", "try", "except", "finally", "raise", "yield",
          "global", "del", "assert", "break", "continue", "is",
        ],
        "#",
      )
    "rust" =>
      (
        [
          "fn", "let", "mut", "pub", "struct", "enum", "impl", "trait", "use", "mod",
          "match", "if", "else", "loop", "while", "for", "in", "return", "Some",
          "None", "Ok", "Err", "self", "crate", "move", "ref", "where", "async",
          "await", "dyn", "as", "break", "const", "continue", "static", "type", "unsafe",
          "true", "false",
        ],
        "//",
      )
    "c" =>
      (
        [
          "include", "define", "typedef", "struct", "union", "enum", "static", "const",
          "int", "void", "char", "float", "double", "return", "if", "else", "for",
          "while", "switch", "case", "break", "default", "sizeof", "long", "short",
          "unsigned", "signed", "extern", "goto", "do",
        ],
        "//",
      )
    "go" =>
      (
        [
          "func", "package", "import", "var", "const", "type", "struct", "interface",
          "map", "chan", "go", "defer", "if", "else", "for", "range", "return", "nil",
          "break", "continue", "switch", "case", "default", "select", "fallthrough",
        ],
        "//",
      )
    "bash" =>
      (
        [
          "echo", "if", "then", "else", "fi", "for", "do", "done", "while", "case",
          "esac", "function", "local", "export", "return", "exit", "read", "shift",
          "in",
        ],
        "#",
      )
    "sql" =>
      (
        [
          "select", "from", "where", "insert", "into", "values", "update", "set",
          "delete", "create", "table", "join", "left", "right", "inner", "outer",
          "on", "group", "order", "by", "limit", "as", "and", "or", "not", "null",
          "distinct", "count", "sum", "avg", "primary", "key", "foreign", "references",
          "alter", "drop", "index", "view",
        ],
        "--",
      )
    _ =>
      // MoonBit 全量关键字(moonc 内置词表对齐):声明/可见性/属性/控制流/
      // 模式与所有权/异步/字面量
      (
        [
          "fn", "let", "mut", "const", "struct", "enum", "trait", "impl", "type",
          "typealias", "derive", "pub", "priv", "open", "override", "readonly", "extern",
          "native", "test", "async", "await", "if", "else", "for", "in", "while",
          "loop", "match", "when", "where", "return", "break", "continue", "as",
          "is", "move", "root", "unsafe", "object", "true", "false",
        ],
        "//",
      )
  }
}

///|
/// 通用语言分词:字符串("…"/'…')、行注释(按语言)、()[]{},;: 标点独立、
/// 运算符连续成词,其余连续非空白为一个词;词再经 classify_word 分为
/// 关键字/类型/函数调用/数字/普通文本。tokenize_moonbit 即 moonbit 特化。
pub fn tokenize_lang(line : String, lang : String) -> Array[Token] {
  let (ts, _st) = scan_line(line, lang, SNormal)
  ts
}

///|
/// 扫描主体：从 `state` 起吃这一行，token 追加进 `out`，返回下一行的行首状态。
fn scan_into(
  line : String,
  lang : String,
  state : ScanState,
  out : Array[Token],
) -> ScanState {
  let (keywords, comment_prefix) = lang_keywords(lang)
  let shape = lang_shape(lang)
  let cs : Array[Char] = []
  for ch in line {
    cs.push(ch)
  }
  let n = cs.length()
  let buf = Ref(StringBuilder())
  // 0 未开始,1 词(标识符/限定名/数字),2 运算符串
  let kind = Ref(0)
  // 词着色需要 lookahead:词后紧跟 '(' 视为函数调用
  fn flush(next : Char) -> Unit {
    let s = buf.val.to_string()
    buf.val = StringBuilder()
    let is_word = kind.val == 1
    kind.val = 0
    if s.length() > 0 {
      out.push(classify_word(s, keywords, is_word && next == '('))
    }
  }

  // —— 行首还挂在跨行构造里：先把这一段的正文吃掉，闭合了才接着正常扫
  let mut i = 0
  let mut heredoc_open : String? = None
  match state {
    SBlockComment(depth) =>
      if depth > 0 {
        let (closed, ni, d2) = eat_block_body(
          cs,
          shape.open,
          shape.close,
          shape.nested,
          0,
          depth,
        )
        out.push(tok(chars_str(cs, 0, ni), Comment))
        if !closed {
          return SBlockComment(d2)
        }
        i = ni
      } else {
        ()
      }
    STriple(delim) => {
      let (closed, ni, _d) = eat_block_body(cs, delim, delim, false, 0, 1)
      out.push(tok(chars_str(cs, 0, ni), StrLit))
      if !closed {
        return STriple(delim)
      }
      i = ni
    }
    SHeredoc(tag) => {
      // heredoc 正文整段按字符串着色；本行内容等于结束标记则吃完回正常
      if n > 0 {
        out.push(tok(line, StrLit))
      }
      return if line.trim() == tag { SNormal } else { SHeredoc(tag) }
    }
    SNormal => ()
  }
  while i < n {
    let ch = cs[i]
    let c = ch.to_int()
    if shape.block && starts_at(cs, i, shape.open) {
      // 块注释：吃到闭记号；没闭就挂着走完这一行
      flush('/')
      let (closed, ni, d2) = eat_block_open(
        cs,
        shape.open,
        shape.close,
        shape.nested,
        i,
      )
      out.push(tok(chars_str(cs, i, ni), Comment))
      if !closed {
        return SBlockComment(d2)
      }
      i = ni
      continue
    } else if triple_at(shape, cs, i) is Some(delim) {
      // 三引号串（python）：闭合在本行内就是一段字符串，否则挂着跨行
      flush('"')
      let (closed, ni) = eat_triple_open(cs, delim, i)
      out.push(tok(chars_str(cs, i, ni), StrLit))
      if !closed {
        return STriple(delim)
      }
      i = ni
      continue
    } else if ch == '"' || ch == '\'' {
      // 字符串字面量:开引号起到闭引号整段
      flush(ch)
      let s = StringBuilder()
      s.write_char(ch)
      i = i + 1
      while i < n {
        s.write_char(cs[i])
        if cs[i] == ch {
          break
        }
        i = i + 1
      }
      out.push(tok(s.to_string(), StrLit))
    } else if ch == '/' &&
      i + 1 < n &&
      cs[i + 1] == '/' &&
      comment_prefix == "//" {
      flush('/')
      let comment = StringBuilder()
      while i < n {
        comment.write_char(cs[i])
        i = i + 1
      }
      out.push(tok(comment.to_string(), Comment))
      break
    } else if ch == '#' && comment_prefix == "#" {
      flush('#')
      let comment = StringBuilder()
      while i < n {
        comment.write_char(cs[i])
        i = i + 1
      }
      out.push(tok(comment.to_string(), Comment))
      break
    } else if ch == '-' &&
      i + 1 < n &&
      cs[i + 1] == '-' &&
      comment_prefix == "--" {
      flush('-')
      let comment = StringBuilder()
      while i < n {
        comment.write_char(cs[i])
        i = i + 1
      }
      out.push(tok(comment.to_string(), Comment))
      break
    } else if c == 32 {
      flush(ch)
      out.push(tok(" ", Fg))
    } else {
      // bash heredoc：`<<TAG` 记下结束标记（字符照旧着色，本行扫完才挂状态，
      // 正文从下一行起）
      if shape.heredoc && ch == '<' && i + 1 < n && cs[i + 1] == '<' {
        match heredoc_tag(cs, i) {
          Some(tag) => heredoc_open = Some(tag)
          None => ()
        }
      }
      let ident = (c >= 65 && c <= 90) ||
        (c >= 97 && c <= 122) ||
        (c >= 48 && c <= 57) ||
        c == 95 ||
        c == 64 ||
        c == 36 ||
        c > 127
      // '.' 在词内续词(小数/限定名),但后随 '.'(区间符 ..)时断开,
      // 让前导数字独立着色;不在词内时归运算符
      let dot_in_word = ch == '.' &&
        kind.val == 1 &&
        !(i + 1 < n && cs[i + 1] == '.')
      if (ident || dot_in_word) && kind.val != 2 {
        buf.val.write_char(ch)
        kind.val = 1
      } else if is_op_char(ch) && kind.val != 1 {
        buf.val.write_char(ch)
        kind.val = 2
      } else {
        // 词与运算符串互切:先冲刷再按新词性开串;()[]{},;: 标点单字符
        flush(ch)
        if !ident && !dot_in_word && !is_op_char(ch) {
          out.push(tok(char_to_string(ch), Fg))
        } else if ident || dot_in_word {
          buf.val.write_char(ch)
          kind.val = 1
        } else {
          buf.val.write_char(ch)
          kind.val = 2
        }
      }
    }
    i = i + 1
  }
  flush(' ')
  match heredoc_open {
    Some(tag) => SHeredoc(tag)
    None => SNormal
  }
}

///|
/// 扫描用的语言形态：块注释开/闭记号与是否嵌套、heredoc 是否可用、三引号定界符。
priv struct ScanShape {
  block : Bool
  open : String
  close : String
  nested : Bool
  heredoc : Bool
  triples : Array[String]
}

///|
/// 三引号的两种定界符（三个双引号 / 三个单引号）。
fn quote_runs() -> Array[String] {
  let d = "\""
  let q = "'"
  [d + d + d, q + q + q]
}

///|
fn lang_shape(lang : String) -> ScanShape {
  match lang {
    // C 系块注释：开 /* 闭 */，不嵌套
    "moonbit" | "js" | "ts" | "c" | "go" | "java" | "sql" =>
      {
        block: true,
        open: "/*",
        close: "*/",
        nested: false,
        heredoc: false,
        triples: [],
      }
    // rust 的块注释允许嵌套（/* /* */ */），闭合要跟着深度走
    "rust" =>
      {
        block: true,
        open: "/*",
        close: "*/",
        nested: true,
        heredoc: false,
        triples: [],
      }
    // python 没有块注释，跨行靠三引号串
    "python" =>
      {
        block: false,
        open: "",
        close: "",
        nested: false,
        heredoc: false,
        triples: quote_runs(),
      }
    // shell：heredoc（结束标记在行首，允许 `<<-` 缩进档）
    "bash" =>
      {
        block: false,
        open: "",
        close: "",
        nested: false,
        heredoc: true,
        triples: [],
      }
    _ =>
      {
        block: true,
        open: "/*",
        close: "*/",
        nested: false,
        heredoc: false,
        triples: [],
      }
  }
}

///|
/// cs[at..] 是否以 `pat` 开头（越界即 false）。
fn starts_at(cs : Array[Char], at : Int32, pat : String) -> Bool {
  let pc = pat.to_array()
  let m = pc.length()
  if m == 0 || at + m > cs.length() {
    return false
  }
  let mut ok = true
  for k in 0..<m {
    if cs[at + k] != pc[k] {
      ok = false
    }
  }
  ok
}

///|
/// [from, to) 区间的字符拼回字符串（越界夹到行尾）。
fn chars_str(cs : Array[Char], from : Int32, to : Int32) -> String {
  let b = StringBuilder()
  let hi = to.min(cs.length())
  let mut i = from
  while i < hi {
    b.write_char(cs[i])
    i += 1
  }
  b.to_string()
}

///|
/// 开记号**已吃掉**的块注释正文：从 `start` 找闭记号（嵌套语言遇开记号加深），
/// 返回 (是否闭合, 走到哪——闭记号之后或行尾)。
fn eat_block_body(
  cs : Array[Char],
  op : String,
  cl : String,
  nested : Bool,
  start : Int32,
  depth : Int32,
) -> (Bool, Int32, Int32) {
  let n = cs.length()
  let mut i = start
  let mut d = depth
  while i < n {
    if starts_at(cs, i, cl) {
      i += cl.to_array().length()
      d -= 1
      if d <= 0 {
        return (true, i, 0)
      }
    } else if nested && starts_at(cs, i, op) {
      i += op.to_array().length()
      d += 1
    } else {
      i += 1
    }
  }
  (false, n, d)
}

///|
/// 行内新开的块注释：`at` 指向开记号首字符。返回 (是否闭合, 新下标, 剩余深度)。
fn eat_block_open(
  cs : Array[Char],
  op : String,
  cl : String,
  nested : Bool,
  at : Int32,
) -> (Bool, Int32, Int32) {
  let (closed, ni, d) = eat_block_body(
    cs,
    op,
    cl,
    nested,
    at + op.to_array().length(),
    1,
  )
  (closed, ni, d)
}

///|
/// 行内命中的三引号定界符：`at` 指向首字符，没有匹配给 None。
fn triple_at(sh : ScanShape, cs : Array[Char], at : Int32) -> String? {
  for d in sh.triples {
    if starts_at(cs, at, d) {
      return Some(d)
    }
  }
  None
}

///|
/// 三引号串：`at` 指向定界符首字符，吃到同名定界符为止；没闭就走到行尾。
fn eat_triple_open(
  cs : Array[Char],
  delim : String,
  at : Int32,
) -> (Bool, Int32) {
  let (closed, ni, _d) = eat_block_body(
    cs,
    delim,
    delim,
    false,
    at + delim.to_array().length(),
    1,
  )
  (closed, ni)
}

///|
/// bash heredoc 的结束标记：`at` 指向 `<<`，跳过可选 `-` 与可选引号，取后面的
/// 标识符串；取不到给 None。
fn heredoc_tag(cs : Array[Char], at : Int32) -> String? {
  let n = cs.length()
  let mut i = at + 2
  if i < n && cs[i] == '-' {
    i += 1
  }
  if i < n {
    let q = cs[i].to_int()
    if q == 34 || q == 39 || q == 96 {
      i += 1
    }
  }
  let b = StringBuilder()
  while i < n {
    let c = cs[i].to_int()
    let word = (c >= 65 && c <= 90) ||
      (c >= 97 && c <= 122) ||
      (c >= 48 && c <= 57) ||
      cs[i] == '_'
    if !word {
      break
    }
    b.write_char(cs[i])
    i += 1
  }
  let tag = b.to_string()
  if tag.length() == 0 {
    None
  } else {
    Some(tag)
  }
}

///|
/// 运算符字符(连续出现时并成一个词,如 ->、<=、..<、&&、@ 无关的 '.')。
fn is_op_char(ch : Char) -> Bool {
  match ch {
    '+'
    | '-'
    | '*'
    | '/'
    | '%'
    | '<'
    | '>'
    | '='
    | '!'
    | '&'
    | '|'
    | '?'
    | '^'
    | '~'
    | '#'
    | '\\'
    | '`'
    | '.' => true
    _ => false
  }
}

///|
fn char_to_string(ch : Char) -> String {
  let b = StringBuilder()
  b.write_char(ch)
  b.to_string()
}

///|
pub fn tokenize_moonbit(line : String) -> Array[Token] {
  tokenize_lang(line, "moonbit")
}

///|
/// 词分类着色:关键字(大小写不敏感);纯数字;@ 限定名按最后一段、
/// 裸标识符按首字符,大写开头视为类型/构造器;后随 '(' 的小写标识符
/// 视为函数调用;其余普通文本。
fn classify_word(
  word : String,
  keywords : Array[String],
  is_call : Bool,
) -> Token {
  let lowered = ascii_lower(word)
  for k in keywords {
    if ascii_lower(k) == lowered {
      return tok(word, Keyword)
    }
  }
  // 着色主体:@ 限定名取最后 '.' 段,裸词取整词
  let mut head = word
  if word.unsafe_get(0).to_int() == 64 {
    let segs : Array[StringView] = word.split(".").collect()
    let last = segs[segs.length() - 1]
    if last.length() > 0 {
      head = last.to_owned()
    }
  }
  let c0 = head.unsafe_get(0).to_int()
  if c0 >= 65 && c0 <= 90 {
    return tok(word, Ty)
  }
  let is_num = word.length() > 0
  for i in 0..<word.length() {
    let c = word.unsafe_get(i).to_int()
    if !((c >= 48 && c <= 57) || c == 46) {
      if is_call && !(c0 >= 48 && c0 <= 57) {
        return tok(word, Call)
      }
      return tok(word, Fg)
    }
  }
  if is_num {
    return tok(word, NumLit)
  }
  tok(word, Fg)
}

// ---------------------------------------------------------------------------
// 组件层
// ---------------------------------------------------------------------------

///|
/// 代码高亮视图（代码块，配色跟主题——深浅基底各一套映射，深浅切换与
/// 换主色后重绘即随）：构造期逐 token 分词并测宽（等宽字体），on_draw
/// 逐段按 `CodeTheme` 现取色；行首可选行号列。
/// `code_theme` 显式传参可钉死一套配色（刻意场景，如截图比对）；缺省跟
/// `theme_current()`。
/// 高度按行数、宽度按最长行自适应（内容不变则尺寸恒定）。
/// 代码行不可折，属「不可折内容」——组件自带横向滚动视口（与表格同口径），
/// 调用方直接摆进容器即可，不必再包 `scroll_view`。
pub fn code_view(
  lines : Array[String],
  lang~ : String = "moonbit",
  font_size~ : Double = 13.0,
  line_numbers~ : Bool = false,
  /// 让代码可用鼠标选中复制（只读：拖选、双击选词、Shift+点击扩选、
  /// Ctrl/Cmd+C 与右键复制）；行号列不进选区，跨行复制按 \n 拼。
  selectable~ : Bool = false,
  /// 代码块顶部留一条头部区，指针悬浮时右上显示「复制」小按钮：点击把全文
  ///（按 \n 拼）写系统剪贴板。缺省关（头部区不占高，现有布局零变化）。
  copyable~ : Bool = false,
  /// 复制按钮点击后回调（参数=剪贴板是否写成功）；toast 回显走它接。
  on_copied~ : (Bool) -> Unit = fn(_ok : Bool) -> Unit { () },
  code_theme? : CodeTheme,
  handle~ : (@widget.Widget) -> Unit = default_handle,
) -> @widget.Node {
  let font = @text.Font::new("Monospace", font_size)
  // 预排版:逐 token 测宽(分词与测量一次完成,重绘零分词开销);颜色角色
  // 留到绘制期解析,主题切换后重绘即随
  let line_h = match @text.line_height_font(font) {
    Some(h) => h.to_double() + 5.0
    None => font_size * 1.7
  }
  let digit_w = text_width("8", font)
  // 行号位数下限 2：与 code_editor 同一口径，位数不同时左右边距才对得齐
  let digits = lines.length().to_string().length().max(2)
  let num_off = if line_numbers {
    digit_w * digits.to_double() + 8.0
  } else {
    0.0
  }
  // 每行 (文本, 角色, x, 宽) 的预排版表
  let laid : Array[Array[(String, TokenRole, Double, Double)]] = []
  let mut max_line_w = 0.0
  // 行首状态顺着行走：块注释 / 三引号串 / heredoc 从此不再按行各扫各的
  let scan_state : Ref[ScanState] = Ref(SNormal)
  for idx, line in lines {
    let segs : Array[(String, TokenRole, Double, Double)] = []
    let mut x = num_off
    if line_numbers {
      let num_txt = (idx + 1).to_string()
      let pad = StringBuilder()
      for _i in 0..<(digits - num_txt.length()) {
        pad.write_char(' ')
      }
      let num_str = pad.to_string() + num_txt
      let nw = text_width(num_str, font)
      // 预排版 x=0：绘制期统一 +16，行号落点与 code_editor 同在 16
      segs.push((num_str, LineNo, 0.0, nw))
    }
    let (toks, next_state) = scan_line(line, lang, scan_state.val)
    scan_state.val = next_state
    for tok in toks {
      let w = text_width(tok.text, font)
      segs.push((tok.text, tok.role, x, w))
      x = x + w
    }
    if x > max_line_w {
      max_line_w = x
    }
    laid.push(segs)
  }
  let content_w = max_line_w + 24.0
  // copyable 时顶部多留一条 20px 头部区（悬浮出复制按钮的悬浮区），布局其余不变
  let top_pad = if copyable { 34.0 } else { 14.0 }
  // 几何口径与 code_editor 同一套（观感统一，两个文件注释互指）：
  // 顶部 14（copyable 时 34 头部区）；行号左缘 16（预排版 0 + 绘制偏移 16）；
  // 代码文字左缘 = 16 + 行号位宽 + 8（无行号 16）；内容右留白 8。
  let view_h = line_h * laid.length().to_double() + top_pad + 14.0
  // 选区参照系：全文 = 各行按 `\n` 拼接，`line_off[i]` 是第 i 行行首的全局字节号。
  // 行与行之间的换行字节算在「行外」——高亮不铺它，但跨行复制天然带 \n。
  let line_off : Array[Int32] = []
  let joined = StringBuilder()
  let mut acc = 0
  for i, l in lines {
    line_off.push(acc)
    let _ = joined.write_string(l)
    acc = acc + @utf8.encode(l).length()
    if i < lines.length() - 1 {
      let _ = joined.write_string("\n")
      acc = acc + 1
    }
  }
  // 文本左缘：行号列宽 + 绘制期的 16px 内缩（与 `seg.2 + 16.0` 同一式）
  let text_l = num_off + 16.0
  let line_measure = fn(t : String, from : Int32, to : Int32) -> Double {
    text_width(byte_slice(t, from, to), font)
  }
  // 单行几何：pad 与 offset_y 都取文本左缘，于是 rects 的 y 落回 0（行原点自己加）、
  // hit 的定行不受纵向影响
  let one_line_layout = fn(line : String) -> @input.TextLayout {
    @input.TextLayout::build(
      line,
      1000000.0,
      line_measure,
      line_h,
      pad=text_l,
      offset_y=text_l,
    )
  }
  let st = if selectable {
    let ed = @input.Editor::new()
    ed.set_text(joined.to_string())
    Some(sel_new_state(ed))
  } else {
    None
  }
  let canvas = @widget.node_of_new(fn(w : @widget.Widget) -> @widget.Widget {
    watch_theme()
    // 宽 = max(容器宽, 最长行)：代码行不可折，比容器窄时**铺满容器**（底色条
    // 不断在最长行处），比容器宽时交给自带视口横滚。高度 = 行数,与宽无关。
    w.node.set_width(@yoga.percent(100.0))
    w.node.set_min_width(@yoga.fixed(content_w))
    w.node.set_height(@yoga.fixed(view_h))
    match st {
      Some(state) => {
        let cid = w.id
        w.cursor = @widget.CURSOR_TEXT
        w.on_pointer = Some(fn(
          self : @widget.Widget,
          ev : @widget.PointerEvent,
        ) -> Bool {
          sel_pointer(self, ev, state, fn(x : Double, y : Double) -> Int32 {
            let n = lines.length()
            if n == 0 {
              return 0
            }
            let row = ((y - top_pad) / line_h)
              .floor()
              .to_int()
              .clamp(min=0, max=n - 1)
            let col = one_line_layout(lines[row]).hit(x, line_h * 0.5)
            state.ed.floor_boundary(line_off[row] + col)
          })
        })
        sel_states.val.set(cid, state)
        w.on_discard = Some(fn(self : @widget.Widget) -> Unit {
          let _ = sel_states.val.remove(self.id)
          @widget.text_sel_release(self.id)
        })
      }
      None => ()
    }
    w.on_draw = Some(fn(
      _self : @widget.Widget,
      p : @render.Painter,
      r : @base.Rect,
    ) -> Unit {
      // 配色：显式传了 code_theme 钉死；否则绘制期跟当前主题（深浅/换主色随动）
      let ct = match code_theme {
        Some(c) => c
        None => code_theme_current()
      }
      p.set_fill_color(ct.bg)
      let rad = @theme.radius_card()
      if rad > 0.0 {
        p.fill_round_rect(0.0, 0.0, r.w, r.h, rad)
      } else {
        p.fill_rect(0.0, 0.0, r.w, r.h)
      }
      // 1px 描边与页面底分层（层次走「底色 + border」，见设计规则四）
      let sty = @style.style_for(_self)
      p.set_stroke_color(
        @style.color_of(sty.border_color, @theme.theme_border()),
      )
      p.set_line_width(@style.number_of(sty.border_width, 1.0))
      if rad > 0.0 {
        p.round_rect_path(0.5, 0.5, r.w - 1.0, r.h - 1.0, rad)
        p.stroke()
      } else {
        p.stroke_rect(0.0, 0.0, r.w, r.h)
      }
      match st {
        Some(state) =>
          match state.ed.selection() {
            Some((a, b)) => {
              let mut yy = top_pad
              for ri, l in lines {
                let g = line_off[ri]
                let gl = g + @utf8.encode(l).length()
                let lo = a.max(g)
                let hi = b.min(gl)
                if hi > lo {
                  p.set_fill_color(@theme.theme_primary_light())
                  for rc in one_line_layout(l).rects(lo - g, hi - g) {
                    p.fill_rect(rc.x, yy + rc.y, rc.w.max(1.0), line_h)
                  }
                }
                yy = yy + line_h
              }
            }
            None => ()
          }
        None => ()
      }
      let mut y = top_pad
      for segs in laid {
        for seg in segs {
          let _ = @text.draw_box_at(
            p,
            seg.2 + 16.0,
            y,
            seg.3 + 4.0,
            line_h,
            seg.0,
            font,
            role_color(ct, seg.1),
            align=@text.Start,
            valign=@text.Center,
            wrap=false,
          )
        }
        y = y + line_h
      }
    })
    handle(w)
    w
  })
  // 自带横滚视口：宽跟随容器（flex 1，摆进任何容器都占满行宽），高即内容高
  // （纵向不滚），代码比容器宽时底缘出横条
  scroll_view([canvas], ScrollState::new(), height=view_h, hscroll=true, handle=fn(
    v : @widget.Widget,
  ) -> Unit {
    v.node.set_width(@yoga.percent(100.0))
    // 复制按钮：绝对定位钉在视口右上（头部区内），悬浮显形——与滚动条
    // 同一套「视口的浮层子件」形态。self-draw 不用 button 组件：显隐是
    // 「视口悬停」驱动的绘制态，不是布局态。
    if copyable {
      let label = @i18n.t_or("gui.ui.edit.copy", "复制")
      let btn_font = @text.Font::new("", 12.0)
      let full = joined.to_string()
      let bw = text_width(label, btn_font) + 16.0
      let btn = @widget.Widget::new()
      btn.node.set_position(@yoga.Absolute)
      btn.node.set_top(@yoga.fixed(5.0))
      btn.node.set_right(@yoga.fixed(8.0))
      btn.node.set_width(@yoga.fixed(bw))
      btn.node.set_height(@yoga.fixed(20.0))
      btn.cursor = @widget.CURSOR_HAND
      btn.on_draw = Some(fn(
        self : @widget.Widget,
        p : @render.Painter,
        r : @base.Rect,
      ) -> Unit {
        // 指针在视口内（或就在按钮上）才显形；平时头部区留白
        if !(v.hovered || self.hovered) {
          return
        }
        let hot = self.hovered
        if hot {
          p.set_fill_color(@theme.theme_fill_hover())
          let rad = (r.h / 2.0).min(4.0)
          p.fill_round_rect(0.0, 0.0, r.w, r.h, rad)
        }
        let _ = @text.draw_box_at(
          p,
          0.0,
          0.0,
          r.w,
          r.h,
          label,
          btn_font,
          @theme.theme_text_secondary(),
          align=@text.Center,
          valign=@text.Center,
          wrap=false,
        )
      })
      btn.on_pointer = Some(fn(
        _self : @widget.Widget,
        ev : @widget.PointerEvent,
      ) -> Bool {
        match ev.kind {
          @widget.PointerKind::Down => {
            let ok = @sys.clipboard_set_text(full)
            on_copied(ok)
            @widget.invalidate()
            true
          }
          _ => false
        }
      })
      v.append_child(btn)
    }
  })
}
