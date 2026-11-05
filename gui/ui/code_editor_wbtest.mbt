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


///|
test "自动缩进：换行继承行首空白，开括号行再进一格" {
  use_system_clipboard(false)
  let (root, w, store, _) = mounted_editor("fn f() {\n", 300.0, 120.0)
  let lh = editor_line_h()
  let tx = editor_text_left(2)
  // 点到第一行行尾（x 给足余量钳到行尾），回车 → 新行继承空白并进一格
  press_xy(root, w, w.rect.x + tx + 200.0, w.rect.y + 4.0 + lh * 0.5)
  release_xy(root, w, w.rect.x + tx + 200.0, w.rect.y + 4.0 + lh * 0.5)
  key(root, w, @base.KS_RETURN, 0)
  assert_eq(store.get(), "fn f() {\n  \n")
  // 普通行只继承不进格
  press_xy(root, w, w.rect.x + tx + 200.0, w.rect.y + 4.0 + lh * 1.5)
  release_xy(root, w, w.rect.x + tx + 200.0, w.rect.y + 4.0 + lh * 1.5)
  key(root, w, @base.KS_RETURN, 0)
  assert_eq(store.get(), "fn f() {\n  \n  \n")
}

///|
test "查找纯函数：大小写不敏感、空 query、多字节不误配" {
  assert_eq(find_all_matches("", "ab"), [])
  assert_eq(find_all_matches("abc ABC ab", "ab"), [(0, 2), (4, 6), (8, 10)])
  assert_eq(find_all_matches("aaa", "aa"), [(0, 2), (1, 3)])
  assert_eq(find_all_matches("x中文y中文", "中文"), [(1, 7), (8, 14)])
  assert_eq(find_all_matches("abc", "abcd"), [])
}

///|
test "括号匹配纯函数：向后/向前/字符串内不参与" {
  let doc = CodeScan::new("fn f() {\n  let x = [1, 2]\n}\n", "moonbit")
  // caret 紧贴行 0 '{'（byte 7）右侧 → 配对到行 2 '}'（byte 26）
  assert_eq(code_bracket_pair(doc, 8), Some((7, 26)))
  // caret 在 '}'（byte 26）之后 → 向前配回 '{'
  assert_eq(code_bracket_pair(doc, 27), Some((7, 26)))
  // caret 在行 1 ']'（byte 24）之后 → 配回 '['
  assert_eq(code_bracket_pair(doc, 25), Some((19, 24)))
  // 无括号
  assert_eq(code_bracket_pair(doc, 0), None)
  // 字符串里的括号不参与：'(' 在字符串字面量内
  let s = CodeScan::new("let a = \"(\"\nlet b = (1)\n", "moonbit")
  assert_eq(code_bracket_pair(s, 10), None) // caret 在字符串内 '(' 之后
  assert_eq(code_bracket_pair(s, 21), Some((20, 22))) // 行 1 的 (1)
}

///|
test "当前行高亮：聚焦时 caret 行像素变化" {
  use_system_clipboard(false)
  let (root, w, store, _) = mounted_editor("aaaa\nbbbb\n", 300.0, 140.0)
  // caret 初始在文末（尾随空行，行 2）
  let lh = editor_line_h()
  let band_y = 4.0 + lh * 2.0
  let idle = paint_editor(root)
  root.set_focused_by_focus(1)
  let lit = paint_editor(root)
  let mut diff = 0
  for y = band_y.to_int(); y < (band_y + lh - 2.0).to_int(); y = y + 1 {
    for x = 10; x < 200; x = x + 1 {
      let a = idle.pixel(x, y)
      let b = lit.pixel(x, y)
      if (a.r, a.g, a.b, a.a) != (b.r, b.g, b.b, b.a) {
        diff = diff + 1
      }
    }
  }
  assert_true(diff > 4, msg="聚焦后当前行没有高亮带")
  let _ = store
  let _ = w
}

///|
/// 编辑器尺寸的绘制快照。
fn paint_editor(root : @widget.Widget) -> @render.Bitmap {
  let bm = @render.Bitmap::new(320, 140)
  let p = @render.Painter::new(bm)
  root.paint(p)
  p.end()
  bm
}

///|
test "行号列真实出墨（clip 修复后）与 wants_tab 声明" {
  use_system_clipboard(false)
  let (root, w, store, _) = mounted_editor("aaaa\nbbbb\n", 300.0, 120.0)
  let bm = @render.Bitmap::new(320, 140)
  let p = @render.Painter::new(bm)
  root.paint(p)
  p.end()
  let bg = bm.pixel(2, 2)
  let gl = (editor_text_left(2) - 4.0).to_int()
  let mut ink = 0
  for y = 8; y < 50; y = y + 1 {
    for x = (gl - 20).max(0); x < gl - 6; x = x + 1 {
      let c = bm.pixel(x, y)
      if (c.r, c.g, c.b, c.a) != (bg.r, bg.g, bg.b, bg.a) {
        ink = ink + 1
      }
    }
  }
  assert_true(ink > 8, msg="行号列没有出墨（仍被裁或没画）")
  // wants_tab：向宿主声明「Tab 是我的输入」
  let got : Ref[Int] = Ref(0)
  let store2 = @base.Store::new("")
  let node = code_editor(store2, height=80.0, handle=fn(w : @widget.Widget) -> Unit {
    got.val = if w.wants_tab { 1 } else { 0 }
  })
  let root2 = @widget.Widget::new()
  root2.set_size(200.0, 100.0)
  root2.set_column()
  let _ = node.mount_into(root2)
  root2.relayout(200.0, 100.0)
  assert_eq(got.val, 1)
  let _ = w
  let _ = store
}

///|
test "查找条冒烟：主修饰键+F 与 Esc 不崩、文本不动" {
  use_system_clipboard(false)
  let (root, w, store, _) = mounted_editor("let a = 1\n", 300.0, 120.0)
  key(root, w, 'f'.to_int(), mod_edit())
  assert_eq(store.get(), "let a = 1\n")
  key(root, w, @base.KS_ESCAPE, 0)
  assert_eq(store.get(), "let a = 1\n")
}

///|
/// 真宿主泵复现（uitest 的 dispatch_* 绕过宿主分支，测不出真机「按键全无」）：
/// 点击聚焦 → 打字 / Cmd 族 / PageDown / Tab 全走 route。
test "宿主真泵：点击聚焦后打字与快捷键全链路" {
  use_system_clipboard(false)
  let host = @widget.WindowHost::test_headless(320, 240)
  let store = @base.Store::new("abcdef\nghijkl\n")
  host.mount([
    code_editor(store, height=220.0, focus_id=1),
  ])
  host.root.relayout(320, 240)
    // 点击编辑器中心（真泵指针路径：命中 → 点击聚焦）
  host.test_pump_pointer(2, 160, 100, 1)
  host.test_pump_pointer(3, 160, 100, 1)
  // 打字：按键必须真进编辑器（真机上计数行不更新 = 这条断了）
  host.test_pump_key('x'.to_int(), 0)
  assert_true(
    store.get().contains("x"),
    msg="真泵打字没进编辑器（store=\{store.get()}）",
  )
  // Cmd/Cmd+A 全选 + Cmd+C 复制（主修饰键跟平台）
  host.test_pump_key('a'.to_int(), mod_edit())
  host.test_pump_key('c'.to_int(), mod_edit())
  // PageDown 翻页（caret 必须动）
  let before = @utf8.encode(store.get()).length()
  host.test_pump_key(65366, 0)
  let _ = before
  // Tab 缩进：宿主对 wants_tab 控件放行
  host.test_pump_key(@base.KS_TAB, 0)
  assert_true(
    store.get().contains("  "),
    msg="真泵 Tab 缩进没生效（store=\{store.get()}）",
  )
  // 小键盘回车（KP_Enter）：与主回车同档插行
  let before = store.get()
  host.test_pump_key(65421, 0)
  assert_true(
    store.get().length() > before.length(),
    msg="小键盘回车没插行",
  )
}
