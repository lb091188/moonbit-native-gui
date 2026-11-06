// terminal 输入面回归：keysym→终端字节映射（控制键/CSI/Alt 前缀/mac Cmd）、
// 控件键路由（裸 Ctrl+C 进输入、组合键复制粘贴走隔离剪贴板）、Shift+PageUp
// 回看翻页、IME commit。

///|
fn term_ev(press : Bool, keysym : Int, mods : Int) -> @widget.KeyEvent {
  { press, keysym, mods }
}

///|
test "映射：回车/退格/Tab/Esc/方向键/导航键/F 键" {
  assert_eq(terminal_input_of(term_ev(true, @base.KS_RETURN, 0), false), Some("\r"))
  assert_eq(terminal_input_of(term_ev(true, @base.KS_BACKSPACE, 0), false), Some("\u{7f}"))
  assert_eq(terminal_input_of(term_ev(true, @base.KS_TAB, 0), false), Some("\t"))
  assert_eq(terminal_input_of(term_ev(true, @base.KS_ISO_LEFT_TAB, @base.MOD_SHIFT), false), Some("\u{1b}[Z"))
  assert_eq(terminal_input_of(term_ev(true, @base.KS_ESCAPE, 0), false), Some("\u{1b}"))
  assert_eq(terminal_input_of(term_ev(true, @base.KS_UP, 0), false), Some("\u{1b}[A"))
  assert_eq(terminal_input_of(term_ev(true, @base.KS_DOWN, 0), false), Some("\u{1b}[B"))
  assert_eq(terminal_input_of(term_ev(true, @base.KS_RIGHT, 0), false), Some("\u{1b}[C"))
  assert_eq(terminal_input_of(term_ev(true, @base.KS_LEFT, 0), false), Some("\u{1b}[D"))
  assert_eq(terminal_input_of(term_ev(true, @base.KS_HOME, 0), false), Some("\u{1b}[H"))
  assert_eq(terminal_input_of(term_ev(true, @base.KS_END, 0), false), Some("\u{1b}[F"))
  assert_eq(terminal_input_of(term_ev(true, @base.KS_DELETE, 0), false), Some("\u{1b}[3~"))
  assert_eq(terminal_input_of(term_ev(true, KS_INSERT, 0), false), Some("\u{1b}[2~"))
  assert_eq(terminal_input_of(term_ev(true, KS_PAGE_UP, 0), false), Some("\u{1b}[5~"))
  assert_eq(terminal_input_of(term_ev(true, KS_PAGE_DOWN, 0), false), Some("\u{1b}[6~"))
  assert_eq(terminal_input_of(term_ev(true, 65470, 0), false), Some("\u{1b}OP"))
  assert_eq(terminal_input_of(term_ev(true, 65474, 0), false), Some("\u{1b}[15~"))
  // 抬起事件不产输入
  assert_eq(terminal_input_of(term_ev(false, 97, 0), false), None)
}

///|
test "映射：Ctrl 组合控制字节（裸 Ctrl+C = \\x03）" {
  assert_eq(terminal_input_of(term_ev(true, 99, @base.MOD_CTRL), false), Some("\u{3}"))
  assert_eq(terminal_input_of(term_ev(true, 67, @base.MOD_CTRL), false), Some("\u{3}"))
  assert_eq(terminal_input_of(term_ev(true, 105, @base.MOD_CTRL), false), Some("\t"))
  assert_eq(terminal_input_of(term_ev(true, 109, @base.MOD_CTRL), false), Some("\r"))
  assert_eq(terminal_input_of(term_ev(true, 97, @base.MOD_CTRL), false), Some("\u{1}"))
  assert_eq(terminal_input_of(term_ev(true, 91, @base.MOD_CTRL), false), Some("\u{1b}"))
  assert_eq(terminal_input_of(term_ev(true, @base.KS_SPACE, @base.MOD_CTRL), false), Some("\u{0}"))
  assert_eq(terminal_input_of(term_ev(true, 64, @base.MOD_CTRL), false), Some("\u{0}"))
}

///|
test "映射：Alt 前缀 ESC；mac Cmd 不进输入" {
  assert_eq(terminal_input_of(term_ev(true, 100, @base.MOD_ALT), false), Some("\u{1b}d"))
  assert_eq(
    terminal_input_of(term_ev(true, @base.KS_LEFT, @base.MOD_ALT), false),
    Some("\u{1b}\u{1b}[D"),
  )
  assert_eq(terminal_input_of(term_ev(true, 120, @base.MOD_META), true), None)
  // 可打印字符直通；控制区/DEL 不产输入
  assert_eq(terminal_input_of(term_ev(true, 120, 0), false), Some("x"))
  assert_eq(terminal_input_of(term_ev(true, 65, 0), false), Some("A"))
  assert_eq(terminal_input_of(term_ev(true, 127, 0), false), None)
}

///|
/// 挂一个已布局的终端，回传 (root, w, 输入轨迹)。
fn mounted_terminal(
  text : String,
) -> (@widget.Widget, @widget.Widget, Ref[Array[String]]) {
  use_system_clipboard(false)
  let term = Terminal::new(cols=20, rows=6)
  term.feed(text)
  let got : Ref[Array[String]] = Ref([])
  let n = terminal(
    term,
    height=120.0,
    focus_id=1,
    blink=false,
    on_input=fn(s : String) -> Unit { got.val.push(s) },
  )
  let root = @widget.Widget::new()
  root.set_size(280.0, 150.0)
  root.set_column()
  let w = n.mount_into(root)
  root.relayout(280.0, 150.0)
  (root, w, got)
}

///|
fn term_key(root : @widget.Widget, w : @widget.Widget, keysym : Int, mods : Int) -> Bool {
  root.dispatch_key(w.focus_id, { press: true, keysym, mods })
}

///|
test "控件键路由：可打印与裸 Ctrl+C 进 on_input" {
  let (root, w, got) = mounted_terminal("hello\n")
  assert_true(term_key(root, w, 120, 0)) // x
  assert_true(term_key(root, w, @base.KS_RETURN, 0)) // \r
  // 裸 Ctrl+C 必须进输入（SIGINT 语义），不当复制吃掉
  assert_true(term_key(root, w, 99, @base.MOD_CTRL))
  assert_eq(got.val, ["x", "\r", "\u{3}"])
}

///|
test "组合键复制/粘贴走隔离剪贴板；无选区 Cmd/Ctrl+Shift+C 不产输入" {
  let mac = @shell.platform_is_macos()
  let combo = if mac { @base.MOD_META } else { @base.MOD_CTRL.lor(@base.MOD_SHIFT) }
  let (root, w, got) = mounted_terminal("hello world\nsecond\n")
  // 拖选第一行 "ello"（本地列 1..5）
  let font = @text.Font::new("Monospace", 13.0)
  let cw = text_width("M", font)
  let ch = 19.0
  let px = w.rect.x
  let py = w.rect.y
  let _ = root.dispatch_pointer_to(w.id, {
    kind: @widget.PointerKind::Down,
    x: px + 6.0 + cw,
    y: py + 6.0 + ch * 0.5,
    button: 1,
    mods: 0,
  })
  let _ = root.dispatch_pointer_to(w.id, {
    kind: @widget.PointerKind::Move,
    x: px + 6.0 + cw * 5.0,
    y: py + 6.0 + ch * 0.5,
    button: 1,
    mods: 0,
  })
  let _ = root.dispatch_pointer_to(w.id, {
    kind: @widget.PointerKind::Up,
    x: px + 6.0 + cw * 5.0,
    y: py + 6.0 + ch * 0.5,
    button: 1,
    mods: 0,
  })
  // 复制 → 隔离槽
  assert_true(term_key(root, w, 99, combo))
  assert_eq(terminal_clip_get(), Some("ello"))
  // 粘贴 → on_input 收到槽内容
  let _ = terminal_clip_set("PAST")
  assert_true(term_key(root, w, 118, combo))
  assert_eq(got.val, ["PAST"])
  // 组合 C 在无选区时（新终端）不产输入也不动剪贴板
  let (root2, w2, got2) = mounted_terminal("abc\n")
  assert_false(term_key(root2, w2, 99, combo))
  assert_eq(got2.val, [])
  assert_eq(terminal_clip_get(), Some("PAST"))
  let _ = root
}

///|
test "Shift+PageUp/Down 回看翻页（不进 on_input）" {
  let term = Terminal::new(cols=20, rows=3, scrollback=10)
  term.feed("1\n2\n3\n4\n5\n6")
  let got : Ref[Array[String]] = Ref([])
  let n = terminal(term, height=90.0, focus_id=1, blink=false, on_input=fn(s : String) -> Unit {
    got.val.push(s)
  })
  let root = @widget.Widget::new()
  root.set_size(240.0, 110.0)
  root.set_column()
  let w = n.mount_into(root)
  root.relayout(240.0, 110.0)
  assert_true(term.is_bottom())
  assert_true(term_key(root, w, KS_PAGE_UP, @base.MOD_SHIFT))
  assert_false(term.is_bottom())
  assert_true(term_key(root, w, KS_PAGE_DOWN, @base.MOD_SHIFT))
  assert_true(term.is_bottom())
  assert_eq(got.val, [])
}

///|
test "IME commit 经 on_input" {
  let (root, w, got) = mounted_terminal("")
  let _ = root.dispatch_commit(w.focus_id, "你好")
  assert_eq(got.val, ["你好"])
}
