// inspector 服务核纯函数用例：socket 路径、命令分发、TSV 组装、截断。
// 不起真监听（那要进程间连，归真机 mng inspect 验）。

///|
test "inspect_socket_path：目录链、文件名与 slug 净化" {
  let p = inspect_socket_path("libyue.hello")
  // 目录：测试机有 XDG_RUNTIME_DIR 或 TMPDIR，都是绝对路径
  assert_true(p.contains("/moonbit-inspect-"))
  assert_true(p.contains(".sock"))
  assert_true(!p.contains("libyue.hello")) // 点号已净化
  // 净化：非 [A-Za-z0-9_-] 全部换下划线
  let q = inspect_socket_path("a b/c.d")
  assert_true(q.contains("moonbit-inspect-a_b_c_d."))
  // 超长截断 + 哈希尾
  let long = inspect_socket_path("x-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
  assert_true(long.length() < 140)
}

///|
test "inspect_handle：tree 列头与数据行、未知命令" {
  let t = inspect_handle("tree")
  assert_true(t.has_prefix("#kind\trole\tname\tid\tparent\tx\ty\tw\th\tstate\tvalue\ttext\tenabled\n"))
  assert_true(inspect_handle("nope").has_prefix("error: 未知命令"))
  assert_true(inspect_handle("").has_prefix("error: 空请求"))
  assert_true(inspect_handle("style").has_prefix("error: style 需要 <id>"))
  assert_true(inspect_handle("style abc").has_prefix("error: style 需要 <id>"))
}

///|
test "insp_truncate：上限内原样、超限切完整行加 truncated" {
  let short = "a\nb\n"
  assert_eq(insp_truncate(short, 100), short)
  let big = "行一\n行二\n行三\n"
  // 上限恰好卡在行中间：截到最近完整行并尾标 truncated
  let t = insp_truncate(big, 10)
  assert_true(t.has_suffix("truncated\n"))
  assert_true(@utf8.encode(t).length() <= 10 + "truncated\n".length())
}

///|
test "parse_insp_int：正负与拒非数字" {
  assert_eq(parse_insp_int("42"), Some(42))
  assert_eq(parse_insp_int("  7 "), Some(7))
  assert_eq(parse_insp_int("-3"), Some(-3))
  assert_true(parse_insp_int("") is None)
  assert_true(parse_insp_int("12x") is None)
  assert_true(parse_insp_int("+") is None)
}

///|
test "inspect_handle：style <id> 不在快照给 error；空树 tree 只有列头" {
  // 测试进程没跑过帧同步，快照为空：tree 只剩列头、style 给 not found
  assert_eq(inspect_handle("tree"), "#kind\trole\tname\tid\tparent\tx\ty\tw\th\tstate\tvalue\ttext\tenabled\n")
  assert_true(inspect_handle("style 5").has_prefix("error: id 5 不在当前树快照"))
}

///|
test "insp_file_slug：文件名净化与空回退" {
  assert_eq(insp_file_slug("你好 MoonBit"), "___MoonBit")
  assert_eq(insp_file_slug(""), "app")
}
