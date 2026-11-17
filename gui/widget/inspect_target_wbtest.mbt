// 检查器取数目标窗的无头回归：inspect_target_set 锁定后 last_frame_* 读
// 指定窗的现役帧，目标关了回落「最近帧」登记；frame_untracked 的窗上屏不
// 进登记（检查器附窗这类取数工具窗，不把检查目标顶成自己）。

///|
/// 清「最近帧」与目标登记：用例间隔离（登记是进程级的）。
fn frame_regs_reset() -> Unit {
  g_last_frame_bitmap.val = None
  g_last_frame_title.val = ""
  g_last_frame_root.val = None
  inspect_target_set(None)
}

///|
test "检查目标窗优先档：设了读指定窗，目标关了回落最近帧，置 None 还原" {
  host_reset()
  frame_regs_reset()
  let a1 = test_app(@shell.fake_session(1, @shell.host_new_wid(), true, 800, 600))
  let a2 = test_app(@shell.fake_session(2, @shell.host_new_wid(), false, 400, 300))
  host_add_app(a1)
  host_add_app(a2)
  // 模拟 a1 最近上屏：登记里有它的根与位图
  g_last_frame_bitmap.val = Some(@render.Bitmap::new(800, 600))
  g_last_frame_title.val = "one"
  g_last_frame_root.val = Some(a1.root)
  // 没指定目标：读最近帧（a1 的根）
  match last_frame_root() {
    Some(r) => assert_eq(r.id, a1.root.id)
    None => assert_true(false)
  }
  // 指定 a2：根与位图都切到 a2 的现役帧（canvas 现读，宽 400 的那块）
  a2.canvas = Some(@render.Bitmap::new(400, 300))
  inspect_target_set(Some(a2))
  match last_frame_root() {
    Some(r) => assert_eq(r.id, a2.root.id)
    None => assert_true(false)
  }
  let (b, _t) = last_frame_bitmap()
  match b {
    Some(bm) => assert_eq(bm.width, 400)
    None => assert_true(false)
  }
  // a2 关了（目标死了）：回落最近帧登记（a1）
  a2.close_window()
  match last_frame_root() {
    Some(r) => assert_eq(r.id, a1.root.id)
    None => assert_true(false)
  }
  // 置 None 还原最近帧口径
  inspect_target_set(None)
  match last_frame_root() {
    Some(r) => assert_eq(r.id, a1.root.id)
    None => assert_true(false)
  }
  frame_regs_reset()
}

///|
test "frame_untracked：上屏登记被跳过，最近帧不被顶掉" {
  host_reset()
  frame_regs_reset()
  let a = test_app(@shell.fake_session(3, @shell.host_new_wid(), true, 800, 600))
  host_add_app(a)
  // untracked 档：登记直接跳过，最近帧还是空
  a.frame_untracked = true
  a.frame_register(@render.Bitmap::new(800, 600))
  assert_true(last_frame_root() is None)
  assert_true(last_frame_bitmap().0 is None)
  // 撤掉 untracked：照常登记
  a.frame_untracked = false
  a.frame_register(@render.Bitmap::new(800, 600))
  match last_frame_root() {
    Some(r) => assert_eq(r.id, a.root.id)
    None => assert_true(false)
  }
  frame_regs_reset()
}
