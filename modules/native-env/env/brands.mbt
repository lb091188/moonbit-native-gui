// 品牌表与信号分值：判据出处 experience/environment-detection.md；分值按
// 提案 P2 口径四档定死（决定性 150 / 强 100 / 中 40-70 / 弱 10-35）。

///|
/// hypervisor CPUID 签名串到品牌：出处 systemd virt.c 的签名串表。
let hypervisor_signatures : Array[(String, String)] = [
  ("KVMKVMKVM", "kvm"),
  ("Linux KVM Hv", "kvm"),
  ("TCGTCGTCGTCG", "qemu"),
  ("VMwareVMware", "vmware"),
  ("Microsoft Hv", "hyperv"),
  ("XenVMMXenVMM", "xen"),
  ("VBoxVBoxVBox", "vbox"),
  ("prl hyperv", "parallels"),
  ("bhyve bhyve", "bhyve"),
  ("QNXQVMBSQG", "qemu"),
  ("ACRNACRNACRN", "kvm"),
  ("Apple VZ", "apple-vz"),
]

///|
/// 显示适配器名关键词：出处 gui/win/stub.c 的 l1_on_virtual_gpu 关键词表，
/// 直通与嵌套虚拟化下 hypervisor 位可能不可见，适配器名是兜底信号。中文系
/// Windows 的基础适配器名是「Microsoft 基本显示适配器」，补两个中文关键词。
let virtual_gpu_keywords : Array[String] = [
  "Virtual", "VMware", "QEMU", "QXL", "Red Hat", "VBox", "Hyper-V", "Parallels",
  "Virtio", "Basic Render", "Basic Display", "Microsoft Basic",
  "基本显示", "基本渲染",
]

///|
/// Linux DMI 厂商串到品牌：systemd detect_vm_dmi_vendor 同款全表。
let dmi_vendor_table : Array[(String, String)] = [
  ("KVM", "kvm"),
  ("OpenStack", "kvm"),
  ("KubeVirt", "kvm"),
  ("Alibaba Cloud ECS", "kvm"),
  ("Amazon EC2", "kvm"),
  ("QEMU", "qemu"),
  ("VMware", "vmware"),
  ("VMW", "vmware"),
  ("innotek GmbH", "vbox"),
  ("VirtualBox", "vbox"),
  ("Oracle Corporation", "vbox"),
  ("Xen", "xen"),
  ("Bochs", "bochs"),
  ("Parallels", "parallels"),
  ("BHYVE", "bhyve"),
  ("Hyper-V", "hyperv"),
  ("Apple Virtualization", "apple-vz"),
  ("Google Compute Engine", "kvm"),
]

///|
/// MAC 地址前缀到品牌：al-khaser 清单与 VMAware MAC 实现。
let mac_prefix_table : Array[(String, String)] = [
  ("08:00:27", "vbox"),
  ("00:05:69", "vmware"),
  ("00:0c:29", "vmware"),
  ("00:1c:14", "vmware"),
  ("00:50:56", "vmware"),
  ("52:54:00", "qemu"),
  ("00:15:5d", "hyperv"),
  ("00:1c:42", "parallels"),
  ("00:16:3e", "xen"),
]

///|
/// 信号分值四档（提案 P2 口径）。
let score_decisive : Int32 = 150

///|
let score_strong : Int32 = 100

///|
let score_registry : Int32 = 60

///|
let score_weak : Int32 = 20

///|
/// 在表中找首个子串命中的项，返回品牌。hay 大小写不敏感匹配。
fn brand_by_contains(hay : String, table : Array[(String, String)]) -> String? {
  for entry in table {
    if contains_ci(hay, entry.0) {
      return Some(entry.1)
    }
  }
  None
}

///|
/// 在表中找首个前缀命中的项，返回品牌。needle 需已小写化。
fn brand_by_prefix(needle : String, table : Array[(String, String)]) -> String? {
  for entry in table {
    if needle.has_prefix(entry.0) {
      return Some(entry.1)
    }
  }
  None
}
