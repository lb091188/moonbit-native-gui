// 文本注入白盒：分片纯函数全覆盖（中文 / 代理对 / 20-21 边界 / 空串）。
// 真注入回环默认跳过——它会把字打进当前聚焦的应用，设 NATIVEGUI_INJECT_EVB=1
// 并聚焦一个文本框后才真投，面向真机验证；CI 与日常 moon test 都不碰。

///|
fn chunks_units(c : Bytes) -> Int {
  c.length() / 2
}

///|
fn chunks_roundtrip(chunks : Array[Bytes]) -> String {
  let mut out = ""
  for c in chunks {
    out = out + @utf16.decode_lossy(c, endianness=Little)
  }
  out
}

test "inject_chunks：空串给零片" {
  assert_eq(inject_chunks("").length(), 0)
}

test "inject_chunks：中文按 20 单元分片" {
  // 26 个汉字，每字一个 UTF-16 单元 → 20 + 6
  let text = "一二三四五六七八九十甲乙丙丁戊己庚壬子丑寅卯辰巳午未"
  let chunks = inject_chunks(text)
  assert_eq(chunks.length(), 2)
  assert_eq(chunks_units(chunks[0]), 20)
  assert_eq(chunks_units(chunks[1]), 6)
  assert_eq(chunks_roundtrip(chunks), text)
}

test "inject_chunks：emoji 代理对不劈开" {
  // 10 个 emoji 各占两个单元，恰好一片 20
  let ten = "😀😀😀😀😀😀😀😀😀😀"
  let one = inject_chunks(ten)
  assert_eq(one.length(), 1)
  assert_eq(chunks_units(one[0]), 20)
  assert_eq(chunks_roundtrip(one), ten)
  // 10 emoji + 1 汉字 + 10 emoji：第二片片界劈在代理对中间，延成 21
  let mixed = "😀😀😀😀😀😀😀😀😀😀汉😀😀😀😀😀😀😀😀😀😀"
  let two = inject_chunks(mixed)
  assert_eq(two.length(), 2)
  assert_eq(chunks_units(two[0]), 20)
  assert_eq(chunks_units(two[1]), 21)
  assert_eq(chunks_roundtrip(two), mixed)
}

test "inject_chunks：中英混合回环" {
  let text = "airtype 测试 abc 😀 你好 🚀 moonbit"
  let chunks = inject_chunks(text)
  assert_eq(chunks_roundtrip(chunks), text)
  for c in chunks {
    let n = chunks_units(c)
    assert_true(n > 0 && n <= 21)
  }
}

test "inject_text：真机回环（NATIVEGUI_INJECT_EVB=1 才投）" {
  if @env.get_env_var("NATIVEGUI_INJECT_EVB") != Some("1") {
    println("inject: skip（默认不投；设 NATIVEGUI_INJECT_EVB=1 并聚焦一个文本框后重跑）")
    return
  }
  if !inject_available() {
    println("inject: skip（本平台无注入通道）")
    return
  }
  // 结果随环境打印记录，不硬断言——未授权机器上 PermissionDenied 是正常读数
  match inject_text("airtype 注入回环 😀") {
    Ok(_) => println("inject: ok")
    Err(e) => println("inject: err \{e}")
  }
}
