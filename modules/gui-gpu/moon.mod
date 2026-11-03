name = "NoahLiu/gui-gpu"
version = "0.1.0"
preferred_target = "native"

description = "native-gui 的 GPU 扩展（独立模块，GPU 对主模块消费者保持「模块级可选」）：wgpu-native 运行期装载探测与后续 present 合成的地基"

readme = "README.md"

keywords = [ "gpu", "wgpu", "graphics", "gui" ]

license = "MIT"

repository = "https://github.com/lb091188/moonbit-native-gui"

options(
  "--moonbit-unstable-prebuild": "prebuild.py",
)
