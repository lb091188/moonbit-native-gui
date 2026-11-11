// 五个步骤的页面体。间距取 8 的档、文字挂字阶预设、颜色全 token。

///|
fn page_welcome(w : Wizard) -> Array[@widget.Node] {
  [
    @ui.text("mng 向导", class=[@style.text_heading]),
    @ui.text(
      "从零到跑起一个 native-gui 应用，共四步：环境体检 → 新建应用 → 启动热更 → 完成。本向导由裸 mng 自动拉起；之后在工程里日常用 mng dev / mng build。",
      color="text_secondary",
    ),
    @ui.row(
      [@ui.button("开始", on_click=fn() { w.page.set(1) })],
      column_gap=8.0,
    ),
  ]
}

///|
fn page_health(w : Wizard) -> Array[@widget.Node] {
  let rows : Array[@widget.Node] = []
  for it in w.items {
    rows.push(health_row(it))
  }
  let all_ok = @doctor.required_ok(w.items)
  let tail : Array[@widget.Node] = if all_ok {
    [
      @ui.alert("环境就绪，可以开始建应用。", t=@ui.Success),
      @ui.row(
        [@ui.button("继续：新建应用", on_click=fn() { w.page.set(2) })],
        column_gap=8.0,
      ),
    ]
  } else {
    [
      @ui.alert(
        "有必选项未通过——按各行「修复」处理后在终端重跑 mng doctor，再重新打开向导。",
        t=@ui.Warning,
      ),
    ]
  }
  [
    @ui.text("环境体检", class=[@style.text_heading]),
    @ui.text(
      "探针日志在 ~/.mng/doctor/；可选项（WebView、媒体库）缺失只提示，不拦流程。",
      color="text_secondary",
    ),
    @ui.col(rows, row_gap=12.0),
    @ui.col(tail, row_gap=16.0),
  ]
}

///|
fn health_row(it : @doctor.DItem) -> @widget.Node {
  let (glyph, tone) : (String, String) = match it.status {
    Ok => ("✓", "success")
    Warn => ("!", "warning")
    Fail => ("✗", "danger")
  }
  let lines : Array[@widget.Node] = [
    @ui.row(
      [@ui.text(glyph, color=tone), @ui.text(it.title.zh)],
      column_gap=8.0,
    ),
    @ui.text(it.detail.zh, color="text_secondary"),
  ]
  match it.fix {
    Some(f) =>
      lines.push(
        @ui.text("修复：" + f.zh, color="text_secondary", selectable=true),
      )
    None => ()
  }
  @ui.col(lines, row_gap=4.0)
}

///|
fn page_new_app(w : Wizard) -> Array[@widget.Node] {
  [
    @ui.text("新建应用", class=[@style.text_heading]),
    @ui.text(
      "生成最小可跑工程（.mng 单文件组件 + mng dev 热更已配好）。工程名会同时是 moon.mod 的模块名。",
      color="text_secondary",
    ),
    @ui.col(
      [
        @ui.row(
          [
            @ui.text("工程名", class=[@style.style(width=72.0)]),
            @ui.input(w.name, placeholder="my_app", width=360.0),
          ],
          column_gap=12.0,
        ),
        @ui.row(
          [
            @ui.text("父目录", class=[@style.style(width=72.0)]),
            @ui.input(
              w.parent,
              placeholder="应用建在这个目录下",
              width=360.0,
            ),
          ],
          column_gap=12.0,
        ),
      ],
      row_gap=12.0,
    ),
    @ui.text_dyn(w.msg.signal(), color="danger"),
    @ui.row(
      [@ui.button("创建应用", on_click=fn() { let _ = create_app(w) })],
      column_gap=8.0,
    ),
  ]
}

///|
fn create_app(w : Wizard) -> Int32 {
  w.msg.set("")
  @scaffold.app_at(parent=w.parent.get(), raw_name=w.name.get(), on_event=fn(
    e : @scaffold.ScafEvent,
  ) {
    match e {
      AppDone(dir~, ..) => {
        w.proj.set(dir)
        w.msg.set("")
        w.page.set(3)
      }
      other => w.msg.set(scaf_msg(other))
    }
  })
}

///|
fn scaf_msg(e : @scaffold.ScafEvent) -> String {
  match e {
    InvalidName(raw) =>
      "工程名非法（字母/数字/下划线/连字符）：" + raw
    DirExists(dir) => "目录已存在，不覆盖：" + dir
    MkdirFail(dir) => "建不出目录：" + dir
    FilesWriteFail(dir) => "工程文件写失败（目录已删除）：" + dir
    CompileFail(err) => "首页模板编译失败（请回报）：" + err
    GenWriteFail(path) => "生成码写失败：" + path
    PageWriteFail(path) => "写不出文件：" + path
    AppDone(..) => ""
    PageDone(..) => ""
  }
}

///|
fn page_dev(w : Wizard) -> Array[@widget.Node] {
  [
    @ui.text("启动热更", class=[@style.text_heading]),
    @ui.text(
      "在工程目录后台启动 mng dev：改 .mng 保存即热更；关掉本向导它继续跑。",
      color="text_secondary",
    ),
    @ui.text_dyn(w.proj.signal(), color="text_secondary"),
    @ui.text_dyn(w.dev_hint.signal(), color="danger"),
    @ui.row(
      [
        @ui.button("启动 mng dev", on_click=fn() { start_dev(w) }),
        @ui.button("下一步", variant=@ui.Border, on_click=fn() {
          w.page.set(4)
        }),
      ],
      column_gap=8.0,
    ),
  ]
}

///|
fn page_done(w : Wizard) -> Array[@widget.Node] {
  [
    @ui.text("完成", class=[@style.text_heading]),
    @ui.alert("向导流程结束。接下来：", t=@ui.Success),
    @ui.col(
      [
        @ui.text(
          "1. 终端进入工程：cd \"" + w.proj.get() + "\"",
          selectable=true,
        ),
        @ui.text(
          "2. mng dev 已在后台（启动页给过日志路径）；改 pages/home.mng 保存即热更",
        ),
        @ui.text(
          "3. 编辑器体验装 VS Code 扩展：仓库 tools/vscode-mng（着色/补全/诊断/跳转）",
        ),
        @ui.text(
          "4. 打包发布看文档「打包与更新」：mng package → mng publish",
        ),
      ],
      row_gap=8.0,
    ),
    @ui.row(
      [
        @ui.button("关闭向导", variant=@ui.Border, on_click=fn() {
          @sys.exit(0)
        }),
      ],
      column_gap=8.0,
    ),
  ]
}
