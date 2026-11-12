// 静态文本的选区持有者（窗口级单 owner）。
//
// 展示件（`@ui.text` 的 selectable 档）自己不可聚焦、不进 Tab 链，键盘事件到不了
// 它们——所以「谁正持有选区」记在这份进程级登记里，宿主的 Ctrl/Cmd+C 支读它执行复制，
// 与 `drag_hover()` 同一形态（绘制/按键方读一个 id 自判，不用 enter/update/leave 三个回调）。
//
// 三条口径：
// - **单 owner 互斥**：后来者起拖即覆盖前任，覆盖时调前任的 `clear`（选区不会两处同时亮）；
//   编辑件（input/textarea）不进这里——焦点唯一性已保证同时只有一个编辑选区。
// - **thunk 不捕 Widget**：`copy`/`clear` 只准捕那件自己的 `Editor`（回调禁捕铁律，
//   见 `widget.mbt` 的字段注释），控件摘除后 thunk 仍安全。
// - **陈旧无害**：owner 对应的控件已不在树上时，最多复制出一份旧文本，不会崩；
//   折叠为空选区时由持有者自己 `release`。

///|
priv struct TextSelOwner {
  mut id : Int32
  mut copy : (() -> Unit)?
  mut clear : (() -> Unit)?
}

///|
let g_text_sel : TextSelOwner = { id: 0, copy: None, clear: None, }

///|
/// 当前持有选区的控件 id（0 = 没有）。绘制方用它判「是不是我」：
/// `@widget.text_sel_owner() == self.id`。
pub fn text_sel_owner() -> Int32 {
  g_text_sel.id
}

///|
/// 认领选区：把 `id` 登记为当前持有者。已有别的持有者时先调它的 `clear`
/// （前任让位即清自己的选区），再覆盖登记。`copy` 执行复制、`clear` 清选区。
pub fn text_sel_claim(
  id : Int32,
  copy : () -> Unit,
  clear : () -> Unit,
) -> Unit {
  if g_text_sel.id != 0 && g_text_sel.id != id {
    match g_text_sel.clear {
      Some(f) => f()
      None => ()
    }
  }
  g_text_sel.id = id
  g_text_sel.copy = Some(copy)
  g_text_sel.clear = Some(clear)
}

///|
/// 释放登记（仅当登记的确实是它）：选区折叠为空、或控件重挂时用。
pub fn text_sel_release(id : Int32) -> Unit {
  if g_text_sel.id == id {
    g_text_sel.id = 0
    g_text_sel.copy = None
    g_text_sel.clear = None
  }
}

///|
/// 宿主的复制支：有持有者就调它的 `copy`，执行了给 true（调用方据此把按键算已消费）。
pub fn text_sel_copy() -> Bool {
  if g_text_sel.id == 0 {
    return false
  }
  match g_text_sel.copy {
    Some(f) => {
      f()
      true
    }
    None => false
  }
}
