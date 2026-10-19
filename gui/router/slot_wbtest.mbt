// 挂载槽回归：选中才挂、其余只隐藏，Keep 保形，Lru 淘汰真的摘树并重建，
// 淘汰把这一代订阅一起退掉，单层树同样能挂。

fn sl_text() -> @widget.Node {
  @ui.text("内容", role=@ui.Body)
}

fn sl_lf(k : String, hits : Ref[Int]) -> Route {
  route_leaf(k, fn() -> @widget.Node {
    hits.val += 1
    sl_text()
  })
}

fn sl_lf_evict(k : String, hits : Ref[Int], n : Int) -> Route {
  route_leaf(k, fn() -> @widget.Node {
    hits.val += 1
    sl_text()
  }, evict=Lru(n))
}

fn sl_br(k : String, kids : Array[Route]) -> Route {
  route_branch(k, kids)
}

fn sl_tree(hits : Ref[Int]) -> Array[Route] {
  [
    sl_br("组件", [sl_lf("按钮", hits), sl_lf("消息框", hits)]),
    sl_br("系统", [sl_lf("托盘", hits), sl_lf("通知", hits)]),
  ]
}

fn sl_mount(view : @widget.Node) -> @widget.Widget {
  let root = @widget.Widget::new()
  root.set_size(1200.0, 800.0)
  root.set_column()
  let w = view.mount_into(root)
  root.relayout(1200.0, 800.0)
  w
}

fn sl_count(w : @widget.Widget) -> Int {
  let kids = w.children()
  let mut n = 1
  for c in kids {
    n += sl_count(c)
  }
  n
}

///|
test "选中才挂，其余只留空壳" {
  let hits = Ref(0)
  let r = new_router(sl_tree(hits))
  let root = sl_mount(r.view(None))
  assert_eq(hits.val, 1)
  assert_true(r.is_mounted("组件"))
  assert_true(r.is_mounted("组件/按钮"))
  assert_false(r.is_mounted("组件/消息框"))
  assert_false(r.is_mounted("系统"))
  // 没选过的页只占一个空容器
  assert_true(sl_count(root) < 40)
}

///|
test "切页挂新页，Keep 的旧页保形不摘" {
  let hits = Ref(0)
  let r = new_router(sl_tree(hits))
  let root = sl_mount(r.view(None))
  let before = sl_count(root)
  r.goto("系统/通知")
  assert_true(r.is_mounted("系统/通知"))
  assert_eq(hits.val, 2)
  assert_true(r.is_mounted("组件/按钮"))
  assert_true(sl_count(root) > before)
  // 再切回去：内容早挂过，thunk 不再跑
  r.goto("组件/按钮")
  assert_eq(hits.val, 2)
}

///|
test "Lru 淘汰是摘树，重进按 thunk 重建" {
  let hits = Ref(0)
  let roots = [
    sl_br("组件", [
      sl_lf_evict("按钮", hits, 1),
      sl_lf_evict("消息框", hits, 1),
      sl_lf_evict("输入", hits, 1),
    ]),
  ]
  let r = new_router(roots)
  let root = sl_mount(r.view(None))
  assert_true(r.is_mounted("组件/按钮"))
  r.goto("组件/消息框")
  assert_true(r.is_mounted("组件/消息框"))
  // 窗口 1：上一个被淘汰
  assert_false(r.is_mounted("组件/按钮"))
  assert_eq(r.mounted_at("组件").length(), 1)
  let after_evict = sl_count(root)
  r.goto("组件/按钮")
  // 重进走 thunk 重建（不是把旧节点重挂，避免 on_mount 排双份）
  assert_eq(hits.val, 3)
  assert_true(r.is_mounted("组件/按钮"))
  assert_false(r.is_mounted("组件/消息框"))
  assert_true(after_evict < 40)
}

///|
test "淘汰把这一代订阅退掉" {
  let hits = Ref(0)
  let sig = @base.Signal::new(0)
  let wakes = Ref(0)
  let roots = [
    sl_br("组件", [
      route_leaf("按钮", fn() -> @widget.Node {
        hits.val += 1
        let _ = sig.subscribe(fn(_v : Int) -> Unit {
          wakes.val += 1
        })
        sl_text()
      }, evict=Lru(1)),
      route_leaf("消息框", fn() -> @widget.Node {
        hits.val += 1
        let _ = sig.subscribe(fn(_v : Int) -> Unit {
          wakes.val += 1
        })
        sl_text()
      }, evict=Lru(1)),
    ]),
  ]
  let r = new_router(roots)
  let _root = sl_mount(r.view(None))
  sig.set(1)
  assert_eq(wakes.val, 1)
  r.goto("组件/消息框")
  // 淘汰「按钮」时把它构造期注册的那批订阅一起退掉：只剩「消息框」那一个还活着
  sig.set(2)
  assert_eq(wakes.val, 2)
  r.goto("组件/按钮")
  sig.set(3)
  assert_eq(wakes.val, 3)
  assert_false(r.is_mounted("组件/消息框"))
}

///|
test "整棵分支被摘时子孙槽的挂载态一起归零" {
  let hits = Ref(0)
  let roots = [
    sl_br("甲", [sl_br("子", [sl_lf("叶", hits)])]),
    sl_br("乙", [sl_br("子", [sl_lf("叶", hits)])]),
  ]
  let r = new_router(roots)
  let _root = sl_mount(r.view(None))
  assert_true(r.is_mounted("甲"))
  assert_true(r.is_mounted("甲/子"))
  assert_true(r.is_mounted("甲/子/叶"))
  r.unmount("甲")
  assert_false(r.is_mounted("甲"))
  assert_false(r.is_mounted("甲/子"))
  assert_false(r.is_mounted("甲/子/叶"))
  r.goto("乙")
  assert_true(r.is_mounted("乙/子/叶"))
}

///|
test "单层路由同样能挂" {
  let hits = Ref(0)
  let roots = [sl_lf("首页", hits), sl_lf("次页", hits)]
  let r = new_router(roots)
  let _root = sl_mount(r.view(None))
  assert_eq(r.level_count(), 1)
  assert_true(r.is_mounted("首页"))
  r.goto("次页")
  assert_true(r.is_mounted("次页"))
  assert_eq(hits.val, 2)
}

///|
test "入口载体挂在分支内容前面" {
  let hits = Ref(0)
  let r = new_router(sl_tree(hits))
  let bar : (Router, Int, String, Array[Route]) -> @widget.Node =
    fn(_ro : Router, _d : Int, _p : String, cs : Array[Route]) -> @widget.Node {
      let names : Array[String] = []
      for c in cs {
        names.push(c.key)
      }
      @ui.text("入口:" + names.join(","), role=@ui.Title)
    }
  let root = sl_mount(r.view(Some(bar)))
  assert_true(sl_count(root) > 4)
  assert_true(r.is_mounted("组件/按钮"))
}
