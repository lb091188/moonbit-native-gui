// 选区持有者登记：单 owner 互斥、让位清理、宿主复制支与按 id 释放。

///|
test "text_sel：认领·覆盖·释放·复制" {
  let copied = Ref(0)
  let cleared = Ref(0)
  text_sel_release(1)
  text_sel_release(2)
  assert_eq(text_sel_owner(), 0)
  assert_false(text_sel_copy())
  text_sel_claim(1, fn() { copied.val += 1 }, fn() { cleared.val += 1 })
  assert_eq(text_sel_owner(), 1)
  assert_true(text_sel_copy())
  assert_eq(copied.val, 1)
  // 同 id 再认领（拖选中反复更新）不动前任，也不清自己的选区
  text_sel_claim(1, fn() { copied.val += 1 }, fn() { cleared.val += 1 })
  assert_eq(cleared.val, 0)
  // 换持有者：前任的 clear 被调到（两处不能同时亮）
  text_sel_claim(2, fn() { copied.val += 1 }, fn() { cleared.val += 1 })
  assert_eq(text_sel_owner(), 2)
  assert_eq(cleared.val, 1)
  // 释放只认登记中的那个 id
  text_sel_release(1)
  assert_eq(text_sel_owner(), 2)
  text_sel_release(2)
  assert_eq(text_sel_owner(), 0)
  assert_false(text_sel_copy())
}
