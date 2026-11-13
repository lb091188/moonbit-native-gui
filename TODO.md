# TODO — 当前进行中的工作

> 只记「待做什么 + 怎么验证」；规划与未来批次见 [docs/zh/reference/roadmap.md](docs/zh/reference/roadmap.md)「已规划」，实测坑与口径见 [experience/adaptation.md](experience/adaptation.md)。完成一项删一项，并同步路线图状态。
>
> 条目格式约定：
>
> - 一条只写一件事；复验条目写清执行者（用户执行 / CI）与编号步骤
> - 进度叙事不进本文件——已做的看 git log，坑与根因看 experience/adaptation.md
> - 状态标记 ✅ / 🚧 / ⏳ 语义见路线图「怎么读」

## 恢复入口

- 无障碍线（2026-11-06 容后）：剩 Orca / NVDA 真机清单，恢复时按 [proposals/text-selection-a11y.md](proposals/text-selection-a11y.md) §九接
- Wayland / DE 专属工作：已移交 [proposals/linux-mbt.md](proposals/linux-mbt.md) 规划，不在本队列

## CI 与门禁

- [ ] **恢复 CI 热更场景门禁**（2026-11-13 移出）：Linux / mac 两腿的「mng 应用侧场景」已标 `continue-on-error`——本机 mng_scenario 连跑 4 轮 15/15 全绿，CI 仍偶发红；查 CI 环境差异（xvfb / 启动耗时 / 构建负载）后删标记恢复门禁
- [ ] **gui-media video_wbtest mac 本机失败**（CI 未覆盖组合）：用例「VideoPlayer 时钟同轴：回退 fps 不影响时间轴」——回拨 500ms 后位置 0.613 / 0.633（期望窗 0.45–0.55），稳定复现；Windows CI 每轮跑且过，Linux / mac 腿不跑 gui-media test 故从未暴露
- [ ] **prebuild mbtx 两腿验证**（CI，最好加无 python 环境腿）：CI 三腿绿（mbtx 在 win / linux 首跑）；另在无 python 环境各跑一次 `moon build examples/hello`——win 摘 PATH 里 python，linux 用无 python 的 docker 镜像

## mng 工具链复验（用户执行）

- [ ] **mngui 向导壳**：`moon install ./tools/native-gui-tools` 后裸 `mng`：
  1. 应开向导窗
  2. 五步走通：体检四项 ✓ → 建 demo 工程 → 起 dev 应用窗弹出 → 关向导 dev 仍在 → 完成页命令可选中复制
  3. 图标步给一个 1024 PNG：应落 `assets/icon.png` 且 `mng.toml` `icon` 键接上；给错路径应红字提示且工程不回滚
  4. 无显示机（SSH）裸 `mng` 应回 usage
  5. 观感三件：任意页步骤条整体撑满窗宽（连线随窗拉伸不缩成点）；点数字方块换内容但高亮不动、顶部出预览提示条；「返回当前步」回进度页
- [ ] **mng run / check / test**（任一工程）：
  1. `mng run`：build 后前台起应用，Ctrl-C 退出码透传
  2. `mng check -p <包>`：参数透传
  3. `mng test`：故意改挂一个测试，退出码非零
- [ ] **mng icons**：`mng icons <任一 1024 PNG> -o /tmp/ic`——mac 出 `.ico`（`file` 验 MS Windows icon resource）+ `.icns` + `.iconset` 十档；linux / win 只出 ico 并提示 icns 跳过
- [ ] **mng ffmpeg-dll**（Windows）：`mng ffmpeg-dll --dry-run` 打印计划不落盘；去 `--dry-run` 后 audio / video exe 旁应齐 5 支 dll；`--run` 起示例
- [ ] **工程面板**：已有工程（ready 有效）裸 `mng` 应开「mng 工程面板」窗（非五步向导）：
  1. 标题下工程路径可选中复制
  2. 四按钮：打包 / 发布 / 启动热更 / 刷新日志
  3. 点打包后提示 pid，跑完刷新日志出 tail（等宽字体末 60 行）
  4. 无 `mng.toml` / `moon.mod` 目录裸 `mng` 仍进新建向导
  5. dev 形态（`_build` 起的）不跳向导
- [ ] **mng new 脚手架冒烟**：
  1. 仓库内 `mng new demo1`（裸名即建工程；demo1 需加进 `moon.work` members，否则按注册表解析）
  2. `cd demo1 && moon run .` 起窗
  3. 改 `pages/home.mng` 保存，`mng dev` 看热更
  4. `mng new page pages/about`（父目录现建）；VS Code 命令面板「MNG: 新建页面」
  5. 仓外腿：gui 0.3.3 已发布（含 mngdev 与 prebuild.mbtx），仓库外 `mng new demo && mng dev` 走全链
- [ ] **Windows LSP 跳转**：Windows 真机 VS Code 里验跳转落点与行号口径（含 hover 的 `moon ide` 桥）
- [ ] **Windows dev 唤醒**（真机）：Windows 下 `mng dev` 唤醒链路真机验证（已合入待真机）
- [ ] **握手与折层**：
  1. `examples/hello` 起 `mng dev`，改 `hello.mng` script 加新 Store 保存 → 该改本应 COLD；若工具侧先推了 HOT 补丁，日志应出 `[HOT→COLD] 握手不符：注册表键集落后…` 随后 `[COLD] … 应用已重启`、应用回首页（不再出现「补丁失败」后界面停在旧树）
  2. 正常 HOT（只改字面量）日志 `[HOT] 补丁已应用`，应用日志同步
  3. components「事件与布局」页给 `hover_group` 挂 `class=[style(padding=14.0)]` 条目，内缩应按 class 走（散参数 < class）

## 示例与控件复验（用户执行）

- [ ] **新窗首帧**：`cd examples/hello` 依次开三档子窗，**不动鼠标**每扇窗内容立即可见（不再白屏等鼠标）
- [ ] **托盘单色**：浅色 / 深色模式下看 hello / 内置托盘图标——纯黑 / 纯白剪影、留白收紧；mac 为模板图（颜色由系统按菜单栏实际明暗自动反色）；Windows / Linux 跟随系统明暗换黑白
- [ ] **hello 开关窗**：同一档按钮「打开 → 关闭」单例（重复点不叠加）；子窗标题栏关闭后 ≤200ms 按钮回「打开」；提示语为单页组件与开发工具说明、无热更字样
- [ ] **sysmonitor 改版**：六项菜单（含 CPU 型号 / 内存品牌频率 / 多显卡名称行）、右栏 <400 横向滚动、CPU 各核小图换行、网络只列实体网卡、磁盘无 loop / 光驱 / 网络盘、显卡页无温度段、进程页搜索 / 结束 / 中文状态 / 列宽拖动 / 表格填满
- [ ] **窗口功能迁 hello**：hello 整页纵滚——mng 入门页 → 基本窗口示例 → 三段窗口功能（窗口 API / 多窗口 / 透明度，瘦身定案；透明度段无「背景穿透」按钮，主窗不提供）；透明测试窗卡片外**透出桌面不呈黑底**（mac 透明档已拦 GPU 档）；components 侧栏不再有「窗口」页（少一项、其余页照常）；用例 HL-4.1~4.3
- [ ] **终端控件**：components「代码文档」→「终端」段按 SC-6.5 走——ANSI 16/256/truecolor、CJK 对齐、折行、滚轮回看 + Shift+PageUp + 滚动条、四按钮、打字 / 退格 / 方向键回显、回车喂回、拖选 Ctrl/Cmd+C 复制、裸 Ctrl+C 进输入、深浅主题
- [ ] **模板 v-for**：components「代码文档」→「模板列表」段按 SC-6.6 走——加 / 删首 / 清空、行序一致、无残影；`mng dev` 下改 `vfor_demo` 行模板应 `[HOT→COLD]` 带原因重启
- [ ] **项目级 build 与 dev watch**：
  1. `cd examples/components && moon run ../../tools/native-gui-tools/mng -- build`：应列全部模板 OK 且 `moon check` 过（会把 dev 形态生成码覆盖成生产形态，验完 `git checkout` 生成码或跑一轮 dev 恢复）
  2. `mng dev` 跑着时新建 `.mng` → 日志 `[NEW]` 并自动重启；删除 → `[GONE]` 清生成码；改 `main.mbt` → `[SRC]` 并重启
- [ ] **hello mng 冒烟**：`moon run examples/hello` 起窗，按 HL-1.x 输入名字 / 步进计数 / 重置；同目录 `mng dev` 改 `hello.mng` 保存看声明页热更（HL-1.4）
- [ ] **热更真机复验**（`cd examples/hello`，`mng.toml` 已提交）：
  1. `moon run ../../tools/native-gui-tools/mng -- dev` 起应用
  2. 改 `hello.mng` 标题 / 提示字面量保存 → HOT（mng 日志 `[HOT] 补丁已推送`、应用日志 `HELLO-DEV: 模板补丁已应用`；`<style>` 类规则的字号 / 颜色值随保存热更）
  3. 改插值与按钮回调里的受限表达式 → 受限文法内 HOT；新函数 / 新符号 → `[HOT→COLD]` 带原因
  4. 改 script 状态声明 → COLD，重启后自动回首页
  5. stepper 调到 7 再只改字面量走 HOT，值仍 7（状态保活）；COLD 后回 0
  6. （v-for 面）`cd examples/components` 起 `mng dev`，改 `pages/vfor_demo.mng` 行模板应 `[HOT→COLD]` 带原因重启（SC-6.6）
- [ ] **编辑器真机复验**：`cd tools/vscode-mng && npx @vscode/vsce package` 打 0.2.9 vsix 安装（覆盖加 `--force`）→ Reload Window，按 `tools/vscode-mng/README.md` 清单走——语义着色（类型 / 变量 / 参数 / 函数 / 方法 / 命名空间分档；主题未开语义高亮需设 `editor.semanticHighlighting.enabled: true`）、TextMate 着色、snippets、补全、Problems 诊断、hover、跳转、命令面板「MNG: 新建页面」
- [ ] **样式补全观感**：components「过渡与效果」页与 canvas「画布与富文本」页：
  1. 渐变背景——线性 / 径向，stop 用主题 token 时随主色变；半透明 stop 在 Windows / mac 的插值口径与 Linux 一致
  2. 每角圆角与每边边框——不等半径四角、四边独立宽色；带圆角时 per-side 回落统一描边是否诚实
  3. `mix_blend_mode` 混排——改档看有没有漏到同帧兄弟
  4. 删除线与上划线——折行段落落在最后一行
  5. 令牌间距——整板留白与改前一致
- [ ] **主题批次观感**：`examples/theme-playground` 按 TP-1.1..5.1 走完——深色系统起窗即深色（默认一次性探测生效）；主题 JSON 落盘改色（dev 档 `mng.toml` `theme` 键存盘即重载）；深浅变体看 tooltip 反色与滚动条 / 分隔线深档提亮；code_view 在浅色 / 深色主题下底色跟 `theme_current()`，显式 `code_theme` 钉死
- [ ] **窗口族探测口径**：无合成器的 Linux 会话上 `shell_caps()` 的 `opacity` / `transparent_bg` 位应为 false，`set_transparent_bg` 应回 `Unsupported` 而非静默无效；`native_handle()` 三平台返回值非 0 且能喂平台 API
- [ ] **浮层原生档 Linux 复验**：browser 示例按 BR-1.4——↑↓ / 回车 / Esc 键盘、开着再点按钮直接收起不闪、点外收起且不触发被点控件、弹出无闪现
- [ ] **inspector v1 只读面板**：检查器演示页——树里能看到当前页控件（按父链缩进）；点行看读数（矩形与界面位置对得上）；动一动界面再点「刷新」树变化；自动刷新开着时不卡帧；重置统计后 frames 重算
- [ ] **inspector v2 样式回灌**：检查器演示页样式类页签——选中一个类改背景色「应用」，用了该类的控件下一帧变色；「还原此类」回原样；空白输入不改字段；token 名与 #hex 都生效
- [ ] **通知 urgent 二档**（mac）：同一应用分别发 `urgent=true`（缺省）与 `urgent=false`——前者出横幅、后者只进通知中心不出条；系统设置关「时间敏感」授权后再发 `urgent=true` 回落静默；状态行 `backend=` 应报 `un-user-notification`（Linux 报 `dbus`、Windows 报 `win-balloon`）

## 发布与更新复验（用户执行）

> 产物钉死四件：macOS DMG、Windows setup（NSIS）、Linux deb + AppImage；tar.gz 与 PKGBUILD 不做。Linux 自动更新走 AppImage 单文件替换，deb 档报新版本引导下载。

- [ ] **A1 mac 打包**：`cd examples/components && moon run ../../tools/native-gui-tools/mng -- package`——`.mng/dist/` 应出 `Native GUI Showcase.app` + `showcase-0.1.0-darwin-aarch64.dmg/.zip` 三件；挂 DMG 拖装运行（adhoc 首启 Gatekeeper 右键放行属已知）；看 Dock 图标（assets/icon.png 派生）与资源
- [ ] **A2 更新器·Linux 腿收口**：
  1. `mng package` 出新版载体（构建前自检三行一致：`git log -1`、`grep ^version mng.toml`、`grep app_version appmeta/appmeta.gen.mbt`）
  2. 应用内检查下载替换重启：版本变新、自动弹新窗、`.mng-old` 清理、不再报更新
- [ ] **A2 更新器·CI 真实清单腿**（依赖 release-app 首跑）：mac 装 0.1.0 → CI 发 0.2.0 draft → 应用内走检查下载替换重启全链
- [ ] **A2 mng publish**（装 gh 并 `gh auth login`）：`cd examples/components && moon run ../../tools/native-gui-tools/mng -- package && moon run ../../tools/native-gui-tools/mng -- publish --no-upload --repo <owner>/<repo>`——`.mng/dist/update.json` 应含 darwin-aarch64 的 zip 条目（url 指 releases/download、sha256 与 `shasum -a 256` 一致）；真上传档核 draft Release 产物清单后删
- [ ] **release-app CI 首跑**（用户执行）：推 tag `app-v0.1.0` 触发——打包腿出 DMG / zip、汇总腿出 `update.json`（只含 darwin-aarch64 的 zip 条目）并发 draft Release；win / linux job 骨架已注释预置，对应腿合入后取消注释启用

## 探针读数（用户执行）

- [ ] **frame_cost_probe Win / mac**：`moon run experiment/frame_cost_probe`，贴全部 `FRAME-COST` 行——重点看 `paint_full` vs `paint_clip` 的 `skip`（纯光栅腿才判交，差值是「图表 / 整页增量重绘」的立项依据）；Linux 腿判据已进测试用例附录 D
- [ ] **媒体硬解探针 Win / mac**：`cc -O2 hwdecode_probe.c $(pkg-config --cflags --libs libavcodec libavutil)`，判据：设备建得起来且 transfer 非空；另剩归档实物核验——`otool -L` 验 mac 归档带 VideoToolbox、LICENSE.txt 口径修正

## 品牌与插画

- [ ] **components 新图标**：`mng package` 后 DMG 拖装看 Dock 图标应为新版（玫红月兔 + 靛蓝空窗口）；全档再生成 `python3 scripts/gen_brand_icons.py`，icns 由 mng 的 sips+iconutil 合成
- [ ] **库内置托盘图标**：system「系统集成」托盘段点「回库内置」——托盘图标应为新版（玫红双耳 + 靛蓝窗口），三平台各看一眼；发 0.4.0 与否用户定
- [ ] **情景插画**（第二批）：README 头图 / 文档站首页「兔子坐在电脑前」叙事版

## 开发待办

- [ ] **A6 CPU/GPU 像素对拍**：与「无头像素快照基线」合并比对器，随控件级 GPU 批扩用例
