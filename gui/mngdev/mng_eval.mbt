// 受限表达式求值器（dev v2a-1）：IR 补丁里新出现的表达式按 AST 求值。
// 文法与类型检查在 mngkit/expr.mbt；本文件只负责执行已通过检查的 AST。

///|
pub(all) enum ExprValue {
  VInt(Int32)
  VDouble(Double)
  VBool(Bool)
  VString(String)
}

///|
priv enum ExprAst {
  AInt(Int32)
  ADouble(Double)
  ABool(Bool)
  AStr(String)
  AId(String)
  AGet(ExprAst)
  AToStr(ExprAst)
  ANot(ExprAst)
  ANeg(ExprAst)
  ABin(String, ExprAst, ExprAst)
  AIf(ExprAst, ExprAst, ExprAst)
  ACall(String, Array[ExprAst])
}

///|
priv suberror EvalRaise {
  EvalRaise(String)
}

///|
fn[A] ev_need(r : Result[A, String]) -> A raise EvalRaise {
  match r {
    Ok(v) => v
    Err(e) => raise EvalRaise(e)
  }
}

///|
fn ast_err(m : String) -> Result[ExprAst, String] {
  Err("表达式 AST：" + m)
}

///|
fn ast_of(j : MJ) -> Result[ExprAst, String] raise EvalRaise {
  let k = match mj_str(mj_get(j, "k")) {
    Some(s) => s
    None => return ast_err("节点缺 k")
  }
  match k {
    "int" =>
      match mj_num(mj_get(j, "v")) {
        Some(v) => Ok(AInt(v.to_int()))
        None => ast_err("int 缺 v")
      }
    "dbl" =>
      match mj_num(mj_get(j, "v")) {
        Some(v) => Ok(ADouble(v))
        None => ast_err("dbl 缺 v")
      }
    "bool" =>
      match mj_get(j, "v") {
        Some(MBool(b)) => Ok(ABool(b))
        _ => ast_err("bool 缺 v")
      }
    "str" =>
      match mj_str(mj_get(j, "v")) {
        Some(s) => Ok(AStr(s))
        None => ast_err("str 缺 v")
      }
    "id" =>
      match mj_str(mj_get(j, "v")) {
        Some(s) => Ok(AId(s))
        None => ast_err("id 缺 v")
      }
    "get" =>
      match mj_get(j, "a") {
        Some(a) => Ok(AGet(ev_need(ast_of(a))))
        None => ast_err("get 缺 a")
      }
    "tostr" =>
      match mj_get(j, "a") {
        Some(a) => Ok(AToStr(ev_need(ast_of(a))))
        None => ast_err("tostr 缺 a")
      }
    "not" =>
      match mj_get(j, "a") {
        Some(a) => Ok(ANot(ev_need(ast_of(a))))
        None => ast_err("not 缺 a")
      }
    "neg" =>
      match mj_get(j, "a") {
        Some(a) => Ok(ANeg(ev_need(ast_of(a))))
        None => ast_err("neg 缺 a")
      }
    "bin" => {
      let op = match mj_str(mj_get(j, "op")) {
        Some(s) => s
        None => return ast_err("bin 缺 op")
      }
      let l = match mj_get(j, "l") {
        Some(a) => ev_need(ast_of(a))
        None => return ast_err("bin 缺 l")
      }
      let r = match mj_get(j, "r") {
        Some(a) => ev_need(ast_of(a))
        None => return ast_err("bin 缺 r")
      }
      Ok(ABin(op, l, r))
    }
    "if" => {
      let c = match mj_get(j, "c") {
        Some(a) => ev_need(ast_of(a))
        None => return ast_err("if 缺 c")
      }
      let t = match mj_get(j, "t") {
        Some(a) => ev_need(ast_of(a))
        None => return ast_err("if 缺 t")
      }
      let f = match mj_get(j, "f") {
        Some(a) => ev_need(ast_of(a))
        None => return ast_err("if 缺 f")
      }
      Ok(AIf(c, t, f))
    }
    "call" => {
      let name = match mj_str(mj_get(j, "f")) {
        Some(s) => s
        None => return ast_err("call 缺 f")
      }
      let args : Array[ExprAst] = []
      match mj_arr(mj_get(j, "a")) {
        Some(arr) =>
          for x in arr {
            args.push(ev_need(ast_of(x)))
          }
        None => ()
      }
      Ok(ACall(name, args))
    }
    _ => ast_err("未知节点 " + k)
  }
}

///|
fn eval_ast(
  n : ExprAst,
  reg : MngReg,
) -> Result[ExprValue, String] raise EvalRaise {
  match n {
    AInt(v) => Ok(VInt(v))
    ADouble(v) => Ok(VDouble(v))
    ABool(v) => Ok(VBool(v))
    AStr(v) => Ok(VString(v))
    AId(name) =>
      match reg.ints.get(name) {
        Some(s) => Ok(VInt(s.get()))
        None =>
          match reg.bools.get(name) {
            Some(s) => Ok(VBool(s.get()))
            None =>
              match reg.strs.get(name) {
                Some(s) => Ok(VString(s.get()))
                None => Err("求值缺状态「" + name + "」")
              }
          }
      }
    AGet(a) => eval_ast(a, reg)
    AToStr(a) =>
      match eval_ast(a, reg) {
        Ok(VInt(v)) => Ok(VString(v.to_string()))
        Ok(VDouble(v)) => Ok(VString(v.to_string()))
        Ok(VBool(v)) => Ok(VString(v.to_string()))
        Ok(VString(v)) => Ok(VString(v))
        Err(e) => Err(e)
      }
    ANot(a) =>
      match eval_ast(a, reg) {
        Ok(VBool(v)) => Ok(VBool(!v))
        Ok(_) => Err("! 需要 Bool")
        Err(e) => Err(e)
      }
    ANeg(a) =>
      match eval_ast(a, reg) {
        Ok(VInt(v)) => Ok(VInt(-v))
        Ok(VDouble(v)) => Ok(VDouble(-v))
        Ok(_) => Err("- 需要数值")
        Err(e) => Err(e)
      }
    ABin(op, l, r) => {
      let lv = ev_need(eval_ast(l, reg))
      let rv = ev_need(eval_ast(r, reg))
      match (op, lv, rv) {
        ("+", VInt(a), VInt(b)) => Ok(VInt(a + b))
        ("+", VDouble(a), VDouble(b)) => Ok(VDouble(a + b))
        ("+", VString(a), VString(b)) => Ok(VString(a + b))
        ("-", VInt(a), VInt(b)) => Ok(VInt(a - b))
        ("-", VDouble(a), VDouble(b)) => Ok(VDouble(a - b))
        ("*", VInt(a), VInt(b)) => Ok(VInt(a * b))
        ("*", VDouble(a), VDouble(b)) => Ok(VDouble(a * b))
        ("/", VInt(a), VInt(b)) => Ok(VInt(a / b))
        ("/", VDouble(a), VDouble(b)) => Ok(VDouble(a / b))
        ("%", VInt(a), VInt(b)) => Ok(VInt(a % b))
        ("==", VInt(a), VInt(b)) => Ok(VBool(a == b))
        ("==", VDouble(a), VDouble(b)) => Ok(VBool(a == b))
        ("==", VString(a), VString(b)) => Ok(VBool(a == b))
        ("==", VBool(a), VBool(b)) => Ok(VBool(a == b))
        ("!=", VInt(a), VInt(b)) => Ok(VBool(a != b))
        ("!=", VDouble(a), VDouble(b)) => Ok(VBool(a != b))
        ("!=", VString(a), VString(b)) => Ok(VBool(a != b))
        ("!=", VBool(a), VBool(b)) => Ok(VBool(a != b))
        ("<", VInt(a), VInt(b)) => Ok(VBool(a < b))
        ("<", VDouble(a), VDouble(b)) => Ok(VBool(a < b))
        ("<=", VInt(a), VInt(b)) => Ok(VBool(a <= b))
        ("<=", VDouble(a), VDouble(b)) => Ok(VBool(a <= b))
        (">", VInt(a), VInt(b)) => Ok(VBool(a > b))
        (">", VDouble(a), VDouble(b)) => Ok(VBool(a > b))
        (">=", VInt(a), VInt(b)) => Ok(VBool(a >= b))
        (">=", VDouble(a), VDouble(b)) => Ok(VBool(a >= b))
        ("&&", VBool(a), VBool(b)) => Ok(VBool(a && b))
        ("||", VBool(a), VBool(b)) => Ok(VBool(a || b))
        _ => Err("运算 " + op + " 的操作数类型不匹配")
      }
    }
    AIf(c, t, f) =>
      match eval_ast(c, reg) {
        Ok(VBool(true)) => eval_ast(t, reg)
        Ok(VBool(false)) => eval_ast(f, reg)
        Ok(_) => Err("if 条件不是 Bool")
        Err(e) => Err(e)
      }
    ACall(name, args) => {
      let vals : Array[ExprValue] = []
      for a in args {
        vals.push(ev_need(eval_ast(a, reg)))
      }
      match reg.calls.get(name) {
        Some(f) => Ok(f(vals))
        None => Err("求值缺函数「" + name + "」")
      }
    }
  }
}

///|
fn eval_text(n : ExprAst, reg : MngReg) -> String {
  try {
    match eval_ast(n, reg) {
      Ok(VString(s)) => s
      Ok(_) => {
        println("MNG-EVAL: 文本表达式结果不是 String")
        ""
      }
      Err(e) => {
        println("MNG-EVAL: " + e)
        ""
      }
    }
  } catch {
    EvalRaise(e) => {
      println("MNG-EVAL: " + e)
      ""
    }
  }
}

///|
fn eval_cond(n : ExprAst, reg : MngReg) -> Bool {
  try {
    match eval_ast(n, reg) {
      Ok(VBool(b)) => b
      Ok(_) => {
        println("MNG-EVAL: 条件表达式结果不是 Bool")
        false
      }
      Err(e) => {
        println("MNG-EVAL: " + e)
        false
      }
    }
  } catch {
    EvalRaise(e) => {
      println("MNG-EVAL: " + e)
      false
    }
  }
}

///|
/// 补丁里一条新表达式登记：`c:` 键进 conds，其余进 exprs；已编译的键不覆盖。
fn mng_reg_eval(reg : MngReg, key : String, j : MJ) -> Result[Unit, String] {
  let ast_r : Result[ExprAst, String] = Ok(ev_need(ast_of(j))) catch {
    EvalRaise(e) => Err(e)
  }
  let ast = match ast_r {
    Ok(v) => v
    Err(e) => return Err("表达式 AST：" + e)
  }
  if key.has_prefix("c:") {
    match reg.conds.get(key) {
      Some(_) => Ok(())
      None => {
        reg.cond(key, fn() { eval_cond(ast, reg) })
        Ok(())
      }
    }
  } else {
    match reg.exprs.get(key) {
      Some(_) => Ok(())
      None => {
        reg.expr(key, fn() { eval_text(ast, reg) })
        Ok(())
      }
    }
  }
}

///|
/// dev 档内置可调用函数（表达式求值用）：与 mngkit 的类型表同口径。
pub fn mng_reg_builtins(reg : MngReg) -> Unit {
  // `@shared.tx/@shared.tr` 是受限文法的约定名（模板作者在表达式里写的
  // 取译调用），与具体应用的包别名无关：库侧直接走 @i18n 取译（中文态
  // 回落原文，英文态命中目录），语义与 showcase 的 tx/tr 同款。
  reg.call("@shared.tx", fn(a) {
    if a.length() == 1 {
      match a[0] {
        VString(s) => VString(@i18n.t_or(s, s))
        _ => VString("")
      }
    } else {
      VString("")
    }
  })
  reg.call("@shared.tr", fn(a) {
    if a.length() == 2 {
      match (a[0], a[1]) {
        (VString(k), VString(z)) => VString(@i18n.t_or(k, z))
        _ => VString("")
      }
    } else {
      VString("")
    }
  })
}
