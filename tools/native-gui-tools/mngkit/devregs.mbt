// dev 档登记表：把模板树摊成应用侧注册表要的键值。
// 键与 IR 现状一致：动态文本/参数 `t:行:列`、条件 `c:行:列`、事件与状态用名字；
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
fn dev_push_val(a : Array[(String, String, Pos)], k : String, e : String, p : Pos) -> Unit {
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
fn dev_push_state(a : Array[(String, String, Pos)], n : String, kd : String, p : Pos) -> Unit {
  for (x, _, _) in a {
    if x == n {
      return
    }
  }
  a.push((n, kd, p))
}

///|
/// 插值文本 → 值表达式（字符串字面量），与生产生成同源。
fn dev_interp_expr(ctx : Ctx, raw : String, pos : Pos) -> Result[String, String] {
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
  let regs : DevRegs = { exprs: [], conds: [], handlers: [], states: [] }
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
          dev_push_val(regs.exprs, "t:\{pos.line}:\{pos.col}", e, pos)
        }
      }
      Elem(tag, attrs, children, pos) => {
        let tk = "t:\{pos.line}:\{pos.col}"
        // 条件槽（v-if / v-show：键取元素坐标，值 = 条件表达式）
        for a in attrs {
          match a.kind {
            If | Show => dev_push_val(regs.conds, "c:\{pos.line}:\{pos.col}", rewrite_value(a.value, ctx.slots), a.pos)
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
              Dyn =>
                if a.name == "text" {
                  dyn_text = Some(a)
                }
              _ => ()
            }
          }
          match dyn_text {
            Some(a) =>
              dev_push_val(regs.exprs, tk, rewrite_value(a.value, ctx.slots), a.pos)
            None =>
              // 元素文本插值：键 = 首个文本子节点的坐标（IR 同口径）
              if children.length() > 0 {
                match children[0] {
                  Text(raw, tp) => {
                    let norm = normalize_text(raw)
                    if has_interp(norm) {
                      let e = match dev_interp_expr(ctx, raw, tp) {
                        Ok(v) => v
                        Err(err) => return Err(err)
                      }
                      dev_push_val(regs.exprs, "t:\{tp.line}:\{tp.col}", e, tp)
                    }
                  }
                  _ => ()
                }
              }
          }
        } else if tag.has_prefix("ui-") {
          match builtin_decl(tag) {
            Some(d) =>
              for spec in d.positional {
                if spec == "children" || spec == "child" {
                  continue
                }
                for a in attrs {
                  match a.kind {
                    Dyn =>
                      if a.name == spec {
                        // 键取属性坐标（IR 对通用组件参数同口径）
                        dev_push_val(
                          regs.exprs,
                          "t:\{a.pos.line}:\{a.pos.col}",
                          rewrite_value(a.value, ctx.slots),
                          a.pos,
                        )
                      }
                    _ => ()
                  }
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
