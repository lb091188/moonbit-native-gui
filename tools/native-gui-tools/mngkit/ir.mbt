// IR 输出：模板编译器第二产物（dev 档热更新供给端）。结构是数据、行为按
// 键引用——结构补丁经单实例通道进应用，applier 查注册表原位重建。
// v2 边界：内置 18 标签全进补丁（容器带 children、表单与值类带全部参数），
// 参数值五态（lit 字面量 / litarr 字符串数组字面量 / expr 动态串槽 / state
// 值槽目标 / 事件 handler 名）；数值与布尔参数只收字面量，动态数值表达式
// 不在受限文法内即转 COLD。动态槽键用表达式内容哈希（t:<hash> / c:<hash>），
// 结构增删挪不换键；节点可带 class 名，补丁另带 classes（类定义数据）与
// eval（新表达式 AST）；v2 规格表（comp_v2_spec）外的组件与参数进 IR 即报
// （应用侧转 COLD）。规格表与 applier 是同一张契约的两端，改动两端同批。

///|
priv enum IrVal {
  ILitStr(String)
  ILitNum(String)
  ILitBool(String)
  ILitArr(Array[String])
  IExpr(String)
  IState(String)
}

///|
fn ir_val_of(a : Attr) -> IrVal {
  match a.kind {
    Model => IState(a.value.trim().to_owned())
    Dyn => IExpr(bind_key("t", a.value.trim().to_owned()))
    _ => {
      // 静态：数字 / 布尔 / 字符串字面量（单引号=MoonBit 串，双引号=串）/ 裸串
      let v = a.value.trim().to_owned()
      let cs = chars_of(v)
      let n = cs.length()
      if n >= 2 && cs[0] == '\'' && cs[n - 1] == '\'' {
        ILitStr(v[1:n - 1].to_owned())
      } else if n >= 2 && cs[0] == '"' && cs[n - 1] == '"' {
        ILitStr(v[1:n - 1].to_owned())
      } else if v == "true" || v == "false" {
        ILitBool(v)
      } else {
        let mut digits = 0
        let mut dots = 0
        let mut num = n > 0
        let mut i = if n > 0 && cs[0] == '-' { 1 } else { 0 }
        while i < n {
          let c = cs[i]
          if is_digit(c) {
            digits += 1
          } else if c == '.' {
            dots += 1
          } else {
            num = false
          }
          i += 1
        }
        if num && digits > 0 && dots <= 1 {
          ILitNum(v)
        } else {
          ILitStr(v)
        }
      }
    }
  }
}

///|
fn ir_val_json(v : IrVal) -> String {
  match v {
    ILitStr(s) => "{\"lit\":\"" + jstr(s) + "\"}"
    ILitNum(x) => "{\"lit\":" + x + "}"
    ILitBool(b) => "{\"lit\":\"" + b + "\"}"
    ILitArr(xs) => {
      let items : Array[String] = []
      for x in xs {
        items.push("\"" + jstr(x) + "\"")
      }
      "{\"litarr\":[" + items.join(",") + "]}"
    }
    IExpr(e) => "{\"expr\":\"" + jstr(e) + "\"}"
    IState(s) => "{\"state\":\"" + jstr(s) + "\"}"
  }
}

///|
priv enum IrNode {
  IText(String) // 纯文本子节点
  IDynText(String) // 纯文本插值
  ITextEl(String, Array[String]) // <ui-text> 静态
  IDynTextEl(String, Array[String]) // <ui-text> 动态
  IIf(String, IrNode, IrNode)
  // tag, 参数, 子元素, 事件（模板事件名 → handler 名）, class
  IComp(String, Array[(String, IrVal)], Array[IrNode], Array[(String, String)], Array[String])
}

///|
/// 极简 JSON 字符串转义（IR 输出用；应用侧 vsc_json_parse 读回）。
fn jstr(s : String) -> String {
  let out : Array[String] = []
  for c in s {
    if c == '"' {
      out.push("\\\"")
    } else if c == '\\' {
      out.push("\\\\")
    } else if c == '\n' {
      out.push("\\n")
    } else if c == '\t' {
      out.push("\\t")
    } else if c == '\r' {
      out.push("\\r")
    } else {
      out.push(c.to_string())
    }
  }
  out.join("")
}

///|
/// 模板树 → IR 节点。返回 Err 即该节点超出热更边界（应用侧转 COLD）。
fn ir_of_node(node : TNode, out : Array[IrNode]) -> Result[Unit, String] {
  match node {
    Text(raw, pos) => {
      let norm = normalize_text(raw)
      if norm.length() == 0 {
        return Ok(())
      }
      let pieces = match split_interp(norm, pos) {
        Ok(p) => p
        Err(e) => return Err(e)
      }
      let mut has_expr = false
      for p in pieces {
        match p {
          PExpr(_) => has_expr = true
          _ => ()
        }
      }
      if has_expr {
        out.push(IDynText(bind_key("t", norm)))
      } else {
        out.push(IText(norm))
      }
      Ok(())
    }
    Elem(tag, attrs, children, pos) => {
      let mut show : Attr? = None
      let mut cond : Attr? = None
      let classes : Array[String] = []
      for a in attrs {
        match a.kind {
          Show => show = Some(a)
          If => cond = Some(a)
          For =>
            return Err("\{pos_str(pos)}：v-for 不在热更边界（应用侧转 COLD）")
          Plain =>
            if a.name == "class" {
              for n in class_names_of(a.value) {
                classes.push(n)
              }
            }
          Dyn =>
            if a.name == "class" {
              return Err(
                "\{pos_str(a.pos)}：动态 class 不在热更边界（应用侧转 COLD）",
              )
            }
          _ => ()
        }
      }
      // 自定义组件先按声明表挡下（v2 补丁不跨补丁重建自定义组件）
      match resolve_comp(tag, pos) {
        Ok(_) => ()
        Err(e) => return Err(e)
      }
      // 递归子节点（含 v-else 回填）
      let kids : Array[IrNode] = []
      match ir_seq(children, kids) {
        Ok(_) => ()
        Err(e) => return Err(e)
      }
      let cond_attr = match cond {
        Some(a) => Some(a)
        None => show
      }
      let cond_key = match cond_attr {
        Some(a) => bind_key("c", a.value.trim().to_owned())
        None => ""
      }
      let built : IrNode = if tag == "ui-text" {
        // 文本内容：:text 动态 → expr 槽；静态 → 字面
        for a in attrs {
          match a.kind {
            Plain | Dyn =>
              if a.name != "text" && a.name != "class" {
                return Err(
                  "\{pos_str(a.pos)}：<ui-text> 的参数 \{a.name} 不在补丁表（应用侧转 COLD）",
                )
              }
            Event | Model =>
              return Err(
                "\{pos_str(a.pos)}：<ui-text> 的事件/绑定不在补丁表（应用侧转 COLD）",
              )
            _ => ()
          }
        }
        let mut found : Attr? = None
        for a in attrs {
          match a.kind {
            Dyn | Plain => if a.name == "text" { found = Some(a) }
            _ => ()
          }
        }
        match found {
          Some(a) =>
            match a.kind {
              Dyn =>
                IDynTextEl(bind_key("t", a.value.trim().to_owned()), classes)
              _ => ITextEl(text_of_lit(a), classes)
            }
          None =>
            if kids.length() == 1 {
              match kids[0] {
                IText(s) => IText(s)
                IDynText(k) => IDynText(k)
                _ => IText("")
              }
            } else if kids.length() == 0 {
              IText("")
            } else {
              return Err("\{pos_str(pos)}：<ui-text> 的 text 混入子元素（热更边界）")
            }
        }
      } else {
        let spec = match comp_v2_spec(tag) {
          Some(s) => s
          None =>
            return Err(
              "\{pos_str(pos)}：组件 <\{tag}> 不在补丁表（应用侧转 COLD）",
            )
        }
        match comp_of(tag, spec, attrs, children, kids, classes, pos) {
          Ok(n) => n
          Err(e) => return Err(e)
        }
      }
      // v-show / v-if 包裹
      match cond_attr {
        Some(_) => out.push(IIf(cond_key, built, IText("")))
        None => out.push(built)
      }
      Ok(())
    }
  }
}

///|
/// v2 组件规格：一个内置标签的参数清单与槽型。工具侧出口（本文件收参）与
/// 应用侧入口（mng_dev.mbt 构树）读同一张契约——改动两端同批。
priv struct CompSpec {
  /// 数值参数（只收字面量；动态数值不在受限文法内）
  nums : Array[String]
  /// 字符串参数（静态直出；可动态的子集另见 dyn_strs）
  strs : Array[String]
  /// 可动态的字符串参数（expr 槽）
  dyn_strs : Array[String]
  /// 布尔参数（只收字面量）
  bools : Array[String]
  /// 字符串数组字面量参数（options 类）
  arrs : Array[String]
  /// 事件：模板事件名 → 处理器槽型（unit/str/bool/int）
  events : Array[(String, String)]
  /// 有 v-model 值槽（值类组件才有）
  has_value : Bool
  /// 子元素落点："children" / "child" / ""
  kids : String
}

///|
fn spec_empty() -> CompSpec {
  {
    nums: [],
    strs: [],
    dyn_strs: [],
    bools: [],
    arrs: [],
    events: [],
    has_value: false,
    kids: "",
  }
}

///|
/// 内置标签的 v2 规格。数值/布尔参数名与槽型照 `@ui` 构造器默认值清单；
/// applier 侧按同一清单构树（缺省传构造器默认值，与不传等价）。
fn comp_v2_spec(tag : String) -> CompSpec? {
  match tag {
    "ui-col" => Some({ ..spec_empty(), nums: container_nums, kids: "children" })
    "ui-row" => Some({ ..spec_empty(), nums: container_nums, kids: "children" })
    "ui-view" =>
      Some({
        ..spec_empty(),
        nums: ["row_gap", "column_gap", "padding", "width", "height", "grow", "corner_radius"],
        kids: "children",
      })
    "ui-panel" =>
      Some({
        ..spec_empty(),
        nums: ["padding", "row_gap", "width"],
        strs: ["title"],
        kids: "children",
      })
    "ui-scroll-view" =>
      Some({
        ..spec_empty(),
        nums: ["width", "height", "min_content_width"],
        bools: ["hscroll", "vscroll"],
        kids: "children",
      })
    "ui-form" =>
      Some({
        ..spec_empty(),
        nums: ["row_gap"],
        strs: ["title"],
        kids: "children",
      })
    "ui-form-item" =>
      Some({ ..spec_empty(), nums: ["label_width"], strs: ["label"], kids: "child" })
    "ui-text" => Some({ ..spec_empty(), strs: ["text"] })
    "ui-button" =>
      Some({
        ..spec_empty(),
        strs: ["text"],
        dyn_strs: ["text"],
        bools: ["disabled"],
        events: [("click", "unit")],
      })
    "ui-input" =>
      Some({
        ..spec_empty(),
        nums: ["width"],
        strs: ["placeholder"],
        dyn_strs: ["placeholder"],
        bools: ["password", "read_only", "clearable"],
        events: [("change", "str"), ("enter", "unit")],
        has_value: true,
      })
    "ui-textarea" =>
      Some({
        ..spec_empty(),
        nums: ["rows", "width"],
        strs: ["placeholder"],
        dyn_strs: ["placeholder"],
        bools: ["read_only"],
        events: [("change", "str")],
        has_value: true,
      })
    "ui-stepper" =>
      Some({ ..spec_empty(), nums: ["min", "max", "step"], has_value: true })
    "ui-slider" =>
      Some({ ..spec_empty(), nums: ["min", "max", "step"], has_value: true })
    "ui-rate" =>
      Some({
        ..spec_empty(),
        nums: ["max", "size", "gap"],
        events: [("change", "int")],
        has_value: true,
      })
    "ui-switch" =>
      Some({
        ..spec_empty(),
        strs: ["on_text", "off_text"],
        bools: ["disabled"],
        events: [("change", "bool")],
        has_value: true,
      })
    "ui-checkbox" =>
      Some({
        ..spec_empty(),
        strs: ["label"],
        dyn_strs: ["label"],
        bools: ["disabled"],
        has_value: true,
      })
    "ui-radio-group" =>
      Some({
        ..spec_empty(),
        nums: ["gap"],
        bools: ["disabled"],
        arrs: ["options"],
        has_value: true,
      })
    "ui-select" =>
      Some({
        ..spec_empty(),
        nums: ["width"],
        strs: ["placeholder"],
        dyn_strs: ["placeholder"],
        bools: ["clearable", "editable"],
        arrs: ["options"],
        events: [("change", "str")],
        has_value: true,
      })
    _ => None
  }
}

///|
/// 容器类共用的数值参数（col/row 全参面；view 另带 corner_radius）。
let container_nums : Array[String] = [
  "row_gap", "column_gap", "padding", "width", "height", "grow",
]

///|
/// MoonBit 字符串数组字面量 → 项列表（`["a", "b"]`；只收引号串与逗号，
/// 含转义的项不收，转 COLD）。
fn str_arr_of(v : String) -> Array[String]? {
  let s = v.trim().to_owned()
  let cs = chars_of(s)
  let n = cs.length()
  if n < 2 || cs[0] != '[' || cs[n - 1] != ']' {
    return None
  }
  let out : Array[String] = []
  let mut i = 1
  while i < n - 1 {
    let c = cs[i]
    if c == ',' || c == ' ' || c == '\t' || c == '\n' || c == '\r' {
      i += 1
      continue
    }
    if c != '\'' && c != '"' {
      return None
    }
    let q = c
    i += 1
    let buf = StringBuilder()
    let mut closed = false
    while i < n - 1 {
      let ch = cs[i]
      if ch == '\\' {
        return None
      }
      if ch == q {
        closed = true
        i += 1
        break
      }
      buf.write_char(ch)
      i += 1
    }
    if !closed {
      return None
    }
    out.push(buf.to_string())
  }
  Some(out)
}

///|
/// 通用组件 → IComp：按规格表收参数与事件；表外参数报错不静默丢。
fn comp_of(
  tag : String,
  spec : CompSpec,
  attrs : Array[Attr],
  children : Array[TNode],
  kids : Array[IrNode],
  classes : Array[String],
  pos : Pos,
) -> Result[IrNode, String] {
  // 子元素落点
  let kid_nodes : Array[IrNode] = match spec.kids {
    "children" => kids
    "child" => {
      if kids.length() != 1 {
        return Err(
          "\{pos_str(pos)}：<\{tag}> 需要恰好一个子元素（现 \{kids.length()}）",
        )
      }
      kids
    }
    _ => {
      if kids.length() > 0 {
        return Err("\{pos_str(pos)}：<\{tag}> 不收子元素（热更边界）")
      }
      []
    }
  }
  let args : Array[(String, IrVal)] = []
  let events : Array[(String, String)] = []
  for a in attrs {
    match a.kind {
      Model =>
        if spec.has_value {
          let v = a.value.trim().to_owned()
          if v.length() > 0 {
            args.push(("value", IState(v)))
          }
        } else {
          return Err(
            "\{pos_str(a.pos)}：<\{tag}> 的 v-model 不在补丁表（应用侧转 COLD）",
          )
        }
      Event => {
        let mut kind_ok = false
        for e in spec.events {
          if e.0 == a.name {
            kind_ok = true
          }
        }
        if !kind_ok {
          return Err(
            "\{pos_str(a.pos)}：<\{tag}> 的事件 @\{a.name} 不在补丁表（应用侧转 COLD）",
          )
        }
        events.push((a.name, a.value.trim().to_owned()))
      }
      Plain | Dyn => {
        if a.name == "class" {
          continue
        }
        match comp_arg_of(tag, spec, a) {
          Ok(Some(pair)) => args.push(pair)
          Ok(None) => ()
          Err(e) => return Err(e)
        }
      }
      _ => ()
    }
  }
  // 元素文本（text 参数）：无 text 属性且子元素全是文本时收
  if arr_contains(spec.strs, "text") && !args_has(args, "text") {
    let mut raw = ""
    let mut bad = false
    for c in children {
      match c {
        Text(x, _) => raw = raw + x
        _ => bad = true
      }
    }
    if bad {
      return Err("\{pos_str(pos)}：<\{tag}> 的 text 混入子元素（热更边界）")
    }
    let raw = normalize_text(raw)
    if has_interp(raw) {
      args.push(("text", IExpr(bind_key("t", raw))))
    } else if raw.length() > 0 {
      args.push(("text", ILitStr(raw)))
    }
  }
  Ok(IComp(tag, args, kid_nodes, events, classes))
}

///|
/// 单个标签参数 → IR 值：按规格分类（数组 / 数值 / 布尔 / 字符串）。
fn comp_arg_of(
  tag : String,
  spec : CompSpec,
  a : Attr,
) -> Result[(String, IrVal)?, String] {
  let name = a.name
  if arr_contains(spec.arrs, name) {
    match str_arr_of(a.value) {
      Some(xs) => Ok(Some((name, ILitArr(xs))))
      None =>
        Err(
          "\{pos_str(a.pos)}：<\{tag}> 的参数 \{name} 只收字符串数组字面量（应用侧转 COLD）",
        )
    }
  } else if arr_contains(spec.nums, name) {
    if a.kind is Dyn {
      return Err(
        "\{pos_str(a.pos)}：<\{tag}> 的动态参数 \{name} 不在补丁表（应用侧转 COLD）",
      )
    }
    match ir_val_of(a) {
      ILitNum(x) => Ok(Some((name, ILitNum(x))))
      ILitStr(s) =>
        if is_number_text(s.trim().to_owned()) {
          Ok(Some((name, ILitNum(s.trim().to_owned()))))
        } else {
          Err(
            "\{pos_str(a.pos)}：<\{tag}> 的参数 \{name} 需数字字面量（应用侧转 COLD）",
          )
        }
      _ =>
        Err(
          "\{pos_str(a.pos)}：<\{tag}> 的参数 \{name} 需数字字面量（应用侧转 COLD）",
        )
    }
  } else if arr_contains(spec.bools, name) {
    if a.kind is Dyn {
      return Err(
        "\{pos_str(a.pos)}：<\{tag}> 的动态参数 \{name} 不在补丁表（应用侧转 COLD）",
      )
    }
    if !a.has_value {
      Ok(Some((name, ILitBool("true"))))
    } else {
      match ir_val_of(a) {
        ILitBool(b) => Ok(Some((name, ILitBool(b))))
        _ =>
          Err(
            "\{pos_str(a.pos)}：<\{tag}> 的参数 \{name} 需布尔字面量（应用侧转 COLD）",
          )
      }
    }
  } else if arr_contains(spec.strs, name) {
    if a.kind is Dyn && !arr_contains(spec.dyn_strs, name) {
      return Err(
        "\{pos_str(a.pos)}：<\{tag}> 的动态参数 \{name} 不在补丁表（应用侧转 COLD）",
      )
    }
    Ok(Some((name, ir_val_of(a))))
  } else {
    Err(
      "\{pos_str(a.pos)}：<\{tag}> 的参数 \{name} 不在补丁表（应用侧转 COLD）",
    )
  }
}

///|
fn text_of_lit(a : Attr) -> String {
  match ir_val_of(a) {
    ILitStr(s) => s
    _ => a.value.trim().to_owned()
  }
}

///|

///|
/// 手写定点的 double 解析（IR 里的字面量数字；格式在 ir_val_of 已验证）。
fn parse_double(s : String) -> Double {
  let cs = chars_of(s)
  let mut neg = false
  let mut i = 0
  if i < cs.length() && cs[i] == '-' {
    neg = true
    i += 1
  }
  let mut int_part = 0.0
  while i < cs.length() && is_digit(cs[i]) {
    int_part = int_part * 10.0 + (cs[i].to_int() - '0'.to_int()).to_double()
    i += 1
  }
  let mut frac = 0.0
  let mut scale = 0.1
  if i < cs.length() && cs[i] == '.' {
    i += 1
    while i < cs.length() && is_digit(cs[i]) {
      frac += (cs[i].to_int() - '0'.to_int()).to_double() * scale
      scale = scale * 0.1
      i += 1
    }
  }
  let v = int_part + frac
  if neg {
    -v
  } else {
    v
  }
}

///|
fn resolve_comp(tag : String, pos : Pos) -> Result[CompDecl, String] {
  if tag.has_prefix("ui-") {
    match builtin_decl(tag) {
      Some(d) => Ok(d)
      None => Err("\{pos_str(pos)}：组件 <\{tag}> 未登记内置表")
    }
  } else {
    // let 绑定组件在补丁里按黑盒处理（v2 不跨补丁重建自定义组件）
    Err(
      "\{pos_str(pos)}：自定义组件 <\{tag}> 不在热更边界（应用侧转 COLD）",
    )
  }
}

///|
fn args_has(args : Array[(String, IrVal)], name : String) -> Bool {
  let mut i = 0
  while i < args.length() {
    if args[i].0 == name {
      return true
    }
    i += 1
  }
  false
}

///|
/// 兄弟序列 → IR：逐节点转换 + v-else 回填最近未填的 IIf；v-else-if 报边界。
fn ir_seq(nodes : Array[TNode], out : Array[IrNode]) -> Result[Unit, String] {
  for node in nodes {
    match node {
      Elem(_, attrs, _, pos) => {
        let mut has_else = false
        for a in attrs {
          match a.kind {
            Else => has_else = true
            ElseIf =>
              return Err(
                "\{pos_str(pos)}：v-else-if 链不在 热更边界（应用侧转 COLD）",
              )
            _ => ()
          }
        }
        if has_else {
          let mut done = false
          let mut k = out.length()
          while k > 0 {
            match out[k - 1] {
              IIf(c, t, IText(s2)) =>
                if s2 == "" {
                  let _ = out.remove(k - 1)
                  let alt : Array[IrNode] = []
                  match ir_of_node(node, alt) {
                    Ok(_) => ()
                    Err(e) => return Err(e)
                  }
                  let f = if alt.length() == 1 {
                    alt[0]
                  } else if alt.length() == 0 {
                    IText("")
                  } else {
                    IComp("ui-col", [], alt, [], [])
                  }
                  out.push(IIf(c, t, f))
                  done = true
                  break
                }
              _ => ()
            }
            k -= 1
          }
          if !done {
            return Err("\{pos_str(pos)}：孤儿 v-else")
          }
        } else {
          match ir_of_node(node, out) {
            Ok(_) => ()
            Err(e) => return Err(e)
          }
        }
      }
      Text(_, _) =>
        match ir_of_node(node, out) {
          Ok(_) => ()
          Err(e) => return Err(e)
        }
    }
  }
  Ok(())
}

///|
/// IR 协议代次（工具 ↔ applier 握手）：补丁带 `rev`，应用侧对不上即回 `stale`，
/// 工具据此走 COLD 重启回原页。加字段 / 换键语义时与 applier 同批 +1。
/// v2：内置 18 标签全进补丁，IComp 统一携带 kids 与 events。
pub const IR_REV : String = "mng-ir-2"

///|
/// 键集摘要：排序后逐键喂双种子哈希（键间喂一个换行码），与 applier 侧
/// `mng_keys_digest` 逐字同算法——两侧不一致就永远判 stale。
fn ir_keys_digest(keys : Array[String]) -> String {
  let ks = keys.copy()
  ks.sort()
  let mut h1 = 5381
  let mut h2 = 52711
  for s in ks {
    h1 = ((h1 << 5) + h1 + 10) & 0x7FFF_FFFF
    h2 = ((h2 << 5) + h2 + 10) & 0x7FFF_FFFF
    for c in s.to_array() {
      h1 = ((h1 << 5) + h1 + c.to_int()) & 0x7FFF_FFFF
      h2 = ((h2 << 5) + h2 + c.to_int()) & 0x7FFF_FFFF
    }
  }
  hotkey_hex8(h1) + hotkey_hex8(h2)
}

///|
/// JSON 组装（应用侧 vsc_json_parse 读回）。exprs 收集动态槽键，states 收集
/// v-model 目标——应用侧注册表按清单登记，缺项由 applier 报错。
pub fn ir_of_with(
  src : String,
  filename : String,
  evals : Map[String, String],
  classes : String,
) -> Result[String, String] {
  let sfc = match parse_sfc(src) {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  if sfc.roots.length() != 1 {
    return Err(
      "\{filename}：模板必须单根（v1），现 \{sfc.roots.length()} 个顶层节点",
    )
  }
  let seq : Array[IrNode] = []
  match ir_seq(sfc.roots, seq) {
    Ok(_) => ()
    Err(e) => return Err(e)
  }
  let root = if seq.length() == 1 {
    seq[0]
  } else if seq.length() == 0 {
    IText("")
  } else {
    IComp("ui-col", [], seq, [], [])
  }
  let exprs : Array[String] = []
  let states : Array[String] = []
  let handlers : Array[String] = []
  fn walk(nd : IrNode) -> Unit {
    match nd {
      IDynText(k) | IDynTextEl(k, _) =>
        if !arr_contains(exprs, k) { exprs.push(k) }
      IIf(c, t, f) => {
        if c.length() > 0 && !arr_contains(exprs, c) {
          exprs.push(c)
        }
        walk(t)
        walk(f)
      }
      IComp(_, args, kids, events, _) => {
        for a in args {
          match a.1 {
            IExpr(k) => if !arr_contains(exprs, k) { exprs.push(k) }
            IState(s) => if !arr_contains(states, s) { states.push(s) }
            _ => ()
          }
        }
        for e in events {
          if !arr_contains(handlers, e.1) {
            handlers.push(e.1)
          }
        }
        for k in kids {
          walk(k)
        }
      }
      _ => ()
    }
  }

  walk(root)
  let stem = collect_stem(filename)
  // 握手用键集：requires（exprs ∪ states ∪ handlers）减去补丁自带 eval 键
  let need_keys : Array[String] = []
  for e in exprs {
    need_keys.push(e)
  }
  for st in states {
    need_keys.push(st)
  }
  for h in handlers {
    need_keys.push(h)
  }
  let parts : Array[String] = []
  parts.push("\"v\":1")
  parts.push("\"rev\":\"" + jstr(IR_REV) + "\"")
  parts.push("\"keys_digest\":\"" + ir_keys_digest(need_keys) + "\"")
  parts.push("\"page\":\"" + jstr(stem) + "\"")
  parts.push("\"root\":" + ir_node_json(root))
  let ea : Array[String] = []
  for e in exprs {
    ea.push("\"" + jstr(e) + "\"")
  }
  parts.push("\"exprs\":[" + ea.join(",") + "]")
  let sa : Array[String] = []
  for st in states {
    sa.push("\"" + jstr(st) + "\"")
  }
  parts.push("\"states\":[" + sa.join(",") + "]")
  let ha : Array[String] = []
  for h in handlers {
    ha.push("\"" + jstr(h) + "\"")
  }
  parts.push("\"handlers\":[" + ha.join(",") + "]")
  let ev : Array[String] = []
  for (k, j) in evals {
    ev.push("\"" + jstr(k) + "\":" + j)
  }
  parts.push("\"eval\":{" + ev.join(",") + "}")
  parts.push("\"classes\":" + classes)
  Ok("{" + parts.join(",") + "}\n")
}

///|
pub fn ir_of(src : String, filename : String) -> Result[String, String] {
  ir_of_with(src, filename, Map([]), "[]")
}

///|
fn collect_stem(filename : String) -> String {
  let a = chars_of(filename)
  let mut start = 0
  for k, c in a {
    if c == '/' {
      start = k + 1
    }
  }
  let base = a[start:].map(fn(c) { c.to_string() }).join("")
  let b = chars_of(base)
  let mut end = b.length()
  for k, c in b {
    if c == '.' {
      end = k
      break
    }
  }
  b[0:end].map(fn(c) { c.to_string() }).join("")
}

///|
fn ir_class_json(names : Array[String]) -> String {
  if names.length() == 0 {
    return ""
  }
  let xs : Array[String] = []
  for n in names {
    xs.push("\"" + jstr(n) + "\"")
  }
  ",\"class\":[" + xs.join(",") + "]"
}

///|
fn ir_node_json(nd : IrNode) -> String {
  match nd {
    IText(s) => "{\"k\":\"text\",\"v\":\"" + jstr(s) + "\"}"
    ITextEl(s, cls) =>
      "{\"k\":\"text\",\"v\":\"" + jstr(s) + "\"" + ir_class_json(cls) + "}"
    IDynText(k) => "{\"k\":\"dyn\",\"key\":\"" + jstr(k) + "\"}"
    IDynTextEl(k, cls) =>
      "{\"k\":\"dyn\",\"key\":\"" + jstr(k) + "\"" + ir_class_json(cls) + "}"
    IIf(c, t, f) =>
      "{\"k\":\"if\",\"c\":\"" +
      jstr(c) +
      "\",\"t\":" +
      ir_node_json(t) +
      ",\"f\":" +
      ir_node_json(f) +
      "}"
    IComp(tag, args, kids, events, cls) => {
      let parts : Array[String] = []
      let short = if tag.has_prefix("ui-") { tag[3:].to_owned() } else { tag }
      parts.push("\"k\":\"" + jstr(short) + "\"")
      let aa : Array[String] = []
      for a in args {
        aa.push("\"" + jstr(a.0) + "\":" + ir_val_json(a.1))
      }
      parts.push("\"args\":{" + aa.join(",") + "}")
      if kids.length() > 0 {
        parts.push("\"kids\":[" + ir_kids_json(kids) + "]")
      }
      if events.length() > 0 {
        let es : Array[String] = []
        for e in events {
          es.push("\"" + jstr(e.0) + "\":\"" + jstr(e.1) + "\"")
        }
        parts.push("\"events\":{" + es.join(",") + "}")
      }
      if cls.length() > 0 {
        let xs : Array[String] = []
        for n in cls {
          xs.push("\"" + jstr(n) + "\"")
        }
        parts.push("\"class\":[" + xs.join(",") + "]")
      }
      "{" + parts.join(",") + "}"
    }
  }
}

///|
fn ir_kids_json(kids : Array[IrNode]) -> String {
  let out : Array[String] = []
  for k in kids {
    out.push(ir_node_json(k))
  }
  out.join(",")
}
