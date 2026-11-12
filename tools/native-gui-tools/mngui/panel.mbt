// 工程面板：已有工程裸 mng 进来的操作按钮组（package / publish / icons /
// dev）+ 运行日志区。命令经兄弟 mng 落日志，日志区按「刷新」按钮拉 tail。

///|
/// 面板模式主页面体（hint 与日志走 text_dyn 随 Store 自动刷新，树静态）。
fn panel_body(w : Wizard) -> @widget.Node {
  @ui.col(
    [
      @ui.text("工程面板", class=[@style.text_heading]),
      @ui.text(w.proj.get(), selectable=true, color="info"),
      @ui.alert(
        "打包与发布落在工程 .mng/dist/；命令日志在 .mng/wizard/",
        t=@ui.Info,
      ),
      @ui.row(
        [
          @ui.button("打包", on_click=fn() -> Unit { panel_run(w, "package") }),
          @ui.button("发布", on_click=fn() -> Unit { panel_run(w, "publish") }),
          @ui.button("启动热更", on_click=fn() -> Unit { start_dev(w) }),
          @ui.button("刷新日志", variant=@ui.Border, on_click=fn() -> Unit {
            refresh_panel_log(w)
          }),
        ],
        column_gap=8.0,
      ),
      @ui.text_dyn(w.dev_hint.signal(), color="info"),
      @ui.divider(),
      @ui.text("运行日志（末 60 行）", class=[@style.text_title]),
      @ui.col(
        [
          @ui.text_dyn(
            w.log_view.signal(),
            selectable=true,
            family="monospace",
            font_size=12.0,
          ),
        ],
        grow=1.0,
      ),
      @ui.row(
        [
          @ui.button("关闭", variant=@ui.Border, on_click=fn() -> Unit {
            @sys.exit(0)
          }),
        ],
        column_gap=8.0,
      ),
    ],
    row_gap=16.0,
    class=[@style.style(width_percent=100.0)],
    grow=1.0,
  )
}

///|
/// 面板按钮跑 mng 子命令：cwd 在工程目录（shell 包装），后台落日志；
/// 完成后把日志 tail 拉进 log_view。
fn panel_run(w : Wizard, subcmd : String) -> Unit {
  let proj = w.proj.get()
  if proj.length() == 0 {
    w.dev_hint.set("没有工程目录")
    return
  }
  let mng_part : String = if w.dev_form {
    "moon -C \"" + w.repo_cwd + "\" run tools/native-gui-tools/mng -- " + subcmd
  } else {
    match exe_exists(w.argv0_dir, name="mng") {
      Some(p) => "\"" + p + "\" " + subcmd
      None => {
        w.dev_hint.set(
          "在面板旁找不到 mng（" +
          w.argv0_dir +
          "）——终端里手动跑 mng " +
          subcmd,
        )
        return
      }
    }
  }
  mkdir_p(proj + "/.mng/wizard")
  let log = proj + "/.mng/wizard/" + subcmd + ".log"
  let cmd = "cd \"" + proj + "\" && " + mng_part
  let res = if @doctor.host() == "win" {
    @proc.spawn("cmd", ["/C", cmd], log)
  } else {
    @proc.spawn("sh", ["-c", cmd], log)
  }
  match res {
    Ok(pid) => {
      w.dev_hint.set(
        "mng " +
        subcmd +
        " 已启动（pid \{pid}）；跑完点「刷新日志」看结果",
      )
      // 先把现有日志（上一轮的）拉出来，别让面板空白
      refresh_panel_log(w)
    }
    Err(e) => w.dev_hint.set("启动失败：" + e)
  }
}

///|
/// 把日志尾巴拉进 log_view。读哪份按 last_hint 里记录的最近子命令
/// （panel_run 启动时埋进 hint）；没有记录读 dev。
fn refresh_panel_log(w : Wizard) -> Unit {
  let proj = w.proj.get()
  if proj.length() == 0 {
    return
  }
  // 从 hint 提取最近命令名（「mng <cmd> 已启动…」形态），兜底 dev
  let hint = w.dev_hint.get()
  let cmd = if hint.has_prefix("mng ") {
    let rest = hint[4:].to_owned()
    let mut end = rest.length()
    let mut i = 0
    while i < rest.length() {
      if rest[i] == ' ' {
        end = i
        break
      }
      i += 1
    }
    rest[0:end].to_owned()
  } else {
    "dev"
  }
  let p = proj + "/.mng/wizard/" + cmd + ".log"
  match fs_tail(p, 60) {
    Some(t) => w.log_view.set(p + "（末 60 行）\n\n" + t)
    None =>
      w.log_view.set("（读不到 " + p + "——命令跑完了吗？）")
  }
}

///|
/// 文本文件末 n 行。
fn fs_tail(p : String, n : Int32) -> String? {
  let text : String = @fs.read_file_to_string(p) catch { _ => return None }
  let lines : Array[String] = []
  for l in text.split("\n") {
    lines.push(l.to_owned())
  }
  let total = lines.length()
  let start = if total > n { total - n } else { 0 }
  let parts : Array[String] = []
  let mut i = start
  while i < total {
    parts.push(lines[i])
    i += 1
  }
  Some(parts.join("\n"))
}
