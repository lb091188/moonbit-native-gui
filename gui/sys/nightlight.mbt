// 夜间色温（夜间模式）：以百分比 0-100 表示色温，0 = 最暖、100 = 最冷
//（6500K 中性，即不改动）。设置色温两条后端：redshift 存在时优先
//（-O 一次性设置色温，K），否则用 xrandr --output <输出> --gamma
// R:G:B，以红/蓝通道 gamma 偏移近似色温（蓝通道衰减越多越暖）。
// nl_supported 真实探测（redshift -V 只打印版本、xrandr --query 只读，
// 均无副作用）。reset 复位：redshift -x / xrandr --gamma 1.00:1.00:1.00
// （不带 --output 的屏幕级复位作用于全部输出）。
// 色温换算与命令参数构造均为纯函数，nightlight_wbtest.mbt 白盒覆盖。

///|
pub(all) enum NightlightError {
  /// 当前平台/环境不支持（非 Linux，或 redshift 与 xrandr 均不可用、
  /// xrandr 无已连接输出）
  Unsupported
  /// 命令执行失败（启动失败 / 非零退出码 / 超时 / 被信号终止），带原因
  CommandFailed(String)
}

///|
pub impl Show for NightlightError with fn output(self, logger) {
  match self {
    Unsupported => logger.write_string("NightlightError::Unsupported")
    CommandFailed(m) =>
      logger.write_string("NightlightError::CommandFailed(\{m})")
  }
}

///|
pub extend NightlightError with Show::{to_string, output}

// ---------------------------------------------------------------------------
// 纯函数层：色温换算 / gamma 文本 / 命令参数构造（白盒测试覆盖）
// ---------------------------------------------------------------------------

///|
/// 百分比钳到 0..100。
fn nl_clamp_percent(p : Int) -> Int {
  if p < 0 {
    0
  } else if p > 100 {
    100
  } else {
    p
  }
}

///|
/// 暖度（0 = 中性/最冷，100 = 最暖）：与 percent 反向。
fn nl_warmth(percent : Int) -> Int {
  100 - nl_clamp_percent(percent)
}

///|
/// 千分比 gamma 值格式化为两位小数字符串（1000 → "1.00"，
/// 850 → "0.85"，2200 → "2.20"；四舍五入到百分位，进位到 1.00）。
fn nl_fmt_permille(v : Int) -> String {
  let mut whole = v / 1000
  let mut frac = (v % 1000 + 5) / 10
  if frac >= 100 {
    whole = whole + 1
    frac = frac - 100
  }
  let frac_text = if frac < 10 { "0\{frac}" } else { "\{frac}" }
  "\{whole}.\{frac_text}"
}

///|
/// 红通道 gamma 千分比：最暖时 0.85（微提红，补偿暖观感）。
fn nl_red_gamma(warmth : Int) -> Int {
  1000 - warmth * 15 / 10
}

///|
/// 蓝通道 gamma 千分比：最暖时 2.20（gamma > 1 衰减该通道，色温向暖偏移）。
fn nl_blue_gamma(warmth : Int) -> Int {
  1000 + warmth * 12
}

///|
/// xrandr --gamma 的 "R:G:B" 参数文本（如 "0.85:1.00:2.20"；绿通道恒
/// 1.00）。percent 出界先钳。
fn nl_gamma_text(percent : Int) -> String {
  let w = nl_warmth(percent)
  "\{nl_fmt_permille(nl_red_gamma(w))}:1.00:\{nl_fmt_permille(nl_blue_gamma(w))}"
}

///|
/// redshift -O 的色温（K）：percent 0 → 2500K（最暖），100 → 6500K
/// （中性）。
fn nl_kelvin(percent : Int) -> Int {
  2500 + nl_clamp_percent(percent) * 40
}

///|
/// xrandr 设色温参数表：--output <输出> --gamma R:G:B。
fn nl_xrandr_set_args(output : String, percent : Int) -> Array[String] {
  ["--output", output, "--gamma", nl_gamma_text(percent)]
}

///|
/// redshift 设色温参数表：-P 先清既有 gamma 斜坡，-O 一次性设置色温。
fn nl_redshift_set_args(percent : Int) -> Array[String] {
  ["-P", "-O", "\{nl_kelvin(percent)}"]
}

// ---------------------------------------------------------------------------
// Windows gamma 直调（SetDeviceGammaRamp）
// ---------------------------------------------------------------------------

///|
/// Windows gamma ramp 字节串：三通道各 256 项 WORD 小端（1536 字节），曲线 =
/// pow(i/255, gamma)，gamma 千分比与 xrandr 路径同源（红提亮/蓝衰减，绿恒
/// 1.00）。语义与 `--gamma` 完全一致——GDI 的 ramp 就是这条幂曲线。
/// 全 1.00（identity）即复位：pow 归一曲线尾值 65535、i*257 恒等斜坡。
fn nl_ramp_bytes(red_permille : Int, blue_permille : Int) -> Bytes {
  let out : Array[Byte] = []
  for ch in 0..<3 {
    let permille = match ch {
      0 => red_permille
      1 => 1000
      _ => blue_permille
    }
    let g = permille.to_double() / 1000.0
    for i in 0..<256 {
      let v = @math.pow(i.to_double() / 255.0, g) * 65535.0
      let w = if v < 0.0 {
        0
      } else if v > 65535.0 {
        65535
      } else {
        v.to_int()
      }
      let _ = out.push((w & 0xFF).to_byte())
      let _ = out.push(((w >> 8) & 0xFF).to_byte())
    }
  }
  Bytes::from_array(out)
}

///|
/// 单通道恒等斜坡 WORD 值：i*257（0,257,…,65535）。
fn nl_ramp_identity_word(i : Int) -> Int {
  i * 257
}

///|
#borrow(ramp, ok)
extern "c" fn ffi_nl_set_ramp(ramp : Bytes, ok : Ref[Int]) -> Unit = "yue_sys_nl_set_ramp"

// ---------------------------------------------------------------------------
// 后端探测（redshift 优先；可用性判定均为只读调用）
// ---------------------------------------------------------------------------

///|
/// 色温后端（探测结果）。
priv enum NlBackend {
  NlRedshift
  NlXrandr
}

///|
/// 执行命令并按结果归一（0 为成功，其余错误带原因映射为 CommandFailed）。
fn nl_run(prog : String, args : Array[String]) -> Result[Unit, NightlightError] {
  match pr_run(prog, args, timeout_ms=5000) {
    Ok(_) => Ok(())
    Err(NonZeroExit(code, err)) =>
      Err(CommandFailed("\{prog}: 退出码 \{code}（\{nl_trim_msg(err)}）"))
    Err(Timeout(m)) => Err(CommandFailed(m))
    Err(SpawnFailed(m)) => Err(CommandFailed(m))
    Err(Signaled(sig)) => Err(CommandFailed("\{prog}: 被信号 \{sig} 终止"))
    Err(Unsupported) => Err(Unsupported)
  }
}

///|
/// stderr 诊断文本压成单行并截断（错误消息只取首行前 120 字符，避免刷屏）。
fn nl_trim_msg(s : String) -> String {
  let buf = StringBuilder()
  let mut n = 0
  for ch in s {
    if ch == '\n' || n >= 120 {
      break
    }
    buf.write_char(ch)
    n = n + 1
  }
  buf.to_string()
}

///|
/// 探测可用后端：redshift -V 能退出 0 即存在（-V 只打印版本，无副作用），
/// 否则看 xrandr --query 是否只读可用。每次调用真实探测。
fn nl_backend() -> NlBackend? {
  // macOS：Night Shift 没有公开控制口（CoreBrightness 是私有框架，
  // `com.apple.CoreBrightness` 域随版本漂移，Control Center 的 UI 自动化不算
  // API）——按「没做」出声，不去 spawn 一定不存在的 redshift/xrandr。
  if sys_platform() == "macos" {
    return None
  }
  if !pr_available() {
    return None
  }
  match pr_run("redshift", ["-V"], timeout_ms=3000) {
    Ok(_) => return Some(NlRedshift)
    Err(_) => ()
  }
  match pr_run("xrandr", ["--query"], timeout_ms=3000) {
    Ok(_) => Some(NlXrandr)
    Err(_) => None
  }
}

// ---------------------------------------------------------------------------
// 公开 API
// ---------------------------------------------------------------------------

///|
/// 当前系统是否支持夜间色温调节（redshift 或 xrandr 任一可用）。
/// 每次调用真实探测，高频场景请调用方自行缓存结果。
pub fn nl_supported() -> Bool {
  // Windows 走 SetDeviceGammaRamp 直调（gdi32 公开口，全虚拟屏 DC 一把设齐
  // 所有输出；曲线换算与 xrandr gamma 同源）。系统「夜间模式」的开关状态
  // 存 CloudStore 私有 blob，不碰；gamma 直调与其互不干扰。
  if sys_platform() == "windows" {
    return true
  }
  nl_backend() is Some(_)
}

///|
/// 设置色温：percent 0-100，0 = 最暖、100 = 最冷（中性不改动），出界
/// 钳制。redshift 存在走 `redshift -P -O <K>`，否则走
/// `xrandr --output <首选输出> --gamma R:G:B`（首选输出取当前主输出，
/// 无主输出取首个已连接输出）。
pub fn nl_set_temperature(percent : Int) -> Result[Unit, NightlightError] {
  let p = nl_clamp_percent(percent)
  if sys_platform() == "windows" {
    let w = nl_warmth(p)
    let ramp = nl_ramp_bytes(nl_red_gamma(w), nl_blue_gamma(w))
    let ok = Ref(0)
    ffi_nl_set_ramp(ramp, ok)
    if ok.val != 1 {
      return Err(CommandFailed("SetDeviceGammaRamp 失败"))
    }
    return Ok(())
  }
  match nl_backend() {
    None => Err(Unsupported)
    Some(NlRedshift) => nl_run("redshift", nl_redshift_set_args(p))
    Some(NlXrandr) =>
      match nl_pick_output() {
        None => Err(Unsupported) // xrandr 在但无已连接输出（无头环境）
        Some(output) => nl_run("xrandr", nl_xrandr_set_args(output, p))
      }
  }
}

///|
/// 复位色温（恢复中性）：redshift 存在走 `redshift -x`，否则走
/// `xrandr --gamma 1.00:1.00:1.00`（不带 --output，复位全部输出）。
pub fn nl_reset() -> Result[Unit, NightlightError] {
  if sys_platform() == "windows" {
    let ok = Ref(0)
    ffi_nl_set_ramp(nl_ramp_bytes(1000, 1000), ok)
    if ok.val != 1 {
      return Err(CommandFailed("SetDeviceGammaRamp 复位失败"))
    }
    return Ok(())
  }
  match nl_backend() {
    None => Err(Unsupported)
    Some(NlRedshift) => nl_run("redshift", ["-x"])
    Some(NlXrandr) => nl_run("xrandr", ["--gamma", "1.00:1.00:1.00"])
  }
}

// ---------------------------------------------------------------------------
// xrandr 路径的输出选择（复用 monitor 解析，选主输出/首个已连接输出）
// ---------------------------------------------------------------------------

///|
/// 选当前应对其生效的输出名：主输出优先，否则首个已连接输出；解析不到
/// （xrandr 不在/输出为空）为 None。
fn nl_pick_output() -> String? {
  match mon_list() {
    Err(_) => None
    Ok(infos) => {
      let mut primary : String? = None
      let mut first : String? = None
      for info in infos {
        if info.connected {
          if first is None {
            first = Some(info.name)
          }
          if info.primary && primary is None {
            primary = Some(info.name)
          }
        }
      }
      match primary {
        Some(_) => primary
        None => first
      }
    }
  }
}

///|
test "nl_ramp_bytes 形状：长度/端点/通道序/恒等" {
  let r = nl_ramp_bytes(1000, 1000)
  assert_eq(r.length(), 1536)
  // 恒等 gamma(千分比 1000)= pow(i/255, 1.0)*65535 = i*257,三通道一致
  for ch in 0..<3 {
    for i in [0, 1, 128, 255] {
      let off = ch * 512 + i * 2
      let w = r[off].to_int() | (r[off + 1].to_int() << 8)
      assert_eq(w, nl_ramp_identity_word(i))
    }
  }
}

///|
test "nl_ramp_bytes 蓝衰减：最暖档蓝通道低于红通道" {
  // warmth=100:红 gamma 0.85(上提)、蓝 gamma 2.20(下压)
  let r = nl_ramp_bytes(850, 2200)
  let word_at = fn(ch : Int, i : Int) -> Int {
    let off = ch * 512 + i * 2
    r[off].to_int() | (r[off + 1].to_int() << 8)
  }
  // 中段采样:红应高于蓝(gamma<1 上提 vs gamma>1 下压)
  assert_true(word_at(0, 128) > word_at(2, 128))
  // 单调递增(GDI ramp 约束)
  let mut prev = 0
  for i in 0..<256 {
    let w = word_at(2, i)
    assert_true(w >= prev)
    prev = w
  }
  // 端点:0 → 0,255 → 65535
  assert_eq(word_at(2, 0), 0)
  assert_eq(word_at(2, 255), 65535)
}
