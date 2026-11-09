# TODO — 当前进行中的工作

> 只记「已实现、待复验 / 待收尾」的现行事项；规划与未来批次见 [docs/zh/roadmap.md](docs/zh/roadmap.md)「已规划」，实测坑与口径见 [experience/adaptation.md](experience/adaptation.md)。完成一项删一项，并同步路线图状态。


## 实施队列（2026-11-04 排定，用户指定顺序：无障碍 → 代码/终端 → GPU。做完一项删一项并同步路线图，一项一提交）

（无障碍线已于 2026-11-06 容后：三平台桥全部落地、mac VoiceOver 首轮已过，剩 Orca/NVDA 真机清单；
进度与剩余项归档 [proposals/text-selection-a11y.md](proposals/text-selection-a11y.md) §九，恢复时按那里接。
Wayland/DE 专属工作（协议客户、spike、DE 实测矩阵）已移交 [proposals/linux-mbt.md](proposals/linux-mbt.md) 规划，不在本库任务队列）

### 一、代码/终端（mng 工具链）

（已全部收口：三项完成见 git log 2026-11-04；Windows 真机复验 2026-11-08 过——复验中揪出非 ASCII 路径定义跳转空白一处，修复见 50f1f748，坑回写 experience/adaptation.md）

### 二、GPU（按 [proposals/gpu-architecture.md](proposals/gpu-architecture.md) 分批）

（2026-11-07 全部收口：X11 三角形真机过（三色三角形、关窗/Esc 正常退出）；GPU 画布 mac/win/Linux 三腿真机全过——Linux 应用进程「检查读回」非零、与无头用例一致；Linux L1 独立 X 子窗口承载真机复验含最小化恢复场景。GPU 验证队列清空，后续实现批（视频直纹理、GPU 控件纹理进合成器等）见 roadmap「已规划 · 渲染」与 proposals）

## 打包与自动更新（2026-11-08 立项，方向见 [proposals/方向.md](proposals/方向.md) A1/A2/A3；一项一提交，做完删一项；先 CPU 光栅最小闭环，不绑 GPU 线）

> 产物钉死四件：macOS DMG、Windows setup（NSIS）、Linux deb + AppImage；tar.gz 与 PKGBUILD 不做。Linux 自动更新走 AppImage 单文件替换，deb 档报新版本引导下载。

- [ ] **A1 mac 腿真机复验**（用户执行）：`cd examples/showcase && moon run ../../tools/native-gui-tools/mng -- package`——`.mng/dist/` 应出 `Native GUI Showcase.app` + `showcase-0.1.0-darwin-aarch64.dmg/.zip` 三件；挂 DMG 拖装运行（adhoc 首启 Gatekeeper 右键放行属已知），看 Dock 图标（assets/icon.png 派生）与资源（2026-11-09 主链已过：拖装双击真机过（demo_app 实测；途中修出 DMG 卷内执行位、.exe 名两缺陷）；showcase DMG 卷内签名/可执行位挂载实测过；剩 showcase 拖装看 Dock 图标与资源一小步）

（A1 linux 腿 2026-11-09 真机过：AppImage + deb 全流程按清单走通（appimagetool 手动放置绕 GitHub 不通，自动下载失败真因靠 run_tool 退出码修复现形）；复验修出 `spawn_wait` 缺陷见 6ad6c68e）
- [ ] **A2 更新器 v1·真机复验**（用户执行）：`update_check/update_download/update_apply_carrier/update_relaunch` 链路——mac 装 0.1.0 → CI 发 0.2.0 draft → 应用内检查下载替换重启后版本变 0.2.0、`.mng-old` 清理；Linux 腿 AppImage 自替换同流程；showcase「系统集成 → 应用自更新」演示后端走全态（检查中旋转弧→0.9.9→下载→就绪→安装提示）、真实清单在 CI 首跑前报拉取失败也属验证
- [ ] **A2 mng publish 真机复验**（用户执行，装 gh 并 `gh auth login`）：`cd examples/showcase && moon run ../../tools/native-gui-tools/mng -- package && moon run ../../tools/native-gui-tools/mng -- publish --no-upload --repo <owner>/<repo>`——`.mng/dist/update.json` 应含 darwin-aarch64 的 zip 条目（url 指向 releases/download、sha256 与 `shasum -a 256` 一致）；真上传档核 draft Release 产物清单后删
- [ ] **release-app CI 首跑**（用户执行）：推 tag `app-v0.1.0` 触发——打包腿出 DMG/zip、汇总腿出 `update.json`（只含 darwin-aarch64 的 zip 条目）并发 draft Release；win/linux job 骨架已注释预置，对应腿合入后取消注释启用

## 内建 inspector（2026-11-08 立项，方向见 [proposals/方向.md](proposals/方向.md) A4；一项一提交，做完删一项）

- [ ] **v1 只读面板真机复验**（用户执行）：showcase「系统 → 检查器」页——树里能看到当前页控件（按父链缩进）、点行看读数（矩形与界面位置对得上）、动一动界面再点「刷新」树变化、自动刷新开着时不卡帧、重置统计后 frames 重算
- [ ] **v2 样式回灌真机复验**（用户执行）：「检查器」页样式类页签——选中一个类改背景色「应用」，用了该类的控件下一帧变色；「还原此类」回原样；空白输入不改字段；token 名与 #hex 都生效

## 方向 A 类其余项（2026-11-08 用户定全部入待办，方向见 [proposals/方向.md](proposals/方向.md)；顺序在打包/更新/inspector 之后，一项一提交）

- [ ] **A6 CPU/GPU 像素对拍**：与「无头像素快照基线」合并比对器，随控件级 GPU 批扩用例

## mngdev 库包与工具链联动（2026-11-07 立项，方案见 [proposals/mngdev-library.md](proposals/mngdev-library.md)；一项一提交，做完删一项）

（代码侧四件全部落地并逐项提交推送：dev 面进库 c8051433、lsp 诊断联动 411cbc2e、脚手架 7acf24e3、文档收口本笔；本批只剩真机/编辑器复验，均由用户执行）

> 机械部分已自动化（2026-11-08）：`scripts/mng_scenario.sh`（脚手架→dev 首轮→HOT→COLD 重启回页→[NEW]/[GONE]/[SRC]→生产构建，14 条）与 `cd tools/vscode-mng && npm test` / `npm run test:vscode`（着色分词、真 mng lsp 会话、真编辑器里的诊断/hover/新建页面）已进 CI。下面留着的是**观感与主观项**，仍由人工过。

（dev 面进库复验 2026-11-09 过：showcase `mng dev` 热更循环 HOT 亚秒、COLD 回改动页，生成码 `@mngdev` 前缀应用侧零复制）

- [ ] **lsp 诊断联动复验**（用户执行，装新版 VSIX）：`.mng` 里写坏 script 段类型（如 `+` 拼非串）→ Ctrl+S → Problems 出「moon check」来源的模板行列错误；恢复保存后错误消失
- [ ] **脚手架冒烟**（用户执行，含 `mng new` 改面复验）：仓库内 `mng new demo1`（裸名即建工程；**需把 demo1 加进 `moon.work` members**，否则按注册表解析、线上 0.3.1 无 mngdev 必挂——发版缺口见下）→ `cd demo1 && moon run .` 起窗 → 改 pages/home.mng 保存看 `mng dev` 热更；另验 `mng new page pages/about`（父目录现建）与命令面板「MNG: 新建页面」。**仓外腿挂起**：等 gui 发布含 mngdev 的版本（脚手架线上/兜底版本随之可用），2026-11-07 记

## 终端与单文件 DX 批（2026-11-06 排定，方案见 [proposals/terminal-sfc-dx.md](proposals/terminal-sfc-dx.md)——代码侧九件全部落地并逐项提交推送，本批只剩真机复验，均由用户执行）

- [ ] **终端控件真机复验**（用户执行）：showcase「代码文档」→「终端」段按 SC-6.5 走（ANSI 16/256/truecolor、CJK 对齐、折行、滚轮回看 + Shift+PageUp + 滚动条、四按钮、打字/退格/方向键回显、回车喂回、拖选 Ctrl/Cmd+C 复制、裸 Ctrl+C 进输入、深浅主题）
- [ ] **模板 v-for 真机复验**（用户执行）：showcase「代码文档」→「模板列表」段按 SC-6.6 走（加/删首/清空、行序一致、无残影）；`mng dev` 下改 vfor_demo 行模板应 `[HOT→COLD]` 带原因重启
- [ ] **项目级 build 与 dev watch 真机复验**（用户执行）：①`cd examples/showcase && moon run ../../tools/native-gui-tools/mng -- build` 应列出全部模板 OK 且 `moon check` 过（注意会把 dev 形态生成码覆盖成生产形态，复验完 `git checkout` 生成码或跑一轮 dev 恢复）；②`mng dev` 跑着时新建一个 `.mng` → 日志 `[NEW]` 并自动重启；删除它 → `[GONE]` 清生成码；改 `main.mbt` → `[SRC]` 并重启
- [ ] **template-hello 冒烟**（用户执行）：`moon run examples/template-hello` 起窗、输入名字/步进计数/重置

## 模板预编译（2026-11-01 启动，方案见 [proposals/native-template.md](proposals/native-template.md) 与 [proposals/mng-project-dev.md](proposals/mng-project-dev.md)；已完成叙事归 roadmap「开发体验」，此处只留未完成项）

### 真机复验（用户执行）

> 日志口径与重启编排这类机械项已由 `scripts/mng_scenario.sh` 覆盖（CI 三腿里 Linux/mac 跑）；下面几条要判的是**看得见的东西**：toast、亚秒手感、状态保活后的数值、样式章观感。

- [ ] **热更真机复验**：①`cd examples/showcase`（`mng.toml` 已提交：templates=「.」、build=`moon build .`、app-id 对齐应用；`run` 留空由 build 的 Artifacts 推导）②`moon run ../../tools/native-gui-tools/mng_cli -- dev` 起应用；③应用进「模板 Dev」页 ④改结构/字面量/`class`/`<style>` 值保存 → HOT（日志 `[HOT] 补丁已推送`、应用内 toast「模板补丁已应用」；样式章视觉——类槽覆盖/令牌/枚举值/交互态——随本步一并看）⑤改表达式文本（`@shared.tx("…")`、`{{ qty + 1 }}`、`v-if="qty > 5"`）→ 受限文法内 HOT；新函数/新符号 → `[HOT→COLD]` 带原因 ⑥改 script / v-for / 自定义组件 / 表外参数 → COLD，重启后自动回到改动页（`[COLD] 已请求回到模板页`）⑦把 stepper 调到 7 再走 HOT，值仍为 7（状态保活）；COLD 后回 3
- [ ] **编辑器真机复验**：`cd tools/vscode-mng && npx @vscode/vsce package` 打 0.2.9 vsix 安装（覆盖加 `--force`）→ Reload Window，按 `tools/vscode-mng/README.md` 清单一走——语义着色（类型/变量/参数/函数/方法/命名空间分档；主题未开语义高亮需设 `editor.semanticHighlighting.enabled: true`）、TextMate 着色、snippets、补全、Problems 诊断、hover、跳转、命令面板「MNG: 新建页面」

### 工具后续批次

- [ ] **Windows LSP 跳转真机复验**（用户执行）：代码侧已收口（2026-11-04：`uri_to_path`/`path_to_uri` 归一——盘符前导岔斜、反斜杠、`file:///c%3A/…` 解岔斜，纯函数用例三平台同跑、集成用例去分流）——Windows 真机在 VS Code 里验一遍跳转落点与行号口径（含 hover 的 `moon ide` 桥），过了本条删除
- [ ] **握手与折层真机复验**（用户执行）：①`mng dev` 跑起来后进「模板 Dev」，改 script 加一个新 Store 并保存 → 该改本应 COLD，若工具侧先推了 HOT 补丁，日志应出现 `[HOT→COLD] 握手不符：注册表键集落后…` 随后 `[COLD] … 应用已重启`、应用回到改动页（**不再出现「补丁失败」toast 后界面停在旧树**）；②正常 HOT（只改结构/字面量）日志 `[HOT] 补丁已应用`，应用内 toast 同步；③样式全序：给 `hover_group` 挂 `class=[style(padding=14.0)]` 的条目看内缩真的按 class 走（散参数 `<` class）

## 主题与样式批次真机复验（用户执行；落地项已在 roadmap「已实现·主题与样式」标 🚧，过了逐条翻 ✅）

- [ ] **样式补全观感**：showcase「过渡与效果」页与「画布与富文本」页看四件——渐变背景（线性/径向、stop 用主题 token 时随主色变；半透明 stop 在 Windows/mac 的插值口径与 Linux 是否一致）、每角圆角与每边边框（不等半径四角、四边独立宽色；带圆角时 per-side 回落统一描边是否诚实）、`mix_blend_mode` 混排（改档看有没有漏到同帧兄弟）、删除线与上划线（折行段落落在最后一行）；令牌间距看整板留白是否仍与改前一致
- [ ] **主题批次观感**：`examples/theme-playground` 按 TP-1.1..5.1 走完（深色系统起窗即深色=默认一次性探测生效）；主题 JSON 落盘改色（dev 档 `mng.toml` `theme` 键存盘即重载）；深浅变体看 tooltip 反色与滚动条/分隔线深档提亮；code_view 在浅色与深色主题下底色跟不跟 `theme_current()`，显式 `code_theme` 是否钉死
- [ ] **窗口族探测口径**：`shell_caps()` 八位在无合成器的 Linux 会话上 `opacity`/`transparent_bg` 位应为 false，`set_transparent_bg` 应回 `Unsupported` 而非静默无效；`native_handle()` 三平台返回值非 0 且能喂给平台 API

## 核查收口批（2026-11-03 核查：浮层原生档与 mac GIF 代码已在树——两件文档追平、三件真机复验；dock/任务栏进度这类单平台条目不做，已从待办与路线图撤下）

- [ ] **浮层原生档 Linux 复验**（用户执行）：browser 示例按 BR-1.4 过一遍——↑↓/回车/Esc 键盘、开着再点按钮应直接收起不闪、点外收起且不触发被点控件、弹出无闪现。win/mac 已过（2026-11-06），Linux GTK 段对齐（accept_focus/focus_on_map 关闭 + 延迟 map）后待确认
- [ ] **通知 urgent 二档真机复验**（用户执行，mac）：同一应用分别发 `urgent=true`（缺省）与 `urgent=false`，应用正在前台跑事件循环时前者出横幅、后者只进通知中心不出条；系统设置里关掉「时间敏感」授权后再发 `urgent=true` 应回落到静默。状态行 `backend=` 应报 `un-user-notification`（Linux 报 `dbus`、Windows 报 `win-balloon`）
- [ ] **frame_cost_probe 三平台读数**（用户执行，Windows / macOS 各一遍）：`moon run experiment/frame_cost_probe`，贴全部 `FRAME-COST` 行——重点看 `paint_full` vs `paint_clip` 的 `skip`（纯光栅腿才判交，那条腿的差值才是「图表/整页增量重绘」的立项依据）。Linux 腿已跑：树不变 relayout 20 帧 `ms=0`、`measure=0`（yoga 布局缓存不立项），整页 240 行 ≈3.5ms/帧（判据进测试用例附录 D）

## 媒体硬解探针（Linux 腿已跑通，Win/mac 两腿待用户执行）

- [ ] **硬解探针**：Linux 腿已跑通到「真解一帧」——`open_video_decoder(hw=true)` 走 VAAPI + transfer，首帧与软解逐字节一致，`hw_status=1`；`experiment/hwdecode_probe` 逐设备 open/frames/transfer 读数进方案 §四，设备建得起来≠能用、transfer 全空两条坑已记。剩 Win/mac 两腿（`cc -O2 hwdecode_probe.c $(pkg-config --cflags --libs libavcodec libavutil)`，判据：设备建得起来且 transfer 非空）+ 归档实物核验（Windows BtbN lgpl 归档已命中 `av_d3d11va_alloc_context`、mac 归档脚本从初立就带 `--enable-videotoolbox`——只剩 `otool -L` 验实物与 LICENSE.txt 口径修正）；未决见 proposals/media-hwdecode.md §六 spike

## 品牌与应用图标 v1（2026-11-09 立项，定案见 [experience/brand.md](experience/brand.md)；一项一提交，做完删一项）

（品牌定案与资产落位已收口：`experience/brand.md` + `assets/brand/` + placement 登记；导出矩阵已落 `scripts/gen_brand_icons.py` 并替换 showcase 图标，2026-11-09）

- [ ] **showcase 新图标真机复验**（用户执行）：`cd examples/showcase && moon run ../../tools/native-gui-tools/mng -- package`——DMG 拖装后看 Dock 图标应为新版（玫红月兔 + 靛蓝空窗口）；旧 64px 月牙已换 1024 master 派生图（全档再生成 `python3 scripts/gen_brand_icons.py`，icns 仍由 mng 的 sips+iconutil 合成）
- [ ] **文档站与 README 品牌区**（中英先行中文）：logo、favicon、品牌色说明
- [ ] **库内置图标替换**（`gui/win` 内置月牙 + `gui/dbus` 托盘）：随批过 `moon check`/`moon test` 门禁；发 0.4.0 与否用户定
- [ ] **情景插画**（第二批）：README 头图 / 文档站首页「兔子坐在电脑前」叙事版

