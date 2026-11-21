// 真 FFI 建图回归：BGRA 预乘像素 → 原生图标句柄。内存内建图，无界面副作用。
// 缘起：托盘内置图标链路曾无可自动化覆盖——像素不合法/建图失败会静默降级，
// 只能在真机上看图缺图标。此测试钉住「合法像素必须建得出句柄」这一环。
// Linux 的 GTK 桩没有建图层——托盘图标走 SNI 像素通道，句柄 0 是「图标
// 不可用」语义而非回归，按档位探针跳过。

///|
/// 建图层档位探针：真实现档（Win32/mac）回 1，GTK/占位桩回 0。
extern "c" fn wm_icon_backend() -> Int32 = "wm_icon_backend"

///|
fn icon_backend_real() -> Bool {
  wm_icon_backend() == 1
}

///|
test "icon_from_bgra: 真 FFI 建图出正句柄" {
  if !icon_backend_real() {
    println("icon: skip [需真后端]（Linux 建图层按设计句柄 0，托盘走 SNI 像素通道）")
    return
  }
  let px : FixedArray[Byte] = FixedArray::make(8 * 8 * 4, b'\xff')
  match icon_from_bgra(px, 8, 8) {
    Some(ic) => {
      assert_true(ic.handle > 0)
      ic.free()
    }
    None => fail("icon_from_bgra 真 FFI 建图失败（平台桩或像素口径回归）")
  }
}
