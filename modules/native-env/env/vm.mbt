// 虚拟机判定臂：采集层读原始串，解析层纯函数出信号——解析层离线可测。
// 判据出处 experience/environment-detection.md「虚拟机检测」节。

///|
/// 平台无关的 VM 信号集与品牌归属：解析层输出，判定层消费。
#derive(Debug)
struct VmCollected {
  signals : Array[Signal]
  /// 命中硬信号（score >= 100）的品牌，按命中顺序
  brands : Array[String]
}

///|
/// 解析 Windows CPUID 两行输出：`hv=<0|1>` 与 `sig=<签名串>`。
/// hvhost 为真时 hypervisor 位与 Microsoft Hv 签名串不计分——Windows 宿主
/// 装了 Hyper-V 角色这两者也置位，裸机误报头号来源（提案特判铁律一）。
fn vm_parse_cpuid(
  text : String,
  hvhost : Bool,
) -> (Array[Signal], Array[String]) {
  let signals : Array[Signal] = []
  let brands : Array[String] = []
  let mut hv = false
  let mut sig = ""
  for line in split_lines(text) {
    match kv_value(line, "hv") {
      Some(v) => hv = v == "1"
      None => ()
    }
    match kv_value(line, "sig") {
      Some(v) => sig = v.trim().to_owned()
      None => ()
    }
  }
  if hv && !hvhost {
    signals.push({
      name: "cpuid_hypervisor_bit",
      score: score_strong,
      detail: "ECX bit 31 = 1",
    })
  }
  if sig != "" {
    match brand_by_contains(sig, hypervisor_signatures) {
      Some(brand) =>
        // Hyper-V 宿主：Microsoft Hv 签名串同样不计分
        if !(hvhost && brand == "hyperv") {
          let is_ms = brand == "hyperv"
          signals.push({
            name: "cpuid_hypervisor_signature",
            score: score_decisive,
            detail: if is_ms {
              sig
            } else {
              "签名串命中 \{brand}"
            },
          })
          brands.push(brand)
        }
      None =>
        if hv && !hvhost {
          signals.push({
            name: "cpuid_hypervisor_signature",
            score: score_weak,
            detail: "hypervisor 置位但签名串未收录：\{sig}",
          })
        }
    }
  }
  (signals, brands)
}

///|
/// 解析 Windows SMBIOS 三行输出：`man=` / `prod=` / `hvhost=`。注册表镜像
/// 在虚拟机固件上常整个为空——空是常态不是错误（windows.md 2026-10-28 实测）。
fn vm_parse_smbios(text : String) -> (Array[Signal], Array[String], Bool) {
  let signals : Array[Signal] = []
  let brands : Array[String] = []
  let mut hvhost = false
  let mut man = ""
  let mut prod = ""
  for line in split_lines(text) {
    match kv_value(line, "man") {
      Some(v) => man = v
      None => ()
    }
    match kv_value(line, "prod") {
      Some(v) => prod = v
      None => ()
    }
    match kv_value(line, "hvhost") {
      Some(v) => hvhost = v == "1"
      None => ()
    }
  }
  for hay in [man, prod] {
    if hay != "" {
      match brand_by_contains(hay, dmi_vendor_table) {
        Some(brand) => {
          signals.push({
            name: "smbios_vendor",
            score: score_registry,
            detail: "\{hay} → \{brand}",
          })
          brands.push(brand)
        }
        None => ()
      }
    }
  }
  (signals, brands, hvhost)
}

///|
/// 解析 Windows 适配器名列表：虚拟关键词命中即信号，带品牌猜测。
/// 关键词表出自 gui/win l1_on_virtual_gpu 并加宽；QXL 与 Red Hat、Virtio
/// 归 qemu-kvm 家族。
fn vm_parse_adapters(text : String) -> (Array[Signal], Array[String], String?) {
  let signals : Array[Signal] = []
  let brands : Array[String] = []
  let mut hit : String? = None
  for line in split_lines(text) {
    if hit is Some(_) {
      continue
    }
    for kw in virtual_gpu_keywords {
      if contains_ci(line, kw) {
        let brand : String = match kw {
          "VMware" => "vmware"
          "QEMU" | "QXL" | "Red Hat" | "Virtio" => "qemu-kvm"
          "VBox" => "vbox"
          "Hyper-V" => "hyperv"
          "Parallels" => "parallels"
          _ => ""
        }
        signals.push({
          name: "adapter_name",
          score: score_strong,
          detail: "\{line}（关键词 \{kw}）",
        })
        if brand != "" {
          brands.push(brand)
        }
        hit = Some(line)
        break
      }
    }
  }
  (signals, brands, hit)
}

///|
/// 解析 Linux /proc/cpuinfo：hypervisor 标志行即信号。
fn vm_parse_cpuinfo(text : String) -> Array[Signal] {
  if contains_ci(text, "hypervisor") {
    [
      {
        name: "cpuinfo_hypervisor_flag",
        score: score_strong,
        detail: "/proc/cpuinfo 含 hypervisor 标志",
      },
    ]
  } else {
    []
  }
}

///|
/// 解析 Linux DMI 厂商串（sys_vendor / product_name / board_vendor 拼接）。
fn vm_parse_dmi(text : String) -> (Array[Signal], Array[String]) {
  let signals : Array[Signal] = []
  let brands : Array[String] = []
  for line in split_lines(text) {
    match brand_by_contains(line, dmi_vendor_table) {
      Some(brand) => {
        signals.push({
          name: "dmi_vendor",
          score: score_strong,
          detail: "\{line} → \{brand}",
        })
        brands.push(brand)
      }
      None => ()
    }
  }
  (signals, brands)
}

///|
/// 解析 Linux MAC 地址候选列表（一行一个，已小写），前缀表命中即信号。
fn vm_parse_macs(text : String) -> (Array[Signal], Array[String]) {
  let signals : Array[Signal] = []
  let brands : Array[String] = []
  for line in split_lines(text) {
    let mac = line.to_lower()
    match brand_by_prefix(mac, mac_prefix_table) {
      Some(brand) => {
        signals.push({
          name: "mac_oui",
          score: score_registry,
          detail: "\{mac} → \{brand}",
        })
        brands.push(brand)
      }
      None => ()
    }
  }
  (signals, brands)
}

///|
/// 解析 macOS hw.model：真机串含 Mac（MacBookPro16,1）；虚拟机是 VMware7,1
/// 或 MacVirtualMachine,1（Apple VZ）。
fn vm_parse_mac_model(text : String) -> (Array[Signal], Array[String]) {
  let signals : Array[Signal] = []
  let brands : Array[String] = []
  if text == "" {
    return (signals, brands)
  }
  if contains_ci(text, "VirtualMachine") {
    signals.push({
      name: "mac_model",
      score: score_strong,
      detail: "hw.model=\{text}（Apple VZ 客户机）",
    })
    brands.push("apple-vz")
  } else if contains_ci(text, "VMware") {
    signals.push({
      name: "mac_model",
      score: score_strong,
      detail: "hw.model=\{text}",
    })
    brands.push("vmware")
  } else if !contains_ci(text, "Mac") {
    signals.push({
      name: "mac_model",
      score: score_strong,
      detail: "hw.model=\{text} 不含 Mac",
    })
  }
  (signals, brands)
}

///|
/// VM 结论判定（P1 简单口径：任一硬信号命中即 VM）。
fn vm_verdict_from(collected : VmCollected) -> VmVerdict {
  let mut hard_brand : String? = None
  for s in collected.signals {
    if s.score >= score_strong {
      match hard_brand {
        Some(_) => ()
        None =>
          // 硬信号的品牌优先；适配器名等无品牌硬信号取弱信号品牌兜底
          if collected.brands.length() > 0 {
            hard_brand = Some(collected.brands[0])
          }
      }
    }
  }
  let has_hard = collected.signals.iter().any(s => s.score >= score_strong)
  if has_hard {
    Vm(hard_brand.unwrap_or("vm"))
  } else if collected.signals.length() > 0 {
    Unknown
  } else {
    BareMetal
  }
}
