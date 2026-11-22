// 布局回归：页签链高度约束——窗口 420×560 里 tabs 必须被约束（min 下限
// 放开），scroll_view 视口必须小于内容高（纵滚可滚）。tabs 面板 min 尺寸
// 与本页 min 链任一回退，这里都会抓红。

///|
fn find_kind(w : @widget.Widget, name : String) -> @widget.Widget? {
  if w.kind == name {
    return Some(w)
  }
  for c in w.children() {
    match find_kind(c, name) {
      Some(x) => return Some(x)
      None => ()
    }
  }
  None
}

///|
test "布局：页签链受约束、纵滚可滚" {
  let app = build_app()
  // 模拟服务已启动的真实地址长度（单行省略口径的回归面）
  app.url.set("http://192.168.0.35:8787/?t=0123456789abcdef0123456789abcdef")
  let t = @uitest.mount_all([page(app)], 420.0, 560.0)
  t.frame()
  t.frame()
  t.frame()
  // 外层 view 宽钉满窗口（宽被内容顶爆的回归面：曾顶到 512）
  let top = t.root.children()[0]
  assert_true(top.rect.w > 419.0 && top.rect.w < 421.0)
  // tabs 高受约束（回退态是内容自然高 582+）
  match find_kind(t.root, "ui-tabs") {
    Some(tabs) => {
      assert_true(tabs.rect.h > 400.0)
      assert_true(tabs.rect.h < 540.0)
    }
    None => abort("找不到 ui-tabs")
  }
  // 纵滚：视口受约束且小于内容高
  match find_kind(t.root, "ui-scroll-view") {
    Some(sv) => {
      assert_true(sv.rect.h > 400.0)
      assert_true(sv.rect.h < 540.0)
      let kids = sv.children()
      assert_true(kids.length() >= 1)
      assert_true(kids[0].rect.h > sv.rect.h + 10.0)
    }
    None => abort("找不到 ui-scroll-view")
  }
}
