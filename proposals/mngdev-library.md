# mngdev 库包：dev 面进库 + 脚手架 + lsp 诊断联动

2026-11-07 立项。收口两轮盘点出的三件事：dev 热更要求应用自带 `shared/mng_dev.mbt`（1807 行复制）；「从零起一个模板应用」没有脚手架；`.mng` 的 MoonBit 类型错误不进 Problems。

## 1. dev 面进库（`NoahLiu/native-gui/mngdev`）

- showcase `shared/` 三件（`mng_dev.mbt` 890 / `mng_eval.mbt` 338 / `mng_style_data.mbt` 579，wbtest 11 条）挪成 `gui/mngdev` 包。依赖查证为零业务耦合（只用 `@base/@style/@ui/@widget/@win`），`MNG_IR_REV` 协议代次随包进库、与 `mngkit.IR_REV` 保持配对发版纪律。
- 编译器 dev 档生成码前缀 `@shared.` → `@mngdev.`（`gen.mbt` 三处 + wbtest 断言）；应用在模板所在包 `moon.pkg` 加一行 `import "NoahLiu/native-gui/mngdev" @mngdev` 即可，不再复制任何 `.mbt`。
- showcase 接入：`main.mbt`（`--mng-hot/--mng-page/--mng-theme` 处理处）与 `pages/moon.pkg` 改 import `@mngdev`；`@shared` 保留为业务包（tx/App/section）；dev 生成码重生成入库（CI 对账跟随）。
- template-hello 接入：moon.pkg 加 import，`hello.gen.mbt` 切 dev 形态——示例升级为支持 `mng dev` 热更。
- 不做「应用复制」方案（升级地狱）与「编译器可配 dev 前缀」（过度设计，先不）。

## 2. `mng new --app` 工程脚手架

- 一个命令生成可跑最小工程：`moon.mod`（gui 版本从 workspace 现读 `gui/moon.mod`，不在仓库内时写当前版本并注释）、`moon.pkg`（ui/base/style/widget/text/yoga + mngdev 全套 import）、`mng.toml`、`main.mbt`、`pages/home.mng` + dev 形态 `home.gen.mbt`。
- `moon new` 官方模板的三处手工调整与 dev 面复制全部消失；`mng init`（只写 toml）保留。

## 3. lsp 诊断联动（moon check 回投）

- 现状：`mng lsp` 只报模板结构错误，MoonBit 类型错误要用户自己跑 `moon check`（README 边界明示）。
- v1：`didSave` 触发一次 `moon check`（`@proc.spawn` 落临时文件，8s 超时杀，与 hover 桥同款；进行中的 check 不叠加）；每次消息循环 tick 用 `@proc.alive` 轮询，退出后解析输出里的 `<stem>.gen.mbt:行:列` → 读 dev map（`.mng/map/`）反查模板行列 → 合并进 `publishDiagnostics`（与模板结构诊断同通道）。
- 不跑 `moon fmt`（adaptation 记档：会重排全仓）；解析不了的行跳过不猜。
- 与官方插件的关系：官方插件只注册 `.mbt`、不会接管 `.mng`；联动面 = hover 桥 `moon ide`（已落）+ 本条类型诊断回投 + 跳转落点由官方插件接管（天然协作）。VSIX README 的「script 段委托给已装的 MoonBit 扩展文法」与实现不符（文法是内置子集，scope 前缀 `source.moonbit.mng` 与官方 `source.moonbit` 同族）——不做 `include: source.moonbit` 委托（TextMate include 无「官方缺失回退内置」语义，降级比现状差），只修 README 口径。

## 提交切分

1. 本提案 + roadmap/TODO 落位。
2. 【功能】mngdev 库包 + 前缀切换 + showcase/template-hello 接入 + 生成码重生成。
3. 【功能】lsp moon check 诊断回投（解析/映射/合并纯函数用例）。
4. 【功能】`mng new --app` 脚手架（wbtest）。
5. 【文档】guide/mng-project-dev/native-template/VSIX README 同步 + 收口 + 真机清单。

## 边界

- 跨工程索引、具名 slot、动态组件热更仍不做（原边界不变）。
- mooncakes 发布仍待用户拍板发版时点。
