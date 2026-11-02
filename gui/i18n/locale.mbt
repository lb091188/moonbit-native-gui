// 语言变更的表面侧登记口：文本组件绘制期现取译文，天然跟随；**原生表面**
// （菜单栏、托盘提示、原生消息框这类画在控件树之外的东西）不认样式槽，
// 靠这里的订阅在换目录那一刻集中重建重挂。用法与主题订阅同构：
// `on_locale_change` 登记重挂函数，`i18n_load`/`i18n_extend`/`i18n_reset`
// 换目录时统一广播；调用方不必再记「切语言时记得刷它」。

///|
priv struct LocaleSubs {
  mut next_id : Int
  mut subs : Array[(Int, (String) -> Unit)]
}

///|
let locale_subs : LocaleSubs = { next_id: 0, subs: [], }

///|
/// 订阅语言变更（入参=新 locale 标签）：登记时**不**立即回调，
/// 之后的每次换目录广播一次。返回退订句柄。
pub fn on_locale_change(f : (String) -> Unit) -> Int {
  locale_subs.next_id += 1
  let h = locale_subs.next_id
  locale_subs.subs.push((h, f))
  h
}

///|
/// 退订（幂等，未知句柄空操作）。长命表面用它配回收袋，页面级表面换代时摘旧句柄。
pub fn off_locale_change(handle : Int) -> Unit {
  locale_subs.subs = locale_subs.subs.filter(fn(e) { e.0 != handle })
}

///|
/// 广播一次语言变更（`i18n_load`/`i18n_extend`/`i18n_reset` 尾部调用）。
/// 快照遍历：回调里退订/新订不影响本趟。
pub fn locale_notify() -> Unit {
  let snapshot = locale_subs.subs.copy()
  let loc = g_store.cur.locale
  for (_, f) in snapshot {
    f(loc)
  }
}
