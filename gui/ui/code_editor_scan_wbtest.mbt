// CodeScan（行级增量扫描缓存）回归：跨行状态传播、字节偏移口径、前缀/后缀
// 对齐的重扫收敛、未闭合构造的正确退化、渐进扫描边界。全走包内白盒。

///|
/// 角色序列里是否有目标角色（TokenRole 不 derive Eq，走 role_is）。
fn scan_roles_have(roles : Array[TokenRole], want : TokenRole) -> Bool {
  for r in roles {
    if role_is(r, want) {
      return true
    }
  }
  false
}

///|
/// 收集一行的角色序列。
fn scan_roles(cs : CodeScan, row : Int) -> Array[TokenRole] {
  let out : Array[TokenRole] = []
  for t in cs.toks[row] {
    out.push(t.role)
  }
  out
}

///|
/// 行内 token 字节区间累加 == 行 UTF-8 长；行首字节号首尾衔接。
fn scan_offsets_ok(cs : CodeScan) -> Bool {
  for row in 0..<cs.line_count() {
    let mut sum = 0
    for t in cs.toks[row] {
      if t.byte_len <= 0 {
        return false
      }
      sum = sum + t.byte_len
    }
    if sum != cs.len_of(row) {
      return false
    }
    if row + 1 < cs.line_count() &&
      cs.start_of(row + 1) != cs.start_of(row) + cs.len_of(row) + 1 {
      return false
    }
  }
  true
}

///|
fn scan_lines(n : Int) -> String {
  let sb = StringBuilder()
  for i in 0..<n {
    sb.write_string("let v\{i} = \{i} // 行注 \{i}")
    sb.write_char('\n')
  }
  sb.to_string()
}

///|
test "跨行块注释状态传播：整段 Comment、闭合行接正常 token" {
  let cs = CodeScan::new("let a = 1\n/* 第一行\n第二行 */ let b = 2\nlet c = 3\n", "moonbit")
  cs.ensure(cs.line_count() - 1)
  assert_eq(cs.line_count(), 5)
  assert_eq(cs.line_at(0), "let a = 1")
  assert_eq(cs.line_at(4), "")
  // 未闭合行整行注释
  for r in scan_roles(cs, 1) {
    assert_true(role_is(r, Comment))
  }
  // 闭合行：注释段在前，后面接正常 token（let 是关键字）
  let roles = scan_roles(cs, 2)
  assert_true(role_is(roles[0], Comment))
  assert_true(scan_roles_have(roles, Keyword))
  assert_true(scan_offsets_ok(cs))
}

///|
test "rust 嵌套块注释按深度闭合" {
  let cs = CodeScan::new("/* /* a */ still */\nlet x = 1\n", "rust")
  cs.ensure(cs.line_count() - 1)
  for r in scan_roles(cs, 0) {
    assert_true(role_is(r, Comment))
  }
  assert_true(scan_roles_have(scan_roles(cs, 1), Keyword))
}

///|
test "python 三引号与 bash heredoc 跨行状态" {
  let py = CodeScan::new("x = \"\"\"abc\ndef\n\"\"\"; y = 2\nz = 3\n", "python")
  py.ensure(py.line_count() - 1)
  for r in scan_roles(py, 1) {
    assert_true(role_is(r, StrLit))
  }
  // 闭合行：三引号串之后接正常 token
  assert_true(scan_roles_have(scan_roles(py, 2), StrLit))
  assert_true(scan_offsets_ok(py))
  let sh = CodeScan::new("cat <<EOF\nhello\nEOF\necho done\n", "bash")
  sh.ensure(sh.line_count() - 1)
  for r in scan_roles(sh, 1) {
    assert_true(role_is(r, StrLit))
  }
  assert_true(scan_roles_have(scan_roles(sh, 3), Keyword))
}

///|
test "字节口径：多字节行 start/len 与 row_of" {
  let cs = CodeScan::new("中文行\nsecond\n", "moonbit")
  assert_eq(cs.start_of(1), 10) // 三个中文字 9 字节 + \n
  assert_eq(cs.len_of(0), 9)
  assert_eq(cs.row_of(0), 0)
  assert_eq(cs.row_of(9), 0) // 换行符本身属上一行
  assert_eq(cs.row_of(10), 1)
  assert_eq(cs.line_count(), 3) // 尾随 \n 的空末行
  assert_eq(cs.row_of(9999), 2) // 越界落末行
  cs.ensure(cs.line_count() - 1)
  assert_true(scan_offsets_ok(cs))
}

///|
test "渐进扫描：ensure 到哪扫到哪，跳转后状态链不断" {
  let cs = CodeScan::new(scan_lines(100), "moonbit")
  cs.ensure(2)
  assert_eq(cs.scanned, 2)
  assert_eq(cs.toks[50].length(), 0) // 未扫行为空缓存
  // 直接编辑第 99 行（已扫区间外）：缓存区无脏行，重扫 0，随后 ensure 补扫
  let old = cs.text
  let lines = old
  let _ = lines
  let nl = cs_lines_replace(cs.text, 99, "let edited = true")
  assert_eq(cs.sync(nl), 0)
  cs.ensure(99)
  assert_eq(cs.scanned, 99)
  assert_eq(cs.line_at(99), "let edited = true")
  assert_true(cs.toks[99].length() > 0)
  assert_true(scan_offsets_ok(cs))
}

///|
/// 把全文第 row 行换成 text（测试助手：按行重拼）。
fn cs_lines_replace(text : String, row : Int, repl : String) -> String {
  let sb = StringBuilder()
  let b = @utf8.encode(text)
  let mut cur = 0
  let mut at = 0
  let n = b.length()
  for i = 0; i <= n; i = i + 1 {
    if i == n || b[i].to_int() == 0x0a {
      if cur == row {
        sb.write_string(repl)
      } else {
        sb.write_string(@utf8.decode_lossy(b[at:i]))
      }
      if i < n {
        sb.write_char('\n')
      }
      cur = cur + 1
      at = i + 1
    }
  }
  sb.to_string()
}

///|
test "单行编辑收敛：只重扫变更行" {
  let cs = CodeScan::new("let a = 1\nlet b = 2\nlet c = 3\n", "moonbit")
  cs.ensure(cs.line_count() - 1)
  assert_eq(cs.sync("let a = 1\nlet B = 22\nlet c = 3\n"), 1)
  cs.ensure(cs.line_count() - 1)
  assert_eq(cs.line_at(1), "let B = 22")
  assert_true(scan_roles_have(scan_roles(cs, 1), Keyword))
  assert_true(scan_offsets_ok(cs))
}

///|
test "插入行收敛：后缀按 delta 映射，重扫个位数" {
  let cs = CodeScan::new("let a = 1\nlet b = 2\nlet c = 3\n", "moonbit")
  cs.ensure(cs.line_count() - 1)
  assert_true(cs.sync("let a = 1\n// inserted\nlet b = 2\nlet c = 3\n") <= 2)
  assert_eq(cs.line_count(), 5) // 4 行 + 尾随空行
  assert_eq(cs.line_at(2), "let b = 2")
  cs.ensure(cs.line_count() - 1)
  assert_true(scan_offsets_ok(cs))
  // 删除一行同口径
  assert_true(cs.sync("let a = 1\nlet c = 3\n") <= 2)
  assert_eq(cs.line_count(), 3) // 2 行 + 尾随空行
  cs.ensure(cs.line_count() - 1)
  assert_true(scan_offsets_ok(cs))
}

///|
test "未闭合块注释：脏段退化到已扫末尾，不死循环；补扫接续传播" {
  let cs = CodeScan::new(scan_lines(10), "moonbit")
  cs.ensure(9)
  // 第 5 行开 /* 不闭：5..9 全部重扫（正确退化）
  assert_eq(cs.sync(cs_lines_replace(cs.text, 5, "  /* 未闭合")), 5)
  // 后续行在补扫时吃到挂着的注释状态
  cs.ensure(cs.line_count() - 1)
  for r in scan_roles(cs, 7) {
    assert_true(role_is(r, Comment))
  }
  // 闭合后第 9 行恢复正常着色（首 token 是 let 关键字；行尾 // 行注仍是 Comment）
  assert_true(cs.sync(cs_lines_replace(cs.text, 8, "  */ let ok = 1")) >= 0)
  cs.ensure(cs.line_count() - 1)
  let roles9 = scan_roles(cs, 9)
  assert_true(roles9.length() > 0)
  assert_true(role_is(roles9[0], Keyword))
}

///|
test "空文本与尾随换行：行模型不塌" {
  let cs = CodeScan::new("", "moonbit")
  assert_eq(cs.line_count(), 1)
  assert_eq(cs.len_of(0), 0)
  cs.ensure(0)
  assert_eq(cs.sync("a\n"), 1) // 行 0 从 "" 变 "a"
  assert_eq(cs.line_count(), 2) // 尾随 \n 的空末行
  assert_eq(cs.line_at(1), "")
  assert_eq(cs.len_of(0), 1)
  cs.ensure(cs.line_count() - 1)
  assert_true(scan_offsets_ok(cs))
}

///|
test "同文本 sync 幂等：不产重扫" {
  let src = scan_lines(5)
  let cs = CodeScan::new(src, "moonbit")
  cs.ensure(4)
  assert_eq(cs.sync(src), -1)
}
