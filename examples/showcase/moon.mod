name = "showcase"

version = "0.1.0"

preferred_target = "native"

description = "native-gui 模板应用（.mng 单文件组件 + mng dev/build）"

license = "MIT"

import {
  "NoahLiu/native-gui@0.3.3",
  "NoahLiu/yoga-mbt@0.1.1",
}

// 版本是兜底值：不在 native-gui workspace 内生成时读不到现读版本，
// 按你锁定的发布版改这两行。
