// GPU 档判定臂：回答「敢不敢走 GPU 档」而不是「有没有显卡」。
// 判据出处 experience/environment-detection.md「无 GPU 加速检测」节。

///|
/// 解析 Windows 适配器名列表加 DXGI 软件旗标，出 GPU 结论。
/// 判定顺序：DXGI 软件旗标（系统显式标注，最硬）→ 适配器名虚拟关键词 →
/// 远程会话 → 适配器存在性。
fn gpu_verdict_windows(
  adapters_text : String,
  dxgi_soft : Bool,
  remote : Bool,
) -> GpuVerdict {
  if dxgi_soft {
    return {
      tier: Software,
      detail: "DXGI 软件适配器旗标置位——Microsoft 基本渲染",
    }
  }
  let mut virtual_hit : String? = None
  for line in split_lines(adapters_text) {
    for kw in virtual_gpu_keywords {
      if contains_ci(line, kw) {
        virtual_hit = Some(line)
        break
      }
    }
    if virtual_hit is Some(_) {
      break
    }
  }
  match virtual_hit {
    Some(name) => return { tier: Virtual, detail: "虚拟显卡：\{name}", }
    None => ()
  }
  if remote {
    return {
      tier: Software,
      detail: "远程桌面会话，硬件加速通路受限",
    }
  }
  let adapters = split_lines(adapters_text)
  if adapters.length() > 0 {
    { tier: Hardware, detail: adapters[0], }
  } else {
    { tier: GpuNone, detail: "枚举不到贴桌面的显示适配器", }
  }
}

///|
/// Linux 软渲染 DRM 驱动清单：这些驱动建出的渲染节点不代表硬件加速。
let linux_soft_drivers : Array[String] = [
  "vkms", // 虚拟 KMS，内核测试用虚拟屏
   "vgem", // 虚拟 GEM，内存态假显卡
   "hyperv_drm", // Hyper-V 虚拟帧缓冲
   "simpledrm", // 固件帧缓冲，无加速
]

///|
/// Linux 虚拟厂商 PCI vendor 值：virtio / QEMU（Red Hat） / VMware / Bochs。
let linux_virtual_vendors : Array[String] = [
  "0x1af4", "0x1b36", "0x15ad", "0x1234",
]

///|
/// 解析 Linux 渲染节点探测四行输出，出 GPU 结论。WSL2 的 /dev/dxg 是 GPU
/// 半虚拟化通路——有 3D 但驱动特殊，归 Virtual。
fn gpu_verdict_linux(render_text : String) -> GpuVerdict {
  let mut open = false
  let mut vendor = ""
  let mut driver = ""
  let mut dxg = false
  for line in split_lines(render_text) {
    match kv_value(line, "open") {
      Some(v) => open = v == "1"
      None => ()
    }
    match kv_value(line, "vendor") {
      Some(v) => vendor = v.trim().to_owned()
      None => ()
    }
    match kv_value(line, "driver") {
      Some(v) => driver = v
      None => ()
    }
    match kv_value(line, "dxg") {
      Some(v) => dxg = v == "1"
      None => ()
    }
  }
  if dxg {
    return {
      tier: Virtual,
      detail: "WSL2 GPU 半虚拟化通路（/dev/dxg）",
    }
  }
  if !open {
    return {
      tier: Software,
      detail: "无 /dev/dri/renderD128 渲染节点，走 CPU 软渲染",
    }
  }
  for v in linux_soft_drivers {
    if driver == v {
      return { tier: Software, detail: "软渲染 DRM 驱动 \{driver}", }
    }
  }
  for v in linux_virtual_vendors {
    if vendor == v {
      return {
        tier: Virtual,
        detail: "虚拟显卡 vendor \{vendor} driver \{driver}",
      }
    }
  }
  { tier: Hardware, detail: "渲染节点可用 driver \{driver}", }
}

///|
/// 解析 macOS Metal 设备存在性，出 GPU 结论。虚拟机里的 Parallels、VMware
/// 正常提供 Metal，不按「虚拟机即无 GPU」处理。
fn gpu_verdict_macos(metal : Bool) -> GpuVerdict {
  if metal {
    { tier: Hardware, detail: "Metal 默认设备可用", }
  } else {
    {
      tier: GpuNone,
      detail: "Metal 默认设备取不到——headless 或无 GPU 通路",
    }
  }
}
