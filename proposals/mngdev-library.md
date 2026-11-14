# mngdev 库包：dev 面进库 + 脚手架 + lsp 诊断联动

2026-11-07 立项。收口两轮盘点出的三件事：dev 热更要求应用自带 `shared/mng_dev.mbt`，1807 行复制；「从零起一个模板应用」没有脚手架；`.mng` 的 MoonBit 类型错误不进 Problems。
- dev：本库的开发者模式，模板改动不重启应用直接生效。
- 热更：hot update，应用运行中替换界面模板、不用重启。
- 脚手架：一键生成可运行初始工程的命令。
- Problems：编辑器的问题面板，集中显示诊断错误与警告。

## 1. dev 面进库·`NoahLiu/native-gui/mngdev`

- showcase `shared/` 三件挪成 `gui/mngdev` 包：`mng_dev.mbt` 890 / `mng_eval.mbt` 338 / `mng_style_data.mbt` 579，wbtest 11 条。依赖查证为零业务耦合，只用 `@base/@style/@ui/@widget/@win`；`MNG_IR_REV` 协议代次随包进库、与 `mngkit.IR_REV` 保持配对发版纪律。
  - showcase：本仓的大而全演示示例工程。
  - wbtest：MoonBit 白盒测试文件后缀，测试代码能访问包内私有符号。
  - 业务耦合：模块之间互相牵扯业务逻辑的程度，零即互不牵扯。
- 编译器 dev 档生成码前缀 `@shared.` → `@mngdev.`；应用在模板所在包 `moon.pkg` 加一行 `import "NoahLiu/native-gui/mngdev" @mngdev` 即可，不再复制任何 `.mbt`。
  - 取证：`gen.mbt` 三处 + wbtest 断言。
- showcase 接入：`main.mbt` 与 `pages/moon.pkg` 改 import `@mngdev`；`@shared` 保留为业务包，含 tx/App/section；dev 生成码重生成入库，CI 对账跟随。
  - 补充：`main.mbt` 指 `--mng-hot/--mng-page/--mng-theme` 处理处。
- template-hello 接入：moon.pkg 加 import，`hello.gen.mbt` 切 dev 形态——示例升级为支持 `mng dev` 热更。
- 不做「应用复制」方案，升级地狱；也不做「编译器可配 dev 前缀」，过度设计、先不。

## 2. `mng new --app` 工程脚手架

- 一个命令生成可跑最小工程：`moon.mod`、`moon.pkg`、`mng.toml`、`main.mbt`、`pages/home.mng` + dev 形态 `home.gen.mbt`。
  - `moon.mod`：gui 版本从 workspace 现读 `gui/moon.mod`，不在仓库内时写当前版本并注释。
  - `moon.pkg`：ui/base/style/widget/text/yoga + mngdev 全套 import。
- `moon new` 官方模板的三处手工调整与 dev 面复制全部消失；`mng init` 保留，只写 toml。

## 3. lsp 诊断联动·moon check 回投

- 现状：`mng lsp` 只报模板结构错误，MoonBit 类型错误要用户自己跑 `moon check`。
  - 补充：README 边界明示。
  - lsp：Language Server Protocol，编辑器与语言工具之间报诊断、补全、跳转的协议。
  - moon check：moon 的静态检查命令，报类型与语法错误。
- v1：`didSave` 触发一次 `moon check`；每次消息循环 tick 用 `@proc.alive` 轮询，退出后解析输出里的 `<stem>.gen.mbt:行:列` → 读 dev map 反查模板行列 → 合并进 `publishDiagnostics`，与模板结构诊断同通道。
  - 补充：`@proc.spawn` 落临时文件，8s 超时杀，与 hover 桥同款；进行中的 check 不叠加。
  - didSave：lsp 的「文件保存」通知事件。
  - hover 桥：编辑器悬停查模板语义的既有联动。
  - dev map：dev 生成码与模板行列的对应表，存 `.mng/map/`。
  - publishDiagnostics：lsp 把诊断推给编辑器的方法。
- 不跑 `moon fmt`，adaptation 记档会重排全仓；解析不了的行跳过不猜。
- 与官方插件的关系：官方插件只注册 `.mbt`、不会接管 `.mng`；联动面 = hover 桥 `moon ide` 已落 + 本条类型诊断回投 + 跳转落点由官方插件接管，天然协作。VSIX README 的「script 段委托给已装的 MoonBit 扩展文法」与实现不符——文法是内置子集，scope 前缀 `source.moonbit.mng` 与官方 `source.moonbit` 同族；不做 `include: source.moonbit` 委托，TextMate include 无「官方缺失回退内置」语义、降级比现状差，只修 README 口径。
  - VSIX：VS Code 插件的安装包格式。
  - TextMate：VS Code 沿用的语法高亮文法格式。
  - scope：文法里的作用域命名，编辑器按它配色。

## 提交切分

1. 本提案 + roadmap/TODO 落位。
2. 【功能】mngdev 库包 + 前缀切换 + showcase/template-hello 接入 + 生成码重生成。
3. 【功能】lsp moon check 诊断回投，解析/映射/合并纯函数用例。
4. 【功能】`mng new --app` 脚手架，wbtest。
5. 【文档】guide/mng-project-dev/native-template/VSIX README 同步 + 收口 + 真机清单。

## 边界

- 跨工程索引、具名 slot、动态组件热更仍不做，原边界不变。
- mooncakes 发布仍待用户拍板发版时点。
