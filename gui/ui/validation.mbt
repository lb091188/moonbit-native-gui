///|
/// 表单校验（§1.5 口径：控件不动，校验只写错误文案槽）：
/// `validate(store, rule)` 把值流接进规则，`rule` 返回 `Some(消息)` 即写红字、
/// `None` 清空；`form_item(..., error=err)` 显示同一条 `err`。订阅进回收袋，
/// 控件卸载自动退订。规则类型就是 `(T) -> String?`。

///|
/// 接线：立即按现值跑一次，之后值一变就重跑，结果写进错误槽。
pub fn[T] validate(
  store : @base.Store[T],
  rule : (T) -> String?,
) -> @base.Store[String] {
  let err : @base.Store[String] = @base.Store::new("")
  let run = fn(v : T) -> Unit {
    match rule(v) {
      Some(m) => err.set(m)
      None => err.set("")
    }
  }
  run(store.get())
  let sid = store.subscribe_id(run)
  @base.sub_bag_register(fn() { store.remove(sid) })
  err
}

///|
/// 必填：去首尾空白后为空即报错。默认消息随语言取译（`gui.ui.validation.required`），
/// 传 `msg=` 用自己的串。
pub fn required(msg~ : String = "") -> (String) -> String? {
  let text = if msg.length() > 0 {
    msg
  } else {
    @i18n.t_or("gui.ui.validation.required", "不能为空")
  }
  fn(v : String) -> String? {
    let t = v.trim()
    if t.length() == 0 { Some(text) } else { None }
  }
}

///|
/// 定长下限（按字符数粗口径，够用即可）。
pub fn min_len(n : Int, msg~ : String = "") -> (String) -> String? {
  let text = if msg.length() > 0 {
    msg
  } else {
    @i18n.t_with_or(
      "gui.ui.validation.min_len",
      [("n", n.to_string())],
      "至少 \{n.to_string()} 个字符",
    )
  }
  fn(v : String) -> String? {
    if v.length() < n { Some(text) } else { None }
  }
}

///|
/// 邮箱粗规则：`x@y.z` 形态，只查 `@`、@ 后有点、结尾不是点，不做完整 RFC 校验。
pub fn email(msg~ : String = "") -> (String) -> String? {
  let text = if msg.length() > 0 {
    msg
  } else {
    @i18n.t_or("gui.ui.validation.email", "邮箱格式不对")
  }
  fn(v : String) -> String? {
    let cs = v.to_array()
    let mut at = -1
    let mut dot_after = false
    let mut i = 0
    while i < cs.length() {
      if cs[i] == '@' {
        at = i
      } else if at >= 0 && cs[i] == '.' {
        dot_after = true
      }
      i += 1
    }
    let ok = at > 0 && at < cs.length() - 1 && dot_after &&
      cs[cs.length() - 1] != '.'
    if ok { None } else { Some(text) }
  }
}

///|
/// 整数区间规则（配合 `stepper`/数值输入的值串）。
pub fn int_range(lo : Int, hi : Int, msg~ : String = "") -> (String) -> String? {
  let text = if msg.length() > 0 {
    msg
  } else {
    @i18n.t_with_or(
      "gui.ui.validation.int_range",
      [("lo", lo.to_string()), ("hi", hi.to_string())],
      "须在 \{lo.to_string()}.. \{hi.to_string()} 之间",
    )
  }
  fn(v : String) -> String? {
    let bad = Some(text)
    let mut neg = false
    let mut body = v
    if body.has_prefix("-") {
      neg = true
      body = body[1:].to_owned()
    }
    if body.length() == 0 {
      return bad
    }
    // 逐位折整数：只认纯数字串，越界或带非数字即坏
    let mut acc = 0
    let mut all_num = true
    for c in body.to_array() {
      let n = c.to_int()
      if n >= 48 && n <= 57 {
        acc = acc * 10 + (n - 48)
      } else {
        all_num = false
      }
    }
    if !all_num {
      return bad
    }
    let y = if neg { -acc } else { acc }
    if y >= lo && y <= hi { None } else { bad }
  }
}

///|
/// 串联多条规则：第一条报错的赢。
pub fn all(rules : Array[(String) -> String?]) -> (String) -> String? {
  fn(v : String) -> String? {
    for r in rules {
      match r(v) {
        Some(m) => return Some(m)
        None => ()
      }
    }
    None
  }
}
