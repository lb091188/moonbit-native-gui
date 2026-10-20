// 系统能力探测页（第 15 页）：只读探针分组展示——系统与桌面 / 显示器 /
// 应用与文件 / 浏览器数据 / 剪贴板与桌面状态。每段带「重新探测」重读本组；
// 能力不在位或读不到的族给「读不到：原因」降级行，不静默吞（探测 + 语义化
// 降级口径）。设置类能力（写自启、改音量等）在「系统集成」页，本页只读。
//
// **本页只列三平台都有对应面的族**：两平台概念（窗口列表、电源计划、最近文件、
// 夜灯）与 Linux 总线族（D-Bus 会话/系统总线、通知能力、MPRIS）不进这块板，
// 库里的 API 与 `@sys` 文档照旧保留——演示板的作用是「跨平台契约长什么样」，
// 摆一排「本平台不支持」反而把它读成契约的一部分。

///|
/// 秒 → 人读时长（天/时/分）。
fn sp_uptime(secs : Double) -> String {
  let total = secs.to_int()
  let d = total / 86400
  let h = (total % 86400) / 3600
  let m = (total % 3600) / 60
  if d > 0 {
    "\{d} 天 \{h} 时 \{m} 分"
  } else if h > 0 {
    "\{h} 时 \{m} 分"
  } else {
    "\{m} 分"
  }
}

///|
/// kB → GB（四舍五入到整数位）。
fn sp_gb(kb : Int) -> String {
  (kb.to_double() / 1024.0 / 1024.0).round().to_int().to_string() + " GB"
}

///|
/// 按码点截断到前 n 个字符（超出补省略号）。
fn sp_clip(s : String, n : Int) -> String {
  if s.length() <= n {
    return s
  }
  let buf = StringBuilder()
  let mut i = 0
  for ch in s {
    if i >= n {
      break
    }
    buf.write_char(ch)
    i = i + 1
  }
  buf.write_string("…")
  buf.to_string()
}

///|
/// 探针面板：标题 + 多行读数（Err 一律落成可读行，不影响其余部分）。
fn sp_panel(
  title : String,
  body : @base.Signal[String],
  width : Double,
) -> @widget.Node {
  @ui.view(
    [
      @ui.text(title, font_size=13.0, weight=@text.SemiBold),
      @ui.text_dyn(body, font_size=12.0, wrap=true, max_width=width - 24.0),
    ],
    width=width,
    row_gap=4.0,
    padding=10.0,
    align_items=@yoga.AlignItems::FlexStart,
    background_color="bg_panel",
    border_color="border",
  )
}

///|
/// 一段探测组：段头「重新探测」按钮 + 若干并排面板（每块绑一个 Store）。
/// 面板数量随「三平台都有对应面」的口径变，不固定两块。
fn sp_group(
  btn_label : String,
  panels : Array[(@base.Store[String], String, () -> String)],
) -> Array[@widget.Node] {
  let refresh = fn() -> Unit {
    for cell in panels {
      cell.0.set((cell.2)())
    }
  }
  refresh()
  let boxes : Array[@widget.Node] = []
  for cell in panels {
    boxes.push(sp_panel(cell.1, cell.0.signal(), 460.0))
  }
  [
    @ui.row(
      [
        @ui.button(btn_label, variant=@ui.Solid, on_click=fn() { refresh() }),
        @ui.text(@shared.tx("读数因机而异；读不到的族显示原因，不影响其余部分。"), role=@ui.Secondary),
      ],
      column_gap=10.0,
      align_items=@yoga.AlignItems::Center,
    ),
    @ui.row(
      boxes,
      column_gap=10.0,
      align_items=@yoga.AlignItems::FlexStart,
    ),
  ]
}

///|
/// 系统与机器：发行版 / 机器 / 内存 / 开机时长 / 桌面环境。
fn sp_sys_machine() -> String {
  let buf = StringBuilder()
  match @sys.si_os() {
    Ok(o) =>
      buf.write_string("发行版: \{o.pretty_name}（id \{o.id}，版本 \{o.version_id}）\n")
    Err(e) => buf.write_string("发行版: 读不到：\{e}\n")
  }
  match @sys.si_machine() {
    Ok(m) =>
      buf.write_string("机器: \{sp_clip(m.vendor + " " + m.product, 50)}（序列号 \{sp_clip(m.serial, 24)}）\n")
    Err(e) => buf.write_string("机器: 读不到：\{e}\n")
  }
  match @sys.si_memory() {
    Ok(mem) =>
      buf.write_string("内存: 共 \{sp_gb(mem.total_kb)}，可用 \{sp_gb(mem.available_kb)}\n")
    Err(e) => buf.write_string("内存: 读不到：\{e}\n")
  }
  match @sys.si_uptime() {
    Ok(secs) => buf.write_string("开机时长: \{sp_uptime(secs)}\n")
    Err(e) => buf.write_string("开机时长: 读不到：\{e}\n")
  }
  buf.write_string("桌面环境: \{@sys.desktop_name()}（\{@sys.sys_platform()}）\n")
  buf.to_string()
}

///|
/// 桌面与外设：环境变量 / 壁纸 / 打印机。夜灯不列——macOS 的 Night Shift 无
/// 公开口（CoreBrightness 是私有框架）、Windows 的夜间光线存在 CloudStore
/// blob 里，只有 Linux 有 redshift/gamma 对位，属两平台概念。
fn sp_sys_desktop() -> String {
  let buf = StringBuilder()
  let envs = @sys.envx_common()
  buf.write_string("常用环境变量: \{envs.length()} 项\n")
  for k, v in envs.iter2() {
    buf.write_string("  \{k} = \{sp_clip(v, 48)}\n")
  }
  match @sys.wp_get() {
    Ok(path) => buf.write_string("壁纸: \{sp_clip(path, 56)}\n")
    Err(e) => buf.write_string("壁纸: 读不到：\{e}\n")
  }
  if @sys.prt_supported() {
    match @sys.prt_list() {
      Ok(ps) => {
        buf.write_string("打印机: \{ps.length()} 台\n")
        for p in ps {
          let ok = if @sys.prt_status_available(p.status) { @shared.tx("可用") } else { @shared.tx("不可用") }
          buf.write_string("  \{sp_clip(p.name, 40)} [\{ok}]\n")
        }
      }
      Err(e) => buf.write_string("打印机列表: 读不到：\{e}\n")
    }
    match @sys.prt_default() {
      Ok(d) => buf.write_string("默认打印机: \{sp_clip(d, 40)}\n")
      Err(_) => buf.write_string("默认打印机: 未设置\n")
    }
  } else {
    buf.write_string("打印机: 本机取不到列表（无 CUPS / winspool）\n")
  }
  buf.to_string()
}

///|
/// 显示器：在用模式 + 全部输出与模式数。
fn sp_monitors() -> String {
  let buf = StringBuilder()
  match @sys.mon_current() {
    Ok(outs) => {
      buf.write_string("在用模式: \{outs.length()} 个\n")
      for o in outs {
        buf.write_string(
          "  \{o.name}: \{o.width}x\{o.height} @ \{o.refresh_centi / 100}.\{o.refresh_centi % 100}Hz 位置 +\{o.pos_x}+\{o.pos_y}\n",
        )
      }
    }
    Err(e) => buf.write_string("在用模式: 读不到：\{e}\n")
  }
  buf.write_string("\n")
  match @sys.mon_list() {
    Ok(mons) => {
      buf.write_string("全部输出: \{mons.length()} 个\n")
      for m in mons {
        let conn = if m.connected { @shared.tx("已连接") } else { @shared.tx("未连接") }
        let prim = if m.primary { @shared.tx("主输出") } else { @shared.tx("非主输出") }
        buf.write_string("  \{m.name}: \{conn} \{prim}，支持模式 \{m.modes.length()} 种\n")
      }
    }
    Err(e) => buf.write_string("全部输出: 读不到：\{e}\n")
  }
  buf.to_string()
}

///|
/// 已装应用：桌面项统计 + 常见二进制查找。
fn sp_apps() -> String {
  let buf = StringBuilder()
  match @sys.appfind_installed() {
    Ok(list) => {
      let first : Array[String] = []
      for i = 0; i < list.length(); i = i + 1 {
        if i >= 4 {
          break
        }
        first.push(list[i].name)
      }
      buf.write_string("已装应用: \{list.length()} 个，例如 \{first.join("、")}\n")
    }
    Err(e) => buf.write_string("已装应用: 读不到：\{e}\n")
  }
  buf.write_string("二进制查找:\n")
  for name in ["sh", "firefox", "code", "google-chrome"] {
    match @sys.appfind_executable(name) {
      Ok(p) => buf.write_string("  \{name} → \{sp_clip(p, 52)}\n")
      Err(_) => buf.write_string("  \{name} → 未找到\n")
    }
  }
  buf.to_string()
}

///|
/// VS Code 最近工作区。「最近文件」不列：Linux 读 recently-used.xbel、Windows
/// 读 Recent 目录环，macOS 没有可直接读的对应面（`RfUnsupported`），属两平台概念。
fn sp_recent() -> String {
  let buf = StringBuilder()
  if @sys.vsc_supported() {
    match @sys.vsc_recent() {
      Ok(paths) => {
        buf.write_string("VS Code 最近工作区: \{paths.length()} 条（列前 6）\n")
        let n = if paths.length() > 6 { 6 } else { paths.length() }
        for i = 0; i < n; i = i + 1 {
          buf.write_string("  \{sp_clip(paths[i], 56)}\n")
        }
      }
      Err(e) => buf.write_string("VS Code 最近工作区: 读不到：\{e}\n")
    }
  } else {
    buf.write_string("VS Code: 本机无用户数据目录\n")
  }
  buf.to_string()
}

///|
/// 浏览器历史与下载（Chromium 系）。
fn sp_browser_hist() -> String {
  let buf = StringBuilder()
  match @sys.bh_browsers() {
    Ok(profiles) => {
      buf.write_string("浏览器 profile: \{profiles.length()} 个有 History 库\n")
      match @sys.bh_history(limit=6) {
        Ok(items) => {
          buf.write_string("历史样本: \{items.length()} 条（列前 6）\n")
          for it in items {
            let title = if it.title == "" { @shared.tx("(无标题)") } else { it.title }
            buf.write_string("  [\{it.visit_count}次] \{sp_clip(title, 34)}\n")
          }
        }
        Err(e) => buf.write_string("历史样本: 读不到：\{e}\n")
      }
      match @sys.bh_downloads(limit=3) {
        Ok(list) => {
          buf.write_string("下载样本: \{list.length()} 条\n")
          for d in list {
            buf.write_string(
              "  \{sp_clip(d.target_path, 44)} \{d.received_bytes}/\{d.total_bytes} 字节 \{@sys.bh_download_state_name(d.state)}\n",
            )
          }
        }
        Err(e) => buf.write_string("下载样本: 读不到：\{e}\n")
      }
    }
    Err(e) => buf.write_string("浏览器历史: 读不到：\{e}\n")
  }
  buf.to_string()
}

///|
/// 书签与 Firefox 历史。
fn sp_bookmarks() -> String {
  let buf = StringBuilder()
  match @sys.bm_browsers() {
    Ok(profs) => {
      if profs.is_empty() {
        buf.write_string("书签: 未发现任何浏览器 profile\n")
      }
      for p in profs {
        buf.write_string("书签源: \{p.browser} / \{p.profile}\n")
      }
      if profs.length() > 0 {
        match @sys.bm_bookmarks(profs[0].browser) {
          Ok(root) => {
            let flats = @sys.bm_flatten(root)
            buf.write_string("书签树: \{flats.length()} 条（列前 6）\n")
            let n = if flats.length() > 6 { 6 } else { flats.length() }
            for i = 0; i < n; i = i + 1 {
              let b = flats[i]
              match b.url {
                Some(u) =>
                  buf.write_string("  \{sp_clip(b.name, 26)}: \{sp_clip(u, 44)}\n")
                None => ()
              }
            }
          }
          Err(e) => buf.write_string("书签树: 读不到：\{e}\n")
        }
      }
    }
    Err(e) => buf.write_string("书签: 读不到：\{e}\n")
  }
  buf.write_string("\n")
  if @sys.ffx_supported() {
    match @sys.ffx_history(limit=6) {
      Ok(items) => {
        buf.write_string("Firefox 历史: \{items.length()} 条（列前 6）\n")
        for it in items {
          let title = if it.title == "" { @shared.tx("(无标题)") } else { it.title }
          buf.write_string("  [\{it.visit_count}次] \{sp_clip(title, 34)}\n")
        }
      }
      Err(e) => buf.write_string("Firefox 历史: 读不到：\{e}\n")
    }
  } else {
    buf.write_string("Firefox: 本机无 profiles.ini / places.sqlite\n")
  }
  buf.to_string()
}

///|
/// 剪贴板与桌面状态（含只读的自启状态与空闲读数）。
/// 电源计划不在这里：macOS 只有 `pmset` 的 lowpowermode 一值，与「平衡/性能/
/// 节能」三值语义对不上，属两平台概念（见本页口径说明）。
fn sp_clip_power() -> String {
  let buf = StringBuilder()
  match @sys.cbw_get_text() {
    Ok(t) => buf.write_string("剪贴板文本: \{sp_clip(t, 56)}\n")
    Err(e) => buf.write_string("剪贴板: 读不到：\{e}\n")
  }
  if @sys.idle_supported() {
    match @sys.idle_seconds() {
      Ok(sec) => buf.write_string("空闲: \{sec.to_int()} 秒（自最后一次输入起）\n")
      Err(e) => buf.write_string("空闲: 读取失败：\{e}\n")
    }
  } else {
    buf.write_string("空闲: 本平台/本会话不支持\n")
  }
  if @sys.autostart_supported() {
    let id = "libyue.showcase"
    match @sys.autostart_is_enabled(id) {
      Ok(v) => buf.write_string("本示例开机自启: \{if v { "已开启" } else { "未开启" }}\n")
      Err(e) => buf.write_string("本示例开机自启: 读不到：\{e}\n")
    }
    match @sys.autostart_path(id) {
      Ok(p) => buf.write_string("自启落点: \{sp_clip(p, 52)}\n")
      Err(e) => buf.write_string("自启落点: 读不到：\{e}\n")
    }
  } else {
    buf.write_string("开机自启: 本平台不支持\n")
  }
  buf.to_string()
}

///|
/// 系统能力探测页。五段各带「重新探测」；每组两块面板并排。
pub fn page_sysprobe(_app : @shared.App) -> @widget.Node {
  let sys_a : @base.Store[String] = @base.Store::new("")
  let sys_b : @base.Store[String] = @base.Store::new("")
  let mon_a : @base.Store[String] = @base.Store::new("")
  let app_a : @base.Store[String] = @base.Store::new("")
  let app_b : @base.Store[String] = @base.Store::new("")
  let brw_a : @base.Store[String] = @base.Store::new("")
  let brw_b : @base.Store[String] = @base.Store::new("")
  let ses_a : @base.Store[String] = @base.Store::new("")
  // 本页口径：只列**三平台都有对应面**的探测族。两平台概念（Linux 的
  // recently-used.xbel 与 D-Bus/MPRIS、Linux+Windows 的窗口列表与电源计划、
  // 只有 Linux 有对位的夜灯）不进这页——库里的 API 照旧，只是不在跨平台
  // 演示板上摆一排「本平台不支持」。
  @shared.page([
    @shared.section(
      "系统桌面",
      "系统与桌面",
      "发行版 / 机器 / 内存 / 开机时长 / 桌面环境，以及环境变量、壁纸、打印机。全部只读。",
      sp_group(
        @shared.tx("重新探测"),
        [
          (sys_a, @shared.tx("系统与机器"), sp_sys_machine),
          (sys_b, @shared.tx("桌面与外设"), sp_sys_desktop),
        ],
      ),
    ),
    @shared.section(
      "显示器",
      "显示器",
      "显示器在用模式与全部输出（三平台各自的原生读数，只读）。窗口列表不列：Linux 走 wmctrl、Windows 走 EnumWindows，macOS 只能靠辅助功能授权，属两平台概念。",
      sp_group(@shared.tx("重新探测"), [(mon_a, @shared.tx("显示器"), sp_monitors)]),
    ),
    @shared.section(
      "应用文件",
      "应用与文件",
      "已装应用统计与常见二进制查找；VS Code 最近工作区。最近文件不列：Linux 读 xbel、Windows 读 Recent 目录，macOS 无对应面。",
      sp_group(
        @shared.tx("重新探测"),
        [(app_a, @shared.tx("已装应用"), sp_apps), (app_b, @shared.tx("编辑器工作区"), sp_recent)],
      ),
    ),
    @shared.section(
      "浏览器",
      "浏览器数据",
      "Chromium 系历史与下载、书签树；Firefox 历史。读的是本机浏览器的本地库，不上网。",
      sp_group(
        @shared.tx("重新探测"),
        [
          (brw_a, @shared.tx("历史与下载"), sp_browser_hist),
          (brw_b, @shared.tx("书签与 Firefox"), sp_bookmarks),
        ],
      ),
    ),
    @shared.section(
      "剪贴板电源",
      "剪贴板与桌面状态",
      "剪贴板文本、空闲读数、自启状态（只读）。电源计划与 D-Bus/MPRIS/通知能力不列：前者 macOS 无三值语义对位，后三者是 Linux 总线族。",
      sp_group(@shared.tx("重新探测"), [(ses_a, @shared.tx("剪贴板与桌面状态"), sp_clip_power)]),
    ),
  ])
}
