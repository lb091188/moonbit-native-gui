// 对外 API：便捷判定 + 一次全采。进程级缓存——虚拟机、容器、会话类型在
// 进程生命周期内不变，便捷判定内部只查一次；GPU 热插拔暂不追，记为边界。

///|
/// 进程级缓存：Ref 装可空报告，首查填充。
let report_cache : Ref[EnvReport?] = Ref(None)

///|
fn linux_read(path : String) -> String {
  decode(ffi_linux_read_file(@utf8.encode(path)))
}

///|
fn linux_exists(path : String) -> Bool {
  ffi_linux_exists(@utf8.encode(path)) == 1
}

///|
/// 平台分派。判定顺序固定：容器 → 虚拟机 → 会话 → 桌面 → GPU——容器限核
/// 会误触 VM 核数启发式，顺序不能反（提案铁律三）。
fn collect_dispatch() -> EnvReport {
  match decode(ffi_platform()) {
    "windows" => collect_windows()
    "linux" => collect_linux()
    "macos" => collect_macos()
    p => {
      let signals : Array[Signal] = []
      {
        platform: p,
        vm: Unknown,
        container: No,
        gpu: { tier: GpuNone, detail: "未知平台", },
        session: UnknownSession,
        desktop: UnknownDesktop,
        signals,
      }
    }
  }
}

///|
fn collect_windows() -> EnvReport {
  let signals : Array[Signal] = []
  let brands : Array[String] = []
  // 顺序铁律：容器判定先行。Windows 侧 P1 无容器判据（Docker Desktop 进程
  // 不在容器内），Verdict 恒 No，留位即表达顺序。
  let container : ContainerVerdict = No
  let smbios_text = decode(ffi_win_smbios())
  let (smbios_signals, smbios_brands, hvhost) = vm_parse_smbios(smbios_text)
  let cpuid_text = decode(ffi_win_cpuid())
  let (cpuid_signals, cpuid_brands) = vm_parse_cpuid(cpuid_text, hvhost)
  let adapters_text = decode(ffi_win_adapters())
  let (adapter_signals, adapter_brands, _) = vm_parse_adapters(adapters_text)
  for s in smbios_signals {
    signals.push(s)
  }
  for s in cpuid_signals {
    signals.push(s)
  }
  for s in adapter_signals {
    signals.push(s)
  }
  for b in smbios_brands {
    brands.push(b)
  }
  for b in cpuid_brands {
    brands.push(b)
  }
  for b in adapter_brands {
    brands.push(b)
  }
  let vm = vm_verdict_from({ signals, brands, })
  let gpu = gpu_verdict_windows(
    adapters_text,
    ffi_win_dxgi_soft() == 1,
    ffi_win_remote() == 1,
  )
  {
    platform: "windows",
    vm,
    container,
    gpu,
    session: Native,
    desktop: Windows,
    signals,
  }
}

///|
fn collect_linux() -> EnvReport {
  let signals : Array[Signal] = []
  let brands : Array[String] = []
  // 容器臂（systemd 顺序）：OpenVZ → WSL → container 环境变量 → 标记文件 →
  // cgroup → PID namespace inode 兜底
  let mut kind : String? = None
  let vz_exists = linux_exists("/proc/vz")
  let bc_exists = linux_exists("/proc/bc")
  if vz_exists && !bc_exists {
    signals.push({
      name: "proc_vz",
      score: score_decisive,
      detail: "/proc/vz 存在且 /proc/bc 不存在",
    })
    kind = Some("openvz")
  }
  let osrelease = linux_read("/proc/sys/kernel/osrelease")
  if kind is None {
    match container_parse_osrelease(osrelease) {
      Some(k) => {
        signals.push({
          name: "osrelease",
          score: score_decisive,
          detail: "osrelease=\{osrelease.trim().to_owned()}",
        })
        kind = Some(k)
      }
      None => ()
    }
  }
  if kind is None {
    match container_parse_env(@coreenv.get_env_var("container")) {
      Some(k) => {
        signals.push({
          name: "container_env",
          score: score_decisive,
          detail: "container 环境变量=\{k}",
        })
        kind = Some(k)
      }
      None => ()
    }
  }
  if kind is None {
    match
      container_parse_files(
        linux_exists("/.dockerenv"),
        linux_exists("/run/.containerenv"),
      ) {
      Some(k) => {
        signals.push({
          name: "container_marker_file",
          score: score_decisive,
          detail: "标记文件命中 \{k}",
        })
        kind = Some(k)
      }
      None => ()
    }
  }
  if kind is None {
    match container_parse_cgroup(linux_read("/proc/self/cgroup")) {
      Some(k) => {
        signals.push({
          name: "cgroup",
          score: score_strong,
          detail: "cgroup 路径含 \{k}",
        })
        kind = Some(k)
      }
      None => ()
    }
  }
  if kind is None {
    match
      container_parse_pidns(
        decode(ffi_linux_read_link(@utf8.encode("/proc/self/ns/pid"))),
      ) {
      Some(k) => {
        signals.push({
          name: "pid_namespace",
          score: score_strong,
          detail: "PID namespace 非根，管理器未知",
        })
        kind = Some(k)
      }
      None => ()
    }
  }
  let container : ContainerVerdict = container_verdict_from({ signals, kind, })
  // 虚拟机臂：容器内跳过弱信号——限核容器必然触发资源类判据（提案铁律三）。
  // P1 的 Linux VM 信号全为硬信号，照采。
  let cpuinfo_signals = vm_parse_cpuinfo(linux_read("/proc/cpuinfo"))
  let dmi_text = "\{linux_read("/sys/class/dmi/id/sys_vendor")}\n\{linux_read("/sys/class/dmi/id/product_name")}\n\{linux_read("/sys/class/dmi/id/board_vendor")}"
  let (dmi_signals, dmi_brands) = vm_parse_dmi(dmi_text)
  let hypervisor_type = linux_read("/sys/hypervisor/type")
  let (mac_signals, mac_brands) = vm_parse_macs(decode(ffi_linux_net_macs()))
  for s in cpuinfo_signals {
    signals.push(s)
  }
  for s in dmi_signals {
    signals.push(s)
  }
  if hypervisor_type.trim().to_owned() == "xen" {
    signals.push({
      name: "sys_hypervisor",
      score: score_strong,
      detail: "/sys/hypervisor/type = xen",
    })
    brands.push("xen")
  }
  for s in mac_signals {
    signals.push(s)
  }
  for b in dmi_brands {
    brands.push(b)
  }
  for b in mac_brands {
    brands.push(b)
  }
  let vm = vm_verdict_from({ signals, brands, })
  // 会话与桌面臂
  let session = session_parse_linux(
    @coreenv.get_env_var("XDG_SESSION_TYPE"),
    @coreenv.get_env_var("WAYLAND_DISPLAY"),
    @coreenv.get_env_var("SSH_CONNECTION"),
  )
  let desktop = desktop_parse_linux(@coreenv.get_env_var("XDG_CURRENT_DESKTOP"))
  // GPU 臂
  let gpu = gpu_verdict_linux(decode(ffi_linux_render()))
  { platform: "linux", vm, container, gpu, session, desktop, signals, }
}

///|
fn collect_macos() -> EnvReport {
  let signals : Array[Signal] = []
  let brands : Array[String] = []
  let container : ContainerVerdict = No
  let model_text = decode(ffi_mac_model())
  let (model_signals, model_brands) = vm_parse_mac_model(model_text)
  let hvvmm = ffi_mac_hvvmm() == 1
  for s in model_signals {
    signals.push(s)
  }
  for b in model_brands {
    brands.push(b)
  }
  if hvvmm {
    signals.push({
      name: "hv_vmm_present",
      score: score_strong,
      detail: "kern.hv_vmm_present 非 0",
    })
  }
  let vm = vm_verdict_from({ signals, brands, })
  let gpu = gpu_verdict_macos(ffi_mac_metal() == 1)
  {
    platform: "macos",
    vm,
    container,
    gpu,
    session: Native,
    desktop: Macos,
    signals,
  }
}

///|
/// 一次全采环境报告：诊断与展示用。进程级缓存，首查采集、后续直接返回。
pub fn detect() -> EnvReport {
  match report_cache.val {
    Some(r) => r
    None => {
      let r = collect_dispatch()
      report_cache.val = Some(r)
      r
    }
  }
}

///|
/// 是否运行在虚拟机里（P1 口径：任一硬信号命中）。
pub fn is_vm() -> Bool {
  detect().vm is Vm(_)
}

///|
/// VM 品牌串：kvm / qemu / qemu-kvm / vmware / hyperv / vbox / parallels /
/// xen / bhyve / apple-vz / bochs / uml。非虚拟机给 None。
pub fn vm_brand() -> String? {
  match detect().vm {
    Vm(brand) => Some(brand)
    _ => None
  }
}

///|
/// 是否运行在容器里。
pub fn is_container() -> Bool {
  detect().container is Yes(_)
}

///|
/// 容器类型串：docker / podman / wsl / lxc / systemd-nspawn / openvz。
/// 非容器给 None。
pub fn container_kind() -> String? {
  match detect().container {
    Yes(k) => Some(k)
    No => None
  }
}

///|
/// GPU 档位。
pub fn gpu_tier() -> GpuTier {
  detect().gpu.tier
}

///|
/// GPU 判定细节：适配器名或不可用原因。
pub fn gpu_detail() -> String {
  detect().gpu.detail
}

///|
/// 图形会话类型。
pub fn session_kind() -> SessionKind {
  detect().session
}

///|
/// 桌面环境。
pub fn desktop_kind() -> DesktopKind {
  detect().desktop
}
