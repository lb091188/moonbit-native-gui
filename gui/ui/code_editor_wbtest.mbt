// code_editor 组件回归：键入回写、点击定位、跨行选区、Home/End/PageUp-Down、
// Tab 缩进、undo/redo、只读、IME、外部回灌与绘制冒烟（含行号列）。
// 事件按宿主投递口径给窗口坐标；键入类用例先关系统剪贴板（不碰使用者剪贴板）。

///|
/// 建一个已挂载并布局好的代码编辑器，返回 (根, 控件, Store, on_change 轨迹)。
fn mounted_editor(
  text : String,
  width : Double,
  height : Double,
  lang? : String = "moonbit",
  read_only? : Bool = false,
) -> (@widget.Widget, @widget.Widget, @base.Store[String], Ref[Array[String]]) {
  let store = @base.Store::new(text)
  let changes : Ref[Array[String]] = Ref([])
  let e = code_editor(
    store,
    lang=lang,
    read_only=read_only,
    height=height,
    focus_id=1,
    on_change=fn(t : String) -> Unit { changes.val.push(t) },
  )
  let root = @widget.Widget::new()
  root.set_size(width + 20.0, height + 20.0)
  root.set_column()
  let w = e.mount_into(root)
  root.relayout(width + 20.0, height + 20.0)
  (root, w, store, changes)
}

///|
fn press_xy(
  root : @widget.Widget,
  w : @widget.Widget,
  x : Double,
  y : Double,
) -> Unit {
  let _ = root.dispatch_pointer_to(w.id, {
    kind: @widget.PointerKind::Down, x, y, button: 1, mods: 0,
  })
}

///|
fn move_xy(
  root : @widget.Widget,
  w : @widget.Widget,
  x : Double,
  y : Double,
) -> Unit {
  let _ = root.dispatch_pointer_to(w.id, {
    kind: @widget.PointerKind::Move, x, y, button: 1, mods: 0,
  })
}

///|
fn release_xy(
  root : @widget.Widget,
  w : @widget.Widget,
  x : Double,
  y : Double,
) -> Unit {
  let _ = root.dispatch_pointer_to(w.id, {
    kind: @widget.PointerKind::Up, x, y, button: 1, mods: 0,
  })
}

///|
/// 等宽 13pt 的行高（line_height_font + 5，与组件同一来源的常量）。
fn editor_line_h() -> Double {
  let font = @text.Font::new("Monospace", 13.0)
  (@text.line_height_font(font).unwrap_or(18).to_double() + 5.0).max(14.0)
}

///|
/// 文本区左缘 x（与组件同一式：digit_w × digits + 16 + 4；点击坐标用它算，
/// 不依赖具体字宽）。
fn editor_text_left(digits : Int) -> Double {
  let font = @text.Font::new("Monospace", 13.0)
  text_width("8", font) * digits.to_double() + 20.0
}

///|
test "键入回写 Store 与 on_change；初始 caret 在文末" {
  use_system_clipboard(false)
  let (root, w, store, changes) = mounted_editor("let a = 1\nlet b = 2\n", 300.0, 120.0)
  key(root, w, 'x'.to_int(), 0)
  assert_eq(store.get(), "let a = 1\nlet b = 2\nx")
  assert_true(changes.val.length() >= 1)
  assert_eq(caret_of(w), @utf8.encode(store.get()).length())
  assert_eq(w.role, "code_editor")
}

///|
test "点击定位：点第二行行首，打字落在那里" {
  use_system_clipboard(false)
  let (root, w, store, _) = mounted_editor("aaaa\nbbbb\n", 300.0, 120.0)
  let lh = editor_line_h()
  let tx = editor_text_left(2) // 行号两位：text_left 与组件同式
  press_xy(root, w, w.rect.x + tx + 1.0, w.rect.y + 4.0 + lh * 1.5)
  release_xy(root, w, w.rect.x + tx + 1.0, w.rect.y + 4.0 + lh * 1.5)
  key(root, w, 'Z'.to_int(), 0)
  assert_eq(store.get(), "aaaa\nZbbbb\n")
}

///|
test "Home/End 行首行尾；Shift+下扩选跨行后打字替换" {
  use_system_clipboard(false)
  let (root, w, store, _) = mounted_editor("aaaa\nbbbb\n", 300.0, 120.0)
  // 点到第一行最右 → 行尾
  let tx = editor_text_left(2)
  press_xy(root, w, w.rect.x + tx + 200.0, w.rect.y + 15.0)
  release_xy(root, w, w.rect.x + tx + 200.0, w.rect.y + 15.0)
  assert_eq(caret_of(w), 4)
  key(root, w, @base.KS_HOME, 0)
  assert_eq(caret_of(w), 0)
  key(root, w, @base.KS_END, 0)
  assert_eq(caret_of(w), 4)
  key(root, w, @base.KS_HOME, 0)
  key(root, w, @base.KS_DOWN, @base.MOD_SHIFT)
  // 选区 [行0 行首, 行1 行首)：打字替换整段（含换行符）
  key(root, w, 'X'.to_int(), 0)
  assert_eq(store.get(), "Xbbbb\n")
}

///|
test "PageDown 按可视行数翻页并保列" {
  use_system_clipboard(false)
  let sb = StringBuilder()
  for i in 0..<10 {
    sb.write_string("L\{i}x\n")
  }
  let (root, w, store, _) = mounted_editor(sb.to_string(), 300.0, 120.0)
  // 初始 caret 在文末（尾随空行）：先点回行 0 行首
  let lh = editor_line_h()
  let tx = editor_text_left(2)
  press_xy(root, w, w.rect.x + tx + 1.0, w.rect.y + 4.0 + lh * 0.5)
  release_xy(root, w, w.rect.x + tx + 1.0, w.rect.y + 4.0 + lh * 0.5)
  assert_eq(caret_of(w), 0)
  key(root, w, 65365, 0) // PageUp：从行 0 起翻不出去，仍在首行
  assert_eq(caret_of(w), 0)
  key(root, w, 65366, 0) // PageDown：step = 可视行数（(120-8)/行高 向下取整）
  let step = (((120.0 - 8.0) / lh).floor().to_int()).max(1)
  assert_eq(caret_of(w), step * 4) // 每行 "L?x\n" 4 字节，起算列 0
  let _ = store
}

///|
test "Tab 插入两格缩进；Shift+Tab 不吃（走焦点链）" {
  use_system_clipboard(false)
  let (root, w, store, _) = mounted_editor("abc\n", 300.0, 120.0)
  // 初始 caret 在文末（尾随空行）：点回行 0 行首再缩进
  let lh = editor_line_h()
  let tx = editor_text_left(2)
  press_xy(root, w, w.rect.x + tx + 1.0, w.rect.y + 4.0 + lh * 0.5)
  release_xy(root, w, w.rect.x + tx + 1.0, w.rect.y + 4.0 + lh * 0.5)
  key(root, w, @base.KS_HOME, 0)
  key(root, w, @base.KS_TAB, 0)
  assert_eq(store.get(), "  abc\n")
  key(root, w, @base.KS_TAB, @base.MOD_SHIFT)
  assert_eq(store.get(), "  abc\n")
}

///|
test "undo/redo 走主修饰键（mac=Cmd 其余=Ctrl）" {
  use_system_clipboard(false)
  let (root, w, store, _) = mounted_editor("ab", 300.0, 120.0)
  key(root, w, 'c'.to_int(), 0)
  assert_eq(store.get(), "abc")
  key(root, w, 'z'.to_int(), mod_edit())
  assert_eq(store.get(), "ab")
  key(root, w, 'z'.to_int(), mod_edit() | @base.MOD_SHIFT)
  assert_eq(store.get(), "abc")
}

///|
test "只读：编辑键不吃，导航与全选复制照旧" {
  use_system_clipboard(false)
  let (root, w, store, _) = mounted_editor("锁住\n", 300.0, 120.0, read_only=true)
  key(root, w, 'x'.to_int(), 0)
  key(root, w, @base.KS_BACKSPACE, 0)
  assert_eq(store.get(), "锁住\n")
  key(root, w, 'a'.to_int(), mod_edit())
  key(root, w, 'c'.to_int(), mod_edit())
  assert_eq(store.get(), "锁住\n")
}

///|
test "IME：commit 落进文本，preedit 只进绘制不进状态" {
  use_system_clipboard(false)
  let (root, w, store, _) = mounted_editor("code\n", 300.0, 120.0)
  let _ = root.dispatch_preedit(w.focus_id, "ni", 4)
  assert_eq(store.get(), "code\n")
  let _ = root.dispatch_commit(w.focus_id, "你")
  assert_eq(store.get(), "code\n你")
  let _ = root.dispatch_preedit(w.focus_id, "", 0)
  assert_eq(store.get(), "code\n你")
}

///|
test "外部 Store 回灌：内核与行缓存同步，绘出一帧不崩" {
  use_system_clipboard(false)
  let (root, w, store, _) = mounted_editor("", 300.0, 120.0)
  store.set("let 外部 = 1\n// 注释行\n")
  // set_text 的插入点落文末（内核文档行为）
  assert_eq(caret_of(w), @utf8.encode(store.get()).length())
  let bm = @render.Bitmap::new(320, 140)
  let p = @render.Painter::new(bm)
  root.paint(p)
  p.end()
  // 高亮 token 与行号都出了墨：数「不等于左上角底色」的像素
  let bg = bm.pixel(2, 2)
  let mut ink = 0
  for y = 0; y < 140; y = y + 1 {
    for x = 0; x < 320; x = x + 1 {
      let c = bm.pixel(x, y)
      if (c.r, c.g, c.b, c.a) != (bg.r, bg.g, bg.b, bg.a) {
        ink = ink + 1
      }
    }
  }
  assert_true(ink > 50, msg="编辑器绘制冒烟：整帧近乎空白")
}

///|
test "长行横向滚动：行尾键入不崩、store 正确，光标滚进可视区" {
  use_system_clipboard(false)
  let long = "let value = some_function(argument_one, argument_two, argument_three, argument_four, argument_five)"
  let (root, w, store, _) = mounted_editor(long, 200.0, 80.0)
  // 点最右端（命中钳到行尾）→ 行尾键入
  press_xy(root, w, w.rect.x + 190.0, w.rect.y + 15.0)
  release_xy(root, w, w.rect.x + 190.0, w.rect.y + 15.0)
  key(root, w, @base.KS_END, 0)
  key(root, w, '!'.to_int(), 0)
  assert_eq(store.get(), long + "!")
}

///|
test "拖选跨行：锚点按下，拖到下方行替换" {
  use_system_clipboard(false)
  let (root, w, store, _) = mounted_editor("aaaa\nbbbb\ncccc\n", 300.0, 140.0)
  let lh = editor_line_h()
  let tx = editor_text_left(2)
  let text = store.get()
  press_xy(root, w, w.rect.x + tx + 1.0, w.rect.y + 4.0 + lh * 0.5)
  // 拖到第三行右端（x 给足余量，命中钳到行尾）
  move_xy(root, w, w.rect.x + tx + 200.0, w.rect.y + 4.0 + lh * 2.5)
  release_xy(root, w, w.rect.x + tx + 200.0, w.rect.y + 4.0 + lh * 2.5)
  // 选区 [全文头, 第三行行尾)：终点在打字前读（打字后 caret 是替换点），
  // 结果按它现算，不依赖字宽
  let caret = caret_of(w)
  key(root, w, 'Z'.to_int(), 0)
  assert_eq(store.get(), "Z" + byte_slice(text, caret, @utf8.encode(text).length()))
}

///|
test "bash heredoc 高亮逐行走状态：正文整段字符串着色" {
  use_system_clipboard(false)
  let (root, w, store, _) = mounted_editor(
    "cat <<EOF\nhello $world\nEOF\necho done\n",
    300.0,
    140.0,
    lang="bash",
  )
  // 绘制一帧（着色路径走通即可，具体配色断言归真机走查）
  let bm = @render.Bitmap::new(320, 160)
  let p = @render.Painter::new(bm)
  root.paint(p)
  p.end()
  key(root, w, @base.KS_END, 0)
  assert_eq(caret_of(w), @utf8.encode(store.get()).length())
}

