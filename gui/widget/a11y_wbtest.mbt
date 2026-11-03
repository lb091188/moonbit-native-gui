// 语义面回归：字段缺省、ARK 解析往返、状态/文本回调的现算与回落。

///|
test "a11y：Widget 缺省可用、无状态无文本" {
  let w = Widget::new()
  assert_true(w.enabled)
  assert_eq(w.role, "")
  assert_eq(w.a11y_state_now(), None)
  assert_eq(w.a11y_text_now(), None)
}

///|
test "a11y：role 字符串与 ARole 往返（未知给 Unknown）" {
  for r in [
    Button, Checkbox, RadioButton, Switch, Slider, Stepper, TextInput, TextArea,
    Select, DatePicker, ColorPicker, Rate, Progress, Tab, MenuItem, Link, Image,
    Heading, Text, Window, Group,
  ] {
    let s = arole_name(r)
    assert_true(s.length() > 0)
    assert_eq(arole_name(arole_of(s)), s)
  }
  assert_true(arole_of("no_such_role") is Unknown)
  assert_eq(arole_name(Unknown), "")
}

///|
test "a11y：状态回调现算、文本回落到 label" {
  let w = Widget::new()
  w.label = "已保存"
  // 没挂回调：文本读 label，状态为 None
  assert_eq(w.a11y_text_now(), Some("已保存"))
  // 挂状态：回调首参就是控件本身
  w.a11y_state = Some(fn(self : Widget) -> (String, String)? {
    Some((if self.enabled { "enabled" } else { "disabled" }, "42%"))
  })
  match w.a11y_state_now() {
    Some((s, v)) => {
      assert_eq(s, "enabled")
      assert_eq(v, "42%")
    }
    None => abort("状态回调没被调到")
  }
  w.enabled = false
  match w.a11y_state_now() {
    Some((s, _v)) => assert_eq(s, "disabled")
    None => abort("状态回调没被调到")
  }
  // 挂文本：现算压过 label
  w.a11y_text = Some(fn(_w : Widget) -> String? { Some("现算文本") })
  assert_eq(w.a11y_text_now(), Some("现算文本"))
  // 空串按「无内容」处理，不朗读空文本
  w.a11y_text = Some(fn(_w : Widget) -> String? { Some("") })
  w.label = ""
  assert_eq(w.a11y_text_now(), None)
}

///|
test "a11y：Node::a11y 包装器挂上两个回调" {
  let base : Node = {
    mount: fn(_p : Widget) -> Widget {
      let w = Widget::new()
      w.label = "兜底"
      w
    },
  }
  let root = Widget::new()
  let n1 = base.a11y(
    state=fn(_w : Widget) -> (String, String)? { Some(("on", "1")) },
    text=fn(_w : Widget) -> String? { Some("正文") },
  )
  let w = (n1.mount)(root)
  match w.a11y_state_now() {
    Some((s, v)) => {
      assert_eq(s, "on")
      assert_eq(v, "1")
    }
    None => abort("包装器没挂上状态回调")
  }
  assert_eq(w.a11y_text_now(), Some("正文"))
  // 只挂状态不挂文本：文本回落 label
  let n2 = base.a11y(state=fn(_w : Widget) -> (String, String)? { None })
  let w2 = (n2.mount)(root)
  assert_eq(w2.a11y_text_now(), Some("兜底"))
}

///|
test "语义快照：帧尾对账产出角色/状态/文本，删控件不留幽灵" {
  let root = Widget::new()
  let btn = Widget::new()
  btn.role = "button"
  btn.label = "确定"
  let box = Widget::new()
  box.role = "checkbox"
  box.enabled = false
  box.a11y_state = Some(fn(_w : Widget) -> (String, String)? { Some(("checked", "")) })
  box.a11y_text = Some(fn(_w : Widget) -> String? { Some("记住我") })
  root.append_child(btn)
  root.append_child(box)
  assert_eq(a11y_frame_sync(root), 3)
  let snap = a11y_last_frame()
  assert_eq(snap.length(), 3)
  // 根在最前、父子关系对得上
  assert_eq(snap[0].id, root.id)
  assert_eq(snap[0].parent, 0)
  assert_eq(snap[1].role, "button")
  assert_eq(snap[1].parent, root.id)
  assert_eq(snap[1].text, "确定")
  assert_true(snap[1].enabled)
  assert_eq(snap[2].state, "checked")
  assert_true(!snap[2].enabled)
  // 删掉一个控件再对账：快照里不留幽灵
  let _ = root.remove_child(box)
  assert_eq(a11y_frame_sync(root), 2)
  let snap2 = a11y_last_frame()
  assert_eq(snap2.length(), 2)
  let mut ghost = false
  for n in snap2 {
    if n.id == box.id {
      ghost = true
    }
  }
  assert_true(!ghost, msg="已删控件仍留在语义快照里")
  // 不可见整棵子树都不进快照
  btn.visible = false
  assert_eq(a11y_frame_sync(root), 1)
}
