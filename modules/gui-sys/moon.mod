name = "NoahLiu/gui-sys"

version = "0.1.0"

preferred_target = "native"

description = "native-gui 的系统工具单件（独立模块，能力模块拆分之一）：纯读写系统面——剪贴板、自启动、壁纸、打印机、音量、电源、显示器、空闲检测、浏览器与编辑器历史等；无窗口、无事件循环，任何进程可调"

readme = "README.md"

keywords = [ "system", "clipboard", "autostart", "wallpaper", "printer", "volume", "power", "history", "idle", "monitor", "moonbit", "desktop" ]

license = "MIT"

repository = "https://github.com/lb091188/moonbit-native-gui"

import {
  "prowk/moonsqlitefile@0.8.0",
}

options(
  homepage: "https://github.com/lb091188/moonbit-native-gui",
  "--moonbit-unstable-prebuild": "prebuild.py",
)
