// 表单组件页：Store/Signal 驱动。表单值是可写源 Store（组件直接吃 Store，
// 组件写回即状态变化），展示端 bind_label/bind 直连派生。
//
// 五条口径：
// ① `input` 由 Store 驱动；`clearable` 在有内容且悬停/聚焦时右缘出 ✕，点它清空并回写 Store；
// ② 数值用 `stepper`（Int 步进器——中间格就是输入框，打字回车/失焦才回写）；
// ③ `radio_group` 的值是索引 `Store[Int]`；
// ④ `checkbox` 的 Store 即状态源；
// ⑤ 宽高/间距全走命名参数（没有 CSS 样式通道）。
pub fn page_form(_app : @shared.App) -> @widget.Node {
  let qty : @base.Store[Int] = @base.Store::new(3)
  let qty2 : @base.Store[Int] = @base.Store::new(1)
  let slider_val : @base.Store[Double] = @base.Store::new(30.0)
  let rate_val : @base.Store[Int] = @base.Store::new(3)
  let picked_color : @base.Store[String] = @base.Store::new("#2D68C4")
  let dp_val : @base.Store[@ui.DateYMD?] = @base.Store::new(None)
  let sync : @base.Store[Bool] = @base.Store::new(false)
  let notify : @base.Store[Bool] = @base.Store::new(true)
  let theme_idx : @base.Store[Int] = @base.Store::new(1)
  let radio_idx : @base.Store[Int] = @base.Store::new(0)
  let wifi_on : @base.Store[Bool] = @base.Store::new(true)
  let locked : @base.Store[Bool] = @base.Store::new(false)
  let dtr : @base.Store[@ui.DateTimeRange] = @base.Store::new({ start: None, end: None })
  let tr_secs : @base.Store[@ui.TimeRange] = @base.Store::new({ start: None, end: None })
  let nick : @base.Store[String] = @base.Store::new("")
  let mail : @base.Store[String] = @base.Store::new("")
  let err_nick = @ui.validate(nick, @ui.all([@ui.required(), @ui.min_len(2)]))
  let err_mail = @ui.validate(mail, @ui.email())
  let count : @base.Store[Int] = @base.Store::new(0)
  let was_ok = Ref(false)
  let bump_ok = fn(_s : String) -> Unit {
    let ok = err_nick.get().length() == 0 && err_mail.get().length() == 0
    if ok && !was_ok.val {
      count.set(count.get() + 1)
    }
    was_ok.val = ok
  }
  err_nick.subscribe(bump_ok)
  err_mail.subscribe(bump_ok)
  @shared.page([
    @shared.section(
      "输入",
      "输入框与多行",
      "单行 input（Store 驱动，密码态逐字符遮罩）+ 多行 textarea（自动折行、超宽滚动）。",
      [
        @ui.col(
          [
            @ui.input(
              @base.Store::new(""),
              placeholder=@shared.tx("输入点什么…"),
              width=300.0,
              clearable=true,
            ),
            @ui.input(
              @base.Store::new(""),
              placeholder=@shared.tx("密码框"),
              password=true,
              width=300.0,
            ),
            @ui.textarea(
              @base.Store::new(@shared.tr("form.textarea_demo", "多行文本输入演示。\n第二行内容。")),
              rows=3,
              width=300.0,
            ),
          ],
          row_gap=10.0,
          align_items=@yoga.AlignItems::FlexStart,
        ),
      ],
      code=[
        "@ui.input(@base.Store::new(\"\"), placeholder=\"输入点什么…\", width=300.0, clearable=true)",
        "@ui.input(@base.Store::new(\"\"), placeholder=\"密码框\", password=true, width=300.0)",
        "@ui.textarea(@base.Store::new(\"多行文本输入演示。\\n第二行内容。\"), rows=3, width=300.0)",
      ],
    ),
    @shared.section(
      "数值",
      "步进器 / 滑杆 / 评分",
      "stepper 步进器 0..10 钳制；slider 自绘轨道 + thumb（拖拽 step 5 量化）；rate 五角星 hover 预亮——值都住 Store，展示端 bind 直连。",
      [
        @ui.stepper(qty, min=0, max=10, step=1),
        @ui.bind_label(qty, fn(v) { @shared.tr_with("dyn.qty_now", [("v", v.to_string())], "当前数量：\{v}") }),
        @ui.slider(slider_val, min=0.0, max=100.0, step=5.0, width=200.0),
        @ui.bind_label(slider_val, fn(v) { @shared.tr_with("dyn.slider_now", [("v", v.round().to_string())], "当前值：\{v.round()}") }),
        @ui.rate(rate_val),
        @ui.bind_label(rate_val, fn(v) { @shared.tr_with("dyn.rate_now", [("v", v.to_string())], "评分：\{v} 星") }),
      ],
      code=[
        "let qty : @base.Store[Int] = @base.Store::new(3)",
        "@ui.stepper(qty, min=0, max=10, step=1)",
        "@ui.bind_label(qty, fn(v) { \"当前数量：\\{v}\" })",
        "let slider_val : @base.Store[Double] = @base.Store::new(30.0)",
        "@ui.slider(slider_val, min=0.0, max=100.0, step=5.0, width=200.0)",
        "let rate_val : @base.Store[Int] = @base.Store::new(3)",
        "@ui.rate(rate_val)",
      ],
    ),
    @shared.section(
      "选择",
      "Select 与 ColorPicker",
      "下拉点字段弹候选（悬停高亮 / 选中 ✓），clearable ✕ 清空；取色器预设色板点击选色，hex 值住 Store。",
      [
        @ui.col(
          [
            @ui.select(
              [@shared.tx("杭州"), @shared.tx("北京"), @shared.tx("上海"), @shared.tx("深圳"), @shared.tx("广州")],
              @base.Store::new(""),
              clearable=true,
              width=170.0,
            ),
            @ui.color_picker(picked_color),
            @ui.bind_label(picked_color, fn(c) { c }),
          ],
          row_gap=10.0,
          align_items=@yoga.AlignItems::FlexStart,
        ),
      ],
      code=[
        "@ui.select([\"杭州\", \"北京\", \"上海\", \"深圳\", \"广州\"], city, clearable=true, width=170.0)",
        "@ui.color_picker(color)",
        "@ui.bind_label(color, fn(c) { c })",
      ],
    ),
    @shared.section(
      "开关",
      "Checkbox / Radio / Switch",
      "勾选与开关的值就是 Store 本身（展示端直连）；单选组点击互斥（第二组禁用）；开关开=主题蓝靠右。",
      [
        @ui.col(
          [
            @ui.checkbox(@shared.tx("启用自动同步"), sync),
            @ui.checkbox(@shared.tx("接收通知"), notify),
            @ui.row(
              [
                @ui.bind_label(sync, fn(v) { if v { @shared.tx("同步：开") } else { @shared.tx("同步：关") } }),
                @ui.bind_label(notify, fn(v) { if v { @shared.tx("通知：开") } else { @shared.tx("通知：关") } }),
              ],
              column_gap=24.0,
            ),
            @ui.row(
              [
                @ui.radio_group(["浅色", "深色", "跟随系统"].map(x => @shared.tx(x)), theme_idx),
                @ui.radio_group(["选项一", "选项二"].map(x => @shared.tx(x)), radio_idx, disabled=true),
              ],
              column_gap=40.0,
            ),
            @ui.row(
              [
                @ui.switch(wifi_on),
                @ui.bind_label(wifi_on, fn(v) { if v { @shared.tx("已开启") } else { @shared.tx("已关闭") } }),
                @ui.switch(locked, disabled=true),
                @ui.text(@shared.tx("禁用"), role=@ui.Body),
              ],
              column_gap=12.0,
            ),
          ],
          row_gap=10.0,
          align_items=@yoga.AlignItems::FlexStart,
        ),
      ],
      code=[
        "let sync : @base.Store[Bool] = @base.Store::new(false)",
        "@ui.checkbox(\"启用自动同步\", sync)",
        "@ui.bind_label(sync, fn(v) { if v { \"同步：开\" } else { \"同步：关\" } })",
        "let theme_idx : @base.Store[Int] = @base.Store::new(1)",
        "@ui.radio_group([\"浅色\", \"深色\", \"跟随系统\"], theme_idx)",
        "let wifi_on : @base.Store[Bool] = @base.Store::new(true)",
        "@ui.switch(wifi_on)",
        "@ui.switch(@base.Store::new(false), disabled=true)",
      ],
    ),
    @shared.section(
      "日期",
      "日期与时间选择",
      "全自绘月历（‹/› 切月）+ 内联 calendar；日期区间与日期时间区间选择器，选中值住 Store。时间弹层是列式步进：每列自上而下 + / 数值 / − / 单位，列间以 `:` 分隔，时 0-23、分秒 0-59 到界回绕；`show_seconds=true` 多一列秒。占位串、月历表头与星期名、确定/取消都走 `gui.ui.datepicker.*` 取译口，切语言即时换。",
      [
        @ui.col(
          [
            @ui.date_picker(dp_val, clearable=true, width=170.0),
            @ui.row(
              [
                @ui.text(@shared.tx("选中："), role=@ui.Body),
                @ui.bind(dp_val.signal(), fn(d) {
                  match d {
                    Some(v) => v.format()
                    None => @shared.tx("未选")
                  }
                }),
              ],
              column_gap=6.0,
            ),
          ],
          row_gap=10.0,
          align_items=@yoga.AlignItems::FlexStart,
        ),
        @ui.calendar(),
        @ui.col([
          @ui.datetime_range_picker(dtr),
          @ui.bind_label(dtr, fn(r) {
            match (r.start, r.end) {
              (Some((sd, st)), Some((ed, et))) => @shared.tr_with(
                  "dyn.dt_range",
                  [
                    ("a", sd.format()),
                    ("b", st.format()),
                    ("c", ed.format()),
                    ("d", et.format()),
                  ],
                  "日期时间区间：\{sd.format()} \{st.format()} ~ \{ed.format()} \{et.format()}",
                )
              _ => @shared.tx("日期时间区间：未完成选择")
            }
          }),
        ], row_gap=6.0),
        @ui.col(
          [
            @ui.time_range_picker(tr_secs, show_seconds=true, width=120.0),
            @ui.bind_label(tr_secs, fn(r) {
              match (r.start, r.end) {
                (Some(a), Some(b)) => @shared.tr_with(
                    "dyn.t_range",
                    [("a", a.format(show_seconds=true)), ("b", b.format(show_seconds=true))],
                    "时间区间：\{a.format(show_seconds=true)} ~ \{b.format(show_seconds=true)}",
                  )
                _ => @shared.tx("时间区间：未完成选择")
              }
            }),
          ],
          row_gap=6.0,
        ),
      ],
      code=[
        "let dp : @base.Store[@ui.DateYMD?] = @base.Store::new(None)",
        "@ui.date_picker(dp, clearable=true, width=170.0)",
        "@ui.bind(dp.signal(), fn(d) { match d { Some(v) => v.format()  None -> \"未选\" } })",
        "@ui.calendar()",
        "let dtr : @base.Store[@ui.DateTimeRange] = @base.Store::new({ start: None, end: None })",
        "@ui.datetime_range_picker(dtr)",
        "@ui.time_range_picker(tr, show_seconds=true, width=120.0)",
      ],
    ),
    @shared.section(
      "表单",
      "Form 表单",
      "form_item 行布局（标签右对齐 + 控件区）+ form 分组标题；placeholder 给空态提示。",
      [
        @ui.form(@shared.tx("用户设置"), [
          @ui.form_item(
            @shared.tx("用户名"),
            @ui.input(@base.Store::new("moonbit"), placeholder=@shared.tx("登录名"), width=200.0, clearable=true),
          ),
          @ui.form_item(@shared.tx("城市"), @ui.input(@base.Store::new(@shared.tx("杭州")), placeholder=@shared.tx("城市名"), width=200.0)),
          @ui.form_item(@shared.tx("数量"), @ui.stepper(qty2, min=1, max=9)),
        ]),
      ],
      code=[
        "@ui.form(\"用户设置\", [",
        "  @ui.form_item(\"用户名\", @ui.input(",
        "    @base.Store::new(\"moonbit\"), placeholder=\"登录名\", width=200.0, clearable=true,",
        "  )),",
        "  @ui.form_item(\"数量\", @ui.stepper(qty2, min=1, max=9)),",
        "])",
      ],
    ),
    @shared.section(
      "表单校验",
      "Form 校验与错误消息",
      "validate(值槽, 规则) 把错误文案写进自己的 String 槽，form_item(error=) 在控件下方显示红字（行高固定，出现/消失不跳版）；规则即时重跑，改对了红字自己消失。",
      [
        @ui.form(@shared.tx("注册资料"), [
          @ui.form_item(
            @shared.tx("昵称"),
            @ui.input(nick, placeholder=@shared.tx("至少 2 个字符"), width=200.0),
            error=err_nick,
          ),
          @ui.form_item(
            @shared.tx("邮箱"),
            @ui.input(mail, placeholder="you@example.com", width=200.0),
            error=err_mail,
          ),
        ]),
        @ui.bind_label(count, fn(n : Int) { @shared.tr_with("dyn.valid_passed", [("n", n.to_string())], "已通过校验 \{n.to_string()} 项") }),
      ],
      code=[
        "let err_nick = @ui.validate(nick, @ui.all([@ui.required(), @ui.min_len(2)]))",
        "let err_mail = @ui.validate(mail, @ui.email())",
        "@ui.form_item(\"昵称\", @ui.input(nick, placeholder=\"至少 2 个字符\"), error=err_nick)",
      ],
    ),
  ])
}
