# TODO — 当前进行中的工作

> 只记「待做什么 + 怎么验证」；规划与未来批次见 [docs/reference/roadmap.md](docs/reference/roadmap.md)「已规划」，实测坑与口径见 [experience/adaptation/index.md](experience/adaptation/index.md)。完成一项删一项，并同步路线图状态。
>
> 条目格式约定：
>
> - 一条只写一件事；复验条目写清执行者与编号步骤
>   - 执行者：用户执行 / CI。
> - 进度叙事不进本文件——已做的看 git log，坑与根因看 `experience/adaptation/`
> - 状态标记 ✅ / 🚧 / ⏳ 语义见路线图「怎么读」
> - 行内不用括号补注——术语解释、日期、平台、出处展开为缩进子要点
> - 专业名词首次出现时紧跟一条大白话解释子要点

## 恢复入口

- 无障碍线：剩 Orca / NVDA 真机清单，恢复时按 [proposals/text-selection-a11y.md](proposals/text-selection-a11y.md) §九接
  - 时间：2026-11-06 容后。
  - Orca：Linux 的屏幕阅读器，把界面内容念给视障用户听。
  - NVDA：Windows 的免费屏幕阅读器。
- Wayland / 桌面环境专属工作：已移交 [proposals/linux-mbt.md](proposals/linux-mbt.md) 规划，不在本队列
  - Wayland：Linux 的新一代窗口显示协议，正逐步取代更老的 X11。
- 窗口材质调研线：[proposals/window-material.md](proposals/window-material.md) 调研稿已成稿未入库；下一步写 S1 / S2 两支探针，真机执行归用户——过了再定是否立项
  - 窗口材质：让系统合成器把窗口背后的桌面实时糊掉的系统级背景模糊，与控件级 backdrop_blur 是两回事。
  - S1：mac 上系统模糊视图能否贴在自绘窗后面——桌面透出且被糊、本窗内容不被糊。
  - S2：Windows 11 上系统 backdrop 与无边框、分层窗、GPU 上屏档是否兼容。
  - 门槛：S1 与 S2 过了才立项；S3 Windows 10 与 S4 KDE 是加分项，S5 Wayland 只记录。

## 待拍板与悬件

- [ ] **GPU 档契约线**：win10 排障会话里两组请示均未拍板——做哪几件待定
  - 三个动作：「env 库单源 + 全窗 3D 直出 + 三档降级」写进 roadmap「已规划」；真机测 B 排进真机清单，已排见开发待办；VM 检测代码迁进 native-env。
  - 落地四件：三条铁律加能力矩阵写进 roadmap 作对外承诺；`native-gui-design` skill 加效果分级；`l1_probe` 与 Linux VM 闸的内联检测迁到 native-env 单源化；L1 对 GDI 两档 A/B 上屏探针。
  - env 库单源：虚拟机与 GPU 档的判定只在 native-env 留一份，C 桩里 Windows 与 Linux 两段内联检测删掉——现状两套并存，这台 VM 第一版关键词漏判就是漂移的教训。
  - 效果分级：GPU 档的观感加成必须有 CPU 档等价简化版，任何界面不允许只有 GPU 档才好看才可用。
  - 全窗 3D 直出：整个窗口画面由 GPU 的 3D 管线直接绘制，不再 CPU 光栅合成；独立小批，不必等 L2。
    - L2：控件级 GPU 渲染档，比只管上屏的 L1 更进一步。
  - 附带可选项：`NATIVEGUI_GPU_FORCE=1` 逃生开关——让 VM 也能强制开 GPU 档测重配，随真机测 B 结果一起定。
- [ ] **native-env 是否发 mooncakes**：独立成库的成立前提是对外发布，至今未正式拍板——发布前需定
  - mooncakes：MoonBit 的官方包仓库，别人用 moon 命令从这里装依赖。
- [ ] **窗口状态记忆的 roadmap 口径**：标 ✅ 却挂着「待验：真机清单」，用例文档没有对应条目，示例也没接 `remember_geometry`——没有真机入口
  - 窗口状态记忆：关窗前记下位置、尺寸与最大化档，下次开窗恢复。
  - 待定：补一个示例入口后写真机清单验收，或改 ⏳ 并进「mng new 脚手架接会话恢复」那条一起做。
- [ ] **D:\ 那台 Windows 机工具链升级**：执行者：用户执行——该机 moon 低于 0.1.20261117，构建报 StringBuilder capacity 错
  1. `moon upgrade -f` 后 `moon version` 确认到 0.1.20261117 或更新
  2. `git pull` 后 `moon check` 不再报 StringBuilder capacity 错即闭环
  - 坑：非交互终端升级可能只换 moon.exe 不换 core，仍报错就重跑一次升级。

## 黑客松答辩

- [ ] **决赛收尾**：按 [proposals/hackathon-defense.md](proposals/hackathon-defense.md) 的 7 分钟骨架填 PPT 并彩排
  - 时间：2026-11-23 发 PPT 模板、11-27 提交、11-28 10:00 答辩，15 分钟含问答。
  - 待拍板三处：四次失败的措辞、信创段的比重、hello 演示去留。
  - 彩排：hello 四步演示练一遍并录屏兜底、文末 20 条参考逐条复核、演示机预热 mooncakes 缓存。
  - mooncakes 缓存：moon 包管理器的依赖下载缓存，演示机提前构建一轮避免现场等下载。

## CI 与门禁

- [ ] **`gui/moon.mod` 的 `homepage` 键告警**：本机 `cd gui && moon check` 输出 `Warning: Unknown configuration key homepage`，与门禁「零错误零警告」不符；workspace 内任一模块的 `moon check` 都带出这行
  - 根因：`homepage` 写在 `options(...)` 块里，工具链 0.1.20261119 不认；实测挪到顶层直接报错 `Unexpected key 'homepage'`——这个键没有合法写法。
  - 漏拦原因：`moon check` 退出码仍是 0，按退出码判绿的检查项拦不住；此前各批门禁读数没有数到这行。
  - 修法：删 `options(...)` 里的 `homepage` 一行，仓库地址已有 `repository` 字段。
  - 收尾：`experience/adaptation/linux.md` 2026-11-21 那条「非库缺陷、升级工具链的机器会看到」的口径改掉；修后 `gui` 与 `tools/native-gui-tools` 两处 `moon check` 输出不含 Warning。
- [ ] **gui-media video_wbtest mac 本机失败**：用例「VideoPlayer 时钟同轴：回退 fps 不影响时间轴」——回拨 500ms 后位置 0.613 / 0.633，稳定复现；Windows CI 每轮跑且过，Linux / mac 腿不跑 gui-media test 故从未暴露
  - 范围：CI 未覆盖的组合。
  - 边界：期望窗 0.45–0.55，即期望位置区间。
- [ ] **ui 动图组件 wbtest 在 linux 容器稳定红、mac 全绿**：`basic_wbtest.mbt:533` 断言 `h.play()` 后帧数续走（611 行）失败；中央动画登记表批合入后出现（合入前同容器 1524/1524 全过），怀疑登记表可见性/离屏停表在无显示环境判停——play 排不上拍
  - 范围：他人批次的既有缺口，非当批引入。
  - 复现：natigui-linux 容器 `dbus-run-session -- moon test ui`，两次同点稳定红。

## 滚动与上屏治理·三平台复验·用户执行

- [ ] **滚动批与上屏回归**：弹簧惯性、条带脏区、视觉偏移、win DIB 双缓冲、自愈帧已合入，按 SC-0.6 复验
  - 条带脏区：滚动时只重画新露出的那一横条，其余整条平移复用。
  - 视觉偏移：滚动位移只改画的位置，不重新排版，滚动帧不再作废布局缓存。
  - 自愈帧：滚动停住后补画一帧整视口，抹掉条带平移累积的残影；现滚动中每 40 拍也补一帧。
  - DIB 双缓冲：Windows 上先画到内存位图再一次上屏，避免逐行闪。
  1. 三平台起 components：打开即有完整画面——灰屏回归判据
     - 灰屏两修：win 上屏帧对象 Release 移到 Present 之后、mac L1 中途死亡摘 Metal 层回退。
     - L1：GPU 上屏档，窗口画面经 wgpu 合成上屏的路径。
  2. mac / Linux 代码文档页 Markdown 段滚动：惯性滑行与触边回弹可见、不再瞬时跳位；Windows 滚动无闪烁
  3. 滚动中与停止后无横纹，或残影最多 1/3 秒一闪即逝；仍可见则回传三要素——平台、定格还是滚动中出现、复现滚法
  4. PROF 对比：`NATIVEGUI_PROF=1` 起应用滚一轮贴回 PROF 行——mac / Linux 的 layout 段较修前读数 mac 8ms、Linux 慢段 222ms 应降到个位毫秒；Windows 首采，控制台已接回，采不到时 `NATIVEGUI_LOG_FILE` 落文件
     - PROF：帧耗时账本，每 2 秒打一行；layout 段即排版耗时。
  5. 那台 9400 Linux 裸机跑 `moon build examples/envprobe --target native && moon run examples/envprobe/main`，把 GPU 档/容器判定段贴回——确认档位与 L1 可用性
  - 判据与回填：SC-0.6 按平台标读数；C2 即 Linux 文本测量缓存批，按新 PROF 数据定做不做；通过后回写 roadmap ✅

## 空闲动画与内存治理·真机复验·用户执行

- [ ] **中央动画登记表 + wgpu 每帧对象释放**：代码已合入，按 SC-0.4 / SC-0.5 复验
  - 根因：eff_chart_t 构造期起 50ms 自续涟漪链且不看可见性，离树控件的 invalidate_id 回退整窗，演示板空闲即 21fps 全窗重绘；wgpu L1 present 每帧 swapchain texture / command encoder / render pass encoder 三对象缺失 Release，mac 实测逐帧泄露
  - 改动：gui/ui 新增中央动画登记表，表空即停、离屏停表、on_draw 喂表复活；eff_chart_t / gif / carousel 三组件迁入；stub.c L1 补三处 Release 与 loader 两个符号
  - mac 本机读数：空闲 CPU 21–28% 降到约 0.1%，原生泄露 40 秒 2356 个对象归零，100 秒 RSS 仅 +48KB 走平
  - 边界：sysmonitor 真机另有一条残余泄漏与本案不同源，读数勿混判——见开发待办 sysmonitor 条
  - 验证·用户执行：
    1. `cd gui && moon check` 零警告零错误，`moon test chart ui widget shell style render` 零失败
    2. mac 起演示板静置 1 分钟：活动监视器 CPU 个位数百分比、内存无持续上涨
    3. 切「过渡与效果」「数据展示」「图表」页：GIF / 轮播 / 涟漪动画正常，离开后 CPU 回落到静置档
    4. win 同口径复验：静置 CPU 接近空闲档，无持续占用

## deepin 20.9 构建链复验·用户执行

- [ ] **ffmpeg 4.x 版本分支 / webview 占位归档 / 非 GUI 可执行 pthread 三项修复的真机复验**：环境对齐报障机（deepin 20.9 + moon 0.1.20261119）
  - deepin 20.9：Debian 10 基线的发行版，glibc 2.28、系统 ffmpeg 4.x、无 webkit2gtk-4.1。
  1. 仓库根 `moon build --target native`：期望零失败——ffmpeg_stub.c 不再报 `ch_layout`，链接不再出 `pthread_setspecific` / `wb_*` 未定义
  2. `moon build examples/audio --target native` 后 `moon run examples/audio`：真机读数，解码出声即 ffmpeg 4.x 分支真链通过
  3. `moon run examples/browser`：期望 webview 探测报不可用、页面降级占位不崩——wb_* 走占位归档
- [ ] **VM 闸（Linux GPU 呈现档不启用）真机复验**：deepin 20.9 VMware 机
  - GPU 呈现档：窗口上屏走 wgpu 合成的路径；纯光栅是 CPU 绘制的回退路径，观感一致。
  1. `moon run examples/hello`：期望不再崩——VM 闸判 off，窗口正常出、走纯光栅
  2. `NATIVEGUI_GPU_LOG=1 moon run examples/hello`：stderr 应有「cpuinfo hypervisor 标志在——虚拟化环境，GPU 档不启用」
  - 判据与回填：通过后从本条删除；linux.md 2026-11-22 定案条待真机读数回填 ✅

## mng 工具链复验·用户执行

- [ ] **mngui 向导壳**：`moon install ./tools/native-gui-tools/mng && moon install ./tools/native-gui-tools/mngui` 后裸 `mng`：
  - mng：本仓的开发者工具命令行，管新建工程、dev 热更、体检与打包发布。
  - mngui：mng 的图形向导外壳，五步引导建工程、起应用。
  - install 按可执行包逐个装，装模块路径会报 not a main package
  1. 应开向导窗
  2. 五步走通：体检四项 ✓ → 建 demo 工程 → 起 dev 应用窗弹出 → 关向导 dev 仍在 → 完成页命令可选中复制
  3. 图标步给一个 1024 PNG：应落 `assets/icon.png` 且 `mng.toml` `icon` 键接上；给错路径应红字提示且工程不回滚
  4. 无显示机裸 `mng` 应回 usage
     - 场景：SSH 远程这类没有图形界面的环境。
  5. 观感三件：任意页步骤条整体撑满窗宽；点数字方块换内容但高亮不动、顶部出预览提示条；「返回当前步」回进度页
     - 步骤条判据：连线随窗拉伸不缩成点。
- [ ] **mng run / check / test**：
  - 范围：任一工程。
  1. `mng run`：build 后前台起应用，Ctrl-C 退出码透传
  2. `mng check -p <包>`：参数透传
  3. `mng test`：故意改挂一个测试，退出码非零
- [ ] **mng icons**：`mng icons <任一 1024 PNG> -o /tmp/ic`——mac 出 `.ico` + `.icns` + `.iconset` 十档；linux / win 只出 ico 并提示 icns 跳过
  - .ico / .icns / .iconset：Windows 图标、macOS 图标、macOS 图标集三种图标文件形态。
  - 取证：mac 的 `.ico` 用 `file` 命令验，应识别为 MS Windows icon resource。
- [ ] **mng ffmpeg-dll**：`mng ffmpeg-dll --dry-run` 打印计划不落盘；去 `--dry-run` 后 audio / video exe 旁应齐 5 支 dll；`--run` 起示例
  - 平台：Windows。
- [ ] **工程面板**：已有工程裸 `mng` 应开「mng 工程面板」窗：
  - 前提：体检 ready 有效；ready 是 doctor 体检全绿后写入的就绪标记。
  - 界定：非五步向导。
  1. 标题下工程路径可选中复制
  2. 四按钮：打包 / 发布 / 启动热更 / 刷新日志
  3. 点打包后提示 pid，跑完刷新日志出 tail
     - 样式：等宽字体末 60 行。
  4. 无 `mng.toml` / `moon.mod` 目录裸 `mng` 仍进新建向导
  5. dev 形态不跳向导
     - 界定：dev 形态指 `_build` 起的。
- [ ] **mng new 脚手架冒烟**：
  1. 仓库内 `mng new demo1`
     - 裸名即建工程。
     - demo1 需加进 `moon.work` members，否则按注册表解析。
  2. `cd demo1 && moon run .` 起窗
  3. 改 `pages/home.mng` 保存，`mng dev` 看热更
  4. `mng new page pages/about`；VS Code 命令面板「MNG: 新建页面」
     - 行为：父目录现建。
  5. 仓外腿：gui 0.3.3 已发布，仓库外 `mng new demo && mng dev` 走全链
     - 发布内容：含 mngdev 与 prebuild.mbtx。
     - mngdev：承载 dev 热更的库包，应用一行 import 即接入。
- [ ] **Windows LSP 跳转**：Windows 真机 VS Code 里验跳转落点与行号口径
  - LSP：语言服务器协议，编辑器与编译器之间传补全、跳转、诊断的标准通道。
  - 范围：含 hover 的 `moon ide` 桥。
- [ ] **mng LSP 令牌与跳转批**：`moon install ./tools/native-gui-tools/mng` 重建后 VS Code Reload Window，逐项验
  1. class 跳转：模板里 class 条目跳到 `<style>` 定义行
  2. `var(--` 令牌补全：候选带中英文档说明、选中整段替换，不再吐坏 JSON 致提示全失
  3. 令牌 hover 与语义高亮
  4. `<ui-scroll-view>` 补全无红、包级组件函数出现在候选
- [ ] **Windows dev 唤醒**：Windows 下 `mng dev` 唤醒链路真机验证
  - 补充：真机执行。
  - 前置已修：build 派生弃 shell 改 spawn_wait 原生重定向（Windows 实测 cmd 单参引号会吃参数）、source map 落点与 lsp 反查认反斜杠——`mng dev` 在 Windows `run` 留空也应直起，不再报「sh 起不来」与「写不出 source map」。
  - 状态：已合入待真机。
- [ ] **握手与折层**：
  - HOT：热更新，小改动不重启应用、原位生效。
  - COLD：改动超出热更范围时走重启生效。
  1. `examples/hello` 起 `mng dev`，改 `hello.mng` script 加新 Store 保存 → 该改本应 COLD；若工具侧先推了 HOT 补丁，日志应出 `[HOT→COLD] 握手不符：注册表键集落后…` 随后 `[COLD] … 应用已重启`、应用回首页
     - 回归判据：不再出现「补丁失败」后界面停在旧树。
  2. 正常 HOT 日志 `[HOT] 补丁已应用`，应用日志同步
     - 范围：只改字面量。
  3. components「事件与布局」页给 `hover_group` 挂 `class=[style(padding=14.0)]` 条目，内缩应按 class 走
     - 优先级：散参数 < class。
- [ ] **检查器真机清单**：按 `测试文档/测试用例.md` 1.5 节 HL-5.1～5.4、5.6～5.9 与 A11Y-9 走，HL-5.5 已撤销
  - 检查器：开发期看界面控件树、读数与样式的工具；独立窗口连应用内的检查服务，与 mngui 向导壳同一可执行，mng 二进制不链 GUI 库。
  - HL-5.1～5.2：`mng dev` 起 hello 后 `mng inspect tree` / `shot` / `style <id>` 三命令取数；不经 `mng dev` 起的应用 inspect 连不上——未注入零监听。
    - TSV：制表符分隔的行文本，一行一条记录。
  - HL-5.3～5.4：`mng mcp` 的 initialize / tools/list / tools/call 三行 stdio 全链，含 `--run` 自拉起应用。
    - MCP：让 AI 助手调外部工具的标准协议；stdio 即走标准输入输出。
  - HL-5.6～5.7：`mng inspect --gui` 图形检查器——左树约 1 秒自动刷新、选中在 hello 上出高亮框并跟随、样式五字段表单直改、拖动与点击不卡。
  - HL-5.8：默认树每个模板标签一行、自定义组件也是一行；「内部实现」开关与 `tree --full` 行数对照。
  - HL-5.9：应用窗按 ⌘⌥I 或 F12 开关附窗，树里是应用窗自己的控件；叉掉再按能重开；样式表单「应用」「还原」生效。
  - A11Y-9：读屏听 hello 模板页，组件根朗读为组节点、名字报模板标签——三平台读屏器各跑一遍。
  - 附：Windows 管道臂由 CI Windows 腿回证。

## 示例与控件复验·用户执行

- [ ] **示例矩阵真机冒烟**：`examples/components`、`examples/system`、`examples/canvas`、`examples/hello` 四示例各起一次，侧栏页逐页点开——起得来、不空白、不崩
  - 背景：showcase 收拢改名为 components，新增 system 与 canvas，hello 改 mng 单文件入门样例；roadmap 该条挂「待验：真机冒烟」。
- [ ] **布局缺省对齐 web**：窗根竖排顶层撑满窗宽、行容器子项缺省撑满行高，按 TP-1.2 与 SC-6.5 走
  - Stretch：flexbox 交叉轴拉齐——子项沿垂直于排列方向的轴撑满容器。
  1. `moon run examples/theme-playground` 起窗拖宽再缩回——四张卡左右随窗拉伸铺满内容区，不留右侧空白带
     - 用例：TP-1.2。
  2. `moon run examples/components` 进「代码文档」页 Markdown 段看三处——列表序号 / 圆点贴首行顶、表格单行格与多行格上缘对齐、引用竖条与整块内容等高
     - 用例：SC-6.5。
  3. `moon run examples/hello` 起窗拖宽——整页卡片随窗宽铺满，高度仍按内容
  4. 抽查原先行内居中的段落没有走样——工具行、面包屑、sysmonitor 顶栏的图标文字不被拉变形
     - 需居中的容器显式传 `align_items=Center`。
- [ ] **新窗首帧**：`cd examples/hello` 依次开三档子窗，**不动鼠标**每扇窗内容立即可见
  - 回归判据：不再白屏等鼠标。
- [ ] **托盘图标与右键菜单**：hello 按 HL-3.1～3.3、system 按 SC-11.6 走，三平台各一遍
  - 托盘：系统桌面上通知区域的小图标，点它弹菜单。
  - 图标：纯月兔剪影——只有兔子头脸、不带窗口；浅色 / 深色模式下纯黑 / 纯白剪影，Windows / Linux 跟随系统明暗换黑白。
    - mac 模板图：颜色由系统按菜单栏实际明暗自动反色。
  - 右键菜单 hello：右键托盘弹「关于窗 / 分隔线 / 退出」；「关于窗」开一次关于窗再点收一次；「退出」整应用退出、托盘图标不残留。
  - 右键菜单 system：右键菜单默认已挂且选中项回调跑到——「冒个提示 / 退出」。
  - 背景：右键菜单此前全仓没有任何示例真挂过——库能力在、示例层从未接线，hello 与 system 两处补挂已合入。
- [ ] **品牌图标透明底**：图标导出管线换掉后全档重导，三处肉眼看一遍
  1. 无痕窗口打开文档站：标签页图标周围无白块，16px 小图是实心蓝窗加粉兔脸
  2. GitHub 仓库页 README 头图：白底上无白框，窗口轮廓清楚
  3. 文档站导航栏 logo：浅色 / 深色模式各看一眼
  - 背景：旧导出管线把透明区压成不透明白底，icns / ico / png / favicon 全档都带白框；验证透明要看像素 alpha，不能只看文件带不带 alpha 通道。
- [ ] **hello 开关窗**：同一档按钮「打开 → 关闭」单例；子窗标题栏关闭后 ≤200ms 按钮回「打开」；提示语为单页组件与开发工具说明、无热更字样
  - 判据：重复点不叠加。
- [ ] **sysmonitor 改版**：按 `测试文档/测试用例.md` 第 9 节 SM-1.1～1.7、SM-2.1～2.6、SM-3.1～3.7 走
  - 左栏六项菜单：处理器 / 内存 / 网络 / 磁盘 / 显卡 / 进程；右栏窄于 400 时横向滚动；CPU 各核小图换行。
  - 左栏精简：CPU 与显卡型号移到右栏详情页；内存只留利用率 / 物理内存 / SWAP；磁盘只留「读」「写」两行速率，不再逐行列挂载点。
  - 右栏：网络只列实体网卡；磁盘无 loop / 光驱 / 网络盘；显卡页无温度段。
  - 进程页：搜索 / 结束 / 中文状态 / 列宽拖动 / 表格填满；按钮后新增「内存 RSS」读数——未选中显示「—」，选中显示该行数值，多选只取第一行，搜索排序后读数仍对应当前选中行。
  - 重点回看：左栏是否清爽、磁盘读写速率与磁盘详情页一致、其它交互没退化。
- [ ] **窗口功能迁 hello**：hello 整页纵滚——mng 入门页 → 基本窗口示例 → 三段窗口功能；透明测试窗卡片外**透出桌面不呈黑底**；components 侧栏不再有「窗口」页；用例 HL-4.1~4.3
  - 三段窗口功能：窗口 API / 多窗口 / 透明度，瘦身定案。
  - 透明度段无「背景穿透」按钮，主窗不提供。
  - 透出判据：mac 透明档已拦 GPU 档。
  - 侧栏变化：少一项、其余页照常。
- [ ] **模板 v-for**：components「数据展示」页「模板列表」段按 SC-4.11 走——加 / 删首 / 清空、行序一致、无残影；`mng dev` 下改 `vfor_demo` 行模板应 `[HOT→COLD]` 带原因重启
- [ ] **项目级 build 与 dev watch**：
  1. `cd examples/components && moon run ../../tools/native-gui-tools/mng -- build`：应列全部模板 OK 且 `moon check` 过
     - 生成码会被覆盖成生产形态；CI 对账认 dev / 生产两种形态任一，直接提交也过，要回 dev 形态跑一轮 `mng dev`。
  2. `mng dev` 跑着时新建 `.mng` → 日志 `[NEW]` 并自动重启；删除 → `[GONE]` 清生成码；改 `main.mbt` → `[SRC]` 并重启
  3. 双形态提交：把生产形态生成码推一次，CI 生成物对账腿应过
     - 执行者：CI。
     - 双形态：同一份生成码文件，`mng dev` 写热更形态、`mng build` 写生产形态。
- [ ] **hello mng 冒烟**：`moon run examples/hello` 起窗，按 HL-1.x 输入名字 / 步进计数 / 重置；同目录 `mng dev` 改 `hello.mng` 保存看声明页热更
  - 用例：HL-1.4。
- [ ] **热更真机复验**：
  - 环境：`cd examples/hello`，`mng.toml` 已提交。
  - 平台：下列步骤走 mac；`<style>` 段布局属性样式化另需 Linux 真机走一遍。
  1. `moon run ../../tools/native-gui-tools/mng -- dev` 起应用
  2. 改 `hello.mng` 标题 / 提示字面量保存 → HOT
     - 读数：mng 日志 `[HOT] 补丁已推送`、应用日志 `HELLO-DEV: 模板补丁已应用`；`<style>` 类规则的字号 / 颜色值随保存热更
  3. 改插值与按钮回调里的受限表达式 → 受限文法内 HOT；新函数 / 新符号 → `[HOT→COLD]` 带原因
  4. 改 script 状态声明 → COLD，重启后自动回首页
  5. stepper 调到 7 再只改字面量走 HOT，值仍 7；COLD 后回 0
     - 判据：状态保活。
  6. v-for 面：`cd examples/components` 起 `mng dev`，改 `pages/vfor_demo.mng` 行模板应 `[HOT→COLD]` 带原因重启
     - 用例：SC-6.6。
- [ ] **编辑器真机复验**：`cd tools/vscode-mng && npx @vscode/vsce package` 打 0.2.15 vsix 安装 → Reload Window，按 `tools/vscode-mng/README.md` 清单走——语义着色、TextMate 着色、snippets、补全、Problems 诊断、hover、跳转、命令面板「MNG: 新建页面」
  - vsix：VS Code 插件安装包格式。
  - 覆盖安装加 `--force`。
  - 平台：清单走完 mac，另在 Linux 装一次 VSIX 走一遍。
  - 插件图标：扩展栏里图标为新构图——实心蓝窗加粉兔，无白底。
  - 语义着色分档：类型 / 变量 / 参数 / 函数 / 方法 / 命名空间。
  - 主题未开语义高亮需设 `editor.semanticHighlighting.enabled: true`。
- [ ] **样式补全观感**：components「过渡与效果」页与 canvas「画布与富文本」页：
  1. 渐变背景——线性 / 径向，stop 用主题 token 时随主色变；半透明 stop 在 Windows / mac 的插值口径与 Linux 一致
  2. 每角圆角与每边边框——不等半径四角、四边独立宽色；带圆角时 per-side 回落统一描边是否诚实
  3. `mix_blend_mode` 混排——改档看有没有漏到同帧兄弟
  4. 删除线与上划线——折行段落落在最后一行
  5. 令牌间距——整板留白与改前一致
- [ ] **主题批次观感**：`examples/theme-playground` 按 TP-1.1..5.1 走完——深色系统起窗即深色；主题 JSON 落盘改色；深浅变体看 tooltip 反色与滚动条 / 分隔线深档提亮；code_view 在浅色 / 深色主题下底色跟 `theme_current()`，显式 `code_theme` 钉死
  - 深色生效方式：默认一次性探测生效。
  - 主题 JSON 改色：dev 档 `mng.toml` `theme` 键存盘即重载。
- [ ] **窗口族探测口径**：无合成器的 Linux 会话上 `shell_caps()` 的 `opacity` / `transparent_bg` 位应为 false，`set_transparent_bg` 应回 `Unsupported` 而非静默无效；`native_handle()` 三平台返回值非 0 且能喂平台 API
  - 合成器：Linux 图形会话里把各窗口画面合成上屏的系统服务。
- [ ] **浮层原生档 Linux 复验**：browser 示例按 BR-1.4——↑↓ / 回车 / Esc 键盘、开着再点按钮直接收起不闪、点外收起且不触发被点控件、弹出无闪现
  - 浮层：气泡、下拉、菜单这类浮在页面内容上方的弹出组件。
- [ ] **通知 urgent 二档**：同一应用分别发 `urgent=true` 与 `urgent=false`——前者出横幅、后者只进通知中心不出条；系统设置关「时间敏感」授权后再发 `urgent=true` 回落静默；状态行 `backend=` 应报 `un-user-notification`
  - 平台：mac。
  - 缺省：`urgent=true` 为缺省档。
  - 其余平台读数：Linux 报 `dbus`、Windows 报 `win-balloon`。
- [ ] **终端控件真机验收**：控件已合入但没挂进任何示例，没有真机入口——先在 components 挂一页，挂完按下列面验
  - 终端控件：库里的 `terminal`，等宽网格显示命令行文字，喂文本即可用。
  - 验收面：16 / 256 / truecolor 三档着色；转义控制串清洗后不花屏；回看缓冲、滚动条与拖选；键入经 `on_input` 出口回显。
    - truecolor：一千六百多万色的完整彩色。
    - 回看缓冲：滚上去还能看到的历史输出行。

## 发布与更新复验·用户执行

> 产物钉死四件：macOS DMG、Windows setup、Linux deb + AppImage；tar.gz 与 PKGBUILD 不做。Linux 自动更新走 AppImage 单文件替换，deb 档报新版本引导下载。
>
> - DMG：macOS 的磁盘映像安装包，打开拖进应用目录即装。
> - NSIS：Windows 的安装包制作工具，setup 安装器由它生成。
> - deb：Debian 系 Linux 的软件包格式。
> - AppImage：Linux 的单文件免安装应用格式。

- [ ] **A1 mac 打包**：`cd examples/components && moon run ../../tools/native-gui-tools/mng -- package`——`.mng/dist/` 应出 `Native GUI Showcase.app` + `showcase-0.1.0-darwin-aarch64.dmg/.zip` 三件；挂 DMG 拖装运行；看 Dock 图标与资源
  - 已知现象：adhoc 首启 Gatekeeper 右键放行。
  - adhoc 签名：没有开发者证书的临时签名。
  - Gatekeeper：macOS 的应用安全门，拦未核验的应用，右键打开可放行。
  - Dock 图标：由 assets/icon.png 派生。
  - 图标源：`examples/components/assets/icon.png` 已换透明底新构图，旧 `.mng/dist` 是陈货——须重跑后再看 `.app` 图标。
- [ ] **A2 更新器·Linux 腿收口**：
  1. `mng package` 出新版载体
     - 自检：构建前自检三行一致——`git log -1`、`grep ^version mng.toml`、`grep app_version appmeta/appmeta.gen.mbt`。
  2. 应用内检查下载替换重启：版本变新、自动弹新窗、`.mng-old` 清理、不再报更新
- [ ] **A2 更新器·CI 真实清单腿**：mac 装 0.1.0 → CI 发 0.2.0 draft → 应用内走检查下载替换重启全链
  - 依赖：release-app 首跑。
- [ ] **A2 mng publish**：`cd examples/components && moon run ../../tools/native-gui-tools/mng -- package && moon run ../../tools/native-gui-tools/mng -- publish --no-upload --repo <owner>/<repo>`——`.mng/dist/update.json` 应含 darwin-aarch64 的 zip 条目；真上传档核 draft Release 产物清单后删
  - 前置：装 gh 并 `gh auth login`。
  - zip 条目：url 指 releases/download、sha256 与 `shasum -a 256` 一致。
- [ ] **release-app CI 首跑**：推 tag `app-v0.1.0` 触发——打包腿出 DMG / zip、汇总腿出 `update.json` 并发 draft Release；win / linux job 骨架已注释预置，对应腿合入后取消注释启用
  - 执行者：用户执行。
  - update.json：只含 darwin-aarch64 的 zip 条目。

## 探针读数·用户执行

- [ ] **frame_cost_probe Win / mac**：mac 已采 2026-11-21（release，1400×900）——`paint_full` 3.55 / 5.2 / 5.5 ms/帧对 `paint_clip` 0.35 / 0.35 / 0.45（15/60/240 行），skip 180→4760、visit 1940→180，剔除收益 10～15 倍；剩 Windows 腿——`moon run experiment/frame_cost_probe --release`，贴全部 `FRAME-COST` 行；Linux 腿判据已进测试用例附录 D
  - 光栅：不走 GPU、由 CPU 逐像素画图的软件绘制路径。
  - 判交条件：纯光栅腿才判交——mac 腿 skip 有效已证、cairo 腿 skip 恒 0 量不到。
  - 理由：差值是「图表 / 整页增量重绘」的立项依据——已随 proposals/data-driven-repaint.md 收窄范围定案引用。
- [ ] **媒体硬解探针 Win / mac**：`cc -O2 hwdecode_probe.c $(pkg-config --cflags --libs libavcodec libavutil)`，判据：设备建得起来且 transfer 非空；另剩归档实物核验——`otool -L` 验 mac 归档带 VideoToolbox、LICENSE.txt 口径修正
  - 硬解：由显卡等专用硬件解码视频，比软件解码省 CPU。
  - VideoToolbox：macOS 的硬件编解码框架。

## 品牌与插画

- [ ] **库内置托盘图标**：system「系统集成」托盘段点「回库内置」——托盘图标应为新版，三平台各看一眼；发 0.4.0 与否用户定
  - 新版样式：纯月兔剪影——只有兔子头脸，窗口撤出，与单色定案一致；图标观感详见「示例与控件复验」的「托盘图标与右键菜单」条。
- [ ] **情景插画**：README 头图 / 文档站首页「兔子坐在电脑前」叙事版
  - 批次：第二批。

## 开发待办

- [ ] **airtype mac 打包产物复验**：执行者：用户执行——11-22 全链过验当晚又合入 mng 模板化改版与十余笔修复，打包形态未再验
  1. `mng package` 出 .app，按 `docs/guide/airtype.md` 重置辅助功能授权——删旧授权条目、装固定位置、去隔离属性，2 秒内刷「已授权」
     - TCC：macOS 的隐私授权数据库，辅助功能授权记在里面；重打包换了可执行路径旧授权不认。
  2. 首页 / 设置页内容超高时页签内可滚——条件显示的宿主壳会顶断高度收缩链，去壳后才能滚
     - 宿主壳：条件显示给内容包的一层容器；它按内容自然撑高、不收缩，滚动视口就拿到完整内容高、永远不裁剪。
  3. 首启未授权自动弹引导卡；手机连上后状态、地址、已连接数实时刷新
  4. 手机操作条回车 / 发送 / 快捷指令 / 全屏键与键盘保持——AT-2.11、AT-2.12
  - 范围：同批还有 tabs 面板放开最小高、滚动容器 class 的排布属性自动落内容壳、页面壳宽高钉满三笔库级改动，对所有 mng 应用生效——components 顺带过一遍页签切换与滚动容器留白
  - 收尾：工作区里未提交的 `apps/airtype/mng.toml` `[package]` 段与 `appmeta/` 生成码，验完定是否入库

- [ ] **airtype linux / Windows 真机复验**：执行者：用户执行——mac 已验过（2026-11-22，AT-1.1～3.2 全过）；注入三臂已合入并升级为全键位模拟，各平台跑 AT-2.2/2.3/2.7 上屏面
  - airtype：手机扫码进网页打字、发送后打进电脑聚焦框的本仓独立应用。
  - 出处：提交 aa818f71、6427c9da。
  - 关键面：辅助功能授权引导、扫码连通、中文/emoji/长文上屏、token 门禁、断线重连、密码框边界
  - 本批新增（2026-11-22）：回车键与发送键两步分立、快捷指令 chips——配置落 `~/.config/airtype/shortcuts.tsv`、亮屏即连与心跳探活——AT-2.6、AT-2.8～2.10；手机页三段式、全屏键与键盘保持——AT-2.11、AT-2.12
  - linux 限 X11 会话（Wayland 只有 XWayland 应用收得到）；Windows 提权目标窗口不收注入

- [ ] **环境判定库 native-env 真机矩阵**：执行者：用户执行——`cd examples/envprobe && moon run main` 按平台各一遍，逐条对 `测试文档/测试用例.md` 的 EP-1.1～1.7
  - 已验 2026-11-21 第一轮：mac 本机 EP-1.1（裸机 / Metal Hardware）；company Linux 容器 EP-1.4（docker 命中、宿主裸机、无渲染节点 Software）——本条真机抓出容器信号漏进 VM 判定一 bug 已修
  - 已验 2026-11-21 第二轮：company win10 KVM EP-1.3——品牌从 enlightenments 漂移的 hyperv 修正为 bochs，`bios_vendor` 信号补进；库测 27/27；EP-1.6 两遍输出一致 PASS；company 宿主 EP-1.5 半边（裸机 / nvidia Hardware / TTY / 修复后零信号，与 systemd-detect-virt 双 none 一致）；home 宿主 EP-1.5 半边（裸机 / i915 Hardware / 零信号）；home ubuntu-24.04、ubuntu-26.04、kubuntu-24.04 三台 KVM VM（qemu 双硬信号 + mac_oui，GPU Software）——第二轮真机抓出 pidns 常量抄成 IPC inode 与 virbr0 qemu OUI 混信号两 bug 已修，Windows SMBIOS 四通路全断加 HardwareConfig 兜底一缺陷已补
  - 待验：deepin 20.9 / 23.1 / 25.2 三台 KVM VM——没装 openssh，须登录后在桌面终端跑 envprobe；Ubuntu 24.04 编译产物在 20.9 的老 glibc 上起不来，需就地构建
    - 采法：登录任一台后在桌面终端粘贴 `for p in /home/noahliu/vm-share /mnt; do [ -x "$p/envprobe" ] && "$p/envprobe" | tee "$p/envprobe.out" && break; done`，输出写回 vm-share，宿主侧直接读。
    - 预期：25.2 能直接跑；23.1 / 20.9 报 GLIBC 版本不够，本身是分发地板的有效读数。
    - 11-22 网络已改：home 宿主与 7 台 VM 全切到网桥 br0 直连路由器——宿主 192.168.0.38、deepin-25.2 与 20.9 运行中、mac 可直连；其余五台开机后自动拿新地址。
  - 待验：EP-1.3 的 GPU 半边——ssh 会话里 EnumDisplayDevicesW 与 DXGI 都拿不到适配器，须 RDP 或控制台会话跑一次看 QXL 命中 Virtual
    - 步骤：RDP 进 company win10 后跑 `C:\natigui\envprobe.ps1`，脚本已留在 VM。
  - 待验：EP-1.5 的另一半——无渲染节点的 Linux 裸机应报 Software；现有两台宿主都有渲染节点，只验了 Hardware 半边
  - 待验：Windows 真机 EP-1.2；home 的 win10 VM 一直没测
  - 环境待办·用户执行：home 宿主本地终端删掉被带起来的 Wi-Fi 热点配置——`sudo nmcli connection delete 186840f1-478a-4e62-97eb-7ce29e1be10e`；home win10 开机拿到 192.168.0.x 后同步 ssh 别名。

- [ ] **批2 transform 收尾读数**：win / linux 各跑一次 `moon run experiment/anim_cost_bench --release`，把 `rot_90x32` 档读数贴回 roadmap；三端真机观感 2026-11-21 已验，mac 读数 20 帧合计 0ms（与同尺寸裸图元同档）

- [ ] **A6 CPU/GPU 像素对拍**：比对器本体单独立项（与「无头像素快照基线」合并）；随控件级 GPU 批的用例扩面已随 SC-16.8/16.9 落
- [ ] **无头化收尾真机复验**：执行者：用户执行
  - Linux：CI 的 Linux bare 腿首跑（dev 合入 master 或开 PR 触发），看「占位降级 19 包全绿 + 降级提示 + 守卫跳过」三判定。
  - 无字体 Linux 真机：`FONTCONFIG_FILE` 指向空配置跑任一示例——应见文字真字形（内嵌字体注册生效），非方框或空白。
  - Windows：`moon build --target native` 链接复验（本批未动 Windows 分支，例行确认）。

- [ ] **sysmonitor Linux 残余内存泄漏**：两源修复后真机仍 +0.35 MB/分钟，容器不复现、真机进程多才复现
  - 已修两源：mac CoreText 字体对象按规格缓存、Linux Pango 排版上下文复用——修复本身有效，残余另源
    - CoreText / Pango：macOS 与 GTK 各自的系统文字排版引擎。
  - 已锁定链条：series_push → 订阅者 invalidate → 重绘路径，非图表绘制本身，最可疑重绘中的原生文本绘制
    - 读法：曲线推点后通知订阅者标脏、触发重绘，漏在重绘这一步。
  - 下一步：跑完中断的对照——`host_repaint_all` 去掉 `@win.wake()`，区分唤醒平台泵与真正重绘谁在漏
  - 验证·用户执行：修复版真机跑 30 分钟每分钟记 RssAnon，判据预热几分钟后走平
    - RssAnon：常驻内存里的匿名部分，持续线性增长即泄漏信号。
  - mac 残余约 +1.2 MB/分钟量级小，随本案一并收口

- [ ] **win sysmon 桩三小修**：`sysmon.c` 两处 DLL 加载器引用漏释放、PDH 查询对象每采样漏一个、nvidia-smi 缓存条件永真致读数不刷新
  - DLL 加载器引用：Windows 每加载一次系统库记一笔引用，用完要还，不还会攒句柄。
  - PDH：Windows 的性能计数器接口，查一次拿一个对象要还。
  - 验证·用户执行：win 真机跑 sysmonitor 30 分钟，任务管理器看句柄数不增、显卡读数随时间会刷新

- [ ] **Windows 真机 GPU 档行为**：执行者：用户执行——全屏崩溃四轮取证都在 VM 虚拟显卡栈上，真机无读数
  1. 测 A：真机设 `NATIVEGUI_GPU_LOG=1` 起 hello——日志出 L1 探测通过，全屏 / 缩放观感正常
  2. 测 B：`git checkout 15ac9682` 重建，重跑全屏进出与缩放——不崩则「尺寸变化永久 CPU 回退」兜底可撤，崩则兜底留终态
  3. 收尾：`git checkout dev` 回分支

## 极致光栅与新立项

- [ ] **混合 DPI 真机复验**：执行者：用户执行——HL-4.5 / HL-4.6
  - 已合入 2026-11-21：三处口径统一——MoonBit 层与 C 桩账本逻辑单位、帧位图恒物理像素、窗级因子 `Window::scale` 每帧现读，定案见 proposals/mixed-dpi-scaling.md；库测 1516/1516、mac 三桩语法门禁、原生链接与示例链接通过，行为变化预告——mac Retina 上既有窗口从入参一半点数变入参原值点数，与 win / Linux 对齐。
  - 待验：Windows 125% / 150% 各起一次 hello——窗口逻辑尺寸与 100% 一致、文字不虚、命中不偏（虚拟屏改系统缩放即可，不依赖高分屏）；单屏改缩放档触发 `WM_DPICHANGED` 的自动重排重采样（跨屏拖动的替代口径）；mac 1x / 2x 屏间拖动——待有 1x 外接屏补验；Linux X11 冒烟零变化。
  - 开放点：Linux 放大变换下的字形清晰度待真机确认——`GDK_SCALE=2` 起 hello 看文字是否发糊。
  - 已知一次性现象：旧 `window_state.json` 存的是旧口径坐标，升级后首次读回位置偏移，首版不迁移。
  - 恢复时核对：提案「批 2 收尾」三项——几何记忆口径、裸位图直绘族调用方、条带快路径在变换下的源目标口径——实施记录里没提是否已做。

- [ ] **数据驱动局部重绘批 2 / 3**：批 1（订阅回调按控件标脏）已合入——`follow_store_at` 全库 50 处组件根绑定、when 族与 swap_node 显隐按矩形标脏、chart 数据变更随通道收窄；剩批 2 chart 悬停与图例（交互类 invalidate）、批 3 点击成交 Up / GIF / 拖放兜底与文本自适应宽的标脏余量（`text_dyn` / `relabel`）
  - 批 1 判据：`experiment/frame_cost_probe` 的 `paint_full` vs `paint_clip` 读数（mac 10～15 倍差值已采，Windows 待补）+ SC-7.3 真机无闪烁。
  - mdview 不立项（滚动已由条带快路径解决）；`bind_node` / `for_list` 结构变化保持整窗（残影面）。

- [ ] **虚拟滚动精度批真机复验**：SC-4.13 / SC-4.14
  - 执行者：用户执行。
  - 范围：components 代码文档页 Markdown 与数据展示页「虚拟滚动 · 任意元素」——滚动区内容有惯性、触顶/触底只弹内容区；页签条、侧栏、页外壳不动；内层滚动时外层不同时滚；滚动不跳行、无残影；有毛玻璃/原生输入框的页面滚动不裂。
  - 附：win / linux 补跑 `experiment/anim_cost_bench` 滚动档读数（mac 0.89ms/帧）。
