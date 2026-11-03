// 语义面回归（组件挂载处）：角色、启用态、状态值、文本各自上报什么。
// 断言只看语义面（role / enabled / a11y_state_now / a11y_text_now），不看像素。

///|
test "语义面：按钮报角色与文本，禁用时 enabled 为假" {
  let (_r1, w1) = mounted(button("确定"), 120.0, 40.0)
  assert_eq(w1.role, "button")
  assert_true(w1.enabled)
  assert_eq(w1.a11y_text_now(), Some("确定"))
  assert_eq(w1.a11y_state_now(), None)
  let (_r2, w2) = mounted(button("取消", disabled=true), 120.0, 40.0)
  assert_true(!w2.enabled)
}

///|
test "语义面：勾选项的勾选态跟 Store 走" {
  let s = @base.Store::new(false)
  let (_r, w) = mounted(checkbox("记住我", s), 200.0, 40.0)
  assert_eq(w.role, "checkbox")
  assert_eq(w.a11y_text_now(), Some("记住我"))
  match w.a11y_state_now() {
    Some((st, v)) => {
      assert_eq(st, "unchecked")
      assert_eq(v, "")
    }
    None => abort("勾选项没报状态")
  }
  s.set(true)
  match w.a11y_state_now() {
    Some((st, _)) => assert_eq(st, "checked")
    None => abort("勾选项没报状态")
  }
}

///|
test "语义面：开关报 checked/unchecked" {
  let s = @base.Store::new(true)
  let (_r, w) = mounted(switch(s), 200.0, 40.0)
  assert_eq(w.role, "switch")
  match w.a11y_state_now() {
    Some((st, _)) => assert_eq(st, "checked")
    None => abort("开关没报状态")
  }
  s.set(false)
  match w.a11y_state_now() {
    Some((st, _)) => assert_eq(st, "unchecked")
    None => abort("开关没报状态")
  }
}

///|
test "语义面：滑杆与进度报百分比值" {
  let sv = @base.Store::new(50.0)
  let (_r1, w1) = mounted(slider(sv, min=0.0, max=100.0), 200.0, 40.0)
  assert_eq(w1.role, "slider")
  match w1.a11y_state_now() {
    Some((st, v)) => {
      assert_eq(st, "")
      assert_eq(v, "50%")
    }
    None => abort("滑杆没报值")
  }
  let pv = @base.Store::new(0.25)
  let (_r2, w2) = mounted(progress(pv, max=1.0), 200.0, 8.0)
  assert_eq(w2.role, "progress")
  match w2.a11y_state_now() {
    Some((_, v)) => assert_eq(v, "25%")
    None => abort("进度条没报值")
  }
  pv.set(1.0)
  match w2.a11y_state_now() {
    Some((_, v)) => assert_eq(v, "100%")
    None => abort("进度条没报值")
  }
}
