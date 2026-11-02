// 契约分类器：dev 循环判断一次保存能否热更——「表达式集合 ⊆ 应用注册表
// 且 script 段逐字未变」= 结构改动（HOT，进程内补丁）；否则 COLD（回退重启）。
// 表达式取改写前原文；契约冻结见 proposals/native-template.md「Spike 契约」。

///|
pub struct Contract {
  script : String
  exprs : Array[String]
}

///|
fn collect_exprs(nodes : Array[TNode], out : Array[String], seen : Map[String, Bool]) -> Unit {
  fn push(e : String) -> Unit {
    if e.length() > 0 && !seen.get_or_default(e, false) {
      let _ = seen.set(e, true)
      out.push(e)
    }
  }
  for n in nodes {
    match n {
      Elem(_, attrs, kids, _) => {
        for a in attrs {
          match a.kind {
            Dyn | Event | Model | If | ElseIf | Show =>
              if a.has_value {
                push(a.value)
              }
            _ => ()
          }
        }
        collect_exprs(kids, out, seen)
      }
      Text(raw, _) =>
        match split_interp(raw, { line: 0, col: 0 }) {
          Ok(pieces) =>
            for p in pieces {
              match p {
                PExpr(e) => push(e)
                _ => ()
              }
            }
          Err(_) => ()
        }
    }
  }
}

///|
/// 提取契约：script 段原文 + 动态表达式集合（去重）。解析失败原样上抛。
pub fn contract_of(src : String, _filename : String) -> Result[Contract, String] {
  let sfc = match parse_sfc(src) {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let exprs : Array[String] = []
  collect_exprs(sfc.roots, exprs, Map([]))
  Ok({ script: sfc.script, exprs })
}

///|
/// HOT 判定：script 段逐字相同且全部表达式都在基线集合里（结构可任意重排）。
pub fn Contract::hot_ok(self : Contract, base : Contract) -> Bool {
  if self.script != base.script {
    return false
  }
  for e in self.exprs {
    if !arr_contains(base.exprs, e) {
      return false
    }
  }
  true
}
