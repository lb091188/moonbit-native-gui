name = "NoahLiu/gui-dbus"

version = "0.1.0"

preferred_target = "native"

description = "native-gui 的 D-Bus 单件（能力模块拆分之一）：纯 MoonBit 线路实现 + 会话/系统总线——托盘 SNI Linux 半边、通知、MPRIS、UPower、NetworkManager、logind、单实例；只依赖 gui-sys"

readme = "README.md"

keywords = [ "dbus", "sni", "tray", "notification", "mpris", "upower", "networkmanager", "logind", "linux", "moonbit" ]

license = "MIT"

repository = "https://github.com/lb091188/moonbit-native-gui"

import {
  "NoahLiu/gui-sys@0.1.0",
}
