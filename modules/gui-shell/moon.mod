name = "NoahLiu/gui-shell"

version = "0.1.0"

preferred_target = "native"

description = "native-gui 的集成层单件（能力模块拆分之一）：菜单/热键/托盘/通知/外部打开/单实例六通道统一门面 + 事件泵 + 平台分派（SNI/Win32 运行期选边），与控件树零耦合；i18n 随迁为同模块包"

readme = "README.md"

keywords = [ "shell", "menu", "tray", "notification", "hotkey", "single-instance", "event-loop", "i18n", "desktop", "moonbit" ]

license = "MIT"

repository = "https://github.com/lb091188/moonbit-native-gui"

import {
  "NoahLiu/gui-window@0.1.0",
  "NoahLiu/gui-sys@0.1.0",
  "NoahLiu/gui-dbus@0.1.0",
}
