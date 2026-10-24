// 窗口显隐事件（W23b）的无头回归：`Hidden`/`Shown` 的宿主侧收口——
// on_hidden / on_shown 按注册序触发；隐藏一并清输入法会话（在途组合串
// 去重缓存复位、焦点哨兵置「未同步」）。假窗句柄越界、wm_* 全部早退，
// 与 host_wbtest.mbt 同款；事件注不入队，drain 分派由真机清单验。

///|
fn vis_app() -> App {
  let root = Widget::new()
  {
    session: @shell.fake_session(910, @shell.host_new_wid(), false, 300, 200),
    root,
    focus: FocusStack::new(),
    host: make_overlay_host(root),
    closed: false,
    canvas: None,
    key_fallthrough: [],
    dirty_rect: None,
    dirty_full: false,
    system_keys: true,
    hidden_cbs: [],
    shown_cbs: [],
  }
}

///|
test "显隐回调按注册序触发；隐藏一并清输入法会话" {
  let a = vis_app()
  let hits : Array[String] = []
  a.on_hidden(fn() { hits.push("h1") })
  a.on_hidden(fn() { hits.push("h2") })
  a.on_shown(fn() { hits.push("s1") })
  // 挂一只可聚焦控件并给它焦点，再手动摆出「上一拍还有焦点、组合串在屏」的现场
  let field = Widget::new()
  field.focus_id = 5
  field.set_size(120.0, 24.0)
  a.root.set_column()
  a.root.append_child(field)
  a.root.relayout(300.0, 200.0)
  assert_true(a.focus_by_id(5))
  a.session.ime_focus = 5
  a.session.last_preedit = ("ni", 1)
  a.handle_hidden()
  assert_eq(hits.length(), 2)
  assert_eq(hits[0], "h1")
  assert_eq(hits[1], "h2")
  // 在途组合串已清：去重缓存复位、焦点哨兵置「未同步」（下一拍必重对齐 IM 门）
  assert_eq(a.session.last_preedit.0, "")
  assert_eq(a.session.ime_focus, -1)
  a.handle_shown()
  assert_eq(hits.length(), 3)
  assert_eq(hits[2], "s1")
}

///|
test "隐藏不动焦点栈：唤回后控件焦点照旧（与整窗失焦同档）" {
  let a = vis_app()
  let field = Widget::new()
  field.focus_id = 7
  field.set_size(120.0, 24.0)
  a.root.set_column()
  a.root.append_child(field)
  a.root.relayout(300.0, 200.0)
  assert_true(a.focus_by_id(7))
  a.handle_hidden()
  match a.focus.current() {
    Some(id) => assert_eq(id, 7)
    None => assert_true(false)
  }
}
