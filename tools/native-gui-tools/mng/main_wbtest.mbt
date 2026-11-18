// CLI 文案语言判定回归：locale 变量的表态分类。

///|
test "env_lang_zh：zh 前缀表态中文，其余已表态值表态英文" {
  assert_eq(env_lang_zh("zh_CN.UTF-8"), Some(true))
  assert_eq(env_lang_zh("zh"), Some(true))
  assert_eq(env_lang_zh("en_US.UTF-8"), Some(false))
  assert_eq(env_lang_zh("ja_JP.UTF-8"), Some(false))
}

///|
test "env_lang_zh：C 与 POSIX 形态是未表态" {
  assert_eq(env_lang_zh("C"), None)
  assert_eq(env_lang_zh("c"), None)
  assert_eq(env_lang_zh("C.UTF-8"), None)
  assert_eq(env_lang_zh("POSIX"), None)
  assert_eq(env_lang_zh("posix.UTF-8"), None)
}
