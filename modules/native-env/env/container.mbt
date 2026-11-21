// 容器判定臂：systemd detect_container 同款顺序——OpenVZ → WSL → container
// 环境变量 → 标记文件 → cgroup → PID namespace inode 兜底。全部免 root。
// 判据出处 experience/environment-detection.md「容器检测」节。

///|
/// 根 PID namespace 的 inode 号：内核 3.8 起固定 0xEFFFFFFC，不等于它即处
/// 于某个 PID namespace（systemd running_in_pidns 同款判据）。
let root_pid_ns_inode : String = "4026531836"

///|
#derive(Debug)
struct ContainerCollected {
  signals : Array[Signal]
  kind : String?
}

///|
/// 解析 /proc/sys/kernel/osrelease：含 Microsoft 或 WSL 即 WSL 环境——
/// 微软官方认可的判定方式（microsoft/WSL#423）。
fn container_parse_osrelease(text : String) -> String? {
  if contains_ci(text, "Microsoft") || contains_ci(text, "WSL") {
    Some("wsl")
  } else {
    None
  }
}

///|
/// 解析 container 环境变量：容器运行时注入，值即品牌；oci 不是具体管理器，
/// 按 systemd 口径回落标记文件判定，返回 None。
fn container_parse_env(value : String?) -> String? {
  match value {
    Some(v) => {
      let t = v.trim().to_owned()
      if t == "" || t == "oci" {
        None
      } else {
        Some(t)
      }
    }
    None => None
  }
}

///|
/// 标记文件判定：/.dockerenv → docker，/run/.containerenv → podman。
/// systemd 特意把文件判定放在其它判定之后——镜像里误带 /.dockerenv 的情
/// 形不再抢先（moby#18355）。
fn container_parse_files(dockerenv : Bool, containerenv : Bool) -> String? {
  if dockerenv {
    Some("docker")
  } else if containerenv {
    Some("podman")
  } else {
    None
  }
}

///|
/// 解析 cgroup 文本：路径段含 docker / kubepods / lxc / openvz 即信号。
/// cgroup v2 统一层级下路径常只剩根，判据失效——命中算数，未命中不排除。
fn container_parse_cgroup(text : String) -> String? {
  let t = text.to_lower()
  for kw in ["docker", "kubepods", "lxc", "openvz"] {
    if t.contains(kw) {
      return match kw {
        "kubepods" => Some("docker")
        _ => Some(kw)
      }
    }
  }
  None
}

///|
/// 解析 /proc/self/ns/pid 的 readlink 输出（形如 `pid:[4026531836]`）：
/// inode 不等于根 namespace 的固定值即处于某个容器，管理器未知。
fn container_parse_pidns(link : String) -> String? {
  let t = link.trim().to_owned()
  let prefix = "pid:["
  if !t.has_prefix(prefix) {
    return None
  }
  let inner = t[prefix.length():]
  if !inner.has_suffix("]") {
    return None
  }
  let inode = inner[:inner.length() - 1].to_owned()
  if inode == root_pid_ns_inode {
    None
  } else {
    Some("container")
  }
}

///|
/// 汇总容器采集：按固定顺序取首个命中为 kind，信号全量保留。
fn container_verdict_from(collected : ContainerCollected) -> ContainerVerdict {
  match collected.kind {
    Some(k) => Yes(k)
    None => No
  }
}
