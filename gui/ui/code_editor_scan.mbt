// 代码编辑器的行级增量扫描缓存（proposals/code-stack.md 定案一）。
//
// 每行缓存「行首状态 + tokens + 逐 token 宽」；编辑后按**前缀/后缀行对齐**找
// 变更区间，只重扫中间（后缀行按行数差 delta 映射旧行缓存，进入后缀且行首
// 状态与旧缓存一致即收敛停）。未闭合块注释 / 三引号 / heredoc 下自然退化为
// 「脏段一路重扫到已扫末尾」——正确退化，不许死循环（wbtest 钉）。
//
// 扫描**渐进推进**：扫到哪缓存哪（`scanned` 是已扫末行），首屏只扫可视行
// 附近；跳到未扫区域的首帧把扫描成本顺延到那一跳（万行 ≈ 0.1s，读数见
// experiment/code_editor_bench——构造期整篇预排版 169ms 不可接受，故不做）。
// 行宽按行惰性测量（`laid` 空 = 未量），与 token 缓存同生命周期失效。
//
// 下标口径与 `@input.Editor` 全文一致：UTF-8 字节，`starts[row]` 是行首的
// 全文字节号。

///|
/// 全文按 `\n` 切行，给 (行文本, 行首全文字节号)。空文本也给一行；
/// 尾随 `\n` 的空末行照出（编辑器的插入点要落在那一行上）。
fn split_code_lines(text : String) -> (Array[String], Array[Int]) {
  let b = @utf8.encode(text)
  let n = b.length()
  let ls : Array[String] = []
  let starts : Array[Int] = []
  let mut line_start = 0
  for i = 0; i <= n; i = i + 1 {
    if i == n || b[i].to_int() == 0x0a {
      ls.push(@utf8.decode_lossy(b[line_start:i]))
      starts.push(line_start)
      line_start = i + 1
    }
  }
  (ls, starts)
}

///|
fn state_eq(a : ScanState, b : ScanState) -> Bool {
  match (a, b) {
    (SNormal, SNormal) => true
    (SBlockComment(x), SBlockComment(y)) => x == y
    (STriple(x), STriple(y)) => x == y
    (SHeredoc(x), SHeredoc(y)) => x == y
    _ => false
  }
}

///|
priv struct CodeScan {
  lang : String
  mut text : String
  mut lines : Array[String]
  mut starts : Array[Int]
  // 行首状态：states[row] 是 row 的进入状态，states[row+1] 是它的吐出状态；
  // 只有 [0, scanned+1] 有效，其余是占位值（渐进扫描顺序填充，不跳行）。
  mut states : Array[ScanState]
  mut toks : Array[Array[Token]]
  // 逐 token 宽（与 toks 同下标；空 = 未量）。行宽 = 累加。
  mut laid : Array[Array[Double]]
  // 已扫末行（含），-1 = 一行未扫。
  mut scanned : Int
  mut max_w : Double
  mut max_dirty : Bool
}

///|
fn CodeScan::new(text : String, lang : String) -> CodeScan {
  let (ls, st) = split_code_lines(text)
  let n = ls.length()
  let toks : Array[Array[Token]] = []
  let laid : Array[Array[Double]] = []
  let states : Array[ScanState] = []
  for _ in 0..<n {
    toks.push([])
    laid.push([])
  }
  for _ in 0..<(n + 1) {
    states.push(SNormal)
  }
  {
    lang,
    text,
    lines: ls,
    starts: st,
    states,
    toks,
    laid,
    scanned: -1,
    max_w: 0.0,
    max_dirty: true,
  }
}

///|
fn CodeScan::line_count(self : CodeScan) -> Int {
  self.lines.length()
}

///|
fn CodeScan::line_at(self : CodeScan, row : Int) -> String {
  self.lines[row]
}

///|
/// 行首的全文字节号。
fn CodeScan::start_of(self : CodeScan, row : Int) -> Int {
  self.starts[row]
}

///|
/// 行的 UTF-8 字节长（不含换行符）。
fn CodeScan::len_of(self : CodeScan, row : Int) -> Int {
  if row + 1 < self.starts.length() {
    self.starts[row + 1] - self.starts[row] - 1
  } else {
    @utf8.encode(self.text).length() - self.starts[row]
  }
}

///|
/// 全文字节号 → 行号（二分；末行之后的字节号落在末行）。
fn CodeScan::row_of(self : CodeScan, byte : Int) -> Int {
  let n = self.lines.length()
  let mut lo = 0
  let mut hi = n - 1
  while lo < hi {
    let mid = (lo + hi + 1) / 2
    if self.starts[mid] <= byte {
      lo = mid
    } else {
      hi = mid - 1
    }
  }
  lo
}

///|
/// row 的 token（调用方先 `ensure(row)`）。
fn CodeScan::tokens_of(self : CodeScan, row : Int) -> Array[Token] {
  self.toks[row]
}

///|
/// 全文字节号处的 token 角色（该行已扫才有意义；未扫/无覆盖给 None）。
/// 括号匹配用它跳过字符串/注释里的括号。
fn CodeScan::role_at(self : CodeScan, byte : Int) -> TokenRole? {
  let row = self.row_of(byte)
  if row > self.scanned {
    return None
  }
  let col = byte - self.starts[row]
  for t in self.toks[row] {
    if col >= t.byte_start && col < t.byte_start + t.byte_len {
      return Some(t.role)
    }
  }
  None
}

///|
/// 渐进扫描：把 0..=row 扫齐（从 scanned+1 顺序推进，不跳行）。
fn CodeScan::ensure(self : CodeScan, row : Int) -> Unit {
  let target = row.min(self.lines.length() - 1)
  while self.scanned < target {
    self.scan_row(self.scanned + 1)
  }
}

///|
fn CodeScan::scan_row(self : CodeScan, row : Int) -> Unit {
  let incoming = self.states[row]
  let (tk, next) = scan_line(self.lines[row], self.lang, incoming)
  self.states[row] = incoming
  self.states[row + 1] = next
  self.toks[row] = tk
  self.laid[row] = []
  if row > self.scanned {
    self.scanned = row
  }
}

///|
/// 全文变了：前缀/后缀行对齐后只重扫中段，返回实际重扫行数（文本没变给
/// -1）。0 = 命中前缀/后缀全部复用，一行没扫。
fn CodeScan::sync(self : CodeScan, new_text : String) -> Int {
  if new_text == self.text {
    return -1
  }
  let old_lines = self.lines
  let old_toks = self.toks
  let old_states = self.states
  let old_laid = self.laid
  let old_scanned = self.scanned
  let oldL = old_lines.length()
  let (ls, st) = split_code_lines(new_text)
  let nl = ls.length()
  let minL = oldL.min(nl)
  // 前缀：逐行相同的开头
  let mut p = 0
  while p < minL && old_lines[p] == ls[p] {
    p = p + 1
  }
  // 后缀：逐行相同的结尾（与前缀不重叠）
  let mut s = 0
  while s < minL - p && old_lines[oldL - 1 - s] == ls[nl - 1 - s] {
    s = s + 1
  }
  let delta = nl - oldL
  self.lines = ls
  self.starts = st
  self.text = new_text
  let toks : Array[Array[Token]] = []
  let laid : Array[Array[Double]] = []
  let states : Array[ScanState] = []
  for _ in 0..<nl {
    toks.push([])
    laid.push([])
  }
  for _ in 0..<(nl + 1) {
    states.push(SNormal)
  }
  // 前缀复用（只有已扫区间有缓存可拿）
  let p_end = p.min(old_scanned + 1).min(nl)
  for j in 0..<p_end {
    toks[j] = old_toks[j]
    states[j] = old_states[j]
    laid[j] = old_laid[j]
  }
  // 中段重扫：从 min(p, old_scanned+1) 到已扫末行；进入后缀且「行首状态与
  // 旧行（按 delta 映射）一致」即收敛停——把旧后缀缓存整段搬过来再停
  let mut rescanned = 0
  if old_scanned >= 0 {
    let hi = old_scanned.min(nl - 1)
    let begin = p.min(old_scanned + 1)
    let s_begin = nl - s
    let mut i = begin
    let mut incoming = old_states[begin]
    while i <= hi {
      if i >= s_begin {
        let o = i - delta
        if o >= 0 && o < oldL && state_eq(incoming, old_states[o]) {
          for j = i; j <= hi; j = j + 1 {
            let oj = j - delta
            toks[j] = old_toks[oj]
            states[j] = old_states[oj]
            laid[j] = old_laid[oj]
          }
          states[hi + 1] = old_states[hi - delta + 1]
          break
        }
      }
      let (tk, next) = scan_line(ls[i], self.lang, incoming)
      toks[i] = tk
      states[i] = incoming
      states[i + 1] = next
      laid[i] = []
      rescanned = rescanned + 1
      incoming = next
      i = i + 1
    }
  }
  self.toks = toks
  self.states = states
  self.laid = laid
  self.scanned = old_scanned.min(nl - 1)
  if rescanned > 0 || delta != 0 {
    self.max_dirty = true
  }
  rescanned
}

///|
/// row 的逐 token 宽（惰性测量；先 `ensure(row)`）。
fn CodeScan::measure_row(self : CodeScan, row : Int, font : @text.Font) -> Array[Double] {
  let laid = self.laid[row]
  if laid.length() == 0 {
    let toks = self.toks[row]
    let out : Array[Double] = []
    let mut sum = 0.0
    for t in toks {
      let w = text_width(t.text, font)
      sum = sum + w
      out.push(w)
    }
    self.laid[row] = out
    if sum > self.max_w {
      self.max_w = sum
    }
    out
  } else {
    laid
  }
}

///|
/// 全文最宽行（只数已量过的行；行宽在滚动/编辑中逐行现量，max 随之更新）。
fn CodeScan::max_width(self : CodeScan) -> Double {
  if self.max_dirty {
    let mut m = 0.0
    for row in 0..<self.lines.length() {
      let ws = self.laid[row]
      if ws.length() > 0 {
        let mut sum = 0.0
        for w in ws {
          sum = sum + w
        }
        if sum > m {
          m = sum
        }
      }
    }
    self.max_w = m
    self.max_dirty = false
  }
  self.max_w
}
