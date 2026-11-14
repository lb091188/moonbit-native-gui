# 项目级 dev·模板热更新的工程形态

定位一句话：**dev 的单位是工程，不是单个 `.mng`**——一条命令盯整个工作区，改任意模板都自动处理。

## 形态

- 配置住模块根的 `mng.toml`：
  - 范围：极小 key=value 子集。
  - 特点：自解析、零依赖。

  ```toml
  [dev]
  templates = ["examples/showcase"]   # 递归扫 *.mng，跳过 _build / .mooncakes
  build = "moon build ./examples/showcase"
  run = ""                            # 可省：跑一次 build 后从 Artifacts 抓可执行路径
  app-id = ""                         # 可省：由 moon.mod 的 name 派生「作者.工程名」
  poll-ms = 300
  ```

- `mng dev` 无参：向上找 `mng.toml`；没有就按 `moon.mod` / `moon.work` 推默认值。
  - 默认值：模板目录 = 模块根递归、build = `moon build`。
- 生成码落到**模板自己所在的包目录**。
  - 变化：不再要 `--out-dir`。
- 一拍内多个改动合并成一次 build / 重启；HOT 的逐个推补丁。
  - HOT：热更新档，改动直接推补丁生效，不重走生成编译。
- 单页过滤是可选参数 `mng dev <某个 .mng>`，不是主形态。
- `mng init` 在模块根写一份带注释的 `mng.toml` 样板。

## 两种生成模式·同一个 `<stem>.gen.mbt`

| 模式 | 入口 | 产物 |
| --- | --- | --- |
| 生产 | `mng build` | 现状骨架，零 dev 痕迹；仓库提交的始终是这一形态 |
| dev | `mng dev` | 多出页面注册表与 holder 落点，只在本地 dev 会话里生成 |

dev 形态骨架：

```moonbit
pub fn <stem>() -> @widget.Node {
  <script 段原文>                 // 状态与辅助函数，随页面挂载建一代
  let reg = @shared.mng_reg_new()
  reg.expr("t:行:列", fn() { … })  // 动态文本/参数
  reg.cond("c:行:列", fn() { … })  // v-if / v-show
  reg.handler("函数名", 函数名)     // @事件
  reg.int/bool/str("名", 名)       // v-model 目标（按 script 注解的元素类型）
  @shared.mng_dev_page("<stem>", reg, fn() { <模板树> })
}
```

- **状态保活**：script 段在 `mng_dev_page` 外执行一次以建状态，模板树放进 `build` 闭包里捕获这一代状态；补丁到达时只重建 `build()` 的树并原位替换 holder 的子节点，**页内状态不重置**。
  - 对齐：与手写演示页的实际行为一致。
  - holder：页面里给生成的模板树留的占位节点。
- 登记键沿用 IR 现状：动态文本/参数 `t:行:列`、条件 `c:行:列`、事件与状态用名字。
  - 坐标规则：ui-text 的 `:text` 与插值文本取元素/文本子节点坐标，通用组件参数取属性坐标。
  - IR：模板编译产物里的中间表示。
- 热更边界：class / `<style>` 值 / 受限表达式走 HOT；自定义组件、children 形组件、v-for、script、文法外表达式走 COLD，不强行登记。
  - 受限表达式：字面量、Store、运算、if、`@shared.tx`·`tr`、插值。
  - COLD：冷更新档，改动要重走生成与编译。

## 应用侧通用件

**2026-11-07 收口：dev 面进库**——`NoahLiu/native-gui/mngdev` 包提供 `mng_dev_page` / 注册表 / applier / 受限表达式求值器；应用在模板所在包 `moon.pkg` 加一行 `import "NoahLiu/native-gui/mngdev" @mngdev` 即可，不再复制任何 `.mbt`。
  - 来源：原 showcase `shared/` 三件挪入，`tx/tr` 求值改 `@i18n` 直调。
  - 机制：编译器 dev 档生成码引用 `@mngdev.mng_*` 家族。

## 落地状态

- **A**：编译器 dev 档、`mng_dev_page`、showcase 演示页改调生成页、`mng dev` 产 dev 形态。
  - 变化：手写注册表删除。
- **B**：`mng.toml` 与 `mng dev` 无参——向上找配置、递归扫模板、生成码落模板所在包、一拍改动合并重启、app-id 派生、`run` 留空时从 build 的 `Artifacts` 按模块名挑可执行、默认 `moon build .` 只建本包；撞名按包聚合、`mng init` 样板；模板文件与用它的页面同包。
  - 补充：演示页模板已移进 `examples/showcase/pages/`。

## 后续

- `mng new --app` 工程脚手架已落：moon.mod 版本现读 workspace、全套 import 的 moon.pkg、mng.toml、main.mbt、首页 dev 生成码。
  - 状态：2026-11-07。
  - 同日改面：裸 `new` 即建工程、`--app` 删除、单页样板挪 `new page <路径>`——高频动作零参数。
- VS Code「MNG: dev」入口。
  - 功能：拉起 `mng dev` 并复用现有 lsp 诊断/补全。
- 上游 native 热重载落地后，IR 通道升格真代码热换。
