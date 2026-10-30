name = "NoahLiu/native-gui"

version = "0.3.0"

preferred_target = "native"

description = "MoonBit 跨平台桌面 GUI 框架：一套代码直出 Windows / Linux / macOS 原生窗口，托盘/通知/快捷键/输入法/自启等系统能力开箱即用，moon add 后零配置"

readme = "README.md"

keywords = [ "gui", "desktop", "native", "cross-platform", "moonbit" ]

license = "MIT"

repository = "https://github.com/lb091188/moonbit-native-gui"

import {
  "NoahLiu/yoga-mbt@0.1.1",
  "NoahLiu/mdparse@0.1.0",
  "prowk/moonsqlitefile@0.8.0",
}

options(
  homepage: "https://github.com/lb091188/moonbit-native-gui",
  "--moonbit-unstable-prebuild": "scripts/prebuild.py",
)
