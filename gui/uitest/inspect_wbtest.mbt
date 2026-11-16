// 无头检查直调用例：dump_tree 列序与 kind 采集、shot 落盘、kind 读数。

///|
test "Tester::dump_tree：列头 + kind/role/name 采集（与服务端 tree 同列序）" {
  let t = mount_all(
    [
      @widget.node_of_new(fn(w : @widget.Widget) -> @widget.Widget {
        w.kind = "Button"
        w.role = "button"
        w.label = "确定"
        w
      }),
    ],
    160.0,
    120.0,
  )
  t.frame()
  let out = t.dump_tree()
  // 首行列头与服务端 tree 命令一致
  assert_true(
    out.has_prefix(
      "#kind\trole\tname\tid\tparent\tx\ty\tw\th\tstate\tvalue\ttext\tenabled\n",
    ),
  )
  // 根行 Window + 按钮行带 kind 与正文
  assert_true(out.contains("Window"))
  assert_true(out.contains("Button\tbutton\t"))
}

///|
test "Tester::kind：读构造自带类型名" {
  let t = mount_all(
    [
      @widget.node_of_new(fn(w : @widget.Widget) -> @widget.Widget {
        w.kind = "Slider"
        w.role = "slider"
        w
      }),
    ],
    160.0,
    120.0,
  )
  t.frame()
  assert_true(t.dump_tree().contains("Slider\tslider\t"))
}

///|
test "Tester::shot：frame 后落盘 PNG；未 frame 给 false" {
  let t = mount_all([], 80.0, 60.0)
  assert_true(!t.shot("/tmp/mng-uitest-shot-empty.png"))
  t.frame()
  assert_true(t.shot("/tmp/mng-uitest-shot-test.png"))
}
