// 共享层：跨段状态 App。页内私有状态留在各页函数体内，不进 App。
//
// 两条口径：① App 只带跨段状态，句柄类字段用到才加；② 主题跟随是「跟随开关 +
// 定时读系统偏好」，见 `main.mbt` 的 tick。

///|
/// 共享状态：轻提示、主题深浅/主色与跟随开关。
pub(all) struct App {
  /// 轻提示推送（转发 `toast_layer` 的函数值字段）
  toast : (String, @ui.SemanticType) -> Unit
  /// 深浅：跟随开关打开时由定时器写
  dark_mode : @base.Store[Bool]
  /// 主题主色（hex）：空串 = 内置基准盘
  accent : @base.Store[String]
  /// 跟随系统深浅/主色开关
  follow : @base.Store[Bool]
}

///|
/// 推送一条轻提示（转发 toast 函数字段；函数值字段不能直接点调用）。
pub fn App::toast_push(self : App, text : String, t : @ui.SemanticType) -> Unit {
  (self.toast)(text, t)
}
