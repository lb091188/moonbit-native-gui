// 校验规则与接线：错误槽随值流即时更新。

///|
test "validate 接线：初跑 + 值变即刷，合法清空" {
  let s = @base.Store::new("")
  let err = validate(s, required(msg="必填"))
  assert_eq(err.get(), "必填")
  s.set("  ")
  assert_eq(err.get(), "必填")
  s.set("ok")
  assert_eq(err.get(), "")
}

///|
test "规则单跑：min_len/email/int_range/all" {
  let len4 = min_len(3)
  assert_eq(len4("ab"), Some("至少 3 个字符"))
  assert_eq(len4("abc"), None)
  let mail = email()
  assert_eq(mail("a@b.c"), None)
  assert_eq(mail("nope"), Some("邮箱格式不对"))
  assert_eq(mail("a@b."), Some("邮箱格式不对"))
  let rng = int_range(1, 10)
  assert_eq(rng("7"), None)
  assert_eq(rng("11"), Some("须在 1.. 10 之间"))
  let signed = int_range(-5, 5)
  assert_eq(signed("-3"), None)
  assert_eq(signed("x"), Some("须在 -5.. 5 之间"))
  let r = all([required(), min_len(4)])
  assert_eq(r(""), Some("不能为空"))
  assert_eq(r("abc"), Some("至少 4 个字符"))
  assert_eq(r("abcd"), None)
}
