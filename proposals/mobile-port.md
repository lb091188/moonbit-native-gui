# 移动端移植（Android / iOS / 鸿蒙）

把现有这一套（widget / ui / render / text / theme / router / yoga 主体）复用到移动平台的可行性与落地路径。平台差异全部收敛进既有「单一 stub.c 多分支 + prebuild 宏」的桩层，主体代码零改动。

## 定位

- **形态**：原生薄壳（几百行 Kotlin / Swift / ArkTS）+ `libapp.so`（现有一套代码编成）。薄壳只干三件事——交一块画布、转发输入事件、通报生命周期。
- **优先级**：按复用度 iOS > 鸿蒙 > Android（iOS 直接复用 CoreText/ImageIO/Cocoa 分支大半，Android 要自带文字栈）；按趟通程度鸿蒙证据最全（见「社区参照」），第一站选鸿蒙还是 iOS 待定。
- **状态**：方向性提案，未立项。探针清单（见下）出结果前不进 roadmap「已规划」。2026-11-03 完成 MoUI / MoonOHOS / ajni 社区调研，探针一、二据此降级。

## 平台缝替换清单

| 能力 | PC 现状 | iOS | 鸿蒙 | Android |
|---|---|---|---|---|
| 上屏 | GTK / Win32 / Cocoa | `CALayer.contents` 收 RGBA | `XComponent` + `NativeWindow` | `SurfaceView` + `ANativeWindow_lock` |
| 字体匹配 | fontconfig / CoreText / DirectWrite | CoreText（复用） | 系统 `OH_Drawing` 字体栈 | `AFontMatcher`（API 29+，CJK 回退系统管） |
| 字形栅格 + 整形 | 同上 | CoreText（复用） | OH_Drawing（Skia 封装） | FreeType + HarfBuzz（vendor 纯 C 源码） |
| 软键盘 IME | XIM / IMM / NSInput | UIKit 文本协议 | ArkTS 输入框架 | GameTextInput（Google 官方） |
| 帧调度 | `gtk_main_iteration` / `GetMessage` / `postEvent:` | `CADisplayLink` | `XComponent` 回调 | Choreographer 回调驱动现有 `pump()`，`wake()` 走原生唤醒 |

- 上屏通道与桌面同构：`Window::present(rgba, w, h)` 的像素缓冲交给三个新目的地，`ANativeWindow` 的 `RGBA_8888` 与 `Bitmap.data` 逐字节同构。
- 交付形态：moon 出 C → 平台工具链（Xcode / NDK clang / DevEco）编成 `.so` / `.a` / framework。`prebuild.py` 按平台加分支下发工具链参数。

## 需要新增的模型（扩展，不是移植）

1. **生命周期**：桌面「进程常驻、窗口随开随关」→ 移动「系统裁决、onPause/onStop 可杀」。新增挂起/恢复回调，窗口树状态留在 MoonBit 内存，杀进程前的持久化归应用层。
2. **触摸事件**：`InputEvent` 现为鼠标键盘五类码，新增触摸（按下/移动/抬起/多点），手势（滑动/捏合）在其上另建。
3. **移动端 IME**：桌面 `im.mbt` 的经验可参考，协议不可平移，按平台各接一套。
4. **桌面专属能力**（dbus / SNI / 托盘 / 自启动 / 浏览器历史 / 全局快捷键）：移动端无对应，走现成「探测 → 返回不支持 → 调用方降级」惯例，第一批全部降级。

## 体积与性能评估

**体积**：Android 自带依赖 FreeType（0.5~1 MB，裁驱动）+ HarfBuzz（1.5~2 MB）+ GameTextInput（~0.1 MB）合计 2~3 MB；字体文件零自带（系统字库路线，与 PC 一致，避开 CJK 字体 10~20 MB 的大头）。只出 arm64-v8a 时 APK 落在 6~10 MB（`hello` 桌面 exe 7.5 MB 基座），在 Flutter（6~10 MB）/ RN（8~15 MB）的正常区间。

**性能**：管线与 PC 同一条（布局 → 脏区裁剪内光栅 → 整窗 blit），差距只在 SoC 算力：

- 静止时脏窗模型零成本，**零差距**；
- 典型交互（局部刷新、表单、小动画）脏区裁剪把光栅量压小，**体感无差**；
- 最坏情况（全屏滚动/大动画，DPR 3x 像素量）约需 150 Mpix/s 软光栅，旗舰可行、中端机掉帧——**唯一要实测探底的场景**；
- 退路：`Painter` 双后端探针口子接 GPU 后端（鸿蒙 OH_Drawing / iOS Metal），与 `gpu-architecture.md` 的 RenderCtx Gpu 变体是同一个方向；`prof.mbt` 分段账本原样带过去，真机每帧布局/光栅/present 毫秒直接可读。

## 体积与性能的社区对照

MoUI 主线自带 Skia（依赖几十 MB 级），与本仓的对照前提要说清：典型 GUI 负载（自家 prof：1080p 每帧不到 2 ms）我们脏区 + 保留树不落下风；极限负载（全屏复杂路径 + 大文字量 + 3x DPR）Skia 的解析式抗锯齿与字形 atlas 缓存占优，本仓是 4×4 超采样（16 倍采样成本）；双方进 GPU 后趋同（同一层硬件 API），本仓 GPU 走 Layer 1 合成先行、Layer 2 绘制跟上（见 `gpu-architecture.md`）。

## 探针清单（第一步，落 `experiment/`）

1. **Android bionic 运行时**：`moon 出的 C + moonbit.h` 经 NDK clang 编 hello world 跑真机/模拟器——GC 内存策略、线程局部、信号处理。这是三平台仅剩的真未知数：鸿蒙已被 MoUI 真机（runtimeL3 通过）与 MoonOHOS（x86_64 模拟器）双重旁证，iOS 有 MoUI 的 Xcode/模拟器流程，均不再需要本仓自探。
2. **照社区形态搭 moon-出-C 外挂管线**：moon native 出 C → 平台 CMake/工具链收工件 → 平台 IDE/CLI 打包，MoUI（三平台）与 MoonOHOS（OHOS/HAR）已趟通，可行性已证，本仓照走一遍并记版本锚点：NDK 28.2 / minSdk 23；OHOS API 26+ / moonc ≥ 0.10.16；Xcode 15.4+ / iOS 15+。
3. **present + 触摸全链路（Android）**：`ANativeWindow` 连续 blit + JNI 事件回灌 + Android 15 的 16 KB 页对齐。鸿蒙侧不用探，照抄 MoUI 已验路径（XComponent surface 唯一来源、滚轮走 UIInputEvent、剪贴板读走 ArkTS PasteButton）。

## 社区参照（2026-11-03 调研）

- **MoUI（wzzc-dev/MoUI）**：多平台 MoonBit 声明式 GUI（Skia 主线 + Web WebGPU）。鸿蒙 committed 且真机验证（egl-direct 上屏、指针/键盘/IME、剪贴板、ArkUI 无障碍、surface detach/recreate）；Android/iOS experimental（编译过、无真机证据）。对本仓是**路书不是零件**——路线不同（Skia + 声明式管线 vs 本仓 CPU 光栅 + 保留树），但其编译管线形态、版本锚点、真机验证纪律（readiness declaration + `checks/platforms/<平台>.json`，无真机证据不升档，与本仓「真机归用户」规则同构）与鸿蒙实测坑直接可抄。
- **MoonOHOS（shop1111/MoonOHOS）**：MoonBit → 鸿蒙 Native 模块工具链（HAR 形态，ArkTS 管界面、MoonBit 管业务）。可借：`moonohos.native.json` 受控 C 代码携带机制（本仓 stub.c 分支进鸿蒙的现成通道）、`moonohos_ohos` 平台包（hilog / rawfile / task，sys 层鸿蒙对应的起点）、init/build/har/verify/doctor 打包件（鸿蒙批次不自己造 hvigor 集成）。成熟度注记：x86_64 模拟器已验、ARM64 真机未验、0.x 快速迭代，引入需 pin 版本。
- **ajni（Nanaloveyuki/ajni）**：MoonBit 原生 JNI（类型化双向调用、句柄生命周期、Android host adapter、可选 webview 包）。本仓薄壳跨边界面小（事件进、像素出），第一批手写 C 桥不用它；能力面（IME / 剪贴板 / 权限 / Intent）铺开与 `gui-webview` Android 子件批次再评估引入。同为单人 0.x，引入需 pin 版本。

## 里程碑

探针 3 → FreeType/HarfBuzz vendor → `win/text/render` 三包各加 `WM_STUB_ANDROID` 分支 → `examples/hello` 跑上真机 → 触摸/IME/生命周期模型批 → 按同一清单铺下一平台。鸿蒙批次的构建打包借 MoonOHOS 的 HAR 工具链，不自己造 hvigor 集成。每步按流程走 roadmap / TODO 流转。

## 不做什么

- 第一批不做 GPU 后端（CPU 路径先落地，探底不够再启动 `gpu-architecture.md`）。
- 不在移动端保留任何桌面 shell 能力。
- 桌面侧现有构建、测试、门禁一行不改——移动端全部工作发生在新桩分支与壳工程里。
