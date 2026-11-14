# 库的无头化收尾：构建期硬前置、探针诚实化与三档分工定档

> **状态**：已核账待拣选。A / B / D / E 四项待拍板立哪几个；C 已在路线图「已规划」单独立项，不进本文施工。
> - 时间：2026-11-13。
> **前置**：[headless-tester.md](headless-tester.md) P1/P2 已落地——本文只写门面之外剩的面，不重复它的内容。
> - 补充：P1/P2 内容为 `gui/uitest` 公开门面 + 虚窗/无头泵/虚拟时钟。
> **起因**：2026-11-13 核账「库的无头化可行性」。结论：测试主链的无头化已经完成，剩余的是**构建期依赖**与**探针诚实度**两块，另有一批「看起来像欠账、其实是分工」的 xvfb 面要定档防止误读。
> - 无头：不开真实图形窗口、在无显示环境运行测试或渲染的方式。
> - xvfb：Linux 的虚拟 X 显示服务，内存里模拟一块屏幕供真窗测试。

## 1. 现状核账：无头化主体已完成

| 面 | 现状 | 证据 |
| --- | --- | --- |
| 库测试套件 | CI Linux 腿 19 包 `moon test` 只包 `dbus-run-session`、**不包 xvfb**；`env -u DISPLAY moon test` 本机复现全绿 | ci.yml:130、experience/adaptation/common.md「CI runner 环境与开发机的差别」节 |
| 公开测试门面 | `gui/uitest` P1 mount/click/pixel 断言 + P2 `Window::virtual_` id<0 哨兵、`App::test_headless` 无头泵 + 确定性虚拟时钟，全部落地 | headless-tester.md |
| 渲染 | cairo 走 `cairo_image_surface` **纯内存**离屏，不碰 X；另有纯 MoonBit 光栅器运行时兜底 | gui/render/painter.mbt:130 |
| 文本测量 | Pango 底座是 fontconfig 文件扫描，无显示可用 | gui/text/stub.c:42 |
| 音视频 | HeadlessAudio / HeadlessVideo 已落 | roadmap「已实现」✅ 条目 |

- dbus-run-session：起一个临时 dbus 会话来跑命令的包装器。
- DISPLAY：X11 的显示地址环境变量，unset 即无显示环境。
- cairo：Linux 常用 2D 绘图库，本库 Linux 腿绘图后端。
- 纯 MoonBit 光栅器：不用任何 C 图形库、直接用 MoonBit 画像素的兜底绘图器。
- fontconfig：Linux 的字体匹配配置系统。
- Pango：Linux 的文本排版库。

**渲染需要 Shell 的只有「开真窗口」一件事**：`session_open → @win.init_backend()`，Linux 上即 `gtk_init_check`。Widget 树画进内存位图，uitest `mount` + `frame()`、全部 wbtest，零 FFI 零窗口，与 Shell 无关——这是已成立的能力，不是提案。
- 取证：gui/win/stub.c:5459。
- Shell：窗口与事件循环的宿主层，`gui/win` 包。
- FFI：跨语言函数调用桥，这里指 MoonBit 调 C。
- uitest：本库公开的无头测试门面，提供挂载控件树、点按与像素断言。
- wbtest：MoonBit 的白盒测试，写在包内、可直接访问内部状态的测试。

## 2. 三档分工定档·无头不替代真机·定案

| 档 | 覆盖 | 归谁 |
| --- | --- | --- |
| ① 无头断言 | wbtest / uitest / 虚拟时钟——数量型、逻辑型判据 | CI 三腿自动跑 |
| ② 平台冒烟 | hello 存活 124、mng 场景、VS Code 场景——「真窗链路通不通」 | xvfb CI 腿 + 本机 |
| ③ 真机人工清单 | 观感、IME、读屏、合成器、托盘通知落系统——「看着对不对」 | 使用者执行，测试用例.md 201 条 + 附录 E/F |

- 冒烟：最基本能不能跑通的一轮快速验证。
- IME：输入法编辑器，输入中日韩等文字的系统组件。
- 读屏：屏幕阅读器，把界面内容念给视障用户的辅助工具。
- 合成器：负责把各窗口像素合成后送上屏幕的显示服务。

- 边界由 `gui/uitest/tester.mbt:12`「虚窗 ≠ 真窗」契约写死：无头档明确不管平台真行为，**不会越界替代③**。
- 口径一句话：**无头 = `moon test` 无 DISPLAY 全绿；xvfb 只留给真窗冒烟；真机清单不变**。无头面向的是可自动化断言面，CI、贡献者裸机、AI 编码代理，观感与平台语义永远归真机。

## 3. 剩余阻隔·按分量排·证据附行号

### 3.1 构建期 GTK 硬前置——Linux 独有的不对称·最大一块

- GTK：Linux 桌面 GUI 工具包，本库 Linux 腿窗口层。
- prebuild 要求 `gtk+-3.0 / pangoft2 / pangocairo / fontconfig / x11 / xext` 六个开发包；缺任一个 → stderr 一行提示后**静默返回空 link_configs** → 构建继续走 → 链接期 undefined symbols，报错误导人。
  - 取证：gui/scripts/prebuild.mbtx:28-30。
  - 取证：prebuild.mbtx:364-378。
  - 开发包：发行版的库头文件与链接描述包，编译 C 程序时才需要。
  - stderr：进程的标准错误输出流。
- 根因：render/text 的 `stub.c` 占位分支只给 Windows/mac——「占位符号保链接 → 运行时探针降级纯光栅」；Linux 上 moon 的 native-stub 把 stub.c 编成**空 TU**，防与 prebuild 真实现归档双定义，符号全靠 prebuild 编的 `.a`。缺开发包时真实现不编、占位也没有 → 符号悬空。
  - 取证：gui/render/stub.c:5 注释。
  - native-stub：moon 工具链编译 C 桩源文件的机制。
  - TU：编译单元，一次 C 编译处理的单个源文件。
  - `.a`：静态归档库，链接期并入可执行文件。
- 后果两层：①真裸容器**连测试二进制都产不出**，「无头 CI 基础镜像」不成立；②使用者机器缺开发包拿到的是天书链接错，而 Windows/mac 同场景是优雅降级。
  - 补充：真裸容器指不装开发包的 docker 镜像。
  - docker：容器技术，用镜像起一个干净隔离的环境。

### 3.2 字体盲区——探针探不出「没字体」

- 没字体时 Pango 量出宽 0 但**仍返回 Some**：`Capabilities.text_measure` 判「有值」探不到；CI 为此专装 `fonts-dejavu-core`。
  - 取证：gui/uitest/tester.mbt:348-355。
  - 取证：ci.yml:39-40 注释原话「runner 上没字体时 Pango 量出的文字宽为 0」。
  - runner：CI 平台分配来执行任务的机器。
- 无内建回退测量器、无内嵌字体，全仓无任何规划条目；ui 层各控件 `unwrap_or(16/18/14)` 常数兜底——布局不崩但尺寸全错。
- 连带口径：`text` 包 wbtest 对 None 是**硬红**、mdview 是 `abort("本平台没有文本测量")`——三平台常态下到不了 None，但 A 落地后裸容器会到，需一并改。
  - 取证：`assert_eq(false, true)`，gui/text/text_wbtest.mbt:28/43。
  - 取证：gui/mdview/markdown_wbtest.mbt:966。

### 3.3 快照基线缺位·已立项·指路不施工

roadmap「已规划」⏳「CPU/GPU 像素对拍与无头像素快照基线」，单独立项。原料已齐：纯 MoonBit PNG 编码器、`Image::from_bitmap`、cairo↔纯光栅对拍已有矩形零容差与路径 16/通道两档。缺比对器工具、基线目录、三平台容差治理。
- 取证：`Image::from_bitmap` 注释点名「离屏快照用」。
- 取证：gui/render/cairo_wbtest.mbt:44-63、94-110。
- 对拍：同一画面用两套实现各画一遍再逐像素比对。

### 3.4 无头档每帧重复 `gtk_init_check`

无头 step 每拍 `drag_external_pump → dragdnd_supported`，Linux 桩惰性 `gtk_init_check` 失败不 memoize——每帧白探一次。不炸不挂，纯性能噪音。
- 取证：gui/widget/app.mbt:1331 → gui/widget/drag.mbt:555。
- 取证：gui/win/stub.c:7335-7337。
- memoize：把第一次计算的结果缓存下来，之后直接复用。

### 3.5 xvfb 三处 = 平台冒烟，不算欠账·定档即可

hello 冒烟 ci.yml:263-274，`xvfb-run` + 124 存活判据；VS Code 场景 ci.yml:183-188；mng 场景 ci.yml:195-201，非门禁。这三处验的正是「真窗/真应用」路径，属第②档，无头化**不该覆盖**——只进 E 的文档定档，不施工。

## 4. 施工方向·待拍板拣选

### A. Linux 占位分支 + prebuild 降级口径

Windows 已有完整先例，占位 → 运行时探针 → 纯光栅，Linux 补齐同款即符合仓库「运行时探针降级」哲学。两条技术路线：

| 路线 | 做法 | 取舍 |
| --- | --- | --- |
| **A1·推荐** | **prebuild 缺包时改编占位 `.a`**：pkg-config 探测失败分支改为——把 stub.c 带**新宏**如 `-DWM_STUB_LINUX_PLACEHOLDER` 编成占位归档，只下发该 `.a`、不下发 GTK/Pango 链接参数；stub.c 补 Linux 占位分支，`cr_*`/`pt_*` 等返 0，native-stub 的「Linux 无宏编空 TU」口径**不动**——三方即真实现 `.a`、native-stub 空 TU、占位 `.a` 永不同场，零撞符号 | 多一个宏、多一支 prebuild 分支；但改动面收敛在 prebuild 判据 + stub.c 分支，不引编译器扩展 |
| A2 | **weak 符号**：native-stub 可见的编译直接出 `__attribute__((weak))` 占位，prebuild 真实现 `.a` 强符号覆盖 | 少一个宏；但引入 attribute 可移植面，且占位永远在链接里，出问题难排查 |

- pkg-config：查询本机已装库的编译与链接参数的工具。
- weak 符号：链接器允许被同名强符号覆盖的弱定义符号。

A 的连带，必做，否则裸容器测试红：

1. `text` wbtest 硬红、mdview abort 改 `guard_text` 计数跳过口径，§3.2 连带；
2. 缺包时 prebuild stderr 提示保留并加「已降级纯光栅/无文本测量」一句——降级要可见，不静默；
3. CI 加「无 GTK 裸镜像跑 `moon test`」腿固化占位路径，低频路径不固化必烂；裸镜像下 `text_measure=false` → guard 跳过口径接上，uitest 既有机制、零新增。

收益：①使用者缺开发包 = 优雅降级 + 明确提示；②真裸容器 CI 可跑全套库测试；③三平台占位形态对称。

### B. `text_measure` 探针升级 + 回退字体单独立项

- 判据从「有值」改「**有值且宽 > 0**」——把「没字体」从假绿变真跳过，守卫语义对齐「探针诚实化」。
  - 取证：gui/uitest/tester.mbt:348-355，一行级。
- 「内嵌字体 / 内建回退测量器」**单独立项**，对无字体的 Linux 真机同样是真收益，不只是测试；B 本项不含它。

### D. dragdnd 探测失败 memoize

`wm_dragdnd_supported` 失败结果也 memoize——无头档每帧一次空探归零。
- 取证：gui/win/stub.c:7335-7337，一行级。

### E. 文档定档批

docs/zh|en build.md 与测试文档补「三档分工」表即本文 §2：无头判据、xvfb 归位平台冒烟、真机清单不变——防「还有 xvfb 是不是没去干净」与「无头要替代真机」两类误读。纯文档。

## 5. 验收·按项

- **A**：无 GTK 裸 docker 镜像 `moon test` 19 包全绿；有开发包机器行为零变化，真实现路径 + cairo↔纯光栅对拍照绿；prebuild 缺包 stderr 有降级提示。
  - 补充：`text_measure=false` 用例按 guard 计数跳过，跳过行可 grep。
- **B**：fontconfig 指向空字体目录时 `Capabilities.text_measure == false`，依赖用例按前缀计数跳过而非假绿。
- **D**：无显示 `moon test uitest` 期间 `gtk_init_check` 每进程至多一次，stub 层计数或日志取证。
- **E**：中英 build.md / 测试文档三档分工表可读，文档站构建 + 索引守卫过。

## 6. 开放问题·待拍板

1. **立哪几项**：A / B / D / E 各自拍板，C 不在此、指 roadmap。
2. **A 技术路线**：A1 prebuild 占位 `.a`，推荐；还是 A2 weak 符号。
3. **A 的连带口径**：text 硬红 / mdview abort → 计数跳过，属测试语义变化，需认可，三平台常态路径不受影响、只有降级路径变。
4. **回退字体**：与 B 同批立项还是后置，推荐后置，B 一行级先落。
