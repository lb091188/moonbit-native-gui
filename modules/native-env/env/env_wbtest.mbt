// 离线白盒测试：解析层是纯函数，构造输入直接断言——不依赖真机环境。
// 真机矩阵按 TODO 条目由用户执行。

///|
test "vm_parse_cpuid：签名串决定性命中" {
  let (signals, brands) = vm_parse_cpuid("hv=1\nsig=KVMKVMKVM", false)
  inspect(signals.length(), content="2")
  inspect(signals[0].name, content="cpuid_hypervisor_bit")
  inspect(signals[1].score, content="150")
  debug_inspect(
    brands,
    content=(
      #|["kvm"]
    ),
  )
}

///|
test "vm_parse_cpuid：Hyper-V 宿主特判——位与 Microsoft Hv 签名串都不计分" {
  let (signals, brands) = vm_parse_cpuid("hv=1\nsig=Microsoft Hv", true)
  inspect(signals.length(), content="0")
  inspect(brands.length(), content="0")
}

///|
test "vm_parse_cpuid：位非宿主未收录签名串给弱信号" {
  let (signals, brands) = vm_parse_cpuid("hv=1\nsig=Foo Bar", false)
  inspect(signals.length(), content="2")
  inspect(signals[1].score, content="20")
  inspect(brands.length(), content="0")
}

///|
test "vm_parse_cpuid：裸机零信号" {
  let (signals, brands) = vm_parse_cpuid("hv=0\nsig=", false)
  inspect(signals.length(), content="0")
  inspect(brands.length(), content="0")
}

///|
test "vm_parse_smbios：QEMU 厂商串注册表级命中" {
  let (signals, brands, hvhost) = vm_parse_smbios(
    "man=QEMU\nprod=Standard PC (Q35 + ICH9, 2009)\nhvhost=0",
  )
  inspect(
    signals.length(),
    content=(
      #|1
    ),
  )
  inspect(signals[0].score, content="60")
  debug_inspect(
    brands,
    content=(
      #|["qemu"]
    ),
  )
  inspect(hvhost, content="false")
}

///|
test "vm_parse_smbios：空镜像零信号——虚拟机固件不给表是常态" {
  let (signals, _, hvhost) = vm_parse_smbios("man=\nprod=\nhvhost=0")
  inspect(signals.length(), content="0")
  inspect(hvhost, content="false")
}

///|
test "vm_parse_adapters：QXL 关键词命中带 qemu-kvm 品牌猜测" {
  let (signals, brands, hit) = vm_parse_adapters(
    "QXL (Red Hat)\n基本显示适配器",
  )
  inspect(signals.length(), content="1")
  inspect(signals[0].name, content="adapter_name")
  debug_inspect(
    brands,
    content=(
      #|["qemu-kvm"]
    ),
  )
  debug_inspect(hit, content="Some(\"QXL (Red Hat)\")")
}

///|
test "vm_parse_adapters：真显卡零信号" {
  let (signals, brands, hit) = vm_parse_adapters("NVIDIA GeForce RTX 4070")
  inspect(signals.length(), content="0")
  inspect(brands.length(), content="0")
  debug_inspect(hit, content="None")
}

///|
test "vm_parse_cpuinfo：hypervisor 标志行" {
  let signals = vm_parse_cpuinfo("flags: fpu hypervisor mmx")
  inspect(signals.length(), content="1")
  inspect(signals[0].score, content="100")
}

///|
test "vm_parse_dmi：systemd 同款厂商串表" {
  let (signals, brands) = vm_parse_dmi("QEMU\nStandard PC")
  inspect(signals.length(), content="1")
  debug_inspect(
    brands,
    content=(
      #|["qemu"]
    ),
  )
  let (signals2, brands2) = vm_parse_dmi("innotek GmbH\nVirtualBox")
  inspect(signals2.length(), content="2")
  debug_inspect(
    brands2,
    content=(
      #|["vbox", "vbox"]
    ),
  )
}

///|
test "vm_parse_macs：QEMU 默认 MAC 前缀 52:54:00" {
  let (signals, brands) = vm_parse_macs("52:54:00:12:34:56")
  inspect(signals.length(), content="1")
  inspect(signals[0].score, content="60")
  debug_inspect(
    brands,
    content=(
      #|["qemu"]
    ),
  )
}

///|
test "vm_parse_mac_model：三种形态" {
  let (s1, b1) = vm_parse_mac_model("MacBookPro16,1")
  inspect(s1.length(), content="0")
  debug_inspect(b1.length(), content="0")
  let (_, b2) = vm_parse_mac_model("MacVirtualMachine,1")
  debug_inspect(
    b2,
    content=(
      #|["apple-vz"]
    ),
  )
  let (_, b3) = vm_parse_mac_model("VMware7,1")
  debug_inspect(
    b3,
    content=(
      #|["vmware"]
    ),
  )
  let (s4, _) = vm_parse_mac_model("Amiga4000")
  debug_inspect(s4.length(), content="1")
}

///|
test "vm_verdict_from：三态结论" {
  // 硬信号带品牌 → Vm
  let hard : VmCollected = {
    signals: [
      { name: "cpuid_hypervisor_signature", score: 150, detail: "kvm", },
    ],
    brands: ["kvm"],
  }
  debug_inspect(vm_verdict_from(hard), content="Vm(\"kvm\")")
  // 只有弱信号 → Unknown
  let weak : VmCollected = {
    signals: [{ name: "mac_oui", score: 60, detail: "", }],
    brands: ["qemu"],
  }
  debug_inspect(vm_verdict_from(weak), content="Unknown")
  // 零信号 → BareMetal
  let none : VmCollected = { signals: [], brands: [], }
  debug_inspect(vm_verdict_from(none), content="BareMetal")
  // 硬信号无品牌 → 通用串
  let hard_nobrand : VmCollected = {
    signals: [{ name: "hv_vmm_present", score: 100, detail: "", }],
    brands: [],
  }
  debug_inspect(vm_verdict_from(hard_nobrand), content="Vm(\"vm\")")
}

///|
test "container_parse_osrelease：WSL 内核串" {
  debug_inspect(
    container_parse_osrelease("5.15.167.4-microsoft-standard-WSL2"),
    content="Some(\"wsl\")",
  )
  debug_inspect(container_parse_osrelease("6.12.8-arch1-1"), content="None")
}

///|
test "container_parse_env：oci 回落文件判定" {
  debug_inspect(container_parse_env(Some("docker")), content="Some(\"docker\")")
  debug_inspect(container_parse_env(Some("oci")), content="None")
  debug_inspect(container_parse_env(Some("")), content="None")
  debug_inspect(container_parse_env(None), content="None")
}

///|
test "container_parse_files：dockerenv 优先于 containerenv" {
  debug_inspect(container_parse_files(true, false), content="Some(\"docker\")")
  debug_inspect(container_parse_files(false, true), content="Some(\"podman\")")
  debug_inspect(container_parse_files(false, false), content="None")
  debug_inspect(container_parse_files(true, true), content="Some(\"docker\")")
}

///|
test "container_parse_cgroup：路径段命中" {
  debug_inspect(
    container_parse_cgroup("12:pids:/docker/abc123"),
    content="Some(\"docker\")",
  )
  debug_inspect(
    container_parse_cgroup("0::/kubepods/burstable/pod xyz"),
    content="Some(\"docker\")",
  )
  debug_inspect(container_parse_cgroup("0::/"), content="None")
}

///|
test "container_parse_pidns：根 inode 与非根" {
  debug_inspect(container_parse_pidns("pid:[4026531836]"), content="None")
  debug_inspect(
    container_parse_pidns("pid:[4026532456]"),
    content="Some(\"container\")",
  )
  debug_inspect(container_parse_pidns("pid:[junk"), content="None")
}

///|
test "gpu_verdict_windows：四档齐测" {
  // DXGI 软件旗标最硬，压过关键词
  let soft = gpu_verdict_windows("Microsoft 基本渲染适配器", true, false, false)
  debug_inspect(soft.tier, content="Software")
  // 虚拟显卡关键词
  let virt = gpu_verdict_windows("QXL (Red Hat)", false, false, false)
  debug_inspect(virt.tier, content="Virtual")
  inspect(virt.detail, content="虚拟显卡：QXL (Red Hat)")
  // 远程会话
  let remote = gpu_verdict_windows("NVIDIA GeForce RTX 4070", false, true, false)
  debug_inspect(remote.tier, content="Software")
  // 真显卡
  let hw = gpu_verdict_windows("NVIDIA GeForce RTX 4070", false, false, false)
  debug_inspect(hw.tier, content="Hardware")
  // 无适配器
  let none = gpu_verdict_windows("", false, false, false)
  debug_inspect(none.tier, content="GpuNone")
}

///|
test "gpu_verdict_windows：VM 保险——认不出的适配器至多 Virtual" {
  // VM 硬信号命中 + 适配器名不在关键词表 → 不给 Hardware
  let capped = gpu_verdict_windows("未知厂商虚拟卡 XYZ", false, false, true)
  debug_inspect(capped.tier, content="Virtual")
  // VM 命中但枚举不到适配器仍 GpuNone——诚实报无通路
  let none_vm = gpu_verdict_windows("", false, false, true)
  debug_inspect(none_vm.tier, content="GpuNone")
  // 非 VM 机器上同一适配器维持 Hardware
  let hw = gpu_verdict_windows("未知厂商虚拟卡 XYZ", false, false, false)
  debug_inspect(hw.tier, content="Hardware")
  // 中文系 Windows 的基本适配器名命中关键词
  let zh = gpu_verdict_windows("Microsoft 基本显示适配器", false, false, false)
  debug_inspect(zh.tier, content="Virtual")
}

///|
test "gpu_verdict_linux：渲染节点五形态" {
  // WSL2 半虚拟化
  let dxg = gpu_verdict_linux("open=1\nvendor=\ndriver=\ndxg=1")
  debug_inspect(dxg.tier, content="Virtual")
  // 无渲染节点
  let no_node = gpu_verdict_linux("open=0\nvendor=\ndriver=\ndxg=0")
  debug_inspect(no_node.tier, content="Software")
  // 软渲染 DRM 驱动
  let soft = gpu_verdict_linux("open=1\nvendor=0x0000\ndriver=vkms\ndxg=0")
  debug_inspect(soft.tier, content="Software")
  // 虚拟厂商
  let virt = gpu_verdict_linux(
    "open=1\nvendor=0x1af4\ndriver=virtio_gpu\ndxg=0",
  )
  debug_inspect(virt.tier, content="Virtual")
  // 真硬件
  let hw = gpu_verdict_linux("open=1\nvendor=0x10de\ndriver=nvidia\ndxg=0")
  debug_inspect(hw.tier, content="Hardware")
}

///|
test "gpu_verdict_macos" {
  debug_inspect(gpu_verdict_macos(true).tier, content="Hardware")
  debug_inspect(gpu_verdict_macos(false).tier, content="GpuNone")
}

///|
test "session_parse_linux：判据链" {
  debug_inspect(session_parse_linux(Some("x11"), None, None), content="X11")
  debug_inspect(
    session_parse_linux(Some("wayland"), None, None),
    content="Wayland",
  )
  debug_inspect(session_parse_linux(Some("tty"), None, None), content="Tty")
  // XDG_SESSION_TYPE 未写时回落 WAYLAND_DISPLAY
  debug_inspect(
    session_parse_linux(None, Some("wayland-0"), None),
    content="Wayland",
  )
  // 再回落 SSH_CONNECTION
  debug_inspect(
    session_parse_linux(None, None, Some("10.0.0.1 54321 10.0.0.2 22")),
    content="Tty",
  )
  // 全缺
  debug_inspect(session_parse_linux(None, None, None), content="UnknownSession")
}

///|
test "desktop_parse_linux：冒号多值取首个可识别段" {
  debug_inspect(desktop_parse_linux(Some("ubuntu:GNOME")), content="Gnome")
  debug_inspect(desktop_parse_linux(Some("KDE")), content="Kde")
  debug_inspect(desktop_parse_linux(Some("X-Cinnamon")), content="Cinnamon")
  debug_inspect(
    desktop_parse_linux(Some("UNKNOWN_DE")),
    content="UnknownDesktop",
  )
  debug_inspect(desktop_parse_linux(None), content="UnknownDesktop")
}

///|
test "辅助函数：kv_value 与 split_lines" {
  debug_inspect(kv_value("open=1", "open"), content="Some(\"1\")")
  debug_inspect(kv_value("open=1", "vendor"), content="None")
  debug_inspect(kv_value("sig=KVM", "sig"), content="Some(\"KVM\")")
  inspect(split_lines("a\n\nb\n").length(), content="2")
  inspect(contains_ci("VMware7,1", "vmware"), content="true")
}

///|
test "品牌表：签名串与 MAC 前缀全表可命中" {
  // 抽查 systemd 签名串表的关键项
  debug_inspect(
    brand_by_contains("TCGTCGTCGTCG", hypervisor_signatures),
    content="Some(\"qemu\")",
  )
  debug_inspect(
    brand_by_contains("XenVMMXenVMM", hypervisor_signatures),
    content="Some(\"xen\")",
  )
  debug_inspect(
    brand_by_contains("bhyve bhyve ", hypervisor_signatures),
    content="Some(\"bhyve\")",
  )
  debug_inspect(
    brand_by_contains("Apple VZ", hypervisor_signatures),
    content="Some(\"apple-vz\")",
  )
  // MAC 前缀表按小写前缀匹配
  debug_inspect(
    brand_by_prefix("00:50:56:a1:b2:c3", mac_prefix_table),
    content="Some(\"vmware\")",
  )
  debug_inspect(
    brand_by_prefix("00:15:5d:11:22:33", mac_prefix_table),
    content="Some(\"hyperv\")",
  )
  debug_inspect(
    brand_by_prefix("ac:de:48:00:11:22", mac_prefix_table),
    content="None",
  )
}
