# 窗口级系统材质：背景模糊的可行性调研与 API 边界

> **状态**：调研稿，未立项。
> - 时间：2026-11-20。
> - 范围：只做平台探针与公开 API 边界，不改实现。
> - 目标：回答「窗口背后的桌面或下层窗口能否由系统合成器糊掉，以及三平台各自能承诺到什么程度」。
> - 不碰：控件级 `backdrop_blur`、大面积 GPU blur、桌面截屏自绘模糊。

## 〇、结论速览

- **有方向记录，没有立项**：2026-11-18 的视觉能力定案只写了一句「窗口级系统材质走 WM 通道」，见 `experience/adaptation/common.md:2195`。
- **控件级 `backdrop_blur` 已落地，但它不是窗口背景模糊**：它只糊本窗口内已经画好的像素，糊不到桌面或下层窗口。
- **三平台能力不对称**：mac 最可行，Windows 11 可落，Windows 10 依赖未公开接口，Linux 只有 KDE X11 一档可试，其余只能诚实降级。
- **建议 v1 只承诺一个语义**：窗口背后的实时模糊；平台各自映射到最接近的原生材质，不承诺像素一致，也不承诺模糊核是严格高斯。
- **先跑 S1 与 S2 两个探针，再决定是否进路线图**；探针完成前不写实现。

## 一、现状核账

| 面 | 现状 | 证据 |
| --- | --- | --- |
| 控件级背景模糊 | 已实现：`backdrop_blur` 在控件自绘前把窗口内已画区域糊掉 | `gui/render/painter.mbt:724`、`docs/reference/roadmap.md:137` |
| 旧 `glass` 组件 | 2026-10-20 整条下线：旧实现读回的是本窗口位图，糊不到窗口外 | `experience/adaptation/common.md:1539` |
| 大面积实时模糊 | 方向记录：走后端 GPU 通道，另立提案 | `experience/adaptation/common.md:2195` |
| 窗口级系统材质 | 只有一句方向记录：mac `NSVisualEffectView`、Windows DWM Acrylic、Linux 无标准诚实降级 | `experience/adaptation/common.md:2195` |
| 本仓代码 | 全仓检索 `NSVisualEffectView`、`DwmEnableBlurBehindWindow`、`SetWindowCompositionAttribute`、`_KDE_NET_WM_BLUR_BEHIND_REGION` 均零命中 | 本仓检索 |
| 窗口透明底座 | 已有 `set_transparent_bg`、逐像素命中、GPU 档互斥与页面底让位 | `gui/win/window.mbt:145`、`gui/widget/app.mbt:418` |

结论：**系统级窗口背景模糊没有 proposal、没有路线图条目、没有 TODO、没有代码**。本文件补的是「是否值得立项」的前置调研。

## 二、语义边界

### 2.1 三种「模糊」不能混用一个 API

| 名称 | 糊的是什么 | 谁执行 | 现状 |
| --- | --- | --- | --- |
| 控件级 `backdrop_blur` | 本窗口内、控件矩形之下已经画好的像素 | 本库 CPU 光栅 | ✅ 已落地 |
| 大面积实时 blur | 本窗口内大块内容 | 本库 GPU 通道 | ⏳ 方向记录 |
| 窗口级系统材质 | 窗口背后的桌面或下层窗口 | 系统合成器 / DWM | ❌ 未立项 |

- 窗口级系统材质：让系统把窗口背后的内容糊掉，再和本窗口的透明像素合成。
- 合成器：桌面里负责把各窗口画面叠成最终屏幕的组件；mac 是 WindowServer，Windows 是 DWM，Linux 是 KWin 这类合成器。
- 这三种能力可以叠加，但不能互相替代。

### 2.2 与现有透明底的关系

- 系统材质要求窗口有透明区域；现有 `Window::set_transparent_bg` 是前置。
- 材质的可见范围等于窗口内未被不透明内容覆盖的区域；不透明页面底会整块盖住它。
- 系统材质是合成器成本，4K 全屏下可能明显；默认关闭，按需开启。
- Windows 的透明底前置无边框，见 `gui/win/stub.c:1452`。
- mac 开透明底会摘掉 GPU L1，见 `gui/win/stub.c:10482` 与 `gui/win/stub.c:10704`。
- Windows 逐像素透明档同样不走 GPU L1，见 `gui/win/stub.c:1542`。
- GTK 建窗时就选 32 位 RGBA visual，见 `gui/win/stub.c:5764`。

因此首版系统材质大概率**走 CPU 光栅路径**：透明档与 GPU present 在现有实现里互斥。这与「极致光栅」方向一致，但意味着应用不能同时要系统材质与 GPU 上屏。

### 2.3 页面底必须让位

宿主默认会铺满 `bg_page`，见 `gui/widget/app.mbt:47` 与 `gui/widget/app.mbt:291`。系统材质要看得见，必须让这层底退场，否则模糊被不透明页面色整块盖住。现有 `WindowHost::set_transparent_bg` 已经在做这件事，见 `gui/widget/app.mbt:418`。

## 三、平台通道与风险矩阵

| 平台 | 通道 | 系统门槛 | 可承诺 | 主要风险 |
| --- | --- | --- | --- | --- |
| macOS | `NSVisualEffectView`，`blendingMode = BehindWindow` | macOS 10.14+ | 窗口背后的实时模糊与系统材质 | 需要窗口非不透明、背景 clear；与 `CAMetalLayer` 是否共存未核 |
| Windows 11 | `DWMWA_SYSTEMBACKDROP_TYPE` | Windows 11 22621+ | `DWMSBT_TRANSIENTWINDOW` 为实时 Acrylic；`DWMSBT_MAINWINDOW` 为壁纸取样的 Mica | 与 layered window、ULW、GPU swapchain 的兼容未核 |
| Windows 10 | `SetWindowCompositionAttribute` 的 `ACCENT_ENABLE_ACRYLICBLURBEHIND` | Windows 10 1803+ | Acrylic 实时模糊 | 未公开接口，可能随版本失效；拖动掉帧口碑 |
| Linux KDE X11 | `_KDE_NET_WM_BLUR_BEHIND_REGION` | KWin 合成开启 | 窗口区域背后的模糊 | KDE 私有属性，非标准；GNOME 无对应入口 |
| Linux KDE Wayland | KWin 私有 blur 协议 | 未核 | 未核 | 需要独立 Wayland 客户端；本仓 `gui/wayland` 只有 wire 地基 |
| GNOME | 无公开 per-window blur 入口 | — | 诚实降级 | 只能 Unsupported，不做扩展依赖 |
| 其他 Linux 桌面 | 无跨 DE 标准 | — | 诚实降级 | XFCE、Cinnamon、MATE 不承诺 |

术语：

- Acrylic：Windows 的实时背景模糊加色调，会跟着窗口后面的内容变。
- Mica：Windows 11 的静态材质，取桌面壁纸做底，不是实时模糊下层窗口。
- Vibrancy：macOS 的系统材质，由 `NSVisualEffectView` 提供。
- DWM：Windows 的桌面窗口管理器，负责窗口合成。
- KWin：KDE Plasma 的窗口管理器与合成器。

证据级别：

- macOS 与 Windows 11 的 API 名称属官方公开面。
- Windows 10 的 `SetWindowCompositionAttribute` 属未公开接口，只能按实测收口。
- Linux 的 KDE 属性属桌面私有约定，版本差异未核。

## 四、API 边界

### 4.1 对外只开一个语义

建议 v1 只暴露：

```text
WindowBackdrop
  None
  Blur
```

- `Blur` 的语义是「窗口背后的实时模糊」，不承诺具体模糊核、不承诺三平台观感一致。
- 不把 `Mica` 与 `Acrylic` 直接做进跨平台枚举：它们是 Windows 平台差异，不是跨平台语义。将来有真实用例，再加独立档。
- 不在 `Style` 里开 `window_blur`：这是窗口级能力，不是控件样式。

### 4.2 建议的公开面

```text
Window::set_backdrop(WindowBackdrop) -> Result[Unit, WindowShellError]
Window::shell_caps() -> WindowShellCaps
  backdrop_blur : Bool

WindowHost::set_backdrop(WindowBackdrop) -> Result[Unit, WindowShellError]
```

- `WindowHost` 门面负责 `transparent_bg` 与 `page_fill` 的让位与恢复。
- `Window` 层只做平台调用与能力判断；它不自动改透明底，前置不满足返回 `Failed`。
- 新增能力位建议用 `wm_shell_caps` 的下一位，占位后端恒 false。
- 具体命名可在立项时再定；`set_backdrop` 与控件级 `backdrop_blur` 共用「backdrop」词根，但层级不同，文档要写清。

### 4.3 行为契约

- 开启成功：`WindowHost` 进入透明档，`page_fill` 让位，系统材质可见。
- `Window::set_backdrop` 要求调用方已经开好透明底；未开时返回 `Failed(原因)`，不擅自改窗口形态。
- 关闭成功：摘掉材质，恢复开启前的 `page_fill` 状态。
- 平台不支持：返回 `Err(Unsupported)`，不改 `page_fill`，也不改透明底。
- 前置不满足：返回 `Err(Failed(原因))`。Windows 未无边框时提示先 `set_borderless(true)`。
- 不自动改无边框：边框是应用外观的一部分，库不替调用方决定。
- 与 `set_opacity` 正交：整窗 alpha 与系统材质可叠加，但观感与性能要真机验。
- 与 `set_click_through` 正交：透明区域可点穿，材质是否还可见要真机验。
- 只承诺整窗材质，不做局部窗口材质；局部毛玻璃继续用控件级 `backdrop_blur`。

### 4.4 与 GPU 档的关系

- 首版不承诺「系统材质 + GPU L1」同时生效；现有透明档已经与 GPU 互斥。
- 若应用先开 GPU 再开材质，平台层按透明档处理，GPU 档让位；是否打一行诊断由立项时定。
- 若未来要两者共存，需单独验证 mac 的 `CAMetalLayer` 与 `NSVisualEffectView`、Windows 的 swapchain 与 DWM backdrop。

## 五、探针清单

探针只写真机读数，不改库 API。每个探针用最小独立程序或临时分支，结论回写 `experience/adaptation/`。

| # | 验什么 | 在哪验 | 判据 |
| --- | --- | --- | --- |
| S1 | mac `NSVisualEffectView` 能否在现有自绘窗后面出模糊 | macOS 真机 | 桌面透出且被糊；本窗内容不被糊；点击、缩放、全屏、多屏拖动正常；开「减少透明度」时能降级 |
| S2 | Windows 11 DWM backdrop 与无边框、ULW、GPU L1 的兼容 | Windows 11 真机 | Acrylic 实时模糊可见；Mica 与 Acrylic 语义可区分；layered 档不冲突；拖窗不卡死 |
| S3 | Windows 10 未公开 Acrylic 接口的可用性 | Windows 10 真机 | 能开、能关、不崩；拖动与缩放可接受；不可用时必须 Unsupported |
| S4 | KDE X11 的 blur-behind region 是否对 GTK 窗生效 | KDE Plasma X11 真机 | 窗口区背后被糊；KWin 关闭模糊效果时降级；GNOME 同场应 Unsupported |
| S5 | Wayland 侧是否有可用的 per-window blur 协议 | KDE Wayland / wlroots 真机 | 给出协议是否存在与版本；不存在则记边界，不排实现 |
| S6 | 开关状态机与页面底恢复 | 三平台 | 开→关后 `page_fill` 恢复原值；失败不动状态；重复开关幂等 |

S1 与 S2 是立项门槛；S3/S4 是加分项；S5 只做记录，不承诺。

### 5.1 探针形态

- S1 mac：50 行 Objective-C 小程序，`NSWindow` + `NSVisualEffectView` + 自绘 `NSView`；或在 `gui/win/stub.c` 的 `WM_STUB_MAC` 分支临时加一个 `wm_probe_material`，用完撤。
  - 关键调用：`[effect setBlendingMode:NSVisualEffectBlendingModeBehindWindow]`、`[effect setMaterial:NSVisualEffectMaterialUnderWindowBackground]`、`[win setOpaque:NO]`、`[win setBackgroundColor:[NSColor clearColor]]`。
  - 要看：效果视图在内容视图之后、窗口矩形之外、缩放后与全屏后的几何。
- S2 Windows 11：独立 Win32 探针，`CreateWindowExW` 无边框窗 + `DwmSetWindowAttribute(hwnd, DWMWA_SYSTEMBACKDROP_TYPE, ...)`。
  - 两组对照：`WS_EX_LAYERED` 开与关；`UpdateLayeredWindow` 提交与不提交。
  - 三种档位：`DWMSBT_TRANSIENTWINDOW` 的 Acrylic、`DWMSBT_MAINWINDOW` 的 Mica、`DWMSBT_NONE` 的关闭。
- S3 Windows 10：同一探针加 `SetWindowCompositionAttribute` 与 `ACCENT_ENABLE_ACRYLICBLURBEHIND`。
  - 看拖动、缩放、最大化、任务栏切换的帧率与闪烁。
- S4 KDE X11：先用 `xprop` 给任一 GTK 窗设属性，确认 KWin 的模糊效果开着。
  - 命令形态：`xprop -id <wid> -f _KDE_NET_WM_BLUR_BEHIND_REGION 32c -set _KDE_NET_WM_BLUR_BEHIND_REGION "0,0,<w>,<h>"`。
  - 属性生效后再看窗口透明区背后是否被糊；不生效就改走临时 GTK 桩里的 `XChangeProperty`。
- S5 Wayland：用 `wayland-info` 看会话里有没有 KWin 私有 blur 协议或 wlroots 系的背景效果协议。
  - 只记录协议名与版本，不排实现。
- S6 状态机：在探针程序里做开→关→再开、失败后再调、透明底未开先调三种序列，记录 `page_fill` 与窗口外观。

## 六、验收口径

- 探针通过的标准是「真机肉眼可见背景被糊，且窗口交互不退化」，不是单元测试。
- 三平台各自记录：能不能糊、糊的是什么、性能读数、系统设置关闭时的降级行为。
- 若只有 mac 与 Windows 11 通过：v1 承诺这两档；Windows 10 与 Linux 记「尽力而为」；GNOME 与其他桌面明确 Unsupported。
- 若 mac 或 Windows 11 任一不通过：不立项，只留 `experience/adaptation/` 记录。
- 立项后再进路线图「已规划」，再写 `TODO.md`；不在探针前写实现。

## 七、明确不做

- 桌面截屏加自绘模糊：隐私、性能与权限都不可接受，且不是系统材质。
- 把窗口材质塞进 `Style`：它是窗口级能力，不是控件样式。
- 局部窗口材质：需要多原生视图或多窗口，超出首版边界。
- 窗口圆角与阴影：系统材质可能自带圆角，与无边框窗、自绘内容的关系待探针；首版不承诺。
- Linux 跨 DE 统一材质：没有标准，不做假承诺。
- 承诺严格高斯核：系统材质由平台决定，观感以原生为准。
- 与 GPU L1 同时承诺：首版不做，未来单独立项。

## 八、开放问题

- v1 是否只支持无边框窗？
- 是否允许系统材质与 GPU L1 同时开启？
- 是否把 Mica 与 Acrylic 作为平台提示暴露给高级用户？
- 是否自动跟随系统「减少透明度」设置降级？
- API 命名用 `set_backdrop`、`set_window_material` 还是 `set_background_blur`？
- Windows 10 的未公开接口是否值得维护，还是只做 Windows 11？

## 九、建议顺序

1. S1 mac 探针：验证 `NSVisualEffectView` 与现有自绘窗、透明档、点击命中的关系。
2. S2 Windows 11 探针：验证 DWM backdrop 与无边框、ULW、GPU L1 的关系。
3. 两项都过，再定 API 名称与能力位，补无头白盒与真机清单。
4. S3 Windows 10、S4 KDE X11 作为尽力而为档。
5. S5 Wayland 只记录，不排实现。
