// Phase 0 探针的严格断言（无头）：结构补丁原位重挂成功、旧代订阅整袋退订、
// 迭代热替换订阅不累积、条件块随 Bool 槽切换。

///|
test "结构补丁：原位重挂换树，旧代订阅整袋退订" {
  let qty = @base.Store::new(3)
  let level = @base.Store::new(30.0)
  let wifi = @base.Store::new(true)
  let fires = Ref(0)
  let reg = make_registry(qty, level, wifi, fires)
  let holder = @widget.Widget::new()
  let _ = holder.set_column()
  let gen = mount_gen(holder, ir_v1(), reg)
  // v1 含 stepper（受控订阅）+ bind_label 各一条 = 2
  assert_eq(qty.signal().sub_count(), 2)
  // 旧代活着：set 一次渲染 +1
  let b0 = fires.val
  qty.set(4)
  assert_eq(fires.val - b0, 1)
  // 打结构补丁：摘 v1 挂 v2
  unmount_gen(holder, gen)
  assert_eq(qty.signal().sub_count(), 0)
  let _ = mount_gen(holder, ir_v2(), reg)
  assert_eq(qty.signal().sub_count(), 2)
  // 新代活着、旧代死透：set 一次仍只渲染 +1
  let b1 = fires.val
  qty.set(5)
  assert_eq(fires.val - b1, 1)
}

///|
test "迭代 50 轮热替换：订阅数不累积、渲染不叠加" {
  let qty = @base.Store::new(3)
  let level = @base.Store::new(30.0)
  let wifi = @base.Store::new(true)
  let fires = Ref(0)
  let reg = make_registry(qty, level, wifi, fires)
  let holder = @widget.Widget::new()
  let _ = holder.set_column()
  let mut gen = mount_gen(holder, ir_v1(), reg)
  for i = 0; i < 50; i = i + 1 {
    unmount_gen(holder, gen)
    gen = mount_gen(holder, if i % 2 == 0 { ir_v2() } else { ir_v1() }, reg)
  }
  // 末代是 v1（i=49 奇数）：qty 2 条（bind_label+stepper）、level 1 条（slider 受控）
  assert_eq(qty.signal().sub_count(), 2)
  assert_eq(level.signal().sub_count(), 1)
  let b = fires.val
  qty.set(9)
  assert_eq(fires.val - b, 1)
}

///|
test "条件块：Bool 槽切换原位换支，bind_node 订阅不累积" {
  let qty = @base.Store::new(3)
  let level = @base.Store::new(30.0)
  let wifi = @base.Store::new(true)
  let fires = Ref(0)
  let reg = make_registry(qty, level, wifi, fires)
  let holder = @widget.Widget::new()
  let _ = holder.set_column()
  let _ = mount_gen(holder, ir_v1(), reg)
  // v1 条件块只有 bind_node 一条 wifi 订阅；来回切换订阅数恒 1
  wifi.set(false)
  assert_eq(wifi.signal().sub_count(), 1)
  wifi.set(true)
  assert_eq(wifi.signal().sub_count(), 1)
}
