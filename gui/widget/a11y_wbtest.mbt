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

///|
test "语义快照：帧尾对账同时推到平台通道，行数与快照一致" {
  let root = Widget::new()
  let btn = Widget::new()
  btn.role = "button"
  btn.label = "确定"
  root.append_child(btn)
  assert_eq(a11y_frame_sync(root), 2)
  assert_eq(@win.a11y_published_count(), 2)
  btn.visible = false
  assert_eq(a11y_frame_sync(root), 1)
  assert_eq(@win.a11y_published_count(), 1)
}

///|
test "读屏动作：点击合成 Down+Up 打到控件中心，按钮回调照常触发" {
  let root = Widget::new()
  root.rect = { x: 0.0, y: 0.0, w: 200.0, h: 100.0, }
  let btn = Widget::new()
  btn.rect = { x: 20.0, y: 30.0, w: 80.0, h: 30.0, }
  let seen : Array[(Int, Double, Double)] = []
  btn.on_pointer = Some(fn(_w : Widget, ev : PointerEvent) -> Bool {
    seen.push((
      match ev.kind {
        Down => 0
        Up => 1
        _ => 2
      },
      ev.x,
      ev.y,
    ))
    true
  })
  root.append_child(btn)
  let (h, c, ch, consumed) = a11y_action_dispatch(
    root,
    btn.id,
    @win.A11Y_ACT_CLICK,
    -1,
    -1,
  )
  // 中心点 = (20+40, 30+15)；本地坐标即相对控件原点
  assert_eq(seen, [(0, 40.0, 15.0), (1, 40.0, 15.0)])
  // Down 置捕获、Up 归还并把悬停落到命中控件：会话状态接得住（与真实点击同链）
  assert_eq(c, -1)
  assert_eq(h, btn.id)
  assert_true(ch)
  assert_true(consumed)
}

///|
test "读屏动作：id 不在树里或动作码不认识时原样返回、不误触" {
  let root = Widget::new()
  root.rect = { x: 0.0, y: 0.0, w: 200.0, h: 100.0, }
  let btn = Widget::new()
  btn.rect = { x: 20.0, y: 30.0, w: 80.0, h: 30.0, }
  let seen : Array[Int] = []
  btn.on_pointer = Some(fn(_w : Widget, ev : PointerEvent) -> Bool {
    seen.push(match ev.kind {
      Down => 0
      Up => 1
      _ => 2
    })
    true
  })
  root.append_child(btn)
  // 陌生 id
  let r1 = a11y_action_dispatch(root, btn.id + 999, @win.A11Y_ACT_CLICK, -1, -1)
  assert_eq(r1, (-1, -1, false, false))
  // 陌生动作码
  let r2 = a11y_action_dispatch(root, btn.id, 99, -1, -1)
  assert_eq(r2, (-1, -1, false, false))
  // 零尺寸控件（未布局）不点
  let bare = Widget::new()
  root.append_child(bare)
  let r3 = a11y_action_dispatch(root, bare.id, @win.A11Y_ACT_CLICK, -1, -1)
  assert_eq(r3, (-1, -1, false, false))
  // 三种情形都没把事件送进控件
  assert_eq(seen.length(), 0)
}

///|
test "事件上行：快照内容不变不重复通知，变了才通知读屏重读" {
  let root = Widget::new()
  let btn = Widget::new()
  btn.role = "button"
  btn.label = "确定"
  root.append_child(btn)
  let before = @win.a11y_layout_notify_count()
  // 第一帧：内容相对初始空串是「变了」→ 通知一次
  let _ = a11y_frame_sync(root)
  assert_eq(@win.a11y_layout_notify_count(), before + 1)
  // 原样再对账一帧：不扰民
  let _ = a11y_frame_sync(root)
  assert_eq(@win.a11y_layout_notify_count(), before + 1)
  // 改标签：内容变 → 再通知
  btn.label = "取消"
  let _ = a11y_frame_sync(root)
  assert_eq(@win.a11y_layout_notify_count(), before + 2)
}

///|
test "事件上行：焦点相同不通知，换了才通知；平台侧读回焦点 id" {
  let root = Widget::new()
  let btn = Widget::new()
  btn.role = "button"
  root.append_child(btn)
  let before = @win.a11y_focus_notify_count()
  a11y_set_focus(btn.id)
  assert_eq(@win.a11y_focus(), btn.id)
  assert_eq(@win.a11y_focus_notify_count(), before + 1)
  // 同一焦点不重复通知
  a11y_set_focus(btn.id)
  assert_eq(@win.a11y_focus_notify_count(), before + 1)
  // 换焦点（含落到「无焦点」的 0）各通知一次
  a11y_set_focus(0)
  assert_eq(@win.a11y_focus_notify_count(), before + 2)
  assert_eq(@win.a11y_focus(), 0)
}

///|
test "读屏动作：泵抽空即停，队列空时状态原样" {
  let root = Widget::new()
  root.rect = { x: 0.0, y: 0.0, w: 100.0, h: 50.0, }
  // 非 Windows 后端没有 provider 压队列，泵应当立即抽空
  let r = a11y_pump_actions(root, 3, 4)
  assert_eq(r, (3, 4, false, false))
}
