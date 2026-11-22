// 网卡地址枚举白盒：私网判定与接口偏好纯函数全覆盖；真机读数随环境打印
// 记录，选中值非空必过私网判定。

///|
test "netif_is_rfc1918：三段私网与常见非私网" {
  assert_true(netif_is_rfc1918("10.1.2.3"))
  assert_true(netif_is_rfc1918("192.168.0.35"))
  assert_true(netif_is_rfc1918("172.16.0.1"))
  assert_true(netif_is_rfc1918("172.31.255.255"))
  assert_false(netif_is_rfc1918("172.15.0.1"))
  assert_false(netif_is_rfc1918("172.32.0.1"))
  assert_false(netif_is_rfc1918("198.18.0.1"))
  assert_false(netif_is_rfc1918("127.0.0.1"))
  assert_false(netif_is_rfc1918("8.8.8.8"))
  assert_false(netif_is_rfc1918("169.254.1.1"))
}

///|
test "netif_iface_preferred：物理网卡优先、虚拟嫌疑排后" {
  assert_true(netif_iface_preferred("en0"))
  assert_true(netif_iface_preferred("eth0"))
  assert_true(netif_iface_preferred("wlan0"))
  assert_false(netif_iface_preferred("utun3"))
  assert_false(netif_iface_preferred("tun0"))
  assert_false(netif_iface_preferred("lo0"))
  assert_false(netif_iface_preferred("bridge100"))
  assert_false(netif_iface_preferred("veth0abc"))
}

///|
test "netif：真机枚举读数（结果随环境打印记录）" {
  let all = netif_ipv4_addresses()
  println("netif: \{all.length()} 条 IPv4")
  for (name, ip) in all {
    println("netif: \{name} \{ip}")
  }
  match netif_lan_ip() {
    Some(ip) => {
      println("netif: lan=\{ip}")
      assert_true(netif_is_rfc1918(ip))
    }
    None => println("netif: lan=无候选（无网卡或无私网地址的环境是正常读数）")
  }
}
