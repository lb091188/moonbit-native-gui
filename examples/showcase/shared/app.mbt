// 共享层：跨页状态 App 与平台判断。各页函数以 app 单参取用；
// 页内私有状态留在各页函数体内，不进 App。
//
// 两条口径：① App 只带跨页状态，句柄类字段用到才加——窗口页要 `host`
// （取 `@widget.App` 宿主，经 `App::window()` 调窗口级 API），共享层不替别的页
// 预置死字段；② 主题跟随是「跟随开关 + 定时读系统偏好」，见 `main.mbt` 的
// tick，手动选色/切深浅先把跟随关掉。

///|
/// 跨页共享状态：导航、主题、跨页计数。
pub(all) struct App {
  /// 侧栏与页切换共用的导航状态（存页名）
  selected : @base.Store[String]
  /// 当前语言标签（"zh-CN" / "en"）；切它触发整棵内容树按新 catalog 重建
  locale : @base.Store[String]
  /// 轻提示推送（转发 `toast_layer` 的函数值字段）
  toast : (String, @ui.SemanticType) -> Unit
  /// 深浅：跟随开关打开时由定时器写，按钮手动改时先关跟随
  dark_mode : @base.Store[Bool]
  /// 主题主色（hex）：空串 = 内置基准盘，否则 `theme_from_accent` 公式派生
  accent : @base.Store[String]
  /// 跟随系统深浅/主色开关（「跟随系统」按钮置真，手动选色置假）
  follow : @base.Store[Bool]
  /// 主题页共享信号：基础页 Button 触发，数据页 Statistic/Progress 展示；
  /// visits/ratio 为 computed 派生（信号版消灭了手动 subscribe 接线）
  counter : @base.Signal[Int]
  visits : @base.Signal[String]
  ratio : @base.Signal[Double]
  /// 最近一次链接点击（基础页回显）
  picked_lang : @base.Signal[String]
  /// 对话框可见性（反馈页的按钮是触发方，两个对话框挂在 main 的窗口根）
  dlg_basic : @base.Store[Bool]
  dlg_form : @base.Store[Bool]
  /// 表单对话框里的名称框（Store 是文本状态的唯一权威，`input` 直连）
  dlg_name : @base.Store[String]
  /// 最近一次对话框确认的回显（与 `dlg_name` 分开，避免确认把输入框内容改掉）
  dlg_result : @base.Store[String]
  /// 圆角总开关：开启时全站圆角按 0 解析（`@style.set_square_corners`）
  flat : @base.Store[Bool]
  /// 侧栏/菜单半透玻璃开关：整窗开背景透明 + 侧栏走 `@ui.glass` 应用内模糊
  translucent : @base.Store[Bool]
  /// 柔焦模糊开关：演示位图背景的模糊态（`@render.Bitmap::soft_blur`）
  soft : @base.Store[Bool]
  /// 宿主句柄（挂载时由 main 的 handle 回调填入）：窗口页要调 `@win.Window` 的
  /// 标题/尺寸/无边框、快捷键页要开轮询表，都经它取。页函数体跑完时还没挂载，
  /// 所以是 Ref——按钮点击时读，那时早已填上。
  host : Ref[@widget.App?]
}

///|
/// 推送一条轻提示（转发 toast 函数字段；函数值字段不能直接点调用）。
pub fn App::toast_push(self : App, text : String, t : @ui.SemanticType) -> Unit {
  (self.toast)(text, t)
}

///|
/// 取译：按当前 `@i18n` 目录查 key，缺失时回落 key 本身（便于用 i18n_cli check 发现漏配）。
pub fn t(key : String) -> String {
  @i18n.t_or(key, key)
}
