// mng_dev 白盒：补丁解析 → applier 构树 → 挂载点原位替换 → 旧代整袋退订。
// 键由编译器按表达式内容哈希生成；夹具随手用同一条键串起 IR 与注册表即可
// （真实键形如 t:3fc746ec39ec6f8e，见 mngkit 的「HOT 键稳定」测试）。

///|
fn demo_ir(page : String) -> String {
  [
    "{\"v\":1,\"rev\":\"mng-ir-1\",\"page\":\"" + page + "\",", "\"root\":{\"k\":\"col\",\"gap\":8.0,\"class\":[\"demo\"],\"kids\":[",
    "  {\"k\":\"checkbox\",\"args\":{\"label\":{\"expr\":\"t:8:18\"},\"value\":{\"state\":\"wifi\"}}},",
    "  {\"k\":\"if\",\"c\":\"c:9:5\",\"t\":{\"k\":\"dyn\",\"key\":\"t:9:5\"},\"f\":{\"k\":\"text\",\"v\":\"已关闭\"}},",
    "  {\"k\":\"stepper\",\"args\":{\"value\":{\"state\":\"qty\"}}},", "  {\"k\":\"dyn\",\"key\":\"t:12:5\"},",
    "  {\"k\":\"input\",\"args\":{\"value\":{\"state\":\"nick\"}}},", "  {\"k\":\"button\",\"args\":{\"text\":{\"lit\":\"重置\"}},\"click\":\"on_reset\"}",
    "]},", "\"exprs\":[\"t:8:18\",\"c:9:5\",\"t:9:5\",\"t:12:5\"],", "\"states\":[\"wifi\",\"qty\",\"nick\"],",
    "\"handlers\":[\"on_reset\"]}",
  ].join("") +
  "\n"
}

///|
fn demo_reg(
  fires : Ref[Int32],
  qty : @base.Store[Int32],
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
test "applier:补丁构树挂进父容器，页不占树行" {
  let fires = Ref(0)
  let reg = demo_reg(
    fires,
    @base.Store::new(3),
    @base.Store::new(true),
    @base.Store::new(""),
  )
  let parent = @widget.Widget::new()
  let _ = parent.set_column()
  let node = mng_dev_page("dev_shell", reg, fn() { @ui.text("初代") })
  let first = node.mount_into(parent)
  // 父容器的直接子项就是模板根：dev 页不占树行、无自带布局壳
  assert_eq(parent.children().length(), 1)
  assert_eq(parent.children()[0].id, first.id)
  assert_eq(first.kind, "ui-text")
  match mng_dev_apply(demo_ir("dev_shell")) {
    Ok(_) => ()
    Err(e) => abort("apply1: \{e}")
  }
  assert_eq(parent.children().length(), 1)
  assert_eq(parent.children()[0].kind, "ui-col")
  // 再应用一次走「摘旧挂新」
  match mng_dev_apply(demo_ir("dev_shell")) {
    Ok(_) => ()
    Err(e) => abort("apply2: \{e}")
  }
  assert_eq(parent.children().length(), 1)
  assert_eq(parent.children()[0].kind, "ui-col")
}

///|
test "applier:旧代订阅整袋退订，迭代不累积" {
  let fires = Ref(0)
  let qty : @base.Store[Int32] = @base.Store::new(3)
  let reg = demo_reg(fires, qty, @base.Store::new(true), @base.Store::new(""))
  let parent = @widget.Widget::new()
  let _ = parent.set_column()
  let _ = mng_dev_page("dev_bag", reg, fn() { @ui.text("初代") }).mount_into(parent)
  let mut i = 0
  while i < 5 {
    match mng_dev_apply(demo_ir("dev_bag")) {
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
fn mj_of_test(s : String) -> MJ {
  match jp_value({ cs: chars_of_m(s), i: 0, }) {
    Ok(v) => v
    Err(e) => abort("测试 IR JSON 解析失败：\{e}")
  }
}

///|
test "类定义数据：属性落 Style、状态桶、同名重注册" {
  let rules = mj_of_test(
    "[{\"n\":\"sd-test\",\"s\":\"\",\"props\":[{\"p\":\"font_size\",\"e\":\"20.0\"},{\"p\":\"color\",\"e\":\"\\\"text_primary\\\"\"},{\"p\":\"justify_content\",\"e\":\"@yoga.JustifyContent::Center\"}]}," +
    "{\"n\":\"sd-test\",\"s\":\"hover\",\"props\":[{\"p\":\"color\",\"e\":\"\\\"primary\\\"\"}]}," +
    "{\"n\":\"sd-test\",\"s\":\"dark\",\"props\":[{\"p\":\"background_color\",\"e\":\"\\\"#101014\\\"\"}]}]",
  )
  let arr = match mj_arr(Some(rules)) {
    Some(a) => a
    None => abort("类数据应为数组")
  }
  match mng_reg_classes(arr) {
    Ok(_) => ()
    Err(e) => abort("\{e}")
  }
  match @style.lookup_class("sd-test") {
    Some(c) => {
      match c.style.font_size {
        Some(v) => assert_eq(v, 20.0)
        None => assert_true(false)
      }
      assert_true(c.style.color is Some(_))
      assert_true(c.style.justify_content is Some(_))
      assert_true(c.style.hover is Some(_))
    }
    None => assert_true(false)
  }
  assert_true(@style.lookup_class("sd-test:dark") is Some(_))
  // 同名重注册：后写赢
  let rules2 = mj_of_test(
    "[{\"n\":\"sd-test\",\"s\":\"\",\"props\":[{\"p\":\"font_size\",\"e\":\"30.0\"}]}]",
  )
  let arr2 = match mj_arr(Some(rules2)) {
    Some(a) => a
    None => abort("类数据应为数组")
  }
  match mng_reg_classes(arr2) {
    Ok(_) => ()
    Err(e) => abort("\{e}")
  }
  match @style.lookup_class("sd-test") {
    Some(c) =>
      match c.style.font_size {
        Some(v) => assert_eq(v, 30.0)
        None => assert_true(false)
      }
    None => assert_true(false)
  }
}

///|
test "受限表达式求值：Store/运算/条件/内置函数" {
  let reg = mng_reg_new()
  reg.int("qty", @base.Store::new(5))
  reg.bool("wifi", @base.Store::new(true))
  reg.str("nick", @base.Store::new("x"))
  mng_reg_builtins(reg)
  // @shared.tx("A")
  let tx_ast = "{\"k\":\"call\",\"f\":\"@shared.tx\",\"a\":[{\"k\":\"str\",\"v\":\"A\"}]}"
  match mng_reg_eval(reg, "t:tx", mj_of_test(tx_ast)) {
    Ok(_) => ()
    Err(e) => abort("\{e}")
  }
  let txv = match reg.exprs.get("t:tx") {
    Some(f) => f()
    None => "缺登记"
  }
  // 库侧语义：@shared.tx 求值 = @i18n.t_or（测试未装载英文目录 → 回落原文）
  assert_eq(txv, "A")
  // qty > 5 → false
  let cond_ast = "{\"k\":\"bin\",\"op\":\">\",\"l\":{\"k\":\"get\",\"a\":{\"k\":\"id\",\"v\":\"qty\"}},\"r\":{\"k\":\"int\",\"v\":5}}"
  match mng_reg_eval(reg, "c:gt", mj_of_test(cond_ast)) {
    Ok(_) => ()
    Err(e) => abort("\{e}")
  }
  let gt = match reg.conds.get("c:gt") {
    Some(f) => f()
    None => true
  }
  assert_true(!gt)
  // qty.to_string()
  let s_ast = "{\"k\":\"tostr\",\"a\":{\"k\":\"get\",\"a\":{\"k\":\"id\",\"v\":\"qty\"}}}"
  match mng_reg_eval(reg, "t:s", mj_of_test(s_ast)) {
    Ok(_) => ()
    Err(e) => abort("\{e}")
  }
  let sv = match reg.exprs.get("t:s") {
    Some(f) => f()
    None => ""
  }
  assert_eq(sv, "5")
}

///|
test "applier：补丁里的 eval 表登记新表达式后再构树" {
  let reg = mng_reg_new()
  reg.int("qty", @base.Store::new(5))
  mng_reg_builtins(reg)
  let parent = @widget.Widget::new()
  let _ = parent.set_column()
  let _ = mng_dev_page("evalpage", reg, fn() { @ui.text("初代") }).mount_into(parent)
  let ir = [
    "{\"v\":1,\"rev\":\"mng-ir-1\",\"page\":\"evalpage\",", "\"root\":{\"k\":\"dyn\",\"key\":\"t:abc\"},",
    "\"exprs\":[\"t:abc\"],\"states\":[],\"handlers\":[],", "\"eval\":{\"t:abc\":{\"k\":\"tostr\",\"a\":{\"k\":\"id\",\"v\":\"qty\"}}}}",
  ].join("")
  match mng_dev_apply(ir) {
    Ok(_) => ()
    Err(e) => abort("\{e}")
  }
  assert_true(reg.exprs.get("t:abc") is Some(_))
  // 再应用一次：已登记键不覆盖，仍能重建
  match mng_dev_apply(ir) {
    Ok(_) => ()
    Err(e) => abort("\{e}")
  }
  assert_eq(parent.children().length(), 1)
}

///|
test "applier:握手不符（注册表缺键）判 stale，原因带缺的键" {
  let parent = @widget.Widget::new()
  let _ = parent.set_column()
  let _ = mng_dev_page("dev_stale", mng_reg_new(), fn() { @ui.text("初代") }).mount_into(parent)
  let r = mng_dev_apply(demo_ir("dev_stale"))
  assert_true(
    match r {
      Err(e) =>
        contains_sub_m(e, "stale：") &&
        contains_sub_m(e, "注册表键集落后") &&
        contains_sub_m(e, "t:12:5") &&
        contains_sub_m(e, "digest=")
      _ => false
    },
  )
}

///|
test "applier:协议代次不符判 stale（旧补丁没有 rev）" {
  let parent = @widget.Widget::new()
  let _ = parent.set_column()
  let _ = mng_dev_page("dev_legacy", mng_reg_new(), fn() { @ui.text("初代") }).mount_into(parent)
  let ir = "{\"v\":1,\"page\":\"dev_legacy\",\"root\":{\"k\":\"text\",\"v\":\"x\"}}"
  let r = mng_dev_apply(ir)
  assert_true(
    match r {
      Err(e) =>
        contains_sub_m(e, "stale：") && contains_sub_m(e, "协议代次不符")
      _ => false
    },
  )
}

///|
test "键集摘要：同键集同摘要（顺序无关），增键即变" {
  let a = mng_keys_digest(["t:1", "qty", "on_reset"])
  let b = mng_keys_digest(["on_reset", "qty", "t:1"])
  assert_eq(a, b)
  assert_true(a != mng_keys_digest(["t:1", "qty", "on_reset", "t:2"]))
  assert_eq(mng_keys_digest([]), mng_keys_digest([]))
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
  let ir = "{\"v\":1,\"rev\":\"mng-ir-1\",\"page\":\"ghost\",\"root\":{\"k\":\"text\",\"v\":\"x\"}}"
  let r = mng_dev_apply(ir)
  assert_true(
    match r {
      Err(e) => contains_sub_m(e, "ghost") && contains_sub_m(e, "未挂载")
      _ => false
    },
  )
}

///|
test "mng_dev_page：挂载时模板根直接挂进父容器，补丁原位替换保持单棵" {
  let page = "io.moonbitlibyue.wbtest.devpage"
  let reg = mng_reg_new()
  reg.expr("t:1:1", fn() { "初代" })
  let node = mng_dev_page(page, reg, fn() {
    @widget.bind_node(@base.Signal::computed(fn() { true }), fn(_v) {
      @ui.text("初代")
    })
  })
  let parent = @widget.Widget::new()
  let _ = parent.set_column()
  let first = node.mount_into(parent)
  // 虚拟节点不建自己的控件：返回句柄就是父容器的直接子项
  assert_eq(parent.children().length(), 1)
  assert_eq(parent.children()[0].id, first.id)
  let ir = "{\"v\":1,\"rev\":\"mng-ir-1\",\"page\":\"io.moonbitlibyue.wbtest.devpage\",\"root\":{\"k\":\"dyn\",\"key\":\"t:1:1\"},\"exprs\":[\"t:1:1\"],\"states\":[],\"handlers\":[]}"
  match mng_dev_apply(ir) {
    Ok(_) => ()
    Err(e) => abort("apply: " + e)
  }
  assert_eq(parent.children().length(), 1)
  assert_eq(parent.children()[0].role, "text")
  assert_eq(parent.children()[0].label, "初代")
}

///|
test "applier:补丁原位替换不动兄弟与下标" {
  let fires = Ref(0)
  let reg = demo_reg(
    fires,
    @base.Store::new(3),
    @base.Store::new(true),
    @base.Store::new(""),
  )
  let parent = @widget.Widget::new()
  let _ = parent.set_column()
  let before_node = @ui.text("前")
  let before = before_node.mount_into(parent)
  let _ = mng_dev_page("dev_sib", reg, fn() { @ui.text("初代") }).mount_into(parent)
  let after_node = @ui.text("后")
  let after = after_node.mount_into(parent)
  assert_eq(parent.children().length(), 3)
  match mng_dev_apply(demo_ir("dev_sib")) {
    Ok(_) => ()
    Err(e) => abort("\{e}")
  }
  let kids = parent.children()
  assert_eq(kids.length(), 3)
  assert_eq(kids[0].id, before.id)
  assert_eq(kids[1].kind, "ui-col")
  assert_eq(kids[2].id, after.id)
}

///|
test "applier:页已卸载后补丁报未挂载，不往共用父容器里挂树" {
  let fires = Ref(0)
  let reg = demo_reg(
    fires,
    @base.Store::new(3),
    @base.Store::new(true),
    @base.Store::new(""),
  )
  let parent = @widget.Widget::new()
  let _ = parent.set_column()
  let root = mng_dev_page("dev_off", reg, fn() { @ui.text("初代") }).mount_into(parent)
  // 模拟路由切页：页根从父容器摘下
  assert_true(parent.remove_child(root))
  let r = mng_dev_apply(demo_ir("dev_off"))
  assert_true(
    match r {
      Err(e) => contains_sub_m(e, "未挂载")
      _ => false
    },
  )
  assert_eq(parent.children().length(), 0)
}

///|
test "applier:同一模板挂多处时补丁逐处替换" {
  let fires = Ref(0)
  let reg = demo_reg(
    fires,
    @base.Store::new(3),
    @base.Store::new(true),
    @base.Store::new(""),
  )
  let a = @widget.Widget::new()
  let _ = a.set_column()
  let b = @widget.Widget::new()
  let _ = b.set_column()
  let _ = mng_dev_page("dev_multi", reg, fn() { @ui.text("甲") }).mount_into(a)
  let _ = mng_dev_page("dev_multi", reg, fn() { @ui.text("乙") }).mount_into(b)
  match mng_dev_apply(demo_ir("dev_multi")) {
    Ok(_) => ()
    Err(e) => abort("\{e}")
  }
  assert_eq(a.children().length(), 1)
  assert_eq(a.children()[0].kind, "ui-col")
  assert_eq(b.children().length(), 1)
  assert_eq(b.children()[0].kind, "ui-col")
}

///|
test "applier:构树失败时旧树保留" {
  let fires = Ref(0)
  let reg = demo_reg(
    fires,
    @base.Store::new(3),
    @base.Store::new(true),
    @base.Store::new(""),
  )
  let parent = @widget.Widget::new()
  let _ = parent.set_column()
  let _ = mng_dev_page("dev_fail", reg, fn() { @ui.text("初代") }).mount_into(parent)
  let ir = "{\"v\":1,\"rev\":\"mng-ir-1\",\"page\":\"dev_fail\",\"root\":{\"k\":\"unknown\"},\"exprs\":[],\"states\":[],\"handlers\":[]}"
  let r = mng_dev_apply(ir)
  assert_true(
    match r {
      Err(e) => contains_sub_m(e, "不在 applier v1 表内")
      _ => false
    },
  )
  assert_eq(parent.children().length(), 1)
  assert_eq(parent.children()[0].kind, "ui-text")
}
