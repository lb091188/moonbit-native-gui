// airtype 桌面页的上下文单例（sfc「页面上下文·应用级」约定）：模板页构建期
// 只读这一层，服务侧（service.mbt）与动作（go_perm）写入。stores 住手写
// 文件而不住 .mng script——script 段的 let 编进生成函数体，是组件局部，
// 外部服务够不着。

///|
let s_url : @base.Store[String] = @base.Store::new("服务启动中…")

///|
let s_qr : @base.Store[QrImage] = @base.Store::new(qr_image_of("airtype:starting"))

///|
let s_state : @base.Store[String] = @base.Store::new("启动中")

///|
let s_addr : @base.Store[String] = @base.Store::new("—")

///|
let s_conns : @base.Store[String] = @base.Store::new("0")

///|
let s_perm : @base.Store[String] = @base.Store::new(perm_text())

///|
let s_page : @base.Store[String] = @base.Store::new("首页")

///|
let s_cfg : @base.Store[String] = @base.Store::new(load_shortcuts())

///|
let s_history : @base.Store[String] = @base.Store::new(
  "暂无记录——手机发送后在这里出现",
)

///|
let g_history : Ref[Array[String]] = Ref([])

///|
/// 辅助功能授权读数（mac 上屏注入的前置权限；其余平台无需）。
fn perm_text() -> String {
  match @sys.permission_probe(@sys.PermAccessibility) {
    Ok(PermGranted) => "已授权"
    Ok(PermNotNeeded) => "本平台无需"
    _ => "未授权——上屏不可用"
  }
}

///|
/// 去授权动作：弹系统引导框并直达设置页，状态随重探定时器刷新。
fn go_perm() -> Unit {
  let _ = @sys.permission_ensure(@sys.PermAccessibility)
  let _ = @sys.open_url(
    "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
  )
  s_perm.set(perm_text())
}

///|
/// 上屏记录：最新在前，点号分隔，最多 8 条，预览截 24 字符。
fn push_history(text : String) -> Unit {
  let preview = if text.length() > 24 {
    text[:24].to_owned() + "…"
  } else {
    text
  }
  let next : Array[String] = [preview]
  for h in g_history.val {
    if next.length() >= 8 {
      break
    }
    next.push(h)
  }
  g_history.val = next
  let mut out = ""
  for i, h in next {
    if i > 0 {
      out = out + " · "
    }
    out = out + h
  }
  s_history.set(out)
}

///|
/// 分段导航组件：mngkit 内置表没有 segmented，同包 fn 组件引入（签名即
/// props——模板属性按参数名映射）。
fn segmented(
  options : Array[String],
  selected : @base.Store[String],
) -> @widget.Node {
  @ui.segmented(options, selected)
}

///|
/// 快捷指令配置变更（模板 textarea 双向绑定）：落盘生效。
fn init {
  let _ = s_cfg.signal().subscribe(fn(_v) { apply_shortcuts(s_cfg.get()) })
}
