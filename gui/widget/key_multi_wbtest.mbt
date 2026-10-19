// W32 键多击：KeyTracker 判定 + Widget.on_key_double 派发。
// 真实按键间隔在单测里无法等待，按既有 ClickTracker 用例同口径：
// 直接改 tracker 的 last_time 造时间窗，再喂第二下。

test "KeyTracker：同键 60–400ms 内二连按计 2" {
  let kt = KeyTracker::new()
  kt.last_keysym = 97
  kt.last_mods = 0
  kt.last_time = @shell.now_ms() - 150L
  kt.press_count = 1
  assert_eq(kt.feed(97, 0), 2)
  assert_true(kt.is_double())
}

test "KeyTracker：不同键重置为 1" {
  let kt = KeyTracker::new()
  kt.last_keysym = 97
  kt.last_mods = 0
  kt.last_time = @shell.now_ms() - 150L
  kt.press_count = 1
  assert_eq(kt.feed(98, 0), 1)
}

test "KeyTracker：自动重复档（<60ms）不计多击" {
  let kt = KeyTracker::new()
  kt.last_keysym = 97
  kt.last_mods = 0
  kt.last_time = @shell.now_ms() - 30L
  kt.press_count = 1
  assert_eq(kt.feed(97, 0), 1)
}

test "Widget.on_key_double：焦点控件命中双击档时回调" {
  let root = Widget::new()
  root.set_size(100.0, 50.0)
  root.focus_id = 7
  root.key_tracker.last_keysym = 97
  root.key_tracker.last_mods = 0
  root.key_tracker.last_time = @shell.now_ms() - 150L
  root.key_tracker.press_count = 1
  let hits : Array[Int] = []
  root.on_key_double = Some(fn(_w : Widget, _ev : KeyEvent) -> Unit { hits.push(1) })
  let ev : KeyEvent = { press: true, keysym: 97, mods: 0 }
  let _ = root.dispatch_key(7, ev)
  assert_eq(hits, [1])
}

test "bind_key_double：单次按键不触发" {
  host_reset()
  let a = fake_win_app()
  let hits : Array[Int] = []
  a.bind_key_double("A", fn() -> Unit { hits.push(1) })
  let _ = a.fire_key_fallthrough({ press: true, keysym: 97, mods: 0 })
  assert_eq(hits.length(), 0)
  host_reset()
}
