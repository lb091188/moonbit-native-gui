// 脚手架内核入口：工程脚手架与单页样板。

///|
/// `new <名字>` 内核：在 `parent/<name>/` 生成可跑最小工程（目录已存在拒绝）。
/// 返回 0 成功、2 工程名非法、1 其余失败；进度经 on_event 上报。
pub fn app_at(
  parent~ : String,
  raw_name~ : String,
  on_event~ : (ScafEvent) -> Unit,
) -> Int32 {
  let name = mod_name(raw_name)
  if name.length() == 0 {
    on_event(InvalidName(raw_name))
    return 2
  }
  let dir = parent + "/" + name
  if @fs.path_exists(dir) {
    on_event(DirExists(dir))
    return 1
  }
  if !mkdir_p(dir + "/pages") {
    on_event(MkdirFail(dir + "/pages"))
    return 1
  }
  let (gui_ver, yoga_ver) = versions(parent)
  let spit_ok = fn(p : String, body : String) -> Bool {
    spit(dir + "/" + p, body)
  }
  let ok = spit_ok("moon.mod", moon_mod_tpl(name, gui_ver, yoga_ver)) &&
    spit_ok("moon.pkg", moon_pkg_tpl(name)) &&
    spit_ok("pages/moon.pkg", pages_pkg_tpl()) &&
    spit_ok("mng.toml", mng_toml_tpl()) &&
    spit_ok("main.mbt", main_mbt_tpl(name)) &&
    spit_ok("pages/home.mng", home_mng_tpl())
  if !ok {
    on_event(FilesWriteFail(dir))
    let _ = @fs.remove_dir(dir) catch { _ => () }
    return 1
  }
  // 首页生成码：dev 形态（热更面在 @mngdev，CI 对账与 mng dev 同形）
  match compile_dev(home_mng_tpl(), dir + "/pages/home.mng") {
    Err(e) => {
      on_event(CompileFail(e))
      return 1
    }
    Ok(r) =>
      if !spit_ok("pages/home.gen.mbt", r.code) {
        on_event(GenWriteFail(dir + "/pages/home.gen.mbt"))
        return 1
      }
  }
  on_event(AppDone(dir~, name~))
  0
}

///|
/// `new page <路径>` 内核：写 `<路径>.mng` 单页样板（父目录不存在现建）。
/// 返回 0 成功、1 失败；进度经 on_event 上报。
pub fn page(raw~ : String, on_event~ : (ScafEvent) -> Unit) -> Int32 {
  let name = if raw.has_suffix(".mng") { raw } else { raw + ".mng" }
  // 父目录补齐：取最后一个 / 之前的部分，非空且不存在时 mkdir_p
  let chars = chars_of(name)
  let mut last = -1
  for i, c in chars {
    if c == '/' {
      last = i
    }
  }
  if last > 0 {
    let dir = slice_path(chars, 0, last)
    if !@fs.path_exists(dir) && !mkdir_p(dir) {
      on_event(MkdirFail(dir))
      return 1
    }
  }
  let stem = basename(name)
  let stem = if stem.has_suffix(".mng") {
    stem[:stem.length() - 4].to_owned()
  } else {
    stem
  }
  let snake = snake_of(stem)
  let tpl = [
    "<script>",
    "// props（可选）：script 段第一行只写签名、不写函数体的 fn 头就是本组件的参数表；",
    "// 必填走位置参数，可选走 `名? : 类型 = 默认值`。不写即零参组件。",
    "// fn " +
    snake +
    "(title : String, qty : @base.Store[Int32], on_reset : () -> Unit, wide? : Bool = false) -> @widget.Node",
    "",
    "// 页状态：Store/Signal 声明在此；被模板引用的 let 绑定即响应槽。",
    "let qty : @base.Store[Int32] = @base.Store::new(0)",
    "",
    "// 组件调用零声明：ui-* 走内置表；同包 `fn 组件名` 直接当标签用；",
    "// 跨包写 `let 组件名 = @包.函数`，路径取自右值、参数顺序取自源码签名。",
    "// 只有不规则落点（子元素不是 Array[@widget.Node] 之类）才需要一行覆盖：",
    "// @mng sh-page = @shared.page positional(children)",
    "</script>",
    "",
    "<template>",
    "  <ui-col row_gap=\"8.0\">",
    "    <ui-stepper v-model=\"qty\" max=\"10\" />",
    "    当前数量：{{ qty }}",
    "  </ui-col>",
    "</template>",
    "",
  ].join("\n")
  if !spit(name, tpl) {
    on_event(PageWriteFail(name))
    return 1
  }
  on_event(PageDone(path=name, fn_name=snake))
  0
}
