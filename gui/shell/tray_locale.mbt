// 托盘的原生文案（提示语 / 右键菜单）随语言广播重算：登记取串函数，
// 换目录时按登记序重算并写回原生侧。与 `@widget.set_menu_bar_localized`
// 是同一条 `@i18n.on_locale_change` 链，调用方只在建托盘时登记一次。

///|
/// 一个托盘的语言口：提示语与右键菜单各一条重算闭包（None = 不走本通道）。
priv struct LocaleSurface {
  mut tip : (() -> Unit)?
  mut menu : (() -> Unit)?
}

///|
/// 登记号 → 语言口；登记号存在 `TrayState.locale_key` 里，随 `Tray::remove` 撤下。
let locale_surfaces : Map[Int, LocaleSurface] = Map([])

let locale_seq : Ref[Int] = Ref(0)

let locale_hook : Ref[Int] = Ref(0)

///|
/// 广播回调：按登记序把每个在册托盘的两条口各算一遍。
fn locale_refresh_all() -> Unit {
  let keys : Array[Int] = []
  for (k, _s) in locale_surfaces {
    keys.push(k)
  }
  keys.sort()
  for k in keys {
    match locale_surfaces.get(k) {
      None => ()
      Some(s) => {
        match s.tip {
          Some(f) => f()
          None => ()
        }
        match s.menu {
          Some(f) => f()
          None => ()
        }
      }
    }
  }
}

///|
/// 第一次用到才订阅广播（订阅号进程级复用）。
fn locale_ensure_hook() -> Unit {
  if locale_hook.val == 0 {
    locale_hook.val = @i18n.on_locale_change(fn(_l : String) -> Unit {
      locale_refresh_all()
    })
  }
}

///|
/// 取（必要时新建）本托盘的语言口。
fn Tray::locale_surface_of(self : Tray) -> LocaleSurface {
  if self.state.locale_key == 0 {
    locale_seq.val += 1
    self.state.locale_key = locale_seq.val
  }
  match locale_surfaces.get(self.state.locale_key) {
    Some(s) => s
    None => {
      let s = { tip: None, menu: None }
      locale_surfaces.set(self.state.locale_key, s)
      s
    }
  }
}

fn locale_run(slot : (() -> Unit)?) -> Unit {
  match slot {
    Some(f) => f()
    None => ()
  }
}

///|
/// 提示语随语言重算：登记即算一次并写进原生托盘，此后每次换目录再算一次。
/// 取串函数在广播那一刻求值，读到的已是换好的目录；`body_of` 里读 Store 也能
/// 顺带把计数类动态文案刷新。重复登记替换旧函数。
pub fn Tray::set_tooltip_localized(
  self : Tray,
  title_of : () -> String,
  body_of : () -> String,
) -> Unit {
  let s = self.locale_surface_of()
  s.tip = Some(fn() { self.apply_tooltip(title_of(), body_of()) })
  locale_ensure_hook()
  locale_run(s.tip)
}

///|
/// 右键菜单随语言重算：登记即建一次并挂上，此后每次换目录重建再挂——
/// 菜单项与回调都来自新的 `build()`，旧菜单整体替换。
pub fn Tray::set_menu_localized(self : Tray, build : () -> Menu) -> Unit {
  let s = self.locale_surface_of()
  s.menu = Some(fn() { self.apply_menu(build()) })
  locale_ensure_hook()
  locale_run(s.menu)
}

///|
/// 撤下本托盘的全部语言口（`Tray::remove` 自动调）。
pub fn Tray::drop_locale_surface(self : Tray) -> Unit {
  if self.state.locale_key != 0 {
    let _ = locale_surfaces.remove(self.state.locale_key)
    self.state.locale_key = 0
  }
}

///|
/// 普通写入口生效即停掉对应的重算口：以最后一次写法为准。
fn Tray::clear_locale_tip(self : Tray) -> Unit {
  match locale_surfaces.get(self.state.locale_key) {
    Some(s) => s.tip = None
    None => ()
  }
}

fn Tray::clear_locale_menu(self : Tray) -> Unit {
  match locale_surfaces.get(self.state.locale_key) {
    Some(s) => s.menu = None
    None => ()
  }
}
