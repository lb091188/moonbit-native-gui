// Phase 0 探针（proposals/native-template.md「Spike 契约」的运行时验证）：
// 手写 IR + 注册表 + applier v0，证明「结构补丁 → 沿 holder 原位重挂」亚秒、
// 订阅整代退订。IR 是探针手写形态（结构树 + 槽名引用注册表）；编译器落地后
// 由 `.mng` 编译产物的序列化形态替代。落点全部是生产 API，无第二引擎。

///|
/// 注册表槽：dev 档 codegen 生成的按名条目（探针手写等价物）。
priv enum Slot {
  IntSlot(@base.Store[Int])
  DoubleSlot(@base.Store[Double])
  BoolSlot(@base.Store[Bool])
  DynFn(() -> @widget.Node)
}

///|
/// IR 节点：结构树 + 槽名引用（可整体替换的数据）。
priv enum Ir {
  Col(Double, Array[Ir])
  Static(String)
  Dyn(String)
  If(String, Ir, Ir)
  Stepper(String)
  Slider(String)
  Checkbox(String, String)
}

///|
/// IR → 现有声明层：只调生产构造器与 bind 家族。
fn apply_ir(ir : Ir, reg : Map[String, Slot]) -> @widget.Node {
  match ir {
    Col(gap, kids) => @ui.col(kids.map(fn(k) { apply_ir(k, reg) }), row_gap=gap)
    Static(s) => @ui.text(s)
    Dyn(name) =>
      match reg.get(name) {
        Some(DynFn(f)) => f()
        _ => abort("ir_probe：Dyn 槽未注册：" + name)
      }
    If(cond, then_ir, else_ir) =>
      match reg.get(cond) {
        Some(BoolSlot(st)) =>
          @widget.bind_node(st.signal(), fn(on) {
            if on {
              apply_ir(then_ir, reg)
            } else {
              apply_ir(else_ir, reg)
            }
          })
        _ => abort("ir_probe：Bool 槽未注册：" + cond)
      }
    Stepper(name) =>
      match reg.get(name) {
        Some(IntSlot(st)) => @ui.stepper(st, min=0, max=99)
        _ => abort("ir_probe：Int 槽未注册：" + name)
      }
    Slider(name) =>
      match reg.get(name) {
        Some(DoubleSlot(st)) => @ui.slider(st, min=0.0, max=100.0, width=200.0)
        _ => abort("ir_probe：Double 槽未注册：" + name)
      }
    Checkbox(label, name) =>
      match reg.get(name) {
        Some(BoolSlot(st)) => @ui.checkbox(label, st)
        _ => abort("ir_probe：Bool 槽未注册：" + name)
      }
  }
}

///|
/// 一代挂载：构造与挂载同一订阅袋窗口（照抄路由 slot.mbt 的回收纪律）。
priv struct Gen {
  widget : @widget.Widget
  offs : Array[() -> Unit]
}

///|
fn mount_gen(holder : @widget.Widget, ir : Ir, reg : Map[String, Slot]) -> Gen {
  @base.sub_bag_begin()
  let w = apply_ir(ir, reg).mount_into(holder)
  let offs = @base.sub_bag_end()
  { widget: w, offs }
}

///|
/// 摘一代：整袋退订 + 摘树（订阅与控件都不残留）。
fn unmount_gen(holder : @widget.Widget, gen : Gen) -> Unit {
  @base.sub_bag_discard(gen.offs)
  let _ = holder.remove_child(gen.widget)
}

///|
/// 探针页状态与注册表（dev 档 codegen 手写等价物；fires 供泄漏断言）。
fn make_registry(
  qty : @base.Store[Int],
  level : @base.Store[Double],
  wifi : @base.Store[Bool],
  fires : Ref[Int],
) -> Map[String, Slot] {
  let reg : Map[String, Slot] = Map([])
  let _ = reg.set("qty", IntSlot(qty))
  let _ = reg.set("level", DoubleSlot(level))
  let _ = reg.set("wifi", BoolSlot(wifi))
  // 动态文本槽：单源 bind_label 预接线，渲染计数挂在闭包上供断言
  let _ = reg.set(
    "qty_label",
    DynFn(fn() {
      @ui.bind_label(qty, fn(v) {
        fires.val = fires.val + 1
        "当前数量：\{v}"
      })
    }),
  )
  reg
}

///|
/// v1：步进器在上、标签在中、条件块与滑杆在尾。
fn ir_v1() -> Ir {
  Col(
    8.0,
    [
      Stepper("qty"),
      Dyn("qty_label"),
      If("wifi", Static("自动开启：开"), Static("自动开启：关")),
      Slider("level"),
    ],
  )
}

///|
/// v2：结构补丁——标签提到最上、插静态说明、条件块换内容、滑杆删除、步进器挪尾。
fn ir_v2() -> Ir {
  Col(
    8.0,
    [
      Dyn("qty_label"),
      Static("结构已热替换"),
      If("wifi", Checkbox("自动开启", "wifi"), Static("自动开启：关")),
      Stepper("qty"),
    ],
  )
}
