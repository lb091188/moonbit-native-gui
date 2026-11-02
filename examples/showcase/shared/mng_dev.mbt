// 模板 dev 面（应用侧）：IR 注册表 + applier + holder 原位替换。
// 补丁由 dev 工具经单实例通道推送（args = ["--mng-hot", <ir 路径>]）。
// v1 边界：组件 col/row/text/dyn/if/button/checkbox/switch/stepper/input，
// 参数三态 lit/expr/state；动态槽键 = 模板坐标（t:行:列），v-if 键 = c:行:列，
// state 与 handler 键 = 变量/函数名——dev 演示页按坐标手写登记。
// 边界依据见 proposals/native-template.md「结构热更新」节。

///|
/// 类型化注册表：dev 档构建时登记，applier 按键取用；缺项报错并提示。
pub struct MngReg {
  exprs : Map[String, () -> String]
  conds : Map[String, () -> Bool]
  handlers : Map[String, () -> Unit]
  ints : Map[String, @base.Store[Int]]
  bools : Map[String, @base.Store[Bool]]
  strs : Map[String, @base.Store[String]]
}

///|
pub fn mng_reg_new() -> MngReg {
  {
    exprs: Map([]),
    conds: Map([]),
    handlers: Map([]),
    ints: Map([]),
    bools: Map([]),
    strs: Map([]),
  }
}

///|
pub fn MngReg::expr(self : MngReg, key : String, f : () -> String) -> Unit {
  let _ = self.exprs.set(key, f)
}

///|
pub fn MngReg::cond(self : MngReg, key : String, f : () -> Bool) -> Unit {
  let _ = self.conds.set(key, f)
}

///|
pub fn MngReg::handler(self : MngReg, name : String, f : () -> Unit) -> Unit {
  let _ = self.handlers.set(name, f)
}

///|
pub fn MngReg::int(self : MngReg, name : String, s : @base.Store[Int]) -> Unit {
  let _ = self.ints.set(name, s)
}

///|
pub fn MngReg::bool(self : MngReg, name : String, s : @base.Store[Bool]) -> Unit {
  let _ = self.bools.set(name, s)
}

///|
pub fn MngReg::str(self : MngReg, name : String, s : @base.Store[String]) -> Unit {
  let _ = self.strs.set(name, s)
}

// ---------------------------------------------------------------------------
// 极简 JSON 解析（applier 自用）：对象/数组/串/数/布尔/null。补丁是自家
// 编译器产的标准 JSON；vsc_json 面无数组遍历，故内嵌一份最小解析。
// ---------------------------------------------------------------------------

///|
priv enum MJ {
  MObj(Map[String, MJ])
  MArr(Array[MJ])
  MStr(String)
  MNum(Double)
  MBool(Bool)
  MNull
}

///|
priv struct JP {
  cs : Array[Char]
  mut i : Int
}

///|
fn jp_ws(p : JP) -> Unit {
  while p.i < p.cs.length() {
    let c = p.cs[p.i]
    if c == ' ' || c == '\t' || c == '\n' || c == '\r' {
      p.i += 1
    } else {
      break
    }
  }
}

///|
fn jp_fail(msg : String) -> Result[MJ, String] {
  Err("IR JSON 解析失败：" + msg)
}

///|
fn jp_value(p : JP) -> Result[MJ, String] {
  jp_ws(p)
  if p.i >= p.cs.length() {
    return jp_fail("提前结束")
  }
  let c = p.cs[p.i]
  if c == '{' {
    p.i += 1
    let m : Map[String, MJ] = Map([])
    jp_ws(p)
    if p.i < p.cs.length() && p.cs[p.i] == '}' {
      p.i += 1
      return Ok(MObj(m))
    }
    while true {
      jp_ws(p)
      let key = match jp_value(p) {
        Ok(MStr(s)) => s
        _ => return jp_fail("对象键需为字符串")
      }
      jp_ws(p)
      if p.i >= p.cs.length() || p.cs[p.i] != ':' {
        return jp_fail("对象缺冒号")
      }
      p.i += 1
      let v = match jp_value(p) {
        Ok(v) => v
        Err(e) => return Err(e)
      }
      let _ = m.set(key, v)
      jp_ws(p)
      if p.i >= p.cs.length() {
        return jp_fail("对象未闭合")
      }
      if p.cs[p.i] == ',' {
        p.i += 1
        continue
      }
      if p.cs[p.i] == '}' {
        p.i += 1
        return Ok(MObj(m))
      }
      return jp_fail("对象缺逗号或右括号")
    }
    jp_fail("不可达")
  } else if c == '[' {
    p.i += 1
    let arr : Array[MJ] = []
    jp_ws(p)
    if p.i < p.cs.length() && p.cs[p.i] == ']' {
      p.i += 1
      return Ok(MArr(arr))
    }
    while true {
      let v = match jp_value(p) {
        Ok(v) => v
        Err(e) => return Err(e)
      }
      arr.push(v)
      jp_ws(p)
      if p.i >= p.cs.length() {
        return jp_fail("数组未闭合")
      }
      if p.cs[p.i] == ',' {
        p.i += 1
        continue
      }
      if p.cs[p.i] == ']' {
        p.i += 1
        return Ok(MArr(arr))
      }
      return jp_fail("数组缺逗号或右括号")
    }
    jp_fail("不可达")
  } else if c == '"' {
    p.i += 1
    let out : Array[String] = []
    while p.i < p.cs.length() && p.cs[p.i] != '"' {
      let ch = p.cs[p.i]
      if ch == '\\' && p.i + 1 < p.cs.length() {
        let n = p.cs[p.i + 1]
        if n == 'n' {
          out.push("\n")
        } else if n == 't' {
          out.push("\t")
        } else if n == 'r' {
          out.push("\r")
        } else {
          out.push(n.to_string())
        }
        p.i += 2
      } else {
        out.push(ch.to_string())
        p.i += 1
      }
    }
    if p.i >= p.cs.length() {
      return jp_fail("字符串未闭合")
    }
    p.i += 1
    Ok(MStr(out.join("")))
  } else if c == 't' {
    if p.i + 4 <= p.cs.length() &&
      p.cs[p.i + 1] == 'r' &&
      p.cs[p.i + 2] == 'u' &&
      p.cs[p.i + 3] == 'e' {
      p.i += 4
      Ok(MBool(true))
    } else {
      jp_fail("字面量非法")
    }
  } else if c == 'f' {
    if p.i + 5 <= p.cs.length() &&
      p.cs[p.i + 1] == 'a' &&
      p.cs[p.i + 2] == 'l' &&
      p.cs[p.i + 3] == 's' &&
      p.cs[p.i + 4] == 'e' {
      p.i += 5
      Ok(MBool(false))
    } else {
      jp_fail("字面量非法")
    }
  } else if c == 'n' {
    if p.i + 4 <= p.cs.length() &&
      p.cs[p.i + 1] == 'u' &&
      p.cs[p.i + 2] == 'l' &&
      p.cs[p.i + 3] == 'l' {
      p.i += 4
      Ok(MNull)
    } else {
      jp_fail("字面量非法")
    }
  } else {
    // 数字
    let start = p.i
    while p.i < p.cs.length() {
      let d = p.cs[p.i]
      if (d >= '0' && d <= '9') || d == '-' || d == '+' || d == '.' || d == 'e' || d == 'E' {
        p.i += 1
      } else {
        break
      }
    }
    let seg = p.cs[start:p.i].map(fn(c) { c.to_string() }).join("")
    match mnum(seg) {
      Some(v) => Ok(MNum(v))
      None => jp_fail("数字非法：" + seg)
    }
  }
}

///|
fn mnum(s : String) -> Double? {
  let cs = chars_of_m(s)
  let mut neg = false
  let mut i = 0
  if i < cs.length() && cs[i] == '-' {
    neg = true
    i += 1
  }
  let mut int_part = 0.0
  let mut digits = 0
  while i < cs.length() && cs[i] >= '0' && cs[i] <= '9' {
    int_part = int_part * 10.0 + (cs[i].to_int() - '0'.to_int()).to_double()
    digits += 1
    i += 1
  }
  let mut frac = 0.0
  let mut scale = 0.1
  if i < cs.length() && cs[i] == '.' {
    i += 1
    while i < cs.length() && cs[i] >= '0' && cs[i] <= '9' {
      frac += (cs[i].to_int() - '0'.to_int()).to_double() * scale
      scale = scale * 0.1
      digits += 1
      i += 1
    }
  }
  if digits == 0 {
    return None
  }
  let v = int_part + frac
  Some(if neg { -v } else { v })
}

///|
fn chars_of_m(s : String) -> Array[Char] {
  let out : Array[Char] = []
  for c in s {
    out.push(c)
  }
  out
}

///|
fn mj_get(m : MJ, key : String) -> MJ? {
  match m {
    MObj(o) => o.get(key)
    _ => None
  }
}

///|
fn mj_str(m : MJ?) -> String? {
  match m {
    Some(MStr(s)) => Some(s)
    Some(MBool(b)) => Some(if b { "true" } else { "false" })
    _ => None
  }
}

///|
fn mj_num(m : MJ?) -> Double? {
  match m {
    Some(MNum(v)) => Some(v)
    _ => None
  }
}

///|
fn mj_arr(m : MJ?) -> Array[MJ]? {
  match m {
    Some(MArr(a)) => Some(a)
    _ => None
  }
}

// ---------------------------------------------------------------------------
// applier：MJ 树 → @widget.Node（只调生产构造器；动态槽查注册表）
// ---------------------------------------------------------------------------

///|
/// 页 → 内容容器（模板补丁的原位替换落点）。
let mng_holders : Map[String, @widget.Widget] = Map([])

///|
/// 页 → (现役树, 该代订阅退订函数)。
let mng_lives : Map[String, (@widget.Widget, Array[() -> Unit])] = Map([])

///|
/// 页 → 注册表（`page` 取 IR 的 `page` 键，即模板文件 stem）。
let mng_regs : Map[String, MngReg] = Map([])

///|
/// dev 档页面壳：登记注册表与 holder，把 `build()` 的树挂进 holder 并记为现役代。
/// script 段在 `build` 外执行（状态建一代），补丁只重建 `build()` 的树——状态保活。
pub fn mng_dev_page(page : String, reg : MngReg, build : () -> @widget.Node) -> @widget.Node {
  mng_dev_set_reg(page, reg)
  @widget.node_of_new(fn(holder : @widget.Widget) {
    mng_dev_bind_holder(page, holder)
    // 构树 + 挂载同处一个订阅袋窗口（computed 的依赖订阅发生在构造时）
    @base.sub_bag_begin()
    let node = build()
    let child = node.mount_into(holder)
    let offs = @base.sub_bag_end()
    let _ = mng_lives.set(page, (child, offs))
    holder
  })
}

///|
/// dev 页登记内容容器（按页登记，补丁按 IR 的 `page` 取）。
pub fn mng_dev_bind_holder(page : String, w : @widget.Widget) -> Unit {
  let _ = mng_holders.set(page, w)
}

///|
fn mreg_miss(kind : String, key : String) -> String {
  "注册表缺 \{kind}「\{key}」——dev 页按模板坐标登记（IR 的 requires 清单见补丁）"
}

///|
fn mj_node(j : MJ, reg : MngReg) -> Result[@widget.Node, String] {
  let kind = match mj_str(mj_get(j, "k")) {
    Some(s) => s
    None => return Err("IR 节点缺 k")
  }
  match kind {
    "text" =>
      match mj_str(mj_get(j, "v")) {
        Some(v) => Ok(@ui.text(v))
        None => Err("text 节点缺 v")
      }
    "dyn" =>
      match mj_str(mj_get(j, "key")) {
        Some(key) =>
          match reg.exprs.get(key) {
            Some(f) =>
              Ok(@ui.bind(@base.Signal::computed(f), fn(s : String) { s }))
            None => Err(mreg_miss("动态文本", key))
          }
        None => Err("dyn 节点缺 key")
      }
    "if" => {
      let key = match mj_str(mj_get(j, "c")) {
        Some(s) => s
        None => return Err("if 节点缺 c")
      }
      let t = match mj_get(j, "t") {
        Some(x) => x
        None => return Err("if 节点缺 t")
      }
      let f = match mj_get(j, "f") {
        Some(x) => x
        None => return Err("if 节点缺 f")
      }
      let then = match mj_node(t, reg) {
        Ok(n) => n
        Err(e) => return Err(e)
      }
      let els = match mj_node(f, reg) {
        Ok(n) => n
        Err(e) => return Err(e)
      }
      match reg.conds.get(key) {
        Some(c) =>
          Ok(
            @widget.bind_node(@base.Signal::computed(c), fn(on : Bool) {
              if on {
                then
              } else {
                els
              }
            }),
          )
        None => Err(mreg_miss("条件", key))
      }
    }
    "col" | "row" => {
      let kids : Array[@widget.Node] = []
      match mj_arr(mj_get(j, "kids")) {
        Some(arr) =>
          for k in arr {
            match mj_node(k, reg) {
              Ok(n) => kids.push(n)
              Err(e) => return Err(e)
            }
          }
        None => ()
      }
      let gap = match mj_num(mj_get(j, "gap")) {
        Some(v) => v
        None => 0.0
      }
      if kind == "col" {
        Ok(@ui.col(kids, row_gap=gap, grow=1.0))
      } else {
        Ok(@ui.row(kids, column_gap=gap, grow=1.0))
      }
    }
    "button" => {
      let text = match mj_param(j, "text", reg, "") {
        Ok(n) => n
        Err(e) => return Err(e)
      }
      let click : (() -> Unit)? = match mj_str(mj_get(j, "click")) {
        Some(h) =>
          match reg.handlers.get(h) {
            Some(f) => Some(f)
            None => return Err(mreg_miss("事件", h))
          }
        None => None
      }
      // text 参数：静态直出；动态包 bind；click 可选
      Ok(text.node(fn(s : String) {
        match click {
          Some(f) => @ui.button(s, on_click=f)
          None => @ui.button(s)
        }
      }))
    }
    "checkbox" | "switch" => {
      let name = match state_of(j) {
        Some(s) => s
        None => return Err("\{kind} 节点缺 state")
      }
      match reg.bools.get(name) {
        Some(st) => {
          if kind == "checkbox" {
            let label = match mj_param(j, "label", reg, "") {
              Ok(p) => p
              Err(e) => return Err(e)
            }
            Ok(@ui.checkbox(label.now(), st))
          } else {
            Ok(@ui.switch(st))
          }
        }
        None => Err(mreg_miss("布尔状态", name))
      }
    }
    "stepper" => {
      let name = match state_of(j) {
        Some(s) => s
        None => return Err("stepper 节点缺 state")
      }
      match reg.ints.get(name) {
        Some(st) => {
          let mx = match mj_num(mj_arg(j, "max")) {
            Some(v) => v.to_int()
            None => 99
          }
          let mn = match mj_num(mj_arg(j, "min")) {
            Some(v) => v.to_int()
            None => 0
          }
          Ok(@ui.stepper(st, min=mn, max=mx))
        }
        None => Err(mreg_miss("整数状态", name))
      }
    }
    "input" => {
      let name = match state_of(j) {
        Some(s) => s
        None => return Err("input 节点缺 state")
      }
      match reg.strs.get(name) {
        Some(st) => {
          let ph = match mj_param(j, "placeholder", reg, "") {
            Ok(p) => p
            Err(e) => return Err(e)
          }
          let phs = match ph {
            MParamStatic(s) => s
            MParamDyn(_) => ""
          }
          Ok(@ui.input(st, placeholder=phs))
        }
        None => Err(mreg_miss("字符串状态", name))
      }
    }
    other => Err("组件「\{other}」不在 applier v1 表内——回 COLD 重启")
  }
}

///|
priv enum MParam {
  MParamStatic(String)
  MParamDyn(@base.Signal[String])
}

///|
/// 参数当前值快照：静态直取；动态取信号现值（v1：String 形参的动态标签
/// 只做快照不订阅——记档，待组件 _dyn 面升格）。
fn MParam::now(self : MParam) -> String {
  match self {
    MParamStatic(s) => s
    MParamDyn(sig) => sig.get()
  }
}

///|
/// 参数节点化：静态直出；动态包 bind（值变原位重建该件）。
fn MParam::node(self : MParam, make : (String) -> @widget.Node) -> @widget.Node {
  match self {
    MParamStatic(s) => make(s)
    MParamDyn(sig) => @widget.bind_node(sig, fn(s : String) { make(s) })
  }
}

///|
fn state_of(j : MJ) -> String? {
  match mj_arg(j, "value") {
    Some(v) => mj_str(mj_get(v, "state"))
    None => None
  }
}

///|
fn mj_arg(j : MJ, name : String) -> MJ? {
  match mj_get(j, "args") {
    Some(args) => mj_get(args, name)
    None => None
  }
}

///|
/// 参数取值：lit → 静态串；expr → 注册表动态信号。fallback 为静态缺省串。
fn mj_param(j : MJ, name : String, reg : MngReg, default : String) -> Result[MParam, String] {
  match mj_arg(j, name) {
    None => Ok(MParamStatic(default))
    Some(v) =>
      match mj_get(v, "lit") {
        Some(lit) =>
          match mj_str(Some(lit)) {
            Some(s) => Ok(MParamStatic(s))
            None => Ok(MParamStatic(default))
          }
        None =>
          match mj_str(mj_get(v, "expr")) {
            Some(key) =>
              match reg.exprs.get(key) {
                Some(f) => Ok(MParamDyn(@base.Signal::computed(f)))
                None => Err(mreg_miss("动态参数", key))
              }
            None => Ok(MParamStatic(default))
          }
      }
  }
}

///|
/// 补丁应用：解析 → 按 `page` 取页 → 构树 → 沿登记 holder 原位替换（整代退订照路由纪律）。
pub fn mng_dev_apply(json : String) -> Result[Unit, String] {
  let parsed = match jp_value({ cs: chars_of_m(json), i: 0 }) {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let page = match mj_str(mj_get(parsed, "page")) {
    Some(p) => p
    None => return Err("补丁缺 page")
  }
  let holder = match mng_holders.get(page) {
    Some(h) => h
    None => return Err("页「\{page}」未挂载（holder 未登记）——先打开该页")
  }
  let root = match mj_get(parsed, "root") {
    Some(r) => r
    None => return Err("补丁缺 root")
  }
  let reg = match mng_regs.get(page) {
    Some(r) => r
    None => return Err("页「\{page}」未登记注册表——该页挂载时用 mng_dev_set_reg 登记")
  }
  // 摘旧：整袋退订（照路由 slot 的回收纪律）
  match mng_lives.get(page) {
    Some((old, offs)) => {
      @base.sub_bag_discard(offs)
      let _ = holder.remove_child(old)
    }
    None => ()
  }
  // 构树 + 挂载必须同处一个订阅袋窗口——computed 的依赖订阅发生在构造时，
  // 只包 mount_into 会让旧代 computed 的订阅漏出回收袋（探针钉过的口径）
  @base.sub_bag_begin()
  let node = match mj_node(root, reg) {
    Ok(n) => n
    Err(e) => {
      @base.sub_bag_discard(@base.sub_bag_end())
      return Err(e)
    }
  }
  let w = node.mount_into(holder)
  let offs = @base.sub_bag_end()
  let _ = mng_lives.set(page, (w, offs))
  @widget.invalidate()
  Ok(())
}

///|
/// dev 页挂载时按页登记注册表（键与 IR 的 `page` 一致 = 模板文件 stem）。
pub fn mng_dev_set_reg(page : String, reg : MngReg) -> Unit {
  let _ = mng_regs.set(page, reg)
}

///|
/// 从补丁文件应用（wake 回调入口）：读文件 → apply。
pub fn mng_dev_apply_from_file(path : String) -> Result[Unit, String] {
  let text = @fs.read_file_to_string(path) catch {
    _ => return Err("读不到补丁文件：" + path)
  }
  mng_dev_apply(text)
}
