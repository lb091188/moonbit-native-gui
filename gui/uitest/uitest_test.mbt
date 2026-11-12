// 黑盒回归（唯一目的：验证本包「包外可用」本身）：以使用者视角经
// test-import 引 @uitest + @ui，走方案 §4.2 的计数器示例与各门面方法。

///|
test "计数器：点一下加一（方案 §4.2 原例）" {
  let n = @base.Store::new(0)
  let t = @uitest.mount_all(
    [
      @ui.bind_label(n, fn(v) { v.to_string() }).named("count"),
      @ui.button("加一", on_click=fn() { n.set(n.get() + 1) }).named("inc"),
    ],
    200.0,
    100.0,
  )
  assert_eq(t.text(t.by_name("count")), Some("0"))
  t.click(t.by_name("inc"))
  t.frame()
  assert_eq(t.text(t.by_name("count")), Some("1"))
  // 连点两次再到 3；frames 计数随 frame 走
  t.click(t.by_name("inc"))
  t.click(t.by_name("inc"))
  t.frame()
  assert_eq(t.text(t.by_text("count")), Some("3"))
  t.finish()
}

///|
test "定位：by_name 未命中、nth 子件、hit 命中最深件、role 读类名" {
  let t = @uitest.mount_all(
    [
      @ui.view([
        @ui.button("确定", on_click=fn() { () })
        .named("ok")
        .with_role("button"),
      ]).named("card"),
    ],
    200.0,
    100.0,
  )
  let card = t.by_name("card")
  assert_true(card.w is Some(_))
  // 未命中：全部方法空操作
  let miss = t.by_name("nope")
  assert_true(miss.w is None)
  assert_true(t.rect(miss) is None)
  assert_true(t.text(miss) is None)
  // nth：card 的第 0 个子件就是按钮
  let btn = t.nth(card, 0)
  assert_eq(t.text(btn), None)
  assert_eq(t.role(btn), Some("button"))
  assert_eq(t.role(t.by_name("card")), Some(""))
  // hit：按钮中心命中按钮本体
  match t.rect(btn) {
    Some(r) => {
      let deep = t.hit(r.x + r.w / 2.0, r.y + r.h / 2.0)
      assert_true(deep.w is Some(_))
    }
    None => abort("按钮没有矩形")
  }
  t.finish()
}

///|
test "type_text：焦点输入框收字符（IME commit 同一入口）" {
  let s = @base.Store::new("")
  let t = @uitest.mount_all(
    [@ui.input(s, focus_id=7).named("box")],
    240.0,
    80.0,
  )
  assert_eq(s.get(), "")
  t.type_text(t.by_name("box"), "你好")
  assert_eq(s.get(), "你好")
  // 键盘注入：Backspace 删一格（keysym 0xFF08）
  let _ = t.key(7, 0xFF08)
  assert_eq(s.get(), "你")
  t.finish()
}

///|
test "scroll 与 drag：不崩、坐标通路在" {
  let hits : @base.Store[Int32] = @base.Store::new(0)
  let t = @uitest.mount_all(
    [
      @ui.hover_group([@ui.text("拖我")], on_click=fn() {
        hits.set(hits.get() + 1)
      }).named("zone"),
    ],
    200.0,
    100.0,
  )
  // 滚轮（无人消费不崩）
  t.scroll(t.by_name("zone"), 40.0)
  // 拖拽起止都在 zone 内：Down+Move+Up 成对 → on_click 一次
  match t.rect(t.by_name("zone")) {
    Some(r) => t.drag((r.x + 10.0, r.y + 10.0), (r.x + 30.0, r.y + 20.0))
    None => abort("zone 没有矩形")
  }
  t.frame()
  assert_eq(hits.get(), 1)
  t.finish()
}

///|
test "capabilities 与守卫：三只读量给值、guard 缺失计数打印" {
  let t = @uitest.mount_all([], 100.0, 60.0)
  let caps = t.capabilities()
  // raster 位图分配在可跑测试的进程里恒可用
  assert_true(caps.raster)
  // 守卫在能力满足时直通；缺失时打印 skip 行（CI grep 汇总）
  if @uitest.guard_text(t) {
    assert_true(caps.text_measure)
  }
  if @uitest.guard_decode(t) {
    assert_true(caps.image_decode)
  }
  @uitest.guard_report()
}

///|
test "frame 后像素可读：点主色按钮中心有非透明墨" {
  let t = @uitest.mount_all(
    [@ui.button("提交", on_click=fn() { () }).named("go")],
    200.0,
    80.0,
  )
  t.frame()
  match t.rect(t.by_name("go")) {
    Some(r) => {
      let (rr, rg, rb, ra) = t.pixel(
        (r.x + r.w / 2.0).round().to_int(),
        (r.y + r.h / 2.0).round().to_int(),
      )
      assert_true(ra > 200)
      assert_true(rr + rg + rb > 0)
    }
    None => abort("按钮没有矩形")
  }
  t.finish()
}

///|
test "断言账本：观察点计数（找/动/看各算一次），零观察即红由 finish() 判" {
  let t = @uitest.mount_all([@ui.text("甲").named("a")], 120.0, 40.0)
  assert_eq(t.assertions(), 0)
  let _ = t.text(t.by_name("a"))
  let _ = t.rect(t.by_name("a"))
  // by_name 两次 + text + rect = 4（定位本身也是观察点：没定位就没断言的对象）
  assert_eq(t.assertions(), 4)
  // 有读数：finish() 不响（零读数时它 abort，红在测试输出里直接可见）
  t.finish()
}

///|
test "确定性时钟:advance 整体推进定时器(与机器速度无关)" {
  let win = @uitest.test_headless(300, 200)
  let fired = @base.Store::new(0)
  let _ = win.timer(50, fn() { fired.update(fn(n) { n + 1 }) })
  let _ = win.timer(150, fn() { fired.update(fn(n) { n + 1 }) })
  // 推 100ms:50ms 的响、150ms 的没响——推多少走多少,不等真实时间
  let n1 = @uitest.advance(win, 100)
  assert_eq(fired.get(), 1)
  assert_true(n1 > 0)
  // 再推 100ms:第二个也响
  let _ = @uitest.advance(win, 100)
  assert_eq(fired.get(), 2)
  // 没有新定时器:再推不再多跑
  let _ = @uitest.advance(win, 200)
  assert_eq(fired.get(), 2)
  @shell.session_vtime_reset()
}

///|
test "确定性时钟:settle 跑到无到期定时器且无脏窗" {
  let win = @uitest.test_headless(300, 200)
  let fired = @base.Store::new(0)
  // settle 只收敛**已到期**的活(未来定时器归 advance 推);0ms 即期任务立刻到期
  let _ = win.timer(0, fn() { fired.update(fn(n) { n + 1 }) })
  let steps = @uitest.settle(win)
  assert_eq(fired.get(), 1)
  assert_true(steps > 0)
  // 已收敛:再 settle 走 0 拍(无到期任务、无脏窗)
  assert_eq(@uitest.settle(win), 0)
  // 定时器回调里自排下一拍(仍 0ms 即期):settle 追到链尾(有界封顶防死循环)
  let chain = @base.Store::new(0)
  let tick : Ref[() -> Unit] = Ref(fn() { () })
  tick.val = fn() -> Unit {
    chain.update(fn(n) { n + 1 })
    if chain.get() < 5 {
      let _ = win.timer(0, tick.val)
    }
  }
  let _ = win.timer(0, tick.val)
  let _ = @uitest.settle(win)
  assert_eq(chain.get(), 5)
  @shell.session_vtime_reset()
}

///|
test "确定性时钟:同一推程结果可复现(两次会话同一读数)" {
  // 会话 A:推 200ms 计数周期表(每 40ms 一拍)
  let a = @uitest.test_headless(300, 200)
  let ca = @base.Store::new(0)
  let tick_a : Ref[() -> Unit] = Ref(fn() { () })
  tick_a.val = fn() -> Unit {
    ca.update(fn(n) { n + 1 })
    let _ = a.timer(40, tick_a.val)
  }
  let _ = a.timer(40, tick_a.val)
  let _ = @uitest.advance(a, 200)
  @shell.session_vtime_reset()
  // 会话 B:同参数同推程
  let b = @uitest.test_headless(300, 200)
  let cb = @base.Store::new(0)
  let tick_b : Ref[() -> Unit] = Ref(fn() { () })
  tick_b.val = fn() -> Unit {
    cb.update(fn(n) { n + 1 })
    let _ = b.timer(40, tick_b.val)
  }
  let _ = b.timer(40, tick_b.val)
  let _ = @uitest.advance(b, 200)
  @shell.session_vtime_reset()
  // 两会话拍数一致(首拍同刻,此后每 40ms 一拍;推程内拍数确定)
  assert_true(ca.get() >= 4)
  assert_eq(ca.get(), cb.get())
}
