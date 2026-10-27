// link 面回归：on_link 的归一化、route_link 的指针认领与框外不触发、面包屑的段数与
// 原位重挂、strip_at/sidebar 与层 store 同源。段条「点一下切段」那一向要真鼠标，
// 归到真机验证清单里。

fn ln_text() -> @widget.Node {
  @ui.text("内容")
}

fn ln_lf(k : String) -> Route {
  route_leaf(k, fn() -> @widget.Node { ln_text() })
}

fn ln_tree() -> Array[Route] {
  [
    route_branch("组件", [ln_lf("按钮"), ln_lf("消息框")]),
    route_branch("系统", [ln_lf("托盘"), ln_lf("通知")]),
  ]
}

fn ln_mount(view : @widget.Node) -> @widget.Widget {
  let root = @widget.Widget::new()
  root.set_size(1200.0, 800.0)
  root.set_column()
  let _ = view.mount_into(root)
  root.relayout(1200.0, 800.0)
  root
}

fn ln_clickable(w : @widget.Widget) -> Int {
  let kids = w.children()
  let mut n = if w.on_pointer is Some(_) { 1 } else { 0 }
  for c in kids {
    n += ln_clickable(c)
  }
  n
}

fn ln_press(w : @widget.Widget, x : Double, y : Double) -> Unit {
  match w.on_pointer {
    None => abort("这一层没接指针")
    Some(f) => {
      let _ = (f)(w, { kind: @widget.PointerKind::Down, x, y, button: 1, mods: 0 })
      let _ = (f)(w, { kind: @widget.PointerKind::Up, x, y, button: 1, mods: 0 })
    }
  }
}

///|
test "on_link 就是导航，深层自动回落首项" {
  let r = new_router(ln_tree())
  let f = r.on_link("系统")
  (f)()
  assert_eq(r.path(), "系统/托盘")
  let g = r.on_link("组件/消息框")
  (g)()
  assert_eq(r.path(), "组件/消息框")
}

///|
test "route_link 点上导航、点框外不导航" {
  let r = new_router(ln_tree())
  let root = @widget.Widget::new()
  root.set_size(1200.0, 800.0)
  root.set_column()
  let wrap = r.route_link("系统/通知", ln_text()).mount_into(root)
  root.relayout(1200.0, 800.0)
  assert_true(wrap.rect.w > 0.0)
  ln_press(wrap, 1.0, 1.0)
  assert_eq(r.path(), "系统/通知")
  r.goto("组件/按钮")
  ln_press(wrap, wrap.rect.w + 50.0, wrap.rect.h + 50.0)
  assert_eq(r.path(), "组件/按钮")
}

///|
test "面包屑段数 = 层数，末段不给点击" {
  let r = new_router(ln_tree())
  let root = ln_mount(r.breadcrumb())
  // 两层路径：第一段可点、末段不可点
  assert_eq(ln_clickable(root), 1)
  let one = new_router([ln_lf("首页"), ln_lf("次页")])
  let root1 = ln_mount(one.breadcrumb())
  assert_eq(ln_clickable(root1), 0)
}

///|
test "面包屑随路径变化原位重挂（不留旧代）" {
  let r = new_router(ln_tree())
  let root = ln_mount(r.breadcrumb())
  let before = root.children()
  assert_eq(before.length(), 1)
  r.goto("系统/通知")
  let after = root.children()
  assert_eq(after.length(), 1)
  assert_true(after[0].id != before[0].id)
  assert_eq(ln_clickable(root), 1)
}

///|
test "join_upto 取前 i 段" {
  assert_eq(join_upto(["甲", "乙", "丙"], 1), "甲")
  assert_eq(join_upto(["甲", "乙", "丙"], 2), "甲/乙")
  assert_eq(join_upto(["甲", "乙", "丙"], 3), "甲/乙/丙")
}

///|
test "strip_at 驱动的层键与槽同源" {
  let r = new_router(ln_tree())
  let root = ln_mount(r.view_strip())
  assert_true(r.is_mounted("组件/按钮"))
  // 段条往第 1 层写键，槽就挂那一层的内容（点击那一下要真鼠标，另见真机清单）
  r.store_at(1).set("消息框")
  assert_true(r.is_mounted("组件/消息框"))
  assert_true(ln_clickable(root) > 0)
}

///|
test "sidebar 与侧栏外载体共享同一份导航状态" {
  let r = new_router(ln_tree())
  let _root = ln_mount(@ui.row(
    [r.sidebar([("导航", ["组件", "系统"])], icons=[]), r.view_strip()],
    grow=1.0,
  ))
  assert_true(r.is_mounted("组件/按钮"))
  r.goto("系统")
  assert_true(r.is_mounted("系统/托盘"))
  assert_eq(r.path(), "系统/托盘")
}
