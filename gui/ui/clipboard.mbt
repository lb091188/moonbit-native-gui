// 系统剪贴板接线（W16）：默认**开**——输入框开箱即与系统剪贴板互通；探测不可用
// （Linux 没装 xclip 等）时自动保持内部剪贴板，属语义化降级。要隔离的场景
// （自动化测试不碰使用者剪贴板）在启动时 `use_system_clipboard(false)` 显式关。

///|
let g_sys_clipboard : Ref[Bool] = Ref(true)

///|
/// 打开/关闭「输入框的 Ctrl+C/X/V 接系统剪贴板」。只影响**此后新建**的
/// 输入框（已建好的保持原槽位，换槽留给需要显式重装的场景）。
pub fn use_system_clipboard(enable : Bool) -> Unit {
  g_sys_clipboard.val = enable
}

///|
/// 按开关与探测结果给内核装槽（input/textarea 构造时调；包内函数）。
fn attach_system_clipboard(ed : @input.Editor) -> Unit {
  if g_sys_clipboard.val && @sys.clipboard_available() {
    ed.set_clipboard(
      @sys.clipboard_get_text,
      fn(t) {
        let _ = @sys.clipboard_set_text(t)
      },
    )
  }
}

///|
/// 输入框内置编辑右键菜单：`can_edit` 给剪切/粘贴，`can_copy` 给复制（密码框
/// 不给复制），末项恒为全选；在指针处开自绘浮层，动作直调内核 Editor——系统槽
/// 在位即与系统剪贴板互通，改了文本经 `changed` 回写 Store。返回 true 表示
/// 右键已被菜单吃掉（祖先的 context_menu_for 先派发，包了自定义菜单时轮不到这里）。
fn show_edit_menu(
  w : @widget.Widget,
  x : Double,
  y : Double,
  ed : @input.Editor,
  can_edit? : Bool = true,
  can_copy? : Bool = true,
  changed? : () -> Unit = fn() -> Unit { @widget.invalidate() },
) -> Bool {
  let items : Array[(String, () -> Unit)] = []
  if can_edit {
    items.push((
      @i18n.t_or("gui.ui.edit.cut", "剪切"),
      fn() -> Unit {
        let _ = ed.cut()
        changed()
      },
    ))
  }
  if can_copy {
    items.push((
      @i18n.t_or("gui.ui.edit.copy", "复制"),
      fn() -> Unit { let _ = ed.copy() },
    ))
  }
  if can_edit {
    items.push((
      @i18n.t_or("gui.ui.edit.paste", "粘贴"),
      fn() -> Unit {
        let t = ed.clip_fetch()
        if t.length() > 0 {
          ed.paste_text(t)
          changed()
        }
      },
    ))
  }
  if items.length() > 0 {
    items.push(("-", fn() -> Unit { () }))
  }
  items.push((
    @i18n.t_or("gui.ui.edit.select_all", "全选"),
    fn() -> Unit {
      ed.select_all()
      @widget.invalidate()
    },
  ))
  let rows : Array[@widget.Node] = []
  for i = 0; i < items.length(); i = i + 1 {
    let it = items[i]
    rows.push(
      menu_row(it.0, fn() -> Unit {
        @widget.overlay_hide_top()
        (it.1)()
      }),
    )
  }
  let _ = @widget.overlay_show_at(
    overlay_pane(rows, 150.0, 0.0),
    w.rect.x + x,
    w.rect.y + y,
  )
  true
}
