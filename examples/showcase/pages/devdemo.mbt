// 模板 Dev 页：内容全部来自 dev_demo.mng 的生成码。
// 生产形态是普通页面（`mng build` 产出，零 dev 痕迹）；本地跑 `mng_cli dev` 时
// 同一文件被改写成 dev 形态——页面壳自登记注册表与 holder，补丁经单实例通道
// （args = ["--mng-hot", <ir 路径>]）到达 shared/mng_dev.mbt 的 applier，原位重建。
// 模板源与补丁链路见 proposals/native-template.md「结构热更新」节。
pub fn page_mng_dev(_app : @shared.App) -> @widget.Node {
  @ui.col(
    [
      @ui.text(
        @shared.tx("本页是模板热更演示：由 tools/native-gui-tools/mng_cli dev 推送补丁原位重建。保存模板后亚秒可见。"),
        max_lines=3,
      ),
      dev_demo(),
    ],
    row_gap=8.0,
  )
}
