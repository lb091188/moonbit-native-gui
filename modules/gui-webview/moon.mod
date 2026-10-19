name = "NoahLiu/gui-webview"
version = "0.2.0"
preferred_target = "native"

description = "native-gui 的 WebView 扩展（独立模块）：内嵌系统 WebView（WebKitGTK / WebView2 / WKWebView），vendor 资产与链接参数由本模块 prebuild 自管，对主模块消费者保持「模块级可选」"

readme = "README.md"

keywords = [ "webview", "webkit", "webview2", "browser", "gui" ]

license = "MIT"

repository = "https://github.com/lb091188/moonbit-native-gui"

import {
  "NoahLiu/native-gui@0.2.0",
  "NoahLiu/yoga-mbt@0.1.1",
}

options(
  "--moonbit-unstable-prebuild": "prebuild.py",
)
