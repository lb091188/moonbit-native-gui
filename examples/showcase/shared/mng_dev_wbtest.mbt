// mng_dev 白盒：补丁解析 → applier 构树 → holder 原位替换 → 旧代整袋退订。
// 键由编译器按表达式内容哈希生成；夹具随手用同一条键串起 IR 与注册表即可
// （真实键形如 t:3fc746ec39ec6f8e，见 mngkit 的「HOT 键稳定」测试）。

///|
fn demo_ir() -> String {
  [
  "{\"v\":1,\"page\":\"dev_demo\",",
  "\"root\":{\"k\":\"col\",\"gap\":8.0,\"kids\":[",
  "  {\"k\":\"checkbox\",\"args\":{\"label\":{\"expr\":\"t:8:18\"},\"value\":{\"state\":\"wifi\"}}},",
  "  {\"k\":\"if\",\"c\":\"c:9:5\",\"t\":{\"k\":\"dyn\",\"key\":\"t:9:5\"},\"f\":{\"k\":\"text\",\"v\":\"已关闭\"}},",
  "  {\"k\":\"stepper\",\"args\":{\"value\":{\"state\":\"qty\"}}},",
  "  {\"k\":\"dyn\",\"key\":\"t:12:5\"},",
  "  {\"k\":\"input\",\"args\":{\"value\":{\"state\":\"nick\"}}},",
  "  {\"k\":\"button\",\"args\":{\"text\":{\"lit\":\"重置\"}},\"click\":\"on_reset\"}",
  "]},",
  "\"exprs\":[\"t:8:18\",\"c:9:5\",\"t:9:5\",\"t:12:5\"],",
  "\"states\":[\"wifi\",\"qty\",\"nick\"],",
  "\"handlers\":[\"on_reset\"]}",
].join("") + "\n"
}

///|
fn demo_reg(
  fires : Ref[Int],
  qty : @base.Store[Int],
  wifi : @base.Store[Bool],
  nick : @base.Store[String],
) -> MngReg {
  let reg = mng_reg_new()
  reg.int("qty", qty)
  reg.bool("wifi", wifi)
  reg.str("nick", nick)
  reg.cond("c:9:5", fn() { wifi.get() })
  reg.expr("t:12:5", fn() {
    fires.val = fires.val + 1
    "当前数量：\{qty.get()}"
  })
  reg.expr("t:8:18", fn() { "自动开启" })
  reg.expr("t:9:5", fn() { "已开启" })
  reg.handler("on_reset", fn() { qty.set(3) })
  reg
}

///|
test "applier:补丁构树挂上 holder，动态槽走注册表" {
  let fires = Ref(0)
  let reg = demo_reg(fires, @base.Store::new(3), @base.Store::new(true), @base.Store::new(""))
  mng_dev_set_reg("dev_demo", reg)
  let holder = @widget.Widget::new()
  let _ = holder.set_column()
  mng_dev_bind_holder("dev_demo", holder)
  match mng_dev_apply(demo_ir()) {
    Ok(_) => ()
    Err(e) => abort("apply1: \{e}")
  }
  assert_eq(holder.children().length(), 1)
  // 补丁里没有 gen 旧树时 live 为空——再应用一次走「摘旧挂新」
  match mng_dev_apply(demo_ir()) {
    Ok(_) => ()
    Err(e) => abort("apply2: \{e}")
  }
  assert_eq(holder.children().length(), 1)
}

///|
test "applier:旧代订阅整袋退订，迭代不累积" {
  let fires = Ref(0)
  let qty : @base.Store[Int] = @base.Store::new(3)
  let reg = demo_reg(fires, qty, @base.Store::new(true), @base.Store::new(""))
  mng_dev_set_reg("dev_demo", reg)
  let holder = @widget.Widget::new()
  let _ = holder.set_column()
  mng_dev_bind_holder("dev_demo", holder)
  let mut i = 0
  while i < 5 {
    match mng_dev_apply(demo_ir()) {
      Ok(_) => ()
      Err(e) => abort("\{e}")
    }
    i += 1
  }
  // 行为断言：换代 5 次后 set 一次，只有现役代的 dyn 插值渲染（1 次）——
  // 旧代若未退订，fires 会随代数叠加
  let b = fires.val
  qty.set(9)
  assert_eq(fires.val - b, 1)
}

///|
test "applier:缺注册项报错并带键名" {
  mng_dev_set_reg("dev_demo", mng_reg_new())
  let holder = @widget.Widget::new()
  let _ = holder.set_column()
  mng_dev_bind_holder("dev_demo", holder)
  let r = mng_dev_apply(demo_ir())
  assert_true(
    match r {
      Err(e) => contains_sub_m(e, "注册表缺")
      _ => false
    },
  )
}

///|
fn contains_sub_m(s : String, sub : String) -> Bool {
  let a = chars_of_m(s)
  let b = chars_of_m(sub)
  let n = a.length()
  let m = b.length()
  if m == 0 || m > n {
    return m == 0
  }
  let mut i = 0
  while i + m <= n {
    let mut ok = true
    for k in 0..<m {
      if a[i + k] != b[k] {
        ok = false
      }
    }
    if ok {
      return true
    }
    i += 1
  }
  false
}

///|
test "applier:补丁按 page 取页，未挂载页报错带页名" {
  let ir = "{\"v\":1,\"page\":\"ghost\",\"root\":{\"k\":\"text\",\"v\":\"x\"}}"
  let r = mng_dev_apply(ir)
  assert_true(
    match r {
      Err(e) => contains_sub_m(e, "ghost") && contains_sub_m(e, "未挂载")
      _ => false
    },
  )
}

///|
test "mng_dev_page：登记起页挂初代树，补丁原位替换保持单棵" {
  let page = "io.moonbitlibyue.wbtest.devpage"
  let reg = mng_reg_new()
  reg.expr("t:1:1", fn() { "初代" })
  let node = mng_dev_page(page, reg, fn() {
    @widget.bind_node(@base.Signal::computed(fn() { true }), fn(_v) {
      @ui.text("初代")
    })
  })
  let root = @widget.Widget::new()
  let _ = root.set_column()
  let _ = node.mount_into(root)
  assert_eq(root.children().length(), 1)
  let holder = match mng_holders.get(page) {
    Some(h) => h
    None => abort("holder 未登记")
  }
  assert_eq(holder.children().length(), 1)
  let ir = "{\"v\":1,\"page\":\"io.moonbitlibyue.wbtest.devpage\",\"root\":{\"k\":\"dyn\",\"key\":\"t:1:1\"},\"exprs\":[\"t:1:1\"],\"states\":[],\"handlers\":[]}"
  match mng_dev_apply(ir) {
    Ok(_) => ()
    Err(e) => abort("apply: " + e)
  }
  assert_eq(holder.children().length(), 1)
}
