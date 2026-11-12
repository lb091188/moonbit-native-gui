// dev 档登记表：把模板树摊成应用侧注册表要的键值。
// 键与 IR 现状一致：动态文本/参数 `t:<内容哈希>`、条件 `c:<内容哈希>`、事件与状态用名字；
// 值语义与生产生成同一套改写（裸槽补 `.get()`）。IR v1 边界外的节点（自定义组件、
// v-for、children 形）不会进补丁，这里仍按同一套规则扫，注册项闲置无副作用。

///|
priv struct DevRegs {
  exprs : Array[(String, String, Pos)]
  conds : Array[(String, String, Pos)]
  handlers : Array[(String, Pos)]
  // (名字, 登记方法名 int/bool/str, 坐标)
  states : Array[(String, String, Pos)]
}

///|
fn dev_push_val(
  a : Array[(String, String, Pos)],
  k : String,
  e : String,
  p : Pos,
) -> Unit {
  for (x, _, _) in a {
    if x == k {
      return
    }
  }
  a.push((k, e, p))
}

///|
fn dev_push_handler(a : Array[(String, Pos)], h : String, p : Pos) -> Unit {
  for (x, _) in a {
    if x == h {
      return
    }
  }
  a.push((h, p))
}

///|
fn dev_push_state(
  a : Array[(String, String, Pos)],
  n : String,
  kd : String,
  p : Pos,
) -> Unit {
  for (x, _, _) in a {
    if x == n {
      return
    }
  }
  a.push((n, kd, p))
}

///|
/// 插值文本 → 值表达式（字符串字面量），与生产生成同源。
fn dev_interp_expr(
  ctx : Ctx,
  raw : String,
  pos : Pos,
) -> Result[String, String] {
  let norm = normalize_text(raw)
  let pieces = match split_interp(norm, pos) {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  Ok(q(pieces_to_e(ctx, pieces)))
}

///|
/// 槽元素类型 → 登记方法名（只认 Int/Bool/String 三档）。
fn state_kind_of(ty : String) -> String? {
  match ty {
    "Int" => Some("int")
    "Bool" => Some("bool")
    "String" => Some("str")
    _ => None
  }
}

///|
/// 模板树 → 登记表（文档序、按键去重）。
fn dev_collect(
  nodes : Array[TNode],
  ctx : Ctx,
  tys : Map[String, String],
) -> Result[DevRegs, String] {
  let regs : DevRegs = { exprs: [], conds: [], handlers: [], states: [], }
  match dev_walk(nodes, ctx, tys, regs) {
    Ok(_) => Ok(regs)
    Err(e) => Err(e)
  }
}

///|
/// 递归走树、往同一份登记表里累加。
fn dev_walk(
  nodes : Array[TNode],
  ctx : Ctx,
  tys : Map[String, String],
  regs : DevRegs,
) -> Result[Unit, String] {
  for node in nodes {
    match node {
      Text(raw, pos) => {
        let norm = normalize_text(raw)
        if norm.length() > 0 && has_interp(norm) {
          let e = match dev_interp_expr(ctx, raw, pos) {
            Ok(v) => v
            Err(err) => return Err(err)
          }
          dev_push_val(regs.exprs, bind_key("t", norm), e, pos)
        }
      }
      Elem(tag, attrs, children, pos) => {
        // v-for 行子树整棵跳过：行模板不在热更范围（别名是行内作用域，
        // 登记成 fn() 闭包在作用域外编不过）；hot_ir 对含 v-for 的模板直接回 Err
        for a in attrs {
          if a.kind is For {
            return Ok(())
          }
        }
        // 条件槽（v-if / v-show：键取条件表达式内容）
        for a in attrs {
          match a.kind {
            If | Show =>
              dev_push_val(
                regs.conds,
                bind_key("c", a.value.trim().to_owned()),
                rewrite_value(a.value, ctx.slots),
                a.pos,
              )
            _ => ()
          }
        }
        // 事件回调
        for a in attrs {
          match a.kind {
            Event => {
              let h = a.value.trim().to_owned()
              if h.length() > 0 {
                dev_push_handler(regs.handlers, h, a.pos)
              }
            }
            _ => ()
          }
        }
        // v-model 目标 → 按元素类型登记 state
        for a in attrs {
          match a.kind {
            Model => {
              let n = a.value.trim().to_owned()
              if n.length() > 0 {
                match tys.get(n) {
                  Some(ty) =>
                    match state_kind_of(ty) {
                      Some(kd) => dev_push_state(regs.states, n, kd, a.pos)
                      None => ()
                    }
                  None => ()
                }
              }
            }
            _ => ()
          }
        }
        // 动态值槽
        if tag == "ui-text" {
          let mut dyn_text : Attr? = None
          for a in attrs {
            match a.kind {
              Dyn => if a.name == "text" { dyn_text = Some(a) }
              _ => ()
            }
          }
          match dyn_text {
            Some(a) =>
              dev_push_val(
                regs.exprs,
                bind_key("t", a.value.trim().to_owned()),
                rewrite_value(a.value, ctx.slots),
                a.pos,
              )
            None =>
              // 元素文本插值：键与 IR 同口径（表达式内容哈希）
              if children.length() > 0 {
                match children[0] {
                  Text(raw, tp) => {
                    let norm = normalize_text(raw)
                    if has_interp(norm) {
                      let e = match dev_interp_expr(ctx, raw, tp) {
                        Ok(v) => v
                        Err(err) => return Err(err)
                      }
                      dev_push_val(regs.exprs, bind_key("t", norm), e, tp)
                    }
                  }
                  _ => ()
                }
              }
          }
        } else if hot_comp_tag(tag) {
          // 通用组件的动态参数：与 IR 同一张 v1 参数表、同一套内容键
          for a in attrs {
            match a.kind {
              Dyn =>
                if hot_comp_arg(tag, a.name) && hot_comp_dyn_arg(tag, a.name) {
                  dev_push_val(
                    regs.exprs,
                    bind_key("t", a.value.trim().to_owned()),
                    rewrite_value(a.value, ctx.slots),
                    a.pos,
                  )
                }
              _ => ()
            }
          }
          // 元素文本内容（text 位置参）：IR 把所有文本子节点拼成一条表达式
          match builtin_decl(tag) {
            Some(d) =>
              if arr_contains(d.positional, "text") {
                let mut raw = ""
                let mut tp = pos
                for c in children {
                  match c {
                    Text(x, q) => {
                      raw = raw + x
                      tp = q
                    }
                    _ => ()
                  }
                }
                let norm = normalize_text(raw)
                if has_interp(norm) {
                  let e = match dev_interp_expr(ctx, raw, tp) {
                    Ok(v) => v
                    Err(err) => return Err(err)
                  }
                  dev_push_val(regs.exprs, bind_key("t", norm), e, tp)
                }
              }
            None => ()
          }
        }
        match dev_walk(children, ctx, tys, regs) {
          Ok(_) => ()
          Err(e) => return Err(e)
        }
      }
    }
  }
  Ok(())
}
