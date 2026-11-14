# 贡献指南（中文）

English: [CONTRIBUTING.md](CONTRIBUTING.md) · 环境搭建：[docs/zh/build.md](docs/zh/build.md)

一句话定位：这是 MoonBit 的**跨平台桌面 GUI 框架**，一套 MoonBit 代码直出 Windows / Linux / macOS 原生窗口，界面自绘、不依赖重型图形引擎。

## 1. 先跑起来

```sh
cd gui && moon check --deny-warn          # 零错误零警告
cd examples/hello && moon run .           # 最小窗口
```

装工具链、装依赖（Linux 的 GTK3 开发包、Windows 的 MSVC、macOS 的 Xcode CLT）、环境自检与常见失败处置都在 [build.md](docs/zh/build.md) §1–§4、§6，不在这里重复。

## 2. 门禁（本地与 CI 同口径）

```sh
cd gui
moon check --deny-warn
dbus-run-session -- moon test base shell widget ui render text theme icons sys input win dbus chart mdview style router
```

- **裸 `moon test` 不是库门禁**：它会连带 examples / experiment / 媒体模块，其中含平台适配缺口，不是库缺陷。要跑整仓请逐包点名。
- 只改 C 桩（`gui/*/*.c`、`*.cpp`）不一定触发重链：`moon build` 可能说 `no work to do` 继续用旧产物，行为看着没变。改过桩先 `moon clean`（[build.md](docs/zh/build.md) §9）。
- 工具链改动另跑：`cd tools/native-gui-tools && moon test ./mngkit ./mng ./proc ./inst`。

## 3. 东西放哪儿

| 位置 | 放什么 |
| ---- | ------ |
| `gui/` | 库本体，按包分目录（`ui` / `widget` / `style` / `theme` / `render` / `text` / `input` / `win` / `sys` / `dbus` / `shell` …） |
| `gui/<包>/stub.c` | 平台 C 桩：单一文件多分支（Win32 / GTK / macOS / 无 GUI 兜底四臂），链接参数归 `gui/scripts/prebuild.mbtx` |
| `examples/<name>/` | 每个示例一个独立 moon 模块，并注册进根目录 `moon.work` |
| `modules/` | 子模块（yoga-mbt / mdparse / gui-media / gui-webview / ffmpeg-mbt） |
| `experiment/` | 探针与微基准，不进库 |
| `tools/` | DX 工具与编辑器插件 |
| `docs/zh/` + `docs/` | 对外文档：中文先写，英文同路径镜像 |
| `测试文档/` | 真机用例（`测试用例.md` 是唯一事实源，记录台 `index.html` 加载它现算清单） |

## 4. 设计口径

- **诚实降级**：平台没实现就报不支持，别返回假值、别静默无效。跨平台接口按**最严平台**定契约，宽平台多出的能力留在实现里不对外。
- **接口由真实用例驱动**：提功能请求请带上你卡住的场景；「另一个工具箱有这个 API」不构成理由（见 [路线图](docs/zh/roadmap.md)「明确不做」）。
- **视觉完全可定制**：主题、样式类、命名类都是覆盖口；新组件要给主题 token 留接线，别硬编码色板。
- **注释只写是什么/怎么用**：原理、根因、踩坑记进 `experience/adaptation/`，与代码同批提交。
- **格式化**：跟随邻近代码的风格，**不要跑全仓 `moon fmt`**——会把无关文件卷进 diff。

## 5. 测试怎么分工

- **无头断言归你**：逻辑、状态机、布局数值、像素快照写进同包 `*_wbtest.mbt`（可钉私有函数）。`moon check --deny-warn` 与 `moon test` 必须零错误零警告。
- **真机观感归人**：视觉与交互按 `测试文档/测试用例.md` 的编号在三种平台上各跑一遍。回报格式：`编号 + 现象 + 截图（能截就截）+ 退出时读数行`。
- 新增真机型行为请补用例条目；无示例入口的库级判据写进该文档附录 D。
- 示例应用**不要自己退出**，窗口由人关。

## 6. 提交与 PR

- 一个功能一次提交，提交信息只写 `【标签】做了什么`（例：`【样式】背景渐变接进 view 盒子`）。
- 0.x 阶段允许破坏性改动，但要在提交信息与文档写明影响面与迁移写法；`pkg.generated.mbti` 由 `moon info` 生成，别手改。
- PR 按模板填：门禁读数、三个平台各自验没验（没验就写「未验」，不留空）、文档同步项。
- 拉最新代码再开工：`git fetch && git rebase origin/master`。

## 7. 提问

用 [issue 模板](.github/ISSUE_TEMPLATE)：Bug 反馈带平台、版本、复现步骤与退出读数行；功能请求带真实用例与三平台通道情况。
