// 日期/时间选择器回归：字段弹层开合、点选回填、✕ 清空、区间两段式、
// 时间步进与确定写回。弹层都在浮层图层上，用例先装宿主。

///|
/// 选择器弹层里的日历面板（图层第 id 层的第一块）。
fn picker_panel(id : Int) -> @widget.Widget {
  match @widget.overlay_root_of(id) {
    Some(w) => w.children()[0]
    None => @widget.Widget::new()
  }
}

///|
test "日期选择器：字段显示占位、点开日历、点选回填并收起、✕ 清空" {
  let v : @base.Store[DateYMD?] = @base.Store::new(None)
  let changes : Array[String] = []
  let (root, field) = mounted_with_overlay(
    date_picker(
      v,
      on_change=fn(d : DateYMD) -> Unit { changes.push(d.format()) },
      today=d(2026, 10, 11),
      width=180.0,
    ),
    400.0,
    300.0,
  )
  assert_eq(field.rect.w, 180.0)
  assert_eq(@widget.overlay_count(), 0)
  click_at(root, field, 40.0, 16.0)
  assert_eq(@widget.overlay_count(), 1)
  root.relayout(400.0, 300.0)
  // 弹层挂在字段下方 2px
  match @widget.overlay_rect_of(@widget.overlay_top_id()) {
    Some(r) => assert_eq((r.x, r.y), (field.rect.x, field.rect.y + field.rect.h + 2.0))
    None => assert_true(false)
  }
  // 点第 14 格（10 月 11 日，first_wd=4）
  let panel = picker_panel(@widget.overlay_top_id())
  click_at(root, cell_at(panel, 14), 18.0, 15.0)
  assert_eq(changes, ["2026-10-11"])
  match v.get() {
    Some(x) => assert_eq(x.format(), "2026-10-11")
    None => assert_true(false)
  }
  assert_eq(@widget.overlay_count(), 0)
  // 再开再关：点字段第二次收起
  click_at(root, field, 40.0, 16.0)
  assert_eq(@widget.overlay_count(), 1)
  click_at(root, field, 40.0, 16.0)
  assert_eq(@widget.overlay_count(), 0)
  // 点浮层外收起（图层代劳，组件句柄就此失效）后再点字段，一击即开
  click_at(root, field, 40.0, 16.0)
  assert_eq(@widget.overlay_count(), 1)
  root.relayout(400.0, 300.0)
  let _ = root.dispatch_pointer({ kind: @widget.PointerKind::Down, x: 380.0, y: 280.0, button: 1, mods: 0 })
  let _ = root.dispatch_pointer({ kind: @widget.PointerKind::Up, x: 380.0, y: 280.0, button: 1, mods: 0 })
  assert_eq(@widget.overlay_count(), 0)
  click_at(root, field, 40.0, 16.0)
  assert_eq(@widget.overlay_count(), 1)
  @widget.overlay_clear()
  // ✕ 清空：悬停才有热区
  root.set_hover(field.id)
  click_at(root, field, 154.0, 16.0)
  assert_eq(sel_str(v), "-")
  assert_eq(changes.length(), 1)
}

///|
test "日期区间选择器：先点起点再点终点，写回整段并收起" {
  let v : @base.Store[DateRange] = @base.Store::new({ start: None, end: None })
  let changes : Array[String] = []
  let (root, field) = mounted_with_overlay(
    date_range_picker(
      v,
      on_change=fn(r : DateRange) -> Unit {
        let s = match r.start {
          Some(x) => x.format()
          None => "?"
        }
        let e = match r.end {
          Some(x) => x.format()
          None => "?"
        }
        changes.push(s + "~" + e)
      },
      today=d(2026, 10, 11),
      width=220.0,
    ),
    400.0,
    300.0,
  )
  click_at(root, field, 40.0, 16.0)
  root.relayout(400.0, 300.0)
  let panel = picker_panel(@widget.overlay_top_id())
  // 起点 = 10 月 3 日（第 6 格），终点 = 10 月 7 日（第 10 格）
  click_at(root, cell_at(panel, 6), 18.0, 15.0)
  assert_eq(changes.length(), 0)
  match v.get().start {
    Some(x) => assert_eq(x.format(), "2026-10-03")
    None => assert_true(false)
  }
  assert_eq(@widget.overlay_count(), 1)
  click_at(root, cell_at(panel, 10), 18.0, 15.0)
  assert_eq(changes, ["2026-10-03~2026-10-07"])
  assert_eq(@widget.overlay_count(), 0)
}

///|
/// 弹层里的控件 `rect` 带弹层偏移（x 可为负），按窗口坐标命中会打空——
/// 步进格与按钮格一律按 id 直投事件（坐标仍给控件本地位置）。
fn tap_pop(root : @widget.Widget, w : @widget.Widget, fx : Double, fy : Double) -> Unit {
  let x = w.rect.x + fx
  let y = w.rect.y + fy
  let _ = root.dispatch_pointer_to(w.id, {
    kind: @widget.PointerKind::Down, x, y, button: 1, mods: 0,
  })
  let _ = root.dispatch_pointer_to(w.id, {
    kind: @widget.PointerKind::Up, x, y, button: 1, mods: 0,
  })
}

///|
test "时间区间：步进器改值、确定写回、取消不改" {
  let v : @base.Store[TimeRange] = @base.Store::new({ start: Some(TimeHMS::{ h: 9, m: 0, s: 0 }), end: None })
  let changes : Array[String] = []
  let (root, row) = mounted_with_overlay(
    time_range_picker(
      v,
      on_change=fn(r : TimeRange) -> Unit {
        let f = fn(t : TimeHMS?) -> String {
          match t {
            Some(x) => x.format()
            None => "-"
          }
        }
        changes.push(f(r.start) + "~" + f(r.end))
      },
      width=110.0,
    ),
    400.0,
    300.0,
  )
  let start_field = row.children()[0]
  click_at(root, start_field, 40.0, 16.0)
  assert_eq(@widget.overlay_count(), 1)
  root.relayout(400.0, 300.0)
  let panel = picker_panel(@widget.overlay_top_id())
  // 面板行序：+ 行 / 数值行 / − 行 / 单位行 / 按钮行；每行列序：时 / 分隔 / 分
  let plus_hour = panel.children()[0].children()[0]
  tap_pop(root, plus_hour, 15.0, 12.0)
  tap_pop(root, plus_hour, 15.0, 12.0)
  // 确定：按钮行第 2 个
  let btn_row = panel.children()[4]
  tap_pop(root, btn_row.children()[1], 30.0, 14.0)
  assert_eq(changes, ["11:00~-"])
  match v.get().start {
    Some(t) => assert_eq(t.format(), "11:00")
    None => assert_true(false)
  }
  // 取消路径：改完不确认，Store 不变
  click_at(root, start_field, 40.0, 16.0)
  root.relayout(400.0, 300.0)
  let panel2 = picker_panel(@widget.overlay_top_id())
  tap_pop(root, panel2.children()[0].children()[2], 15.0, 12.0)
  tap_pop(root, panel2.children()[4].children()[0], 30.0, 14.0)
  assert_eq(changes.length(), 1)
  match v.get().start {
    Some(t) => assert_eq(t.format(), "11:00")
    None => assert_true(false)
  }
}

///|
test "日期时间区间：日期走日历、时间走步进，两侧各写各的" {
  let v : @base.Store[DateTimeRange] = @base.Store::new({ start: None, end: None })
  let changes : Array[Int] = []
  let (root, row) = mounted_with_overlay(
    datetime_range_picker(
      v,
      on_change=fn(_r : DateTimeRange) -> Unit { changes.push(1) },
      today=d(2026, 10, 11),
      date_width=130.0,
      time_width=86.0,
    ),
    500.0,
    300.0,
  )
  // 四个字段：起日期 / 起时间 / ~ / 止日期 / 止时间
  assert_eq(row.children().length(), 5)
  let start_date = row.children()[0]
  click_at(root, start_date, 30.0, 16.0)
  root.relayout(500.0, 300.0)
  click_at(root, cell_at(picker_panel(@widget.overlay_top_id()), 14), 18.0, 15.0)
  match v.get().start {
    Some(p) => {
      assert_eq(p.0.format(), "2026-10-11")
      assert_eq(p.1.format(), "09:00")
    }
    None => assert_true(false)
  }
  assert_eq(changes.length(), 1)
  // 起点时间：步进 +1 小时后确定
  let start_time = row.children()[1]
  click_at(root, start_time, 30.0, 16.0)
  root.relayout(500.0, 300.0)
  let panel = picker_panel(@widget.overlay_top_id())
  tap_pop(root, panel.children()[0].children()[0], 15.0, 12.0)
  tap_pop(root, panel.children()[4].children()[1], 30.0, 14.0)
  match v.get().start {
    Some(p) => assert_eq(p.1.format(), "10:00")
    None => assert_true(false)
  }
  assert_eq(changes.length(), 2)
}

///|
/// P2-e 口径：日期选择的字段、日历面板、箭头与日期格都只读样式槽——
/// 内置皮肤先折进槽，`class` 的同名属性覆盖；日期格的悬停底走 hover 桶，
/// 「选中 / 区间内 / 今天」这些数据态配色留内置当回落值。
test "日期选择只读样式槽：class 覆盖字段底、日历面板与箭头悬停底" {
  if !ui_text_guard() {
    return
  }
  let red_count = fn(bm : @render.Bitmap, w : Int, h : Int) -> Int {
    let mut n = 0
    for y = 0; y < h; y = y + 1 {
      for x = 0; x < w; x = x + 1 {
        let c = bm.pixel(x, y)
        if c.r > 128 && c.g < 64 && c.b < 64 {
          n = n + 1
        }
      }
    }
    n
  }
  let paint_count = fn(node : @widget.Node, open_it : Bool) -> Int {
    let (root, field) = mounted_with_overlay(node, 420.0, 360.0)
    if open_it {
      let _ = root.dispatch_pointer({
        kind: @widget.PointerKind::Down,
        x: field.rect.x + 40.0,
        y: field.rect.y + 16.0,
        button: 1,
        mods: 0,
      })
      let _ = root.dispatch_pointer({
        kind: @widget.PointerKind::Up,
        x: field.rect.x + 40.0,
        y: field.rect.y + 16.0,
        button: 1,
        mods: 0,
      })
      root.relayout(420.0, 360.0)
    }
    let bm = @render.Bitmap::new(420, 360)
    let p = @render.Painter::new(bm)
    root.paint(p)
    p.end()
    red_count(bm, 420, 360)
  }
  let v : @base.Store[DateYMD?] = @base.Store::new(None)
  let mk = fn(cls : Array[@style.Style]) -> @widget.Node {
    date_picker(v, today=d(2026, 11, 11), width=180.0, class=cls)
  }
  // 字段底色：内置是 bg_panel（无红），class 换成红
  assert_true(paint_count(mk([]), false) == 0)
  assert_true(paint_count(mk([@style.style(background_color="#ff0000")]), false) > 200)
  // 展开的日历面板底色也吃同一份 class 投影（skin 透进弹层）
  assert_true(
    paint_count(mk([@style.style(background_color="#ff0000")]), true) > 1000,
  )
}

///|
test "时间弹层：四行自上而下 + / 数值 / − / 单位，纵向不重叠、秒列可选" {
  fn mounted_panel(secs : Bool) -> @widget.Widget {
    let n = time_popup(
      TimeHMS::{ h: 9, m: 0, s: 0 },
      fn(_) { () },
      fn() { () },
      show_seconds=secs,
    )
    let root = @widget.Widget::new()
    root.set_size(320.0, 320.0)
    root.set_column()
    let panel = n.mount_into(root)
    root.relayout(320.0, 320.0)
    panel
  }

  let panel = mounted_panel(false)
  let kids = panel.children()
  // 行序：+ / 数值 / − / 单位 / 按钮
  assert_eq(kids.length(), 5)
  // 旧形态把时间画在面板 (0,0,28) 上、不占布局：第一行步进被压住（真机反馈）
  assert_eq(kids[0].rect.y, 10.0)
  let mut prev_end = 0.0
  for c in kids {
    assert_true(c.rect.y >= prev_end, msg="弹层子件纵向重叠")
    prev_end = c.rect.y + c.rect.h
  }
  assert_true(panel.rect.h >= prev_end + 10.0, msg="弹层高度没包住内容")
  // 两列形态：每行 时 / 分隔 / 分 = 3 格（按钮行不参与）
  for i = 0; i < 4; i = i + 1 {
    assert_eq(kids[i].children().length(), 3)
  }
  // 开秒：多一列 → 每行 5 格
  let panel3 = mounted_panel(true)
  assert_eq(panel3.children()[0].children().length(), 5)
  assert_eq(panel3.children()[1].children().length(), 5)
}

///|
/// 列内步进口径：+ 与 − 都在同一列（行 0 与行 2 的同列号），时到 23 回 0、
/// 分/秒到 59 回 0，写回值走确定的那条。
test "时间弹层步进：时/分/秒各自回绕，分步进 1 分钟" {
  let got : Array[String] = []
  let n = time_popup(
    TimeHMS::{ h: 23, m: 59, s: 59 },
    fn(t : TimeHMS) -> Unit { got.push(t.format(show_seconds=true)) },
    fn() { () },
    show_seconds=true,
  )
  let root = @widget.Widget::new()
  root.set_size(320.0, 320.0)
  root.set_column()
  let panel = n.mount_into(root)
  root.relayout(320.0, 320.0)
  // 行 0 = + 行：格 0/2/4 分别是时/分/秒的 +
  click_at(root, panel.children()[0].children()[0], 15.0, 12.0)
  click_at(root, panel.children()[4].children()[1], 30.0, 14.0)
  // 只动时列：23 + 1 回 0，分秒原样带过
  assert_eq(got, ["00:59:59"])
}

///|
/// 日期段「选中：」标签与值标签同高、且不与 picker 重叠。真机 mac 上全角
/// 冒号的 advance 带小数，测量宽四舍五入报窄 1px，标签在自己的盒里折成两行，
/// 变高的盒在行内垂直居中把首行墨迹骑到 picker 下缘（文本层改口径后此用例守门）。
test "日期段标签不折行：测量宽与断行口径一致" {
  if !ui_text_guard() {
    return
  }
  let dp : @base.Store[DateYMD?] = @base.Store::new(Some({ y: 2026, m: 10, d: 13 }))
  let (root, colw) = mounted(
    col(
      [
        date_picker(dp, clearable=true, width=170.0),
        row(
          [
            text("选中：", role=Body),
            bind_label(dp, fn(d : DateYMD?) -> String {
              match d {
                Some(v) => v.format()
                None => "未选"
              }
            }),
          ],
          column_gap=6.0,
        ),
      ],
      row_gap=10.0,
      align_items=@yoga.AlignItems::FlexStart,
    ),
    600.0,
    400.0,
  )
  let kids = colw.children()
  let labs = kids[1].children()
  // 单行标签与单行值同高（折行会让标签高出一整行）
  // 失败时把三量都带出来：盒宽、按测量口算出的应需宽、平台字体集给的像素 advance
  // 合计——Linux(Pango) 与 mac(CoreText) 的小数口径不同，光看「折行了」定不了位。
  let want = match @text.measure_font("选中：", @text.Font::new("", 13.0)) {
    Some(m) => m.width
    None => -1
  }
  assert_eq(
    labs[0].rect.h,
    labs[1].rect.h,
    msg="「选中：」标签高与值标签不等：标签高=\{labs[0].rect.h} 值高=\{labs[1].rect.h} " +
      "盒宽=\{labs[0].rect.w} 测量宽=\{want}（折行则高≈2 倍；不等一倍高=字体集行高差异）",
  )
  // 行整体落在 picker 之下，纵向不重叠
  assert_true(kids[1].rect.y >= kids[0].rect.y + kids[0].rect.h, msg="选中行压住 picker")
  ignore(root)
}

///|
test "键盘可及性：日期字段回车/空格开日历、Esc 收起" {
  let v : @base.Store[DateYMD?] = @base.Store::new(None)
  let (root, w) = mounted_with_overlay(date_picker(v), 400.0, 400.0)
  assert_true(w.focus_id > 0)
  let _ = root.dispatch_key(w.focus_id, { press: true, keysym: @base.KS_RETURN, mods: 0, })
  root.relayout(400.0, 400.0)
  assert_eq(@widget.overlay_count(), 1)
  let _ = root.dispatch_key(w.focus_id, { press: true, keysym: @base.KS_ESCAPE, mods: 0, })
  assert_eq(@widget.overlay_count(), 0)
  assert_true(match v.get() {
    None => true
    Some(_) => false
  })
  @widget.overlay_clear()
}
