name = "NoahLiu/gui-window"

version = "0.1.0"

preferred_target = "native"

description = "native-gui 的窗口层单件（能力模块拆分之一）：窗口与事件循环、surface 贴屏、拖放、IME、任务栏、托盘（Win32 半边）、通知、全局热键、单实例、文件对话框——全套桌面窗口能力，事件循环寄生型"

readme = "README.md"

keywords = [ "window", "tray", "notification", "hotkey", "ime", "single-instance", "taskbar", "dialog", "drag-drop", "desktop", "moonbit", "gui" ]

license = "MIT"

repository = "https://github.com/lb091188/moonbit-native-gui"

options(
  homepage: "https://github.com/lb091188/moonbit-native-gui",
  "--moonbit-unstable-prebuild": "prebuild.py",
)
