// 网卡地址枚举（netif）：getifaddrs 的跨平台门面。私网过滤与接口偏好
// 在这里做——UDP connect 出口技巧在代理 TUN 接管默认路由时会拿到
// 198.18.x 假地址，枚举 + RFC1918 过滤不受路由影响。

///|
#borrow(ok)
extern "c" fn ffi_netif_list(ok : Ref[Int32]) -> Bytes = "yue_sys_netif_list"

///|
/// 全部 IPv4 网卡地址：(接口名, 地址)，getifaddrs 顺序。回环接口的
/// 127.x 也如实给出（消费方按需过滤）；枚举失败给空表。
pub fn netif_ipv4_addresses() -> Array[(String, String)] {
  let ok = Ref(0)
  let raw = ffi_netif_list(ok)
  if ok.val != 1 {
    return []
  }
  let out : Array[(String, String)] = []
  for ln in @utf8.decode_lossy(raw).split("\n") {
    let ln = ln.to_owned()
    if ln.length() == 0 {
      continue
    }
    match ln.find(" ") {
      Some(i) => out.push((ln[:i].to_owned(), ln[i + 1:].to_owned()))
      None => ()
    }
  }
  out
}

///|
/// RFC1918 私网段判定：10/8、172.16/12、192.168/16。回环与 198.18/15
/// 基准段（代理 TUN 常用）都不在其列。
fn netif_is_rfc1918(ip : String) -> Bool {
  if ip.has_prefix("10.") || ip.has_prefix("192.168.") {
    return true
  }
  if !ip.has_prefix("172.") {
    return false
  }
  // 172.16 ～ 172.31：第二段是 16~31 才算
  match (ip[4:]).find(".") {
    Some(i) => {
      let second = @string.parse_int(ip[4 : 4 + i]) catch {
        _ => -1
      }
      second >= 16 && second <= 31
    }
    None => false
  }
}

///|
/// 物理网卡偏好：utun/tun/tap/lo/veth/bridge/docker/ztl 开头的按虚拟或
/// 回环嫌疑排后，其余（en* / eth* / wlan* 等）优先。
fn netif_iface_preferred(name : String) -> Bool {
  let suspects = [
    "utun", "tun", "tap", "lo", "veth", "bridge", "docker", "vbr", "ztl",
  ]
  for p in suspects {
    if name.has_prefix(p) {
      return false
    }
  }
  true
}

///|
/// 挑一个局域网可达的私网地址：物理网卡优先、虚拟网卡兜底，同层取首个；
/// 无候选给 None。多网卡并存时取枚举序里第一条物理网卡私网地址。
pub fn netif_lan_ip() -> String? {
  let mut fallback : String? = None
  for (name, ip) in netif_ipv4_addresses() {
    if !netif_is_rfc1918(ip) {
      continue
    }
    if netif_iface_preferred(name) {
      return Some(ip)
    }
    if fallback is None {
      fallback = Some(ip)
    }
  }
  fallback
}
