// 回归：`panel` 必须收 `class`，否则圆角等皮肤无法下达（0.2.0 的接口缺口）。

///|
test "panel 收 class：背景与圆角经 class 生效" {
  let node = panel(
    "",
    [],
    padding=10.0,
    class=[
      @style.style(
        background_color="#ff0000",
        border_radius=6.0,
        width=120.0,
        height=80.0,
      ),
    ],
  )
  let root = mount_root([node], 200.0, 120.0)
  let w = kid(root, 0)
  assert_eq((w.rect.w, w.rect.h), (120.0, 80.0))
  let bm = @render.Bitmap::new(200, 120)
  let p = @render.Painter::new(bm)
  root.paint(p)
  p.end()
  let red = fn(x : Int, y : Int) -> Bool {
    let c = color_of(bm, x, y)
    c.0 > 128 && c.1 < 64 && c.2 < 64
  }
  assert_true(red(60, 40))
  // 左上角落在半径 6 的弧外：class 的圆角真的裁剪了面板底
  assert_false(red(0, 0))
}
