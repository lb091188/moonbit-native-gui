# 黑客松季度决赛答辩预案

入围通知：11 月 28 日答辩，每人 15 分钟，评委现场提问打分；11 月 23 日发 PPT 模板，11 月 27 日前交 PPT。

## 一句话主线

- 一个桌面 GUI 的执念，在 AI 时代等到了 MoonBit。
- 讲述 7 分钟，问答 8 分钟。
- 讲述结构用 4-3-2-1：四次失败、三个条件、两个问题、一次重写。

## 时间线

| 日期 | 事项 |
|---|---|
| 11-22 日 | 讲述大纲与 Q&A 预案定稿 |
| 11-23 一 | PPT 模板下发 |
| 11-24 二 | 按模板填内容；演示彩排第一轮，录屏备份 |
| 11-25 三 | 口语排练计时，压到 7 分钟内 |
| 11-26 四 | PPT 成稿与视觉检查 |
| 11-27 五 | 提交 PPT，截止 |
| 11-28 六 | 10:00 前到场，下午现场决出一、二等奖 |

## 评分对齐

黑客松官网公布四项评分，每项 25 分：

- 工程深度与实现强度。
- 技术贡献与攻关。
- 生态增量。
- 开发与验证能力。

验收标准里有一条「AI 可解释」：

- 原文：「可以使用 AI 辅助，但目标、路径与质量必须由参赛者掌握。」
- 这条正好是本场叙事的主轴：AI 负责产能，人负责方向与验收。

讲述策略：

- 少讲技术细节，讲清「为什么做、为什么是现在、为什么是 MoonBit」。
- 技术追问留给问答，备弹在附录。
- 评委初赛已看过仓库与文档站，功能清单不再念。
- 「为 AI 而生」讲官方定位加自己的体感，不替官方下定义。

## 故事线：一页看清

| 阶段 | 发生了什么 | 结论 |
|---|---|---|
| 四次失败 | Node 配 libui、Node 配 libyue、Electron、Lua 配 libyue | 缺的不是 GUI 库，是一种足够简单的桌面开发方式 |
| 等语言条件 | AI 还不够、Go 的 GUI 大多要 cgo、Python 慢且不轻、Rust 与 C++ 有难度 | 等的是一个「语言条件」：简单、AI 友好、直通 C |
| 遇到 MoonBit | 教程能写简单程序、官方 skill 让 AI 像写 JS、C FFI 直通 | 三个条件第一次同时成立 |
| 九月第一版 | 以 libyue 为依赖跑通 | 能跑，但原生控件样式不统一、传统范式不够简单 |
| 十月重写 | 去 libyue、去原生控件、系统渲染引擎自绘 | 跨平台统一、零额外依赖；CPU 光栅打底、GPU 可选加速 |
| 前端思维 | 声明式、flexbox、CSS、类 .vue 单文件组件、工具链 | 开发难度向 web 靠 |
| 愿景 | web 的简单加 C++ 与 Rust 的运行 | 给 MoonBit 一条贴近大众电脑的路；信创的第三种可能 |
| AI 时代适配 | 无头开发 MCP、开发 skill、合集 skill | 让 AI 能起应用、看界面、自己验收 |

## 7 分钟讲述大纲

口语稿可直接念。数字只用三个：两个多月、20.6 万行、三平台。

### 0 开场 · 0:20

- 「大家好，我是 NoahLiu。我对桌面 GUI 有执念。」
- 「两个多月前，这个执念只是我反复失败后的一个念头；今天，它是一个 20 万行的跨平台 GUI 框架，能让 MoonBit 写出原生桌面应用。」

### 1 四次失败 · 1:10

- 「离开 Node.js 之后，我一直在找一个写桌面应用的办法。我试过四样东西：Node.js 配 libui、Node.js 配 libyue、Electron、还有 Lua 配 libyue。」
- 「结果是四种熟悉的失望：要么太重、启动慢；要么 Node 的事件循环和界面的消息循环叠在一起，冲突起来很难受；要么能跑，但不好用。」
- 「拿 libyue 来说，它是跨平台 GUI 库，但设计是每个系统用自己的原生控件。Windows 一套、mac 一套、Linux 一套，样式不统一、看起来粗糙；写起来还是传统桌面那一套，能跑，但不简单。」
- 「四次之后我想清楚了：我缺的不是一个 GUI 库，是一种足够简单的桌面开发方式。」

### 2 等语言条件 · 0:45

- 「后来 AI 来了，但我发现还差一块：语言。」
- 「我逐个看过：AI 那时还不够强；Go 的 GUI 库大多要 cgo，构建门槛高；Python 慢、也不够轻；Rust 和 C++ 能到性能，但学习和迭代成本高，对我来说不够简单。」
- 「所以我等的其实是一个语言条件：要简单到我能想清楚整个项目，要适合 AI 帮我写，还要能直接接上 C 和 C++ 的底层。」
- 「而 Go、Rust、Python 都各有自己的桌面方案——MoonBit 还没有自己的桌面位。这就是我要补的位置。」

### 3 遇到 MoonBit · 0:55

- 「然后我遇到了 MoonBit。」
- 「第一，照着基础教程就能写出简单程序；官方把它总结为简单、实用的数据导向设计。」
- 「第二，它有官方的 Agent Skills。AI 照着这套 skill 写 MoonBit，体验就像写 JavaScript 一样顺。」
- 「第三，它和 C 与 C++ 的结合是直通的：主体逻辑用 MoonBit，C 代码只留很少一层，整个项目就好理解、好维护。」
- 「简单、AI 友好、直通 C——三个条件第一次同时成立。我就决定：基于 MoonBit 造一个 GUI 库。」

### 4 九月跑通，十月重写 · 1:20

- 「九月，第一版跑起来了，底层用的是 libyue。能跑，但我不满意，两个问题。」
- 「第一，libyue 是各系统的原生控件，样式不统一，粗糙。第二，它是传统桌面的写法，项目能跑，但不够简单。」
- 「十月国庆，我决定重写：去掉 libyue，去掉系统原生控件，改成用系统渲染引擎自绘控件。这样跨平台样式统一，又不多带一个依赖。」
- 「渲染分两档：基础渲染走 CPU 光栅，虚拟机和低配置电脑也能画出完整界面；有 GPU 的电脑，再开更好的动画和 3D。」
- 「这不是换一层皮，是换了一条路线。10 月 10 日方案定稿，之后整个库按这条路线重搭。」

### 5 前端思维与开发体验 · 0:50

- 「重写之后，我把前端的开发方式搬了过来：声明式、flexbox 布局、基础 CSS 样式对齐，还有类 .vue 的单文件组件——一个文件里写 MoonBit、CSS 和 XML 模板。」
- 「开发工具也按 web 的体验做：安装依赖、新建项目、开发辅助、改代码自动重编译重启、应用打包。libyue 没有的国际化、主题、明暗切换也补上了。」
- 「后面还会做图标生成和国际化数据管理，继续把开发体验往 web 靠。」

### 6 愿景：信创的第三种可能 · 0:50

- 「我做这个库的愿景，一句话：在 MoonBit 的原生后端上，做出一种开发难度像 web、运行接近 C++ 和 Rust 的方式。」
- 「这还有一层现实意义。现在信创市场，桌面应用大多是 Qt 和 GTK 这一套 C++ 的路子。统信的开发者平台主推的就是 Qt 和 GTK，他们自己的 DTK 也是基于 Qt。Electron 太重，Flutter 自带一整套运行时；而信创电脑受制于国产硬件，配置通常不高。这里正好缺一种比 C++ 简单、比 Electron 轻的选择。」
- 「MoonBit 编译成原生，我们的 CPU 光栅能保底跑。这就是我想占的位置。」

### 7 收尾 · 0:20

- 「两个多月前，我是一个反复失败的桌面开发者；今天，我用 MoonBit 造出了我当年想要的那个简单方式。」
- 「执念负责方向，AI 负责产能，MoonBit 负责让产能可信。谢谢。」

## 演示预案

可选 20 到 30 秒，超时直接跳过，不伤主线：

1. `cd examples/hello && moon run --target native`，零配置起窗。
2. 指一眼窗，点开一档子窗，指一下托盘图标。
3. 一句收束：「这就是 `moon run` 之后的样子。」

sysmonitor 的用途：

- 不在 7 分钟主线里放。
- 回答「能复杂到什么程度」时展示或口头带过。

录屏兜底：

- hello 演示录一份 1080p 备用。
- 现场构建超时或拉包失败即切录屏。
- 演示机提前预热 mooncakes 缓存，现场不走网络拉包。

## Q&A 预案

8 分钟大约三到五个问题。个人经历与外部事实分开说。

### 组 A · 执念与四次失败

**A1 你的执念从哪来？**

- 相信桌面软件是程序最终的样子；网页标签不是我要的终点。
- 执念不是怀旧，是相信桌面还有未被满足的需求：快、小、和系统融为一体。

**A2 四次尝试具体失败在哪？**

- Node 配 libui：库简单但能力有限、生态维护弱。
- Node 配 libyue：Yue 用各平台原生控件；Yue 的 FAQ 也说明 Node 下程序阻塞在 `gui.MessageLoop.run()`，两个事件循环叠在一起，使用体验差。
- Electron：官方架构是 Chromium 多进程加 Node.js，界面本质是网页，重。
- Lua 配 libyue：只换了脚本层，底层范式没变。
- 结论：不是缺库，是缺「简单」。

**A3 你说的「简单」标准是什么？**

- 三条：一套代码三平台、一条命令、界面自绘不依赖外部引擎。
- 再加一条：项目能被人完整理解，主体逻辑一种语言，C 代码少。

**A4 为什么不用 Flutter？**

- 先承认 Flutter 成熟：自带 C++ 引擎与 Dart 运行时，跨平台自绘。
- 不选它的原因：它是另一套语言与运行时生态；我的目标是让 MoonBit 生态有桌面，不是再引入一套 Dart 生态。
- 信创低配场景对运行时体积与内存更敏感。

### 组 B · MoonBit 与 AI

**B1 为什么说 MoonBit 为 AI 而生？证据是什么？**

- 官方定位原文：AI 原生编程语言工具链，支持 wasm、wasm-gc、js 与 native 目标。
- 官方 Agent Skills 仓库与 moonbit-agent-guide 已公开发布，安装即用。
- 我的体感三条：简单、AI 写起来顺、C FFI 直通。
- 证据：两个多月 2263 个提交的迭代速度本身。

**B2 AI 写了多少？这些代码你真的都懂吗？★ 最尖锐**

- 分层诚实：
  - 架构与关键路径——渲染管线、布局引擎、平台适配层——设计与验收我自己持有一手。
  - 面广量大的组件层，靠门禁、1684 个用例、199 条真机清单兜底。
  - 「懂」的定义是能定位、能改、能验收，这个闭环我是持有人。
- 反攻点：门禁与测试让「不必逐行背下 20 万行」也能安全持有 20 万行；AI 时代只是把杠杆拉长了。

**B3 怎么保证 AI 代码质量？**

- 三件套：`moon check` 零警告门禁、1684 个库测试、三平台 CI 加本地五腿脚本。
- 真机 199 条用例由人执行回填。

**B4 为什么不用 Rust、Go、Python？**

- 先说清这是当时的判断，不是绝对结论。
- Go：GUI 库大多要 cgo，构建门槛高；MyGo 是 2026-09-26 才创建的，我 9 月 10 日已用 libyue 跑通第一版，选型时它还不存在；今天它做得很好，见下一题。
- Python 慢、也不够轻。
- Rust 的 GUI 生态碎片化：areweguiyet 自己写着「根基不深」，没有共识，也没有成熟易用的全 Rust 方案；编译迭代也慢，对 AI 自纠不友好。
- C++ 的 Qt 与 GTK 能到性能，但门槛高，不满足「简单」。

**B5 现在有 MyGo 了，为什么不用 Go？★ 新增**

- 先划清时间：MyGo 不在我立项时的选项里，是答辩前的参照；这题只回答「现在有了为什么不用」。
- 先承认 MyGo 做得好：2026-09-26 创建，不到两个月 6745 stars，截至 2026-11-23；原生 UI 由自己在 GPU 上画，也支持 webview 混合；flexbox 与 grid、输入法、无障碍、无头测试、打包更新一整套，路线和我几乎同构。
- 时间：它出现时我 9 月 10 日已跑通第一版，十月重写时它才刚起步。
- 路线：MyGo 的「no cgo」指构建期不引入 C 工具链；运行时它用 purego 动态加载系统库、调用 C 与 Objective-C（macOS 走 objc_msgSend，Linux 走 GTK/WebKitGTK，Windows 走 syscall），本身仍走 C ABI。这恰好说明桌面 GUI 绕不开 C。
- 差异：MoonBit native FFI 把直通 C 做成语言一等公民，编译期链接、编译期检查；我要接的不只是系统 UI 库，还有 Cairo、ffmpeg、wgpu 这些 C 库，编译期绑定更合我的取舍。
- 生态位：MyGo 让 Go 生态有了桌面，MoonBit 生态还没有，这是我要补的位。
- 低配：我的基础档明确以 CPU 光栅保底，虚拟机与低配信创机器能跑；MyGo 的原生 UI 走 GPU。这里只说我的取舍，不评价它有没有回退。
- 反守为攻：MyGo 证明「自绘 + web 范式 + 工具链」这条路是对的，也说明窗口期很短；同一个方向在 Go 生态被验证，MoonBit 生态还没有人做。
- 不是首创：purego 2022-05 就有了，Ebitengine 出品；Windows 上 walk 更早用 syscall 调 Win32。但把 purego、GTK/WebKit、Win32、自绘与工具链整合成一个产品，MyGo 是第一个；现有 Go GUI 大多建在 cgo 上，没人有动机推倒重来。
- AI 的角色：不是 AI 想到 purego，是 AI 把三平台整合的成本打下来——58 天 1640 个 PR，提交记录含大量 AI 共同作者。方向由人判断，产能由 AI 放大，这和我的项目是同一种工作方式。

**B6 cgo 和 MoonBit 的 FFI，哪个更简单？★ 新增**

- 先分维度：只比一行调用，cgo 更简单，`import "C"` 就完事；我说的是把 GTK、Cairo、ffmpeg 这些 C 库接成跨三平台 GUI 库的整条链路。
- cgo 的复杂度在边界规则：`import "C"` 是伪包，C 代码写在 preamble；Go 指针传给 C 要固定内存，C 不能留指针；回调要 `//export` 生成头文件；`#cgo` 的编译与链接参数按平台散在文件里；交叉编译默认关闭。这些规则都能学会，但每一层都要人记。
- MoonBit 把 FFI 收进语言与 `moon` 工具链：`extern "c"` 声明、C stub、`native-stub`、`link.native` 在一处配置；`#borrow`/`#owned` 把所有权写进类型；编译期链接，没有 cgo 那层伪包与生成包装。
- AI 维度：cgo 的规则散在 `cmd/cgo` 文档里，AI 容易漏掉指针与生命周期约束；MoonBit 官方 Agent Skills 把这些规则写成了可照着执行的清单。
- 也要承认：两者都要本机 C 工具链，MoonBit native 同样不能交叉编译；我不拿构建矩阵说事。
- 收口：cgo 的简单停在 hello world；MoonBit 的简单是规则集中、显式、AI 可检查，适合一个几十个 C 库的长期项目。

**B7 对 MoonBit 官方有什么诉求？**

- 三条已立项：native 热重载、运行时多模块、native 增量链接。
- 另外希望官方 skill 持续覆盖 native GUI 与桌面场景。

### 组 C · 重写与架构

**C1 九月第一版失败，重写是不是浪费？**

- 第一版验证了可行性，也暴露了范式问题。
- libyue 退出运行时后，行为参考与可平移资产仍保留。
- 这不是推翻，是升级路线：十月方案定稿后按自绘重搭。

**C2 为什么自绘？观感会不会不如原生控件？**

- 自绘换来跨平台一致、主题自由、一套测试面。
- 系统能力仍走各平台原生通道，两不误。
- 「原生控件皮肤」明确不做。

**C3 CPU 光栅会不会慢？**

- 帧成本读数：小脏区三平台全低于 0.5ms；全窗帧 mac 0.8ms、Linux 容器 2ms、win10 虚拟机 27ms。
- 低配场景保底，GPU 可选加速。

**C4 GPU 为什么是可选档？**

- 构建失败降级、运行时探测回退纯光栅。
- 无 GPU 也能跑完整界面；逐像素透明档不走 GPU。

**C5 平台与输入法覆盖？**

- Windows 10 与 11、macOS Apple Silicon、Linux X11 完整 Wayland 有限。
- 输入法三平台各走原生通道：Linux ibus 与 fcitx、Windows TSF、macOS NSTextInputClient。

**C6 现在都有什么？**

- 30+ 组件族、19 种图表、Markdown 与代码视图、终端与编辑器。
- 20+ 系统能力、媒体播放、WebView、GPU 合成、三平台打包与自动更新。

### 组 D · 信创与愿景

**D1 信创市场为什么需要你们？**

- 统信 UOS 开发者平台把 Qt 与 GTK 列为主推开发环境，自有 DTK 也基于 Qt，说明主流路线是 C++ 系。
- Electron 重，Flutter 自带整套运行时。
- 信创整机受国产硬件限制，配置通常不高。
- 缺的正是「比 C++ 简单、比 Electron 轻」的第三种选择。

**D2 为什么不直接绑定 Qt 或 GTK？**

- 绑定只能得到「C 库的皮」，样式与范式仍是传统桌面。
- 自绘加 web 范式才是「简单」。
- 但窗口与系统能力仍走 GTK、X11 等原生通道，Linux 侧明确基于 GTK3。

**D3 国产化适配做了什么，还要做什么？**

- 已做：Linux 基于 GTK3、X11 完整；CPU 光栅保底低配。
- 未做，需诚实：国产 CPU 与信创发行版的真机验证、生态认证、打包适配。
- 话术：这是方向与可能性，不是已经进军的市场。

**D4 开源与商业化怎么打算？**

- MIT 已开源，mooncakes 公开发版。
- 短期不做商业化，先把「简单」做透。

### 组 E · 可信与可持续

**E1 一个人两个多月 20 万行，可信吗？**

- 全部公开可查：仓库 2263 个提交、每个功能一次提交、真机用例记录台在仓内。
- 口径：20.6 万行是剔除构建产物与依赖缓存后的源码。

**E2 可持续吗？**

- 门禁与测试资产本身就是维护杠杆，回归成本低。
- roadmap 按「已规划、已实现」流转，接手者能续上下文。
- 文档站与 llms.txt 让 AI 与人都能接手。

**E3 已知短板是什么？**

- Wayland 支持面有限，X11 完整。
- 媒体硬解 Linux 已通，mac 与 Windows 未接。
- 无障碍的文档视图语义挂载有缺口。
- 模板亚秒热更未到，当前是改码重编译重启。
- Windows GPU 档尺寸变化回退 CPU 路径。
- 话术：短板全部记录在 roadmap，「诚实降级」是本仓工程原则。

**E4 GUI 怎么测？**

- 无头测试加确定性时钟，两会话同推程同读数。
- uitest 门面，观察点没跑即红。
- 三档分工：无头断言归 CI、真窗冒烟归 xvfb、真机清单归人。
- 199 条真机用例配记录台。

**E5 和 libyue、Qt 分别是什么关系？**

- libyue：第一版依赖，现已退出运行时，只作行为参考与资产来源。
- Qt 与 GTK：Linux 的窗口与系统通道，不是界面范式。

### 组 F · 现场与边缘

**F1 现场演示挂了怎么办？**

- 录屏备份、预编译包兜底。
- 口径：「现场环境问题，录屏里是同样操作」。

**F2 「为什么不做 X」类问题？**

- 边界话术：明确不做清单在 roadmap，接口由真实用例驱动，不为对齐而补。
- 不在清单上的当场记下，答辩后回填。

**F3 「AI 可解释」你怎么理解？**

- 目标、路径、质量由我掌握；AI 是产能，不是方向。
- 门禁、测试、真机清单是把关的三个装置。

## 附录 · 技术追问备查

- FFI 内存安全：binding 走 `moonbit.h` 桩，`#borrow` 与 `#owned` 管所有权，原生桩语法门禁进 CI。
- 渲染后端：Linux 走 Cairo；其余平台走纯软件光栅；GPU 是独立可选模块 `gui-gpu`。
- 体积：size-gate 三平台量可执行字节数，增量超上限拦红；hello mac 2.9MB。
- 无障碍：控件语义挂 role 与 name，接 macOS NSAccessibility、Windows UIA、Linux AT-SPI。
- 打包与更新：mac 的 .app 与 DMG、Windows NSIS、Linux AppImage 与 deb；更新链带 SHA256 校验与原子替换。
- 检查器与 MCP：inspector 服务核已合入待真机，`mng mcp` 按 MCP 规范提供 stdio 服务。

## 参考佐证清单

外部参考，按主题分组。每条一句要点，答辩前点开复核一次。

### 桌面框架与架构

1. Yue 项目主页
   - https://github.com/yue/yue
   - 定位是「creating native cross-platform GUI apps」，提供 Node.js、C++、Lua 三种用法。
2. Yue 文档索引
   - http://libyue.com/docs/latest/cpp/
   - Button 标注 Native button，Window 标注 Native window，Browser 标注 Native webview，可证「各系统原生控件」。
3. Yue FAQ
   - http://libyue.com/docs/latest/cpp/guides/faq.html
   - 设计目标第一条是 Uses native widgets；Node 下程序阻塞在 `gui.MessageLoop.run()`。
4. Electron 进程模型
   - https://www.electronjs.org/docs/latest/tutorial/process-model
   - 继承 Chromium 多进程架构；每个窗口加载一个网页；界面用 HTML 与 CSS 与 JavaScript；主进程跑 Node.js。
5. Tauri 官网
   - https://tauri.app/
   - 使用操作系统原生 web 渲染器，体积可小至 600KB；前端 JavaScript、逻辑 Rust，属网页壳路线。
6. Flutter 架构总览
   - https://docs.flutter.dev/resources/architectural-overview
   - C++ 引擎负责光栅化合成，自带 Dart 运行时与各平台嵌入层，属另一套自绘生态。
7. areweguiyet
   - https://areweguiyet.com/
   - 列出五十余个条目，自述「根基不深」、没有共识、缺少成熟易用的全 Rust 方案。

### MoonBit

8. MoonBit 官方文档概览
   - https://docs.moonbitlang.cn/language/index.html
   - 原文：「AI 原生编程语言工具链」，支持 wasm、wasm-gc、js 与 native 目标；「简单且实用的数据导向语言设计」。
9. MoonBit FFI 文档
   - https://docs.moonbitlang.cn/language/ffi.html
   - 五个后端含 C 与 LLVM；native 发布构建走 C 后端；提供 moonbit.h、`#borrow` 与 `#owned` 的生命周期约定。
10. MoonBit 官方 Agent Skills
    - https://github.com/moonbitlang/skills
    - 官方 Agent Skills 仓库，按通用 skill 规范安装，Write once, use everywhere。
11. MoonBit 官方 Agent Guide
    - https://github.com/moonbitlang/moonbit-agent-guide
    - 描述为 SKILLs of MoonBit language and toolchain。
12. MoonBit 官网
    - https://www.moonbitlang.com/
    - 页脚原文：专注于 AI-native general-purpose programming language 的语言、编译器、运行时、IDE 与构建系统。
13. 2026 MoonBit 黑客松官网
    - https://moonbitlang.github.io/Hackathon2026/
    - 主题「用 MoonBit 与 AI，把真实需求做成开源软件」；四项评分各 25 分；验收含「AI 可解释」。

### 信创

14. 统信 UOS 开发者平台
    - https://uosdn.uniontech.com/
    - 开发环境支持明确列出 Qt 与 GTK；DTK 描述为「基于 Qt 开发的通用开发框架」。
15. 麒麟软件官网
    - https://www.kylinos.cn/
    - 国产操作系统厂商与开发者门户入口，可作信创生态背景。
16. 龙芯资料
    - https://en.wikipedia.org/wiki/Loongson
    - 家族规格区间 1 到 8 核、800MHz 到 2.0GHz，可作国产硬件性能背景；最新型号在追赶，引用时说明是家族区间。

### 前端范式与 AI 时代

17. Vue 单文件组件
    - https://vuejs.org/guide/scaling-up/sfc.html
    - SFC 把模板、逻辑、样式封装在一个文件里，正是本仓 .mng 单文件组件的参照。
18. MDN Flexbox
    - https://developer.mozilla.org/en-US/docs/Web/CSS/CSS_flexible_box_layout/Basic_concepts_of_flexbox
    - 一维布局模型，主轴与交叉轴，按容器空间分配，本仓布局语义来源。
19. Model Context Protocol
    - https://modelcontextprotocol.io/
    - 连接 AI 应用与外部系统的开放标准，官方比喻为 AI 应用的 USB-C 口。
20. Vibe coding
    - https://en.wikipedia.org/wiki/Vibe_coding
    - Karpathy 于 2025 年 2 月提出；用自然语言描述任务，由大模型生成代码。

### Go 生态

21. MyGo
    - https://github.com/egoist/mygo
    - 2026-09-26 创建；原生 UI 由自己在 GPU 上绘制，也可嵌 webview；纯 Go 无 cgo（构建期不需要 C 工具链，运行时经 purego 动态绑定系统 C 与 Objective-C 接口）；不到两个月 6745 stars，截至 2026-11-23。
    - 底座 purego 2022-05 创建，Ebitengine 出品；MyGo 58 天 1640 个 PR，提交记录含大量 AI 共同作者。
22. Go cgo 文档
    - https://pkg.go.dev/cmd/cgo
    - cgo 用 `import "C"` 调 C；需 C 编译器，交叉编译默认关闭；Go 指针传递、`//export` 回调、`#cgo` 参数各有规则。

## 仓库内事实锚点

- 2026-09-10 首提交：初始化 libyue 的 MoonBit 封装项目。
- 2026-10-10 提交：MoonBit 原生 GUI 栈方案定稿，明确自绘路线，libyue 退出运行时。
- 2026-10-16 提交：定位统稿为「渲染管线自绘」。
- `docs/reference/roadmap.md`：自绘渲染、Cairo 与软件光栅、GPU 可选、CPU 光栅降级、国际化、主题明暗、检查器 MCP 均在此。
- `examples/hello/hello.mng`：script 写 MoonBit、template 写 XML、style 写 CSS，三段式单文件组件。
- `gui/i18n/`：国际化包已存在。
- `gui/render/`：`raster.mbt` 与 `cairo.mbt` 双后端。
- `modules/gui-gpu/`：GPU 独立可选模块。

## 统一口径表

讲述只用前三个数，其余备查：

| 数字 | 口径 |
|---|---|
| 两个多月 | 2026-09-10 首提交至 2026-11-21 |
| 20.6 万行 | 全仓 MoonBit 源码，剔除构建产物与依赖缓存 |
| 三平台 | Windows 10 与 11、macOS Apple Silicon、Linux X11 完整 Wayland 有限 |
| 2.9MB | hello mac arm64 release strip 二进制 |
| 13.4 万行 | 库本体 gui，其中测试 3.1 万行、1684 个 test 块 |
| 2263 个提交 | 自 2026-09-10 首提交 |
| 199 条 | 真机测试用例 |
| 0.3.3 | 当前 mooncakes 发版 |

## 风险与话术边界

- 个人体感与外部事实分开说：Python 慢、Rust 与 C++ 难，都是当时的个人判断，不是行业定论。
- 不贬低 MyGo：用时间窗口、生态位、C 直通三点解释，先承认它做得好；「Go GUI 不成熟」不再作为绝对判断。
- 「no cgo」不等于「不调 C」：MyGo 运行时经 purego 调用系统 C 与 Objective-C 接口；被问到先讲清这一点，再落到绑定模型差异。
- 不把 MyGo 说成「AI 的产物」或「purego 首创」：准确说法是「整合第一」——路径的砖块是多年积累，AI 放大的是整合与验证的产能。
- 比较 cgo 与 MoonBit 先分维度：单行调用 cgo 更简单，整条绑定链路 MoonBit 更简单；不说「cgo 全面更难」，也不说 MoonBit 能交叉编译。
- 不吹「亚秒热更」：当前是改码自动重编译重启，原位热更在路上。
- 不吹「已进信创市场」：这是方向与可能性，国产 CPU 与发行版真机验证还没做。
- 「为 AI 而生」用官方 AI-native 原文加自己的体感，不替官方下定义。
- 被问倒时诚实承认是已知边界，并指出 roadmap 记录，不现场编造。
- 本文档答辩后删除或归档，不进对外文档站。
