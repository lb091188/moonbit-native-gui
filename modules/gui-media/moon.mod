name = "NoahLiu/gui-media"
version = "0.1.0"
preferred_target = "native"

description = "native-gui 的媒体扩展（独立模块，媒体对主模块消费者保持「模块级可选」）：media/ 提供 ffmpeg 解码 + miniaudio 输出的引擎与播放器组件"

readme = "README.md"

keywords = [ "media", "audio", "video", "player", "gui" ]

license = "MIT"

repository = "https://github.com/lb091188/moonbit-native-gui"

import {
  "NoahLiu/native-gui@0.1.2",
  "NoahLiu/ffmpeg-mbt@0.1.0",
  "NoahLiu/yoga-mbt@0.1.1",
}

options(
  "--moonbit-unstable-prebuild": "prebuild.py",
)
