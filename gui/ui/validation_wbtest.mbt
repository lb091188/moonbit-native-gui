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
/// 默认消息走 `gui.ui.validation.*` 取译口：换目录后同一条规则给英文消息，
/// 显式传 `msg=` 的仍按调用方给的串。
test "默认消息随语言取译，显式 msg 不受影响" {
  @i18n.i18n_load(
    "[gui.ui.validation]\nrequired = \"Required\"\nmin_len = \"At least {n} chars\"\nemail = \"Bad email\"\nint_range = \"Must be {lo}..{hi}\"\n[meta]\nlocale = \"en\"\n",
  )
  let r = all([required(), min_len(4)])
  assert_eq(r(""), Some("Required"))
  assert_eq(r("abc"), Some("At least 4 chars"))
  assert_eq(email()("nope"), Some("Bad email"))
  assert_eq(int_range(1, 10)("11"), Some("Must be 1..10"))
  assert_eq(required(msg="必填")(""), Some("必填"))
  @i18n.i18n_reset()
  // 复位后回落内置默认（中文源串）
  assert_eq(required()(""), Some("不能为空"))
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
