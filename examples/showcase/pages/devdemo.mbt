// 模板 Dev 页：结构热更演示面。补丁由 tools/native-gui-tools/mng_cli dev 推送（单实例通道
// args = ["--mng-hot", <ir 路径>]），applier 按本页登记的注册表原位重建本容器。
// 注册表键 = dev_demo.mng 的模板坐标（t:行:列 / c:行:列）与变量/函数名；
// 键对不上时 applier 的报错会给出缺项键。模板源与补丁链路见
// proposals/native-template.md「结构热更新」节。
pub fn page_mng_dev(_app : @shared.App) -> @widget.Node {
  let reg = @shared.mng_reg_new()
  // 演示状态（与 dev_demo.mng 的 v-model 目标同名）
  let qty : @base.Store[Int] = @base.Store::new(3)
  let wifi : @base.Store[Bool] = @base.Store::new(true)
  let nick : @base.Store[String] = @base.Store::new("")
  reg.int("qty", qty)
  reg.bool("wifi", wifi)
  reg.str("nick", nick)
  // 动态槽（键 = dev_demo.mng 坐标）
  reg.cond("c:9:5", fn() { wifi.get() })
  reg.expr("t:12:5", fn() { "当前数量：\{qty.get()}" })
  reg.expr("t:8:18", fn() { @shared.tx("自动开启") })
  reg.expr("t:9:5", fn() { @shared.tx("已开启") })
  // 事件
  reg.handler("on_reset", fn() {
    qty.set(3)
    nick.set("")
  })
  @shared.mng_dev_set_reg("dev_demo", reg)
  @ui.col(
    [
      @ui.text(@shared.tx("本页是模板热更演示：由 tools/native-gui-tools/mng_cli dev 推送补丁原位重建。保存模板后亚秒可见。"), max_lines=3),
      @widget.node_of_new(fn(w : @widget.Widget) {
        @shared.mng_dev_bind_holder("dev_demo", w)
        w
      }),
    ],
    row_gap=8.0,
  )
}
