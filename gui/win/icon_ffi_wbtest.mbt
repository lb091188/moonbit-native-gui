// 真 FFI 建图回归：BGRA 预乘像素 → 原生图标句柄。内存内建图，无界面副作用。
// 缘起：托盘内置图标链路曾无可自动化覆盖——像素不合法/建图失败会静默降级，
// 只能在真机上看图缺图标。此测试钉住「合法像素必须建得出句柄」这一环。

///|
test "icon_from_bgra: 真 FFI 建图出正句柄" {
  let px : FixedArray[Byte] = FixedArray::make(8 * 8 * 4, b'\xff')
  match icon_from_bgra(px, 8, 8) {
    Some(ic) => {
      assert_true(ic.handle > 0)
      ic.free()
    }
    None => fail("icon_from_bgra 真 FFI 建图失败（平台桩或像素口径回归）")
  }
}
