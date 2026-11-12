// 可选中静态文本回归：四种指针交互、跨件互斥、宿主复制支、文本变化清选区、
// 缺省档一行不变。全程无头（内存位图 + 手工投递事件）。

///|
fn sel_click(
  root : @widget.Widget,
  x : Double,
  y : Double,
  mods~ : Int32 = 0,
  button~ : Int32 = 1,
) -> Unit {
  let _ = root.dispatch_pointer({
    kind: @widget.PointerKind::Down,
    x,
    y,
    button,
    mods,
  })
  let _ = root.dispatch_pointer({
    kind: @widget.PointerKind::Up,
    x,
    y,
    button,
    mods,
  })
}

///|
fn sel_down(root : @widget.Widget, x : Double, y : Double) -> Unit {
  let _ = root.dispatch_pointer({
    kind: @widget.PointerKind::Down,
    x,
    y,
    button: 1,
    mods: 0,
  })
}

///|
fn sel_move(root : @widget.Widget, x : Double, y : Double) -> Unit {
  let _ = root.dispatch_pointer({
    kind: @widget.PointerKind::Move,
    x,
    y,
    button: 1,
    mods: 0,
  })
}

///|
fn sel_up(root : @widget.Widget, x : Double, y : Double) -> Unit {
  let _ = root.dispatch_pointer({
    kind: @widget.PointerKind::Up,
    x,
    y,
    button: 1,
    mods: 0,
  })
}

///|
/// 挂一件 selectable 文本，返回 (根, 控件)。
fn mount_selectable(content : String) -> (@widget.Widget, @widget.Widget) {
  let root = mount_root(
    [text(content, selectable=true, wrap=false, font_size=13.0)],
    260.0,
    40.0,
  )
  (root, kid(root, 0))
}

///|
test "selectable 档：单击折叠定位、双击选词、拖选成段、Shift+点击扩展" {
  if !ui_text_guard() {
    return
  }
  use_system_clipboard(false)
  let (root, w) = mount_selectable("hello world")
  let st = match sel_states.val.get(w.id) {
    Some(s) => s
    None => abort("selectable 档没装起来")
  }
  let x0 = w.rect.x
  let ym = w.rect.y + w.rect.h / 2.0
  // 单击：无选区、caret 落在命中处（点行首即 0）
  sel_click(root, x0 + 1.0, ym)
  assert_true(st.ed.selection() is None)
  assert_eq(st.ed.caret_pos(), 0)
  // 双击：整词选中（hello = 字节 [0,5)）
  sel_click(root, x0 + 5.0, ym)
  sel_click(root, x0 + 6.0, ym)
  assert_eq(st.ed.selection(), Some((0, 5)))
  assert_eq(@widget.text_sel_owner(), w.id)
  // 拖选：从行首拖到行尾（无头投递按矩形命中派发，落点留在件内）
  let xe = x0 + w.rect.w - 2.0
  sel_down(root, x0 + 2.0, ym)
  sel_move(root, xe, ym)
  sel_up(root, xe, ym)
  match st.ed.selection() {
    Some((s, e)) => {
      assert_eq(s, 0)
      assert_true(e >= 8)
    }
    None => abort("拖选没成选区")
  }
  // Shift+点击：从 anchor 扩到命中点
  sel_down(root, x0 + 2.0, ym)
  sel_up(root, x0 + 2.0, ym)
  sel_click(root, xe, ym, mods=@base.MOD_SHIFT)
  match st.ed.selection() {
    Some((s, e)) => {
      assert_eq(s, 0)
      assert_true(e > 0)
    }
    None => abort("Shift+点击没扩选区")
  }
  // 复制：装了内部槽（测试关系统剪贴板），复制文本等于选区内容
  match st.ed.selection() {
    Some((s, e)) => {
      assert_true(@widget.text_sel_copy())
      assert_eq(st.ed.clip_text(), st.ed.get_text_in_range(s, e))
    }
    None => abort("复制前应有选区")
  }
  use_system_clipboard(true)
}

///|
test "selectable 档：跨件互斥——后来者起拖，前任让位即清选区" {
  if !ui_text_guard() {
    return
  }
  let root = mount_root(
    [
      text("第一段文字", selectable=true, wrap=false),
      text("第二段文字", selectable=true, wrap=false),
    ],
    260.0,
    90.0,
  )
  let a = kid(root, 0)
  let b = kid(root, 1)
  let sa = match sel_states.val.get(a.id) {
    Some(s) => s
    None => abort("第一件没装起来")
  }
  let sb = match sel_states.val.get(b.id) {
    Some(s) => s
    None => abort("第二件没装起来")
  }
  let ax = a.rect.x + a.rect.w - 2.0
  let ay = a.rect.y + a.rect.h / 2.0
  sel_down(root, a.rect.x + 2.0, ay)
  sel_move(root, ax, ay)
  sel_up(root, ax, ay)
  assert_eq(@widget.text_sel_owner(), a.id)
  assert_true(sa.ed.selection() is Some(_))
  // 换一件拖：owner 走，前一件的选区被清（两处不能同时亮）
  let bx = b.rect.x + b.rect.w - 2.0
  let by = b.rect.y + b.rect.h / 2.0
  sel_down(root, b.rect.x + 2.0, by)
  sel_move(root, bx, by)
  sel_up(root, bx, by)
  assert_eq(@widget.text_sel_owner(), b.id)
  assert_true(sb.ed.selection() is Some(_))
  assert_true(sa.ed.selection() is None)
}

///|
test "selectable 档：动态文本变了就清选区并让出持有" {
  if !ui_text_guard() {
    return
  }
  let sig = @base.Signal::new("可变的段落文字")
  let root = mount_root(
    [text_dyn(sig, selectable=true, wrap=false)],
    260.0,
    40.0,
  )
  let w = kid(root, 0)
  let st = match sel_states.val.get(w.id) {
    Some(s) => s
    None => abort("动态文本没装起来")
  }
  let wx = w.rect.x + w.rect.w - 2.0
  let wy = w.rect.y + w.rect.h / 2.0
  sel_down(root, w.rect.x + 2.0, wy)
  sel_move(root, wx, wy)
  sel_up(root, wx, wy)
  assert_true(st.ed.selection() is Some(_))
  sig.set("换了一段")
  assert_true(st.ed.selection() is None)
  assert_eq(@widget.text_sel_owner(), 0)
  assert_eq(st.ed.get_text(), "换了一段")
}

///|
test "缺省档一行不变：没挂指针、光标不是 I 梁、没有选中态" {
  let root = mount_root([text("普通标签", wrap=false)], 260.0, 40.0)
  let w = kid(root, 0)
  assert_true(w.on_pointer is None)
  assert_true(sel_states.val.get(w.id) is None)
}
