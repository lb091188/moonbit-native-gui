// 终端输入映射：KeyEvent → 终端字节串（纯函数，可无头测试）。
// 键位口径：Enter=\r、Backspace=\x7f、Tab=\t、Esc=\x1b、Shift+Tab=\x1b[Z；
// Ctrl+字母=控制字节（Ctrl+I/M/H 与 \t \r \x08 自然重合）；Ctrl+@/=+[ … 按惯例；
// 方向键/Home/End/Delete/Insert/PageUp/PageDown/F1..F12 走 CSI/SS3；
// Alt 修饰给一切输出前缀 ESC；mac 的 Cmd 不进输入（留给复制/粘贴等应用组合）。
// Shift+PageUp/Down 是控件级回看滚动，不经本函数（terminal_draw 截获）。

///|
/// @base 未提供的 keysym（XKC 页键/插入键族）。
const KS_PAGE_UP : Int = 65365
const KS_PAGE_DOWN : Int = 65366
const KS_INSERT : Int = 65379

///|
/// 终端剪贴板槽：默认系统剪贴板；`use_system_clipboard(false)`（自动化测试
/// 等隔离场景）时走内存槽，不碰使用者剪贴板。与输入框同一开关语义。
let term_clip_mem : Ref[String] = Ref("")

///|
fn terminal_clip_set(t : String) -> Bool {
  if g_sys_clipboard.val {
    @sys.clipboard_set_text(t)
  } else {
    term_clip_mem.val = t
    true
  }
}

///|
fn terminal_clip_get() -> String? {
  if g_sys_clipboard.val {
    @sys.clipboard_get_text()
  } else {
    Some(term_clip_mem.val)
  }
}

///|
/// 控制字节 → 单字符文本。
fn term_ctrl_byte(b : Int) -> String {
  match b.to_char() {
    Some(c) => c.to_string()
    None => ""
  }
}

///|
/// 按键 → 终端输入（None = 控件不消费，交回宿主路由）。
pub fn terminal_input_of(ev : @widget.KeyEvent, mac : Bool) -> String? {
  if !ev.press {
    return None
  }
  if mac && ev.mods.land(@base.MOD_META) != 0 {
    return None
  }
  let k = ev.keysym
  let alt = ev.mods.land(@base.MOD_ALT) != 0
  let prefix = if alt { "\u{1b}" } else { "" }
  // 特殊键表（Ctrl/Shift 不改变 v1 编码）
  let special : String? = match k {
      @base.KS_RETURN => Some("\r")
      @base.KS_BACKSPACE => Some("\u{7f}")
      @base.KS_TAB => Some("\t")
      @base.KS_ISO_LEFT_TAB => Some("\u{1b}[Z")
      @base.KS_ESCAPE => Some("\u{1b}")
      @base.KS_LEFT => Some("\u{1b}[D")
      @base.KS_UP => Some("\u{1b}[A")
      @base.KS_RIGHT => Some("\u{1b}[C")
      @base.KS_DOWN => Some("\u{1b}[B")
      @base.KS_HOME => Some("\u{1b}[H")
      @base.KS_END => Some("\u{1b}[F")
      @base.KS_DELETE => Some("\u{1b}[3~")
      KS_INSERT => Some("\u{1b}[2~")
      KS_PAGE_UP => Some("\u{1b}[5~")
      KS_PAGE_DOWN => Some("\u{1b}[6~")
      65470 => Some("\u{1b}OP") // F1
      65471 => Some("\u{1b}OQ") // F2
      65472 => Some("\u{1b}OR") // F3
      65473 => Some("\u{1b}OS") // F4
      65474 => Some("\u{1b}[15~") // F5
      65475 => Some("\u{1b}[17~") // F6
      65476 => Some("\u{1b}[18~") // F7
      65477 => Some("\u{1b}[19~") // F8
      65478 => Some("\u{1b}[20~") // F9
      65479 => Some("\u{1b}[21~") // F10
      65480 => Some("\u{1b}[23~") // F11
      65481 => Some("\u{1b}[24~") // F12
      _ => None
    }
  match special {
    Some(s) => return Some(prefix + s)
    None => ()
  }
  // Ctrl 组合 → 控制字节（字母大小写归一；标点按惯例表）
  if ev.mods.land(@base.MOD_CTRL) != 0 {
    let lk = if k >= 65 && k <= 90 { k + 32 } else { k }
    if lk >= 97 && lk <= 122 {
      return Some(term_ctrl_byte(lk.land(0x1f)))
    }
    let ctrl_punct : Int? = match k {
      64 => Some(0) // Ctrl+@
      32 => Some(0) // Ctrl+Space
      91 => Some(27) // Ctrl+[
      92 => Some(28) // Ctrl+\
      93 => Some(29) // Ctrl+]
      94 => Some(30) // Ctrl+^
      95 => Some(31) // Ctrl+_
      63 => Some(127) // Ctrl+?
      _ => None
    }
    match ctrl_punct {
      Some(b) => return Some(term_ctrl_byte(b))
      None => ()
    }
    // Ctrl + 不可映射键：不消费
    return None
  }
  // 可打印字符（keysym 即 Unicode 码点；代理区与控制区不产输入）
  if k >= 32 && k != 127 {
    match k.to_char() {
      Some(c) => return Some(prefix + c.to_string())
      None => ()
    }
  }
  None
}
