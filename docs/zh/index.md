---
layout: home
hero:
  name: native-gui
  text: MoonBit 轻量跨平台桌面 GUI 框架
  tagline: 窗口原生直连、渲染管线自绘、界面组件齐全、系统接口完备。一份 MoonBit 代码直出 Windows 🟩 / Linux 🟩 原生窗口,macOS 🟨 已合入 master(真机验证收口中),moon add 之后零配置。
  actions:
    - theme: brand
      text: 包结构
      link: /zh/README
    - theme: alt
      text: GitHub
      link: https://github.com/lb091188/moonbit-native-gui
features:
  - title: 自绘控件,全平台一套观感
    details: 库自带光栅器绘制每个控件,各平台渲染一致;默认跟随系统强调色与明暗模式,主题就是一个普通值,可整体覆写。
  - title: 声明式 UI 与响应式状态
    details: 界面描述为 @widget.Node 树,mount_window 一步挂载;状态放 Store / Signal,绑定点随数据自动刷新。
  - title: 桌面级系统集成
    details: 托盘、通知、原生菜单、全局快捷键、文件对话框、拖放、剪贴板、开机自启与系统查询,统一在 @sys / @shell 门面之后;系统能力探测页逐项呈现本机实测结果。
  - title: 内容组件开箱即用
    details: 20 种图表含横切交互层、GFM Markdown 视图、多语言代码高亮;内嵌 WebView 与音视频引擎由可选模块 gui-webview / gui-media 提供。
  - title: 如实降级
    details: 每个能力族都带探测,环境不支持时返回结构化 Unsupported / NotFound,不崩溃、不假装成功。
  - title: 只为引入的包付费
    details: 主模块 15 包,没引入的包不进二进制;更重的能力(WebView、音视频)各自成模块,在默认依赖闭包之外。
---

## 快速开始

```sh
moon add NoahLiu/native-gui
```

```moonbit
fn main {
  let app = match @ui.mount_window(
    [@ui.text("Hello, MoonBit!", font_size=18.0)],
    title="Hello, MoonBit!",
    width=400,
    height=300,
  ) {
    None => {
      // 本平台没有窗口后端或没有显示服务
      return
    }
    Some(a) => a
  }
  app.run()
}
```

`@ui.*` 来自 `NoahLiu/native-gui/ui`——完整包表见[文档索引](/zh/README)。
