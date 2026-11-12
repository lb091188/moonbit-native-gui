# TODO — 当前进行中的工作

> 只记「已实现、待复验 / 待收尾」的现行事项；规划与未来批次见 [docs/zh/reference/roadmap.md](docs/zh/reference/roadmap.md)「已规划」，实测坑与口径见 [experience/adaptation.md](experience/adaptation.md)。完成一项删一项，并同步路线图状态。


## 实施队列（2026-11-04 排定，用户指定顺序：无障碍 → 代码/终端 → GPU。做完一项删一项并同步路线图，一项一提交）

（无障碍线已于 2026-11-06 容后：三平台桥全部落地、mac VoiceOver 首轮已过，剩 Orca/NVDA 真机清单；
进度与剩余项归档 [proposals/text-selection-a11y.md](proposals/text-selection-a11y.md) §九，恢复时按那里接。
Wayland/DE 专属工作（协议客户、spike、DE 实测矩阵）已移交 [proposals/linux-mbt.md](proposals/linux-mbt.md) 规划，不在本库任务队列）

### 一、代码/终端（mng 工具链）

（已全部收口：三项完成见 git log 2026-11-04；Windows 真机复验 2026-11-08 过——复验中揪出非 ASCII 路径定义跳转空白一处，修复见 50f1f748，坑回写 experience/adaptation.md）

### 二、GPU（按 [proposals/gpu-architecture.md](proposals/gpu-architecture.md) 分批）

（2026-11-07 全部收口：X11 三角形真机过（三色三角形、关窗/Esc 正常退出）；GPU 画布 mac/win/Linux 三腿真机全过——Linux 应用进程「检查读回」非零、与无头用例一致；Linux L1 独立 X 子窗口承载真机复验含最小化恢复场景。GPU 验证队列清空，后续实现批（视频直纹理、GPU 控件纹理进合成器等）见 roadmap「已规划 · 渲染」与 proposals）

## mng 全入口 P0：doctor 体检 + ready（2026-11-11 立项并全收口，分期与入口状态机见 [docs/zh/reference/roadmap.md](docs/zh/reference/roadmap.md)「已规划 · 开发体验」）

（2026-11-11 代码全合入 + 三平台真机全过，本段收口归档——**mac 腿**：裸 mng 先体检后 usage、二跑一跳而过、`doctor -f` 重检全绿重盖 ready、中文档正常、含构建探针项；**win 腿三轮**：①vswhere 组件判定误报红→改构建探针判（29116521）②探针写盘失败 [!]→落盘路径两坑修 + 探针写失败改拦 ready（014a29a5）③用户确认全绿；**linux 腿**：2026-11-11 用户确认过（GTK/修复行读数正常）。坑记 adaptation.md）

## prebuild 去 py：移植 prebuild.mbtx（2026-11-11 探针定案可做，见 adaptation.md「moon prebuild 钩子去 py 探针」；一项一提交，做完删一项）

（2026-11-11 主模块批已合入（67938096）：prebuild.py 407 行移植 mbtx、moon.mod 切换、py 删除、doctor Python 项退役、build.md/mng.md 双语同步；mac 对拍逐字段一致 + hello 端到端链接 + stamp 缓存 0.3s。移植坑记 adaptation.md「prebuild.py → prebuild.mbtx 移植坑」）

- [ ] **win/linux 腿验证**（用户/CI）：CI 三腿绿（mbtx 在两平台首跑）+ 最好在无 python 环境各跑一次 `moon build examples/hello`（win：摘 PATH 里 python；linux：docker 无 python 镜像）
- [ ] **gui-media / gui-gpu 的 prebuild 移植**：确认含归档下载（HTTP 已实锤 grep 到）；评估 mbtx 网络能力（async 有无 http 客户端）或下载前移 mng，随后同款移植

## mng 全入口 P1：mngui 向导壳（2026-11-11 动手，分期见 roadmap「已规划 · 开发体验」；一项一提交，做完删一项）

- [x] **scaffold 内核化**：`@scaffold` 事件回调（f689452c），mng 留渲染层
- [x] **mngui 五步壳 + 裸 mng 下一跳**（本批）：欢迎→体检→新建（@scaffold）→起 dev（shell 包装 cwd 工程目录；dev 形态经 `moon -C <仓库> run … mng -- dev`）→完成；体检开窗前同步跑完；无显示 exit 3，裸 mng 据此回 usage；dev 形态（_build 路径）不跳向导；mngui 查找按进程真实路径自解析（argv[0] 是 shell 敲的名字——真坑，proc 加 self_path 三平台自报路径，兜底 ~/.moon/bin；未装给安装提示，0a128ef9 + 本批）
- [ ] **mngui 真机复验**（用户执行）：`moon install ./tools/native-gui-tools` 后裸 `mng` 应开向导窗；五步走通——体检四项 ✓、建 demo 工程（可试给一个 1024 PNG：应落 `assets/icon.png` 且 mng.toml `icon` 键接上；给错路径应红字提示且工程不回滚）、启动 mng dev 后应用窗弹出、关向导 dev 仍在、完成页命令可选中复制；无显示机（SSH）裸 mng 应回 usage；另验本批两修复——任意页步骤条整体撑满窗宽（连线随窗拉伸不缩成点）、点数字方块换内容但高亮不动且顶部出预览提示条、「返回当前步」回进度页
- [x] **步骤条点击预览 + 满宽修复**（本批）：`@ui.steps` 数字方块可点（缺省切换 current/on_select 接管 + 每格进 Tab 链方向键换步）；mngui 点数字只动 view 做预览、进度高亮不动，顶部出「正在预览」提示条 + 返回按钮；根 col 补 `grow=1.0` 修「体检页整块收窄」——窗口根是 Row 方向，根容器不设 grow 会按内容收宽
- [x] **图标步**（本批）：`@scaffold.icon_step`——PNG 收进工程 `assets/icon.png` + 改写 mng.toml `icon` 键（wbtest 钉行替换口径）；icns/ico 各档派生归 `mng package` 打包时做，向导不重复

## mng 全入口 P2：工程中心化真机复验（2026-11-12 代码合入，用户执行）

- [ ] **mng run/check/test 冒烟**（用户执行）：任一工程里 `mng run`（应 build 后前台起应用，Ctrl-C 退出码透传）、`mng check -p <包>`（参数透传）、`mng test`（退出码透传——故意改挂一个测试看非零）
- [ ] **mng icons 真机复验**（用户执行）：`mng icons <任一 1024 PNG> -o /tmp/ic`——mac 应出 `.ico`（`file` 验 MS Windows icon resource）+ `.icns` + `.iconset` 十档；linux/win 应只出 ico 并提示 icns 跳过
- [ ] **mng ffmpeg-dll win 腿**（用户执行）：`mng ffmpeg-dll --dry-run` 打印计划不落盘；去 `--dry-run` 后 audio/video exe 旁应齐 5 支 dll；`--run` 起示例
- [ ] **工程面板真机复验**（用户执行）：已有工程里裸 `mng`（ready 有效）应开「mng 工程面板」窗（非五步向导）——标题下工程路径可选中复制、四按钮（打包/发布/启动热更/刷新日志）、点打包后提示 pid、跑完刷新日志出 tail（等宽字体末 60 行）；无 mng.toml/moon.mod 目录裸 mng 仍进新建向导；dev 形态（_build 起的）不跳向导



> 产物钉死四件：macOS DMG、Windows setup（NSIS）、Linux deb + AppImage；tar.gz 与 PKGBUILD 不做。Linux 自动更新走 AppImage 单文件替换，deb 档报新版本引导下载。

- [ ] **A1 mac 腿真机复验**（用户执行）：`cd examples/components && moon run ../../tools/native-gui-tools/mng -- package`——`.mng/dist/` 应出 `Native GUI Showcase.app` + `showcase-0.1.0-darwin-aarch64.dmg/.zip` 三件；挂 DMG 拖装运行（adhoc 首启 Gatekeeper 右键放行属已知），看 Dock 图标（assets/icon.png 派生）与资源（2026-11-09 主链已过：拖装双击真机过（demo_app 实测；途中修出 DMG 卷内执行位、.exe 名两缺陷）；components DMG 卷内签名/可执行位挂载实测过；剩 components 拖装看 Dock 图标与资源一小步）

（A1 linux 腿 2026-11-09 真机过：AppImage + deb 全流程按清单走通（appimagetool 手动放置绕 GitHub 不通，自动下载失败真因靠 run_tool 退出码修复现形）；复验修出 `spawn_wait` 缺陷见 6ad6c68e）
- [ ] **A2 更新器 v1·真机复验**（用户执行）：`update_check/update_download/update_apply_carrier/update_relaunch` 链路——mac 装 0.1.0 → CI 发 0.2.0 draft → 应用内检查下载替换重启后版本变 0.2.0、`.mng-old` 清理；Linux 腿 AppImage 自替换同流程；system 示例「系统集成 → 应用自更新」演示后端走全态（检查中旋转弧→0.9.9→下载→就绪→安装提示）、真实清单在 CI 首跑前报拉取失败也属验证；**免 CI 先走本地服务腿**（2026-11-10 落地，SC-11.16）：`mng package` 出新版载体 → `python3 scripts/update_local_server.py --version <同载体版本>` → 旧版应用点「检查更新(本地服务)」走全链路——**mac 腿真机过**（2026-11-10：检查/下载/替换/自动弹新窗/自报新版本不再报更新/.mng-old 清理全过）。**Linux 腿部分验证、未收口**：AppImage 替换与重启已通（`$APPIMAGE` 修复 3df4eeec 真机生效——替换落 .AppImage 真身、重启自动弹窗、不再报挂载点挪不动）；卡「更新完成后版本号仍 0.2.0」——根因已定位并修复：mng package 构建前不同步 appmeta，载体文件名新版本而二进制自报旧版本（修复 d5da9b60），**待 Linux 拉取后重新打包复验**（修复只作用于之后的打包，旧载体文件不受影响；自检三行必须一致：`git log -1`、`grep ^version mng.toml`、`grep app_version appmeta/appmeta.gen.mbt`）。另修 appimagetool 坏缓存自愈（ff022c36，断网期失败一次后永久报不可用；代理场景已证下载链路通）。剩：Linux 腿复验收口、CI 真实清单腿（依赖 release-app 首跑）。首测修出：mac 替换臂只读位置可读报错+挪旧装新（4a206caf）、自报版本双源漂移根治为 appmeta 生成码单源（改版本只动 mng.toml，components 已接）
- [ ] **A2 mng publish 真机复验**（用户执行，装 gh 并 `gh auth login`）：`cd examples/components && moon run ../../tools/native-gui-tools/mng -- package && moon run ../../tools/native-gui-tools/mng -- publish --no-upload --repo <owner>/<repo>`——`.mng/dist/update.json` 应含 darwin-aarch64 的 zip 条目（url 指向 releases/download、sha256 与 `shasum -a 256` 一致）；真上传档核 draft Release 产物清单后删
- [ ] **release-app CI 首跑**（用户执行）：推 tag `app-v0.1.0` 触发——打包腿出 DMG/zip、汇总腿出 `update.json`（只含 darwin-aarch64 的 zip 条目）并发 draft Release；win/linux job 骨架已注释预置，对应腿合入后取消注释启用

## 内建 inspector（2026-11-08 立项，方向见 [proposals/方向.md](proposals/方向.md) A4；一项一提交，做完删一项）

（演示页已随示例收拢从 components 出清，库包 `gui/inspector` 保留；下面两条真机清单随「dev 工具独立示例」批恢复执行——验收后见 roadmap「已规划 · 示例与文档」，原页源码从历史取回）

- [ ] **v1 只读面板真机复验**（用户执行）：检查器演示页——树里能看到当前页控件（按父链缩进）、点行看读数（矩形与界面位置对得上）、动一动界面再点「刷新」树变化、自动刷新开着时不卡帧、重置统计后 frames 重算
- [ ] **v2 样式回灌真机复验**（用户执行）：检查器演示页样式类页签——选中一个类改背景色「应用」，用了该类的控件下一帧变色；「还原此类」回原样；空白输入不改字段；token 名与 #hex 都生效

## 方向 A 类其余项（2026-11-08 用户定全部入待办，方向见 [proposals/方向.md](proposals/方向.md)；顺序在打包/更新/inspector 之后，一项一提交）

- [ ] **A6 CPU/GPU 像素对拍**：与「无头像素快照基线」合并比对器，随控件级 GPU 批扩用例

## mngdev 库包与工具链联动（2026-11-07 立项，方案见 [proposals/mngdev-library.md](proposals/mngdev-library.md)；一项一提交，做完删一项）

（代码侧四件全部落地并逐项提交推送：dev 面进库 c8051433、lsp 诊断联动 411cbc2e、脚手架 7acf24e3、文档收口本笔；本批只剩真机/编辑器复验，均由用户执行）

> 机械部分已自动化（2026-11-08）：`scripts/mng_scenario.sh`（脚手架→dev 首轮→HOT→COLD 重启回页→[NEW]/[GONE]/[SRC]→生产构建，14 条）与 `cd tools/vscode-mng && npm test` / `npm run test:vscode`（着色分词、真 mng lsp 会话、真编辑器里的诊断/hover/新建页面）已进 CI。下面留着的是**观感与主观项**，仍由人工过。

（dev 面进库复验 2026-11-09 过、lsp 诊断联动复验 2026-11-10 过：热更循环 HOT/COLD；`moon check` 错误回投模板行列、修复后清零。复验修出三缺陷：check 超预算静默丢 258f3612、重入吞保存迟一拍 6041f1c9、与 dev regen 抢跑读旧生成码致反相幽灵 aad9256b——check 前就地 regen 根治，`mng dev` 不跑诊断也成立。gen.mbt 的 MLS 双报已压 31e8e1eb（*.gen.mbt 关联 mng-gen 语言，VSIX ≥0.2.15 生效）；已知观感：修复型保存后闪一次旧状态自纠）

- [ ] **脚手架冒烟**（用户执行，含 `mng new` 改面复验）：仓库内 `mng new demo1`（裸名即建工程；**需把 demo1 加进 `moon.work` members**，否则按注册表解析）→ `cd demo1 && moon run .` 起窗 → 改 pages/home.mng 保存看 `mng dev` 热更；另验 `mng new page pages/about`（父目录现建）与命令面板「MNG: 新建页面」。**仓外腿**：gui 0.3.2 已发布（含 mngdev 与 prebuild.mbtx），可在仓库外 `mng new demo && mng dev` 走一遍全链

## 终端与单文件 DX 批（2026-11-06 排定，方案见 [proposals/terminal-sfc-dx.md](proposals/terminal-sfc-dx.md)——代码侧九件全部落地并逐项提交推送，本批只剩真机复验，均由用户执行）

- [ ] **终端控件真机复验**（用户执行）：components「代码文档」→「终端」段按 SC-6.5 走（ANSI 16/256/truecolor、CJK 对齐、折行、滚轮回看 + Shift+PageUp + 滚动条、四按钮、打字/退格/方向键回显、回车喂回、拖选 Ctrl/Cmd+C 复制、裸 Ctrl+C 进输入、深浅主题）
- [ ] **模板 v-for 真机复验**（用户执行）：components「代码文档」→「模板列表」段按 SC-6.6 走（加/删首/清空、行序一致、无残影）；`mng dev` 下改 vfor_demo 行模板应 `[HOT→COLD]` 带原因重启
- [ ] **项目级 build 与 dev watch 真机复验**（用户执行）：①`cd examples/components && moon run ../../tools/native-gui-tools/mng -- build` 应列出全部模板 OK 且 `moon check` 过（注意会把 dev 形态生成码覆盖成生产形态，复验完 `git checkout` 生成码或跑一轮 dev 恢复）；②`mng dev` 跑着时新建一个 `.mng` → 日志 `[NEW]` 并自动重启；删除它 → `[GONE]` 清生成码；改 `main.mbt` → `[SRC]` 并重启
- [ ] **hello mng 冒烟**（用户执行）：`moon run examples/hello` 起窗，按 HL-1.x 输入名字 / 步进计数 / 重置；同目录 `mng dev` 改 `hello.mng` 保存看声明页热更（HL-1.4）

## 模板预编译（2026-11-01 启动，方案见 [proposals/native-template.md](proposals/native-template.md) 与 [proposals/mng-project-dev.md](proposals/mng-project-dev.md)；已完成叙事归 roadmap「开发体验」，此处只留未完成项）

### 真机复验（用户执行）

> 日志口径与重启编排这类机械项已由 `scripts/mng_scenario.sh` 覆盖（CI 三腿里 Linux/mac 跑）；下面几条要判的是**看得见的东西**：toast、亚秒手感、状态保活后的数值、样式章观感。

- [ ] **热更真机复验**：①`cd examples/hello`（`mng.toml` 已提交：templates=「.」、build=`moon build .`、app-id 对齐应用；`run` 留空由 build 的 Artifacts 推导）②`moon run ../../tools/native-gui-tools/mng_cli -- dev` 起应用；③改 `hello.mng` 的标题/提示字面量保存 → HOT（日志 `[HOT] 补丁已推送`、应用日志 `HELLO-DEV: 模板补丁已应用`；`<style>` 里类规则的字号/颜色值随保存热更）④改插值与按钮回调里的受限表达式 → 受限文法内 HOT；新函数/新符号 → `[HOT→COLD]` 带原因 ⑤改 script 状态声明 → COLD，重启后自动回到首页 ⑥把 stepper 调到 7 再只改字面量走 HOT，值仍为 7（状态保活）；COLD 后回 0 ⑦（v-for 面）`cd examples/components` 起 `mng dev`，改 `pages/vfor_demo.mng` 行模板应 `[HOT→COLD]` 带原因重启（SC-6.6）
- [ ] **编辑器真机复验**：`cd tools/vscode-mng && npx @vscode/vsce package` 打 0.2.9 vsix 安装（覆盖加 `--force`）→ Reload Window，按 `tools/vscode-mng/README.md` 清单一走——语义着色（类型/变量/参数/函数/方法/命名空间分档；主题未开语义高亮需设 `editor.semanticHighlighting.enabled: true`）、TextMate 着色、snippets、补全、Problems 诊断、hover、跳转、命令面板「MNG: 新建页面」

### 工具后续批次

- [ ] **Windows LSP 跳转真机复验**（用户执行）：代码侧已收口（2026-11-04：`uri_to_path`/`path_to_uri` 归一——盘符前导岔斜、反斜杠、`file:///c%3A/…` 解岔斜，纯函数用例三平台同跑、集成用例去分流）——Windows 真机在 VS Code 里验一遍跳转落点与行号口径（含 hover 的 `moon ide` 桥），过了本条删除
- [ ] **握手与折层真机复验**（用户执行）：①`examples/hello` 起 `mng dev`，改 `hello.mng` script 加一个新 Store 并保存 → 该改本应 COLD，若工具侧先推了 HOT 补丁，日志应出现 `[HOT→COLD] 握手不符：注册表键集落后…` 随后 `[COLD] … 应用已重启`、应用回到首页（**不再出现「补丁失败」后界面停在旧树**）；②正常 HOT（只改字面量）日志 `[HOT] 补丁已应用`，应用日志同步；③样式全序：components「事件与布局」页给 `hover_group` 挂 `class=[style(padding=14.0)]` 的条目看内缩真的按 class 走（散参数 `<` class）

## 主题与样式批次真机复验（用户执行；落地项已在 roadmap「已实现·主题与样式」标 🚧，过了逐条翻 ✅）

- [ ] **样式补全观感**：components「过渡与效果」页与 canvas「画布与富文本」页看四件——渐变背景（线性/径向、stop 用主题 token 时随主色变；半透明 stop 在 Windows/mac 的插值口径与 Linux 是否一致）、每角圆角与每边边框（不等半径四角、四边独立宽色；带圆角时 per-side 回落统一描边是否诚实）、`mix_blend_mode` 混排（改档看有没有漏到同帧兄弟）、删除线与上划线（折行段落落在最后一行）；令牌间距看整板留白是否仍与改前一致
- [ ] **主题批次观感**：`examples/theme-playground` 按 TP-1.1..5.1 走完（深色系统起窗即深色=默认一次性探测生效）；主题 JSON 落盘改色（dev 档 `mng.toml` `theme` 键存盘即重载）；深浅变体看 tooltip 反色与滚动条/分隔线深档提亮；code_view 在浅色与深色主题下底色跟不跟 `theme_current()`，显式 `code_theme` 是否钉死
- [ ] **窗口族探测口径**：`shell_caps()` 八位在无合成器的 Linux 会话上 `opacity`/`transparent_bg` 位应为 false，`set_transparent_bg` 应回 `Unsupported` 而非静默无效；`native_handle()` 三平台返回值非 0 且能喂给平台 API

## 核查收口批（2026-11-03 核查：浮层原生档与 mac GIF 代码已在树——两件文档追平、三件真机复验；dock/任务栏进度这类单平台条目不做，已从待办与路线图撤下）

- [ ] **浮层原生档 Linux 复验**（用户执行）：browser 示例按 BR-1.4 过一遍——↑↓/回车/Esc 键盘、开着再点按钮应直接收起不闪、点外收起且不触发被点控件、弹出无闪现。win/mac 已过（2026-11-06），Linux GTK 段对齐（accept_focus/focus_on_map 关闭 + 延迟 map）后待确认
- [ ] **通知 urgent 二档真机复验**（用户执行，mac）：同一应用分别发 `urgent=true`（缺省）与 `urgent=false`，应用正在前台跑事件循环时前者出横幅、后者只进通知中心不出条；系统设置里关掉「时间敏感」授权后再发 `urgent=true` 应回落到静默。状态行 `backend=` 应报 `un-user-notification`（Linux 报 `dbus`、Windows 报 `win-balloon`）
- [ ] **frame_cost_probe 三平台读数**（用户执行，Windows / macOS 各一遍）：`moon run experiment/frame_cost_probe`，贴全部 `FRAME-COST` 行——重点看 `paint_full` vs `paint_clip` 的 `skip`（纯光栅腿才判交，那条腿的差值才是「图表/整页增量重绘」的立项依据）。Linux 腿已跑：树不变 relayout 20 帧 `ms=0`、`measure=0`（yoga 布局缓存不立项），整页 240 行 ≈3.5ms/帧（判据进测试用例附录 D）

## 媒体硬解探针（Linux 腿已跑通，Win/mac 两腿待用户执行）

- [ ] **硬解探针**：Linux 腿已跑通到「真解一帧」——`open_video_decoder(hw=true)` 走 VAAPI + transfer，首帧与软解逐字节一致，`hw_status=1`；`experiment/hwdecode_probe` 逐设备 open/frames/transfer 读数进方案 §四，设备建得起来≠能用、transfer 全空两条坑已记。剩 Win/mac 两腿（`cc -O2 hwdecode_probe.c $(pkg-config --cflags --libs libavcodec libavutil)`，判据：设备建得起来且 transfer 非空）+ 归档实物核验（Windows BtbN lgpl 归档已命中 `av_d3d11va_alloc_context`、mac 归档脚本从初立就带 `--enable-videotoolbox`——只剩 `otool -L` 验实物与 LICENSE.txt 口径修正）；未决见 proposals/media-hwdecode.md §六 spike

## 品牌与应用图标 v1（2026-11-09 立项，定案见 [experience/brand.md](experience/brand.md)；一项一提交，做完删一项）

（品牌定案与资产落位已收口：`experience/brand.md` + `assets/brand/` + placement 登记；导出矩阵已落 `scripts/gen_brand_icons.py` 并替换 components 图标；文档站 logo/favicon 与中英 README 头图已接，2026-11-10）

- [ ] **components 新图标真机复验**（用户执行）：`cd examples/components && moon run ../../tools/native-gui-tools/mng -- package`——DMG 拖装后看 Dock 图标应为新版（玫红月兔 + 靛蓝空窗口）；旧 64px 月牙已换 1024 master 派生图（全档再生成 `python3 scripts/gen_brand_icons.py`，icns 仍由 mng 的 sips+iconutil 合成）
- [ ] **库内置托盘图标真机复验**（用户执行）：system「系统集成」托盘段点「回库内置」——托盘图标应为新版（玫红双耳 + 靛蓝窗口），三平台各看一眼；代码侧已收口（`gui/dbus/icon.mbt` 程序绘制品牌造型，`moon check --deny-warn` 零警告、`moon test dbus shell` 143/143，2026-11-10）；发 0.4.0 与否用户定
- [ ] **情景插画**（第二批）：README 头图 / 文档站首页「兔子坐在电脑前」叙事版

