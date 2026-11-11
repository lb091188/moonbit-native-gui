// mng 向导主界面：五个步骤共用一扇窗，页面体经 bind_node 随 page Store 重建。
// 体检在开窗前同步跑完（构建探针一次几秒，窗起后只展示结果）。

///|
struct Wizard {
  page : @base.Store[Int32]
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
}

///|
fn steps_labels() -> Array[String] {
  ["欢迎", "环境体检", "新建应用", "启动热更", "完成"]
}

///|
fn main {
  let raw = @env.args()
  let argv0 = if raw.length() > 0 { raw[0] } else { "" }
  let cwd = match @env.current_dir() {
    Some(d) => d
    None => "."
  }
  let w = Wizard::{
    page: @base.Store::new(0),
    // 体检在开窗前同步跑完；结果只读展示
    items: @doctor.run_all(),
    name: @base.Store::new(""),
    parent: @base.Store::new(cwd),
    icon: @base.Store::new(""),
    msg: @base.Store::new(""),
    proj: @base.Store::new(""),
    dev_hint: @base.Store::new(""),
    repo_cwd: cwd,
    argv0_dir: argv0_dir(argv0),
    dev_form: argv0.contains("_build"),
  }
  let root = @ui.col(
    [
      @ui.steps(steps_labels(), w.page),
      @ui.divider(),
      @widget.bind_node(w.page.signal(), fn(_p : Int32) { wizard_body(w) }),
    ],
    padding=24.0,
    row_gap=16.0,
  )
  let mounted = @ui.mount_window(
    [root],
    title="mng 向导",
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
  let body : Array[@widget.Node] = match w.page.get() {
    0 => page_welcome(w)
    1 => page_health(w)
    2 => page_new_app(w)
    3 => page_dev(w)
    _ => page_done(w)
  }
  @ui.col(body, row_gap=16.0, class=[@style.style(width_percent=100.0)])
}
