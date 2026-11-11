// mng 向导主界面：五个步骤共用一扇窗，页面体经 bind_node 随 page Store 重建。
// 体检在开窗前同步跑完（构建探针一次几秒，窗起后只展示结果）。

///|
struct Wizard {
  // page = 真实进度（步骤条高亮跟它走）；view = 当前展示的页（点步骤条数字
  // 只动 view 做预览，进度不动）
  page : @base.Store[Int32]
  view : @base.Store[Int32]
  items : Array[@doctor.DItem]
  name : @base.Store[String]
  parent : @base.Store[String]
  icon : @base.Store[String]
  msg : @base.Store[String]
  proj : @base.Store[String]
  dev_hint : @base.Store[String]
  repo_cwd : String
  argv0_dir : String
  dev_form : Bool
  // 工程面板模式（--project <路径>）：跳过五步向导，直接工程操作按钮组
  panel : Bool
  log_view : @base.Store[String]
}

///|
fn steps_labels() -> Array[String] {
  ["欢迎", "环境体检", "新建应用", "启动热更", "完成"]
}

///|
/// 前进跳页：进度与展示一起走（点步骤条数字才只动 view 做预览）。
fn goto(w : Wizard, p : Int32) -> Unit {
  w.page.set(p)
  w.view.set(p)
}

///|
fn main {
  let raw = @env.args()
  let argv0 = if raw.length() > 0 { raw[0] } else { "" }
  let cwd = match @env.current_dir() {
    Some(d) => d
    None => "."
  }
  // --project [路径]：工程面板模式。路径缺省当前目录。
  let mut panel_proj = ""
  let mut k = 1
  while k < raw.length() {
    if raw[k] == "--project" {
      if k + 1 < raw.length() && !raw[k + 1].has_prefix("--") {
        panel_proj = raw[k + 1]
        k += 2
      } else {
        panel_proj = cwd
        k += 1
      }
    } else {
      k += 1
    }
  }
  let w = Wizard::{
    page: @base.Store::new(0),
    view: @base.Store::new(0),
    // 体检在开窗前同步跑完；结果只读展示
    items: @doctor.run_all(),
    name: @base.Store::new(""),
    parent: @base.Store::new(cwd),
    icon: @base.Store::new(""),
    msg: @base.Store::new(""),
    proj: @base.Store::new(panel_proj),
    dev_hint: @base.Store::new(""),
    repo_cwd: cwd,
    argv0_dir: argv0_dir(argv0),
    dev_form: argv0.contains("_build"),
    panel: panel_proj.length() > 0,
    log_view: @base.Store::new("（还没有日志——点上面的按钮跑命令）"),
  }
  let top : Array[@widget.Node] = if w.panel {
    // 面板模式无步骤条：标题 + 操作按钮组 + 日志区（hint 与日志走
    // text_dyn 随 Store 自动刷新，整树静态）
    [panel_body(w)]
  } else {
    [
      // 点数字方块只换展示页做预览；高亮仍跟进度
      @ui.steps(steps_labels(), w.page, on_select=fn(i : Int) -> Unit {
        w.view.set(i)
      }),
      @ui.divider(),
      @widget.bind_node(w.view.signal(), fn(_p : Int32) { wizard_body(w) }),
    ]
  }
  let root = @ui.col(
    top,
    padding=24.0,
    row_gap=16.0,
    // 根容器撑满窗宽：窗口根是 Row 方向，不设 grow 会按内容收宽
    grow=1.0,
  )
  let mounted = @ui.mount_window(
    [root],
    title=(if w.panel { "mng 工程面板" } else { "mng 向导" }),
    width=720,
    height=560,
    handle=fn(_h : @widget.WindowHost) { () },
  )
  match mounted {
    // 3 = 无显示服务：裸 mng 据此回 usage
    None => {
      println("mngui: 本平台无窗口后端或无显示服务")
      @sys.exit(3)
    }
    Some(host) => host.run()
  }
}

///|
/// 当前页的完整页面体（步骤条常驻，内容区随 bind_node 重建）。
fn wizard_body(w : Wizard) -> @widget.Node {
  let body : Array[@widget.Node] = match w.view.get() {
    0 => page_welcome(w)
    1 => page_health(w)
    2 => page_new_app(w)
    3 => page_dev(w)
    _ => page_done(w)
  }
  // 预览态（点数字方块进来的）：内容区顶部插提示条，进度页不受影响
  let all = if w.view.get() != w.page.get() {
    let labels = steps_labels()
    let v = w.view.get()
    [
      @ui.row(
        [
          @ui.text(
            "正在预览「\{labels[v]}」——进度仍停在第 \{w.page.get() + 1} 步",
            color="info",
          ),
          @ui.button("返回当前步", variant=@ui.Border, on_click=fn() -> Unit {
            goto(w, w.page.get())
          }),
        ],
        column_gap=12.0,
      ),
      @ui.divider(),
    ] + body
  } else {
    body
  }
  @ui.col(all, row_gap=16.0, class=[@style.style(width_percent=100.0)])
}
