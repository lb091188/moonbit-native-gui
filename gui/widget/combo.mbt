// W32 组合键便捷 API：把 "Ctrl+Shift+S" 一类人可读字符串解析为 (mods, keysym)，
// 并提供 match_combo/ev_is_combo 判定 KeyEvent 是否命中。

///|
/// 解析组合键字符串为 (mods, keysym)；格式不合法返回 None。
/// `mac=true` 时 `CmdOrCtrl` 落 Cmd（`MOD_META`），否则落 Ctrl——词表与
/// `@win.parse_accelerator`（全局热键、菜单加速键）同一套：同一串 spec
/// 不该在窗口内与系统层有两个意思。修饰键的入乡随俗由调用方传平台读数
/// （`@shell.platform_is_macos()`）。
pub fn parse_combo(spec : String, mac? : Bool = false) -> (Int, Int)? {
  let parts = spec.split("+")
  let cleaned : Array[String] = []
  for p in parts {
    let s = p.trim()
    if s != "" {
      cleaned.push(s.to_owned())
    }
  }
  if cleaned.length() == 0 {
    return None
  }
  let mut mods = 0
  let mut key_part = ""
  for p in cleaned {
    let low = p.to_lower()
    // 词表与 `@win.parse_accelerator` 对齐；-1 = 不是修饰键，它就是主键
    let bit = match low {
      "ctrl" | "control" => @base.MOD_CTRL
      "alt" | "option" | "opt" => @base.MOD_ALT
      "shift" => @base.MOD_SHIFT
      "meta" | "super" | "win" | "cmd" | "command" => @base.MOD_META
      "cmdorctrl" | "cmdorctl" | "commandorcontrol" =>
        if mac { @base.MOD_META } else { @base.MOD_CTRL }
      _ => -1
    }
    if bit >= 0 {
      mods = mods | bit
    } else {
      key_part = low
    }
  }
  if key_part.length() == 0 {
    return None
  }
  let ks = keysym_of_name(key_part)
  if ks < 0 {
    None
  } else {
    Some((mods, ks))
  }
}

///|
/// 判定 KeyEvent 是否命中已解析的组合（按下 + mods + keysym 全等）。
pub fn match_combo(ev : KeyEvent, mods : Int, keysym : Int) -> Bool {
  ev.press && ev.mods == mods && ev.keysym == keysym
}

///|
/// 便捷：用组合键字符串判定 KeyEvent。解析失败不命中。
pub fn ev_is_combo(ev : KeyEvent, spec : String) -> Bool {
  match parse_combo(spec) {
    Some((m, k)) => match_combo(ev, m, k)
    None => false
  }
}

/// 键名 → keysym 值。控制键用 @base 常量，字母数字用 ASCII 码。
fn keysym_of_name(name : String) -> Int {
  match name {
    "backspace" | "bs" => @base.KS_BACKSPACE
    "tab" => @base.KS_TAB
    "space" => @base.KS_SPACE
    "return" | "enter" => @base.KS_RETURN
    "escape" | "esc" => @base.KS_ESCAPE
    "left" => @base.KS_LEFT
    "up" => @base.KS_UP
    "right" => @base.KS_RIGHT
    "down" => @base.KS_DOWN
    "home" => @base.KS_HOME
    "end" => @base.KS_END
    "delete" | "del" => @base.KS_DELETE
    _ => {
      if name.length() == 1 {
        let c = name[0]
        let v = c.to_int()
        // a-z (97-122) 和 0-9 (48-57) 直接当 keysym
        if (v >= 97 && v <= 122) || (v >= 48 && v <= 57) {
          v
        } else {
          -1
        }
      } else {
        -1
      }
    }
  }
}
