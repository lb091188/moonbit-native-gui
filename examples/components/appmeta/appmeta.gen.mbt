// 由 mng 从 mng.toml [package] 生成——勿手改;改 mng.toml 后跑 mng dev / mng build 同步

///|
/// 应用版本(mng.toml [package].version):更新链路「当前版本」的同源值。
pub let app_version : String = "0.2.0"

///|
/// 应用 id(mng.toml [package].id,反域名):单实例/托盘/通知的同源值。
pub let app_id : String = "com.moonbitlibyue.showcase"

///|
/// 应用显示名(mng.toml [package].name):托盘/通知/桌面登记的同源值。
pub let app_name : String = "Native GUI Showcase"
