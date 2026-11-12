// 共享层：跨段状态 App 与取译函数。页内私有状态留在各页函数体内，不进 App。
//
// 两条口径：① App 只带跨段状态，句柄类字段用到才加；② 主题跟随是「跟随开关 +
// 定时读系统偏好」，见 `main.mbt` 的 tick。

///|
/// 共享状态：语言、轻提示、主题深浅/主色与跟随开关。
pub(all) struct App {
  /// 当前语言标签（"zh-CN" / "en"）；切换后由 `@widget.localized` 的广播重建
  locale : @base.Store[String]
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

///|
/// 取译：按当前 `@i18n` 目录查 key，缺失时回落 key 本身。
pub fn t(key : String) -> String {
  @i18n.t_or(key, key)
}

///|
/// 中文原文当 key 的取译（页正文用）：中文态回落原文，英文态命中「原文 → 译文」条目。
pub fn tx(zh : String) -> String {
  @i18n.t_or(zh, zh)
}

///|
/// 带插值的取译：目录条目用 `\{名}` 占位；中文态回落 `zh`（调用处已插值好）。
pub fn tr_with(key : String, vars : Array[(String, String)], zh : String) -> String {
  @i18n.t_with_or(key, vars, zh)
}

///|
/// 切当前语言的目录：en 载入英文目录，其余复位到内置中文默认。
pub fn set_locale_catalog(locale : String) -> Unit {
  if locale == "en" {
    @i18n.i18n_load(EN_CATALOG)
  } else {
    @i18n.i18n_reset()
  }
}
