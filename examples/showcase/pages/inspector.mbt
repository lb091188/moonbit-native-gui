// 检查器页（第 18 页）：内建 inspector v1 只读面板整页演示——控件树浏览吃
// a11y_last_frame 帧尾快照、点行看布局/语义读数、paint_profile_summary 帧耗时。
// 面板本体在库包 `gui/inspector`（应用按需 import）；本页只装配与说明。
//
// 口径：快照是「上一帧」的只读账，与本页自身的树互相包含（面板也出现在快照
// 里，属预期）；自动刷新开着时每次刷新整表重填，选中行落在表外就清。

///|
pub fn page_inspector(_app : @shared.App) -> @widget.Node {
  @shared.page([
    @shared.section(
      "检查器",
      "内建 Inspector（只读）",
      "三块：控件树（数据源 a11y_last_frame 帧尾语义快照——与屏读同源，不可见子树整棵不在快照里，面板自己也出现在树里属预期）、选中读数（id/父/角色/名/状态/值/正文/启用/窗口矩形）、帧耗时账本（paint_profile_summary：布局/绘制/上屏分段的累计与最大帧，重置统计清零重算）。刷新读上一帧——先动一动界面再点刷新，或开自动刷新（500ms 一拍，自重排延时表）。v1 边界：跨控件高亮框不做（面板嵌在内容里，浮层框会盖住自己）；编辑回灌随 v2 走 mngdev 样式通道。",
      [
        @inspector.inspector_panel(width=680.0, table_h=300.0),
      ],
      code=[
        "// 库包 gui/inspector，应用按需 import（不进核心链）",
        "@inspector.inspector_panel(",
        "  refresh_ms=500,   // 自动刷新间隔",
        "  auto=false,       // 初始是否自动刷新（开关在面板里）",
        "  table_h=240.0,    // 树表高度",
        "  width=640.0,",
        ")",
        "// 数据源同源口径：树读的就是屏读那份帧尾快照",
        "let nodes = @widget.a11y_last_frame()",
        "// 帧耗时账本：常开不设开关，面板外也能读",
        "println(@base.paint_profile_summary())",
        "@base.paint_profile_reset()",
      ],
    ),
  ])
}
