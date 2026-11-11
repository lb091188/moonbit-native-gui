// 体检结果类型与渲染无关的双语文案。

///|
/// 单项体检的三档状态。
pub(all) enum DStatus {
  Ok
  Warn
  Fail
}

///|
/// CLI 双语文案对：调用方按自己的语言开关取一侧。
pub(all) struct DBi {
  zh : String
  en : String
}

///|
/// 单项体检结果。`optional` 为真的项（WebView / 媒体库等）失败只警告，不拦 ready。
pub(all) struct DItem {
  id : String
  optional : Bool
  status : DStatus
  title : DBi
  detail : DBi
  fix : DBi?
}
