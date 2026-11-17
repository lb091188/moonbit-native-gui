// 单件样式覆写：检查器 `style set` 写、`style reset` 清。覆写在绘制读数
// （style_for）与检查器读数（resolved_by_id）里最后并入——压过基块、状态桶
// 与过渡，是这一件的最高优先档；只存设置过的字段，清掉即回基层样式。

///|
let override_table : Map[Int32, Style] = Map([])

///|
/// 覆写某件的一段样式（只并入给到的字段，同字段以后写的赢），下一帧生效。
pub fn override_set(id : Int32, st : Style) -> Unit {
  let cur = match override_table.get(id) {
    Some(c) => c
    None => empty_style()
  }
  override_table[id] = merge(cur, st)
  @widget.invalidate()
}

///|
/// 清某件的全部覆写，回基层样式。
pub fn override_reset(id : Int32) -> Unit {
  if override_table.contains(id) {
    let _ = override_table.remove(id)
    @widget.invalidate()
  }
}

///|
/// 某件当前是否有覆写。
pub fn override_has(id : Int32) -> Bool {
  override_table.contains(id)
}

///|
/// 控件丢弃钩子的清理口（不重绘——件都没了）。
pub fn override_remove_for_drop(id : Int32) -> Unit {
  let _ = override_table.remove(id)
}

///|
/// 覆写并入（style_for 与 resolved_by_id 共用）：无覆写原样返回。
fn override_merge(id : Int32, st : Style) -> Style {
  match override_table.get(id) {
    Some(o) => merge(st, o)
    None => st
  }
}
