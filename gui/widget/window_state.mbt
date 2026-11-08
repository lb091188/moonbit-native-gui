// 窗口状态记忆(A9):每应用一份小 JSON(位置/尺寸/最大化档),`WindowHost`
// 收口——开窗后一行 `win.remember_geometry("com.example.app")`:先把上次
// 的几何恢复到平台上,再把应用 id 记在本窗;关窗(`close_window`)与整体
// 退出(`shutdown`)时自动写回当前几何。
//
// 落盘位置按平台选「应用自有目录」:
//   macos   $HOME/Library/Application Support/<app_id>/
//   windows %APPDATA%/<app_id>/
//   linux   $XDG_STATE_HOME 或 $HOME/.local/state + /<app_id>/(XDG state:
//           会话相关、丢了不心疼的数据,正合几何记忆)
// 文件名 window-state.json。JSON 手拼手解(五字段,无依赖)。
//
// 边界(v1):恢复信任文件里的数值,不做屏幕边界钳位(换显示器/拔显示器
// 的怪位置属用户自己删文件解决;文件位置在文档写明);多窗应用对同一 id
// 只记一份——各窗想分别记,用不同的 id 后缀自己分开。

///|
/// 一份窗口几何(平台像素口径,与 `Window::origin`/`size` 同源)。
pub(all) struct WinGeom {
  x : Int
  y : Int
  w : Int
  h : Int
  maximized : Bool
}

///|
/// 拼 JSON(五字段固定序)。
pub fn wstate_text(g : WinGeom) -> String {
  "{ \"x\": \{g.x}, \"y\": \{g.y}, \"w\": \{g.w}, \"h\": \{g.h}, \"maximized\": \{g.maximized} }\n"
}

///|
/// 从 JSON 文本解五字段:键都在且值合法才给 Some(允许键序任意、容忍空白;
/// 其余内容一律拒——状态文件是本包自己写的,不必宽容)。
pub fn wstate_parse(text : String) -> WinGeom? {
  fn num_of(key : String) -> Int? {
    let i = find_quoted_key(text, key)
    if i < 0 {
      return None
    }
    let after = skip_ws_colon(text, i + key.length() + 2)
    if after < 0 {
      return None
    }
    parse_int_at(text, after)
  }
  let x = match num_of("x") {
    Some(v) => v
    None => return None
  }
  let y = match num_of("y") {
    Some(v) => v
    None => return None
  }
  let w = match num_of("w") {
    Some(v) => v
    None => return None
  }
  let h = match num_of("h") {
    Some(v) => v
    None => return None
  }
  let mi = find_quoted_key(text, "maximized")
  if mi < 0 {
    return None
  }
  let after = skip_ws_colon(text, mi + "maximized".length() + 2)
  if after < 0 {
    return None
  }
  let mut maximized = false
  if text.has_suffix("") && text.length() >= after + 4 && text[after:after + 4].to_owned() == "true" {
    maximized = true
  } else if text.length() >= after + 5 && text[after:after + 5].to_owned() == "false" {
    maximized = false
  } else {
    return None
  }
  if w <= 0 || h <= 0 {
    return None
  }
  Some({ x, y, w, h, maximized })
}

///|
/// 找 `"key"`(带引号)在文本里的下标;没有给 -1。
fn find_quoted_key(text : String, key : String) -> Int {
  let pat = "\"" + key + "\""
  let n = text.length()
  let m = pat.length()
  let mut i = 0
  while i + m <= n {
    if text[i:i + m].to_owned() == pat {
      return i
    }
    i += 1
  }
  -1
}

///|
/// 从 `at`(键尾引号之后)向后跳过空白与冒号,落在值首字符;越界给 -1。
fn skip_ws_colon(text : String, at : Int) -> Int {
  let n = text.length()
  let mut i = at
  while i < n {
    let c = text[i]
    if c == ' ' || c == '\t' || c == '\n' || c == '\r' {
      i += 1
      continue
    }
    if c == ':' {
      i += 1
      while i < n {
        let c2 = text[i]
        if c2 == ' ' || c2 == '\t' || c2 == '\n' || c2 == '\r' {
          i += 1
        } else {
          break
        }
      }
      return if i < n { i } else { -1 }
    }
    return -1
  }
  -1
}

///|
/// 从 `at` 起解析一个(可带负号的)十进制整数;没有数字给 None。
fn parse_int_at(text : String, at : Int) -> Int? {
  let n = text.length()
  let mut i = at
  let mut neg = false
  if i < n && text[i] == '-' {
    neg = true
    i += 1
  }
  let mut v = 0
  let mut seen = false
  while i < n {
    let c = text[i]
    if c >= '0' && c <= '9' {
      v = v * 10 + (c.to_int() - 48)
      seen = true
      i += 1
    } else {
      break
    }
  }
  if !seen {
    return None
  }
  // 本包格式只有整数:值后紧跟小数点即坏文件,拒收(否则 "1.5" 被截成 1)
  if i < n && text[i] == '.' {
    return None
  }
  Some(if neg { -v } else { v })
}

///|
/// 状态目录(应用 id 下的应用自有目录;拿不到环境给 None)。平台与目录
/// 基座拆出来是纯函数,白盒用例直接喂环境值。
pub fn wstate_dir(
  platform : String,
  home : String,
  appdata : String,
  xdg_state : String,
  app_id : String,
) -> String? {
  if app_id.length() == 0 {
    return None
  }
  match platform {
    "macos" =>
      if home.length() > 0 {
        Some(home + "/Library/Application Support/" + app_id)
      } else {
        None
      }
    "windows" =>
      if appdata.length() > 0 {
        Some(appdata + "\\" + app_id)
      } else {
        None
      }
    _ => {
      let base = if xdg_state.length() > 0 {
        xdg_state
      } else if home.length() > 0 {
        home + "/.local/state"
      } else {
        ""
      }
      if base.length() > 0 {
        Some(base + "/" + app_id)
      } else {
        None
      }
    }
  }
}

///|
/// 状态文件绝对路径(macos/windows 落到平台形态分隔符,linux 用斜杠)。
pub fn wstate_path(app_id : String) -> String? {
  let platform = match @sys.sys_platform() {
    "macos" => "macos"
    "windows" => "windows"
    p => p
  }
  let home = match @sys.sys_getenv("HOME") {
    Some(h) => h
    None => ""
  }
  let appdata = match @sys.sys_getenv("APPDATA") {
    Some(a) => a
    None => ""
  }
  let xdg = match @sys.sys_getenv("XDG_STATE_HOME") {
    Some(x) => x
    None => ""
  }
  match wstate_dir(platform, home, appdata, xdg, app_id) {
    Some(d) =>
      Some(if platform == "windows" {
        d + "\\window-state.json"
      } else {
        d + "/window-state.json"
      })
    None => None
  }
}

///|
/// 记窗:恢复上次几何 + 在关窗/退出时自动写回。
///
/// 恢复序:位置 → 尺寸 → 最大化(最后盖前两样;文件记的是最大化时的外框,
/// 先落再 maximize 与手动最大化轨迹一致)。文件不在/不合法就跳过恢复,
/// 只挂记忆——首次运行不动窗口。
pub fn WindowHost::remember_geometry(self : WindowHost, app_id : String) -> Unit {
  self.remember_id = app_id
  match wstate_path(app_id) {
    Some(p) =>
      match @sys.sys_read_text_file(p) {
        Some(t) =>
          match wstate_parse(t) {
            Some(g) => {
              self.session.window.move_to(g.x, g.y)
              self.session.window.set_size_pixels(g.w, g.h)
              if g.maximized {
                self.session.window.set_maximized(true)
              }
            }
            None => ()
          }
        None => ()
      }
    None => ()
  }
}

///|
/// 立即写回当前几何(正常关窗/退出会自动做;想在别的时机落盘就手动调)。
/// 没接 `remember_geometry` 的窗是空操作。
pub fn WindowHost::save_geometry(self : WindowHost) -> Unit {
  if self.remember_id.length() == 0 {
    return
  }
  match wstate_path(self.remember_id) {
    Some(p) => {
      let dir = {
        // 目录 = 文件路径去掉末段;两种分隔符都认
        let mut cut = -1
        let mut i = 0
        let n = p.length()
        while i < n {
          let c = p[i]
          if c == '/' || c == '\\' {
            cut = i
          }
          i += 1
        }
        if cut > 0 {
          p[:cut].to_owned()
        } else {
          "."
        }
      }
      if @sys.sys_make_dirs(dir) {
        let (x, y) = self.session.window.origin()
        let (w, h) = self.session.window.size()
        let g : WinGeom = {
          x,
          y,
          w,
          h,
          maximized: self.session.window.is_maximized(),
        }
        ignore(@sys.sys_write_text_file(p, wstate_text(g)))
      }
    }
    None => ()
  }
}
