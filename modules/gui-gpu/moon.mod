name = "NoahLiu/gui-gpu"
version = "0.1.0"
preferred_target = "native"

description = "native-gui 的 GPU 扩展（独立模块，GPU 对主模块消费者保持「模块级可选」）：wgpu-native 运行期装载探测、X11 三角形探针、present 合成地基，以及 @render.GpuSink 的实现（GpuCanvas，GPU 线首消费者）"

readme = "README.md"

keywords = [ "gpu", "wgpu", "graphics", "gui" ]

license = "MIT"

repository = "https://github.com/lb091188/moonbit-native-gui"

import {
  "NoahLiu/native-gui@0.3.3",
  "NoahLiu/yoga-mbt@0.1.1",
}

options(
  "--moonbit-unstable-prebuild": "scripts/prebuild.mbtx",
)
