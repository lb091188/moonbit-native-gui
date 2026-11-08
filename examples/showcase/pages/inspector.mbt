// 检查器页（第 17 页）：内建 inspector 面板整页演示——控件树浏览吃
// a11y_last_frame 帧尾快照、点行看布局/语义读数、paint_profile_summary 帧耗时；
// v2 加「样式类」页签：改命名类样式值经 @style.define_class 回灌（与 mngdev
// 样式热更同口），应用即下一帧生效，「还原此类」回会话首见快照。
// 面板本体在库包 `gui/inspector`（应用按需 import）；本页只装配与说明。
//
// 口径：快照是「上一帧」的只读账，与本页自身的树互相包含（面板也出现在快照
// 里，属预期）；自动刷新开着时每次刷新整表重填，选中行落在表外就清。

///|
pub fn page_inspector(_app : @shared.App) -> @widget.Node {
  @shared.page([
    @shared.section(
      "检查器",
      "内建 Inspector",
      "页签一「控件树」（v1 只读）：树表数据源 a11y_last_frame 帧尾语义快照——与屏读同源，不可见子树整棵不在快照里，面板自己也出现在树里属预期；点行看读数（id/父/角色/名/状态/值/正文/启用/窗口矩形）；帧耗时账本（paint_profile_summary：布局/绘制/上屏分段的累计与最大帧，重置统计清零重算）。刷新读上一帧——先动一动界面再点刷新，或开自动刷新（500ms 一拍）。页签二「样式类」（v2 编辑回灌）：列出 @style 注册表的命名类（与 mngdev 样式热更同口），选中后改背景/文字/边框色/边框宽/圆角五样（base 与 :hover 各一套），「应用」即 define_class 回灌、用了该类的控件下一帧换新样式；「还原此类」回本会话首次刷新类列表时抓的快照。空白输入 = 不改该字段；token 名（primary 等）与 #hex 都吃。",
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
        "// v2 回灌：与 mngdev 样式热更同一个注册表口",
        "@style.define_class(\"btn-primary\", @style.style(background_color=\"primary\"))",
        "@widget.invalidate() // 下一帧，用了这个类的控件换新样式",
      ],
    ),
  ])
}
