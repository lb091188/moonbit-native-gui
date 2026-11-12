// 键码与修饰位：与旧 @yue 的 GDK keysym 口径同源（yue/events.mbt 的表在旧包里，
// 本包不 import 它，避免把红包拖进新栈；值取 X11 keysym 常量）。

///|
pub const MOD_SHIFT : Int32 = 1

///|
pub const MOD_CTRL : Int32 = 2

///|
pub const MOD_ALT : Int32 = 4

///|
pub const MOD_META : Int32 = 8

///|
pub const KS_BACKSPACE : Int32 = 65288

///|
pub const KS_TAB : Int32 = 65289

///|
pub const KS_SPACE : Int32 = 32

///|
pub const KS_RETURN : Int32 = 65293

///|
pub const KS_ESCAPE : Int32 = 65307

///|
pub const KS_LEFT : Int32 = 65361

///|
pub const KS_UP : Int32 = 65362

///|
pub const KS_RIGHT : Int32 = 65363

///|
pub const KS_DOWN : Int32 = 65364

///|
pub const KS_HOME : Int32 = 65360

///|
pub const KS_END : Int32 = 65367

///|
pub const KS_DELETE : Int32 = 65535

///|
pub const KS_ISO_LEFT_TAB : Int32 = 65056

///|
/// 是否为可打印字符键（走文本提交路径，而不是编辑控制键）。
pub fn keysym_is_printable(ks : Int32) -> Bool {
  ks >= 32 && ks != 127 && ks < 65280
}
