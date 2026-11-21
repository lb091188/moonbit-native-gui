// FFI 声明与行式输出的解码辅助。桩符号全平台有定义（env_stub.c 互斥占位），
// extern 声明不分平台；读不到的信号桩给空串或 0，MoonBit 侧按信号缺失处理。

///|
/// 平台标识："windows" / "linux" / "macos"。
extern "c" fn ffi_platform() -> Bytes = "envx_platform"

///|
/// Windows CPUID 两行：`hv=<0|1>` 与 `sig=<hypervisor 签名串>`。
extern "c" fn ffi_win_cpuid() -> Bytes = "envx_win_cpuid"

///|
/// Windows 贴桌面适配器名，一行一个。
extern "c" fn ffi_win_adapters() -> Bytes = "envx_win_adapters"

///|
/// Windows SMBIOS 注册表镜像三行：`man=` / `prod=` / `hvhost=`。
extern "c" fn ffi_win_smbios() -> Bytes = "envx_win_smbios"

///|
/// Windows DXGI 首适配器软件旗标：1 即 WARP。
extern "c" fn ffi_win_dxgi_soft() -> Int32 = "envx_win_dxgi_soft"

///|
/// Windows 远程桌面会话：GetSystemMetrics(SM_REMOTESESSION) 非 0。
extern "c" fn ffi_win_remote() -> Int32 = "envx_win_remote"

///|
/// macOS hw.model。
extern "c" fn ffi_mac_model() -> Bytes = "envx_mac_model"

///|
/// macOS kern.hv_vmm_present 非 0。
extern "c" fn ffi_mac_hvvmm() -> Int32 = "envx_mac_hvvmm"

///|
/// macOS Metal 默认设备存在性。
extern "c" fn ffi_mac_metal() -> Int32 = "envx_mac_metal"

///|
/// Linux 路径存在性。
#borrow(path)
extern "c" fn ffi_linux_exists(path : Bytes) -> Int32 = "envx_linux_exists"

///|
/// Linux 读小文件全文；打不开给空串。
#borrow(path)
extern "c" fn ffi_linux_read_file(path : Bytes) -> Bytes = "envx_linux_read_file"

///|
/// Linux readlink；失败给空串。
#borrow(path)
extern "c" fn ffi_linux_read_link(path : Bytes) -> Bytes = "envx_linux_read_link"

///|
/// Linux 渲染节点探测四行：`open=` / `vendor=` / `driver=` / `dxg=`。
extern "c" fn ffi_linux_render() -> Bytes = "envx_linux_render"

///|
/// Linux 网卡 MAC 候选列表，一行一个（/sys/class/net/*/address）。
extern "c" fn ffi_linux_net_macs() -> Bytes = "envx_linux_net_macs"

///|
fn decode(b : Bytes) -> String {
  @utf8.decode_lossy(b)
}

///|
/// 行式输出按行拆，去掉空行与首尾空白。
fn split_lines(text : String) -> Array[String] {
  let out : Array[String] = []
  for line in text.split("\n") {
    let t = line.trim().to_owned()
    if t != "" {
      out.push(t)
    }
  }
  out
}

///|
/// `key=value` 行式输出取值：命中前缀即剥前缀返回余部。
fn kv_value(line : String, key : String) -> String? {
  if line.has_prefix(key + "=") {
    Some(line[key.length() + 1:].to_owned())
  } else {
    None
  }
}

///|
/// 大小写不敏感的包含匹配：判据串全 ASCII，to_lower 是 ASCII 小写化。
fn contains_ci(hay : String, needle : String) -> Bool {
  hay.to_lower().contains(needle.to_lower())
}
