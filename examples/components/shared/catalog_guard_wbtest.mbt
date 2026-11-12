// 英文目录自检。曾经的静默失效：`[meta]` 段头写在开头，读器把其后所有裸键都算进
// `meta.` 前缀，「中文原文当键」的条目一律查不到、静默回落中文（原生菜单的键在
// `[menu]` 段里反而正常）。三条口径钉死：逐条键都要查得到、段头必须排在顶层键之后、
// 各类键抽查一条。

///|
fn chars_of(s : String) -> Array[Char] {
  let out : Array[Char] = []
  for c in s.to_array() {
    out.push(c)
  }
  out
}

///|
fn join(cs : Array[Char], from : Int, to : Int) -> String {
  let mut s = ""
  let mut i = from
  while i < to {
    s = s + cs[i].to_string()
    i = i + 1
  }
  s
}

///|
/// 按单字符分隔符切行（目录串按 `\n` 逐行看）。
fn split_char(s : String, sep : Char) -> Array[String] {
  let cs = chars_of(s)
  let out : Array[String] = []
  let mut start = 0
  let mut i = 0
  while i < cs.length() {
    if cs[i] == sep {
      out.push(join(cs, start, i))
      start = i + 1
    }
    i = i + 1
  }
  out.push(join(cs, start, cs.length()))
  out
}

///|
/// 键值行的键：取第一个「引号外」的 ` = ` 之前的部分（没有则给空串，调用方跳过）。
/// 与读器 `i_split_eq` 同一条口径——键里可以带 `=`（原文当键的正文串就有）。
fn key_of_line(line : String) -> String {
  let cs = chars_of(line)
  let n = cs.length()
  let mut i = 0
  let mut in_str = false
  while i < n {
    if in_str {
      if cs[i] == '\\' {
        i = i + 1
      } else if cs[i] == '"' {
        in_str = false
      }
    } else if cs[i] == '"' {
      in_str = true
    } else if cs[i] == '=' && i > 0 && cs[i - 1] == ' ' && i + 1 < n && cs[i + 1] == ' ' {
      return join(cs, 0, i - 1)
    }
    i = i + 1
  }
  ""
}

///|
fn trim(s : String) -> String {
  s.trim().to_owned()
}

///|
fn strip_quotes(s : String) -> String {
  let cs = chars_of(s)
  if cs.length() >= 2 && cs[0] == '"' && cs[cs.length() - 1] == '"' {
    join(cs, 1, cs.length() - 1)
  } else {
    s
  }
}

///|
/// 段头行的前缀：`[nav]` → "nav."
fn section_prefix(line : String) -> String {
  let cs = chars_of(line)
  let mut i = 1
  while i < cs.length() && cs[i] != ']' {
    i = i + 1
  }
  join(cs, 1, i) + "."
}

///|
test "英文目录逐条自检：每一条键装载后都查得到（含段前缀）" {
  @i18n.i18n_load(EN_CATALOG)
  let mut prefix = ""
  let mut checked = 0
  for raw in split_char(EN_CATALOG, '\n') {
    let t = trim(raw)
    if t.length() == 0 {
      continue
    }
    if t.to_array()[0] == '[' {
      prefix = section_prefix(t)
      continue
    }
    let key = strip_quotes(key_of_line(t))
    if key.length() == 0 {
      continue
    }
    assert_true(
      @i18n.t(prefix + key) is Some(_),
      msg="查不到键：" + prefix + key,
    )
    checked = checked + 1
  }
  assert_true(checked > 300)
  @i18n.i18n_reset()
}

///|
test "英文目录：`[meta]` 段头排在所有顶层键之后" {
  // `[meta]` 之前必须已经出现过键值行（段头写最前会把全表吞进 `meta.` 前缀）
  let head = join(chars_of(EN_CATALOG), 0, meta_offset())
  assert_true(key_of_line_first(head), msg="[meta] 段头不能写在顶层键之前")
}

///|
fn meta_offset() -> Int {
  let cs = chars_of(EN_CATALOG)
  let n = cs.length()
  let mut i = 0
  while i + 6 <= n {
    if join(cs, i, i + 6) == "[meta]" {
      return i
    }
    i = i + 1
  }
  0
}

///|
fn key_of_line_first(s : String) -> Bool {
  for line in split_char(s, '\n') {
    if key_of_line(trim(line)).length() > 0 {
      return true
    }
  }
  false
}

///|
test "英文目录装载后抽查：正文/段标题/段描述/侧栏/菜单/插值" {
  @i18n.i18n_load(EN_CATALOG)
  assert_eq(@i18n.i18n_locale(), "en")
  assert_eq(@i18n.t_or("上一步", "?"), "Back")
  assert_eq(@i18n.t_or("暂停推点", "?"), "Pause feed")
  assert_eq(@i18n.t_or("文本基方向与布局镜像", "?"), "Base direction & layout mirror")
  assert_true(@i18n.t_or("desc§从右起排的右侧文字", "?").has_prefix("Arabic"))
  assert_eq(@i18n.t_or("nav.基础组件", "?"), "Basics")
  assert_eq(@i18n.t_or("nav.g.组件", "?"), "Components")
  assert_eq(@i18n.t_or("nav.g.系统", "?"), "System")
  assert_eq(@i18n.t_or("menu.theme", "?"), "Theme")
  assert_eq(@i18n.t_with_or("gen.subtree", [("n", "3")], "?"), "Subtree generation 3")
  // 段条通道（`seg.` + 段名）与状态回显通道（`dyn.` + 语义名）
  assert_eq(@i18n.t_or("seg.主题", "?"), "Theme")
  // 窗口标题走常量（`@shared.tx(SHOWCASE_TITLE)`），目录侧只能按这条键抽查
  assert_eq(@i18n.t_or("组件库演示板", "?"), "Component Showcase")
  assert_eq(@i18n.t_with_or("dyn.accent_now", [("c", "#123456")], "?"), "Accent now: #123456")
  // 值里带 `\n` 的条目：读手要把转义还原成两行
  assert_true(@i18n.t_or("form.textarea_demo", "?").has_prefix("Text area demo.\n"))
  @i18n.i18n_reset()
  assert_eq(@i18n.t_or("上一步", "回落"), "回落")
}
