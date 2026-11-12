// 共享层：跨段状态 App 与取译函数。页内私有状态留在各页函数体内，不进 App。
//
// 两条口径：① App 只带跨段状态，句柄类字段用到才加——托盘是应用级单例，句柄
// 归 main 建、放这里给托盘段操作；② 单实例应用 id 常量在这里单源，main 声称与
// 段内回显必须同一个串。

///|
/// 共享状态：语言、轻提示、宿主句柄、托盘与单实例回显。
pub(all) struct App {
  /// 当前语言标签（"zh-CN" / "en"）；切换后由 `@widget.localized` 的广播重建
  locale : @base.Store[String]
  /// 轻提示推送（转发 `toast_layer` 的函数值字段）
  toast : (String, @ui.SemanticType) -> Unit
  /// 宿主句柄（挂载时由 main 的 handle 回调填入）：对话框 parent / 退出都经它
  host : Ref[@widget.WindowHost?]
  /// 托盘句柄：main 挂载期建好，托盘段只做「换提示 / 换图标」这类操作
  tray : Ref[@shell.Tray?]
  /// 托盘左键计数（main 的回调写，段里读）
  tray_clicks : @base.Store[Int]
  /// 托盘操作回显（main 建托盘时写后端名，段里按钮改写）
  tray_note : @base.Store[String]
  /// 单实例：本进程收到过的唤起条数（main 的 `on_instance_wake` 回调写，段里读）
  inst_wakes : @base.Store[Int]
  /// 单实例操作回显（main 声称时写「哪一档拿到了首实例」，段里按钮改写）
  inst_note : @base.Store[String]
}

///|
/// 本示例的单实例应用 id（反向域名形态）：main 声称用，单实例段读后端与自环
/// 唤起也用，两边必须同一个串。
pub let sys_app_id : String = "libyue.sysdemo"

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
