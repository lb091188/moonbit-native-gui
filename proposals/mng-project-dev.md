# 项目级 dev（模板热更新的工程形态）

定位一句话：**dev 的单位是工程，不是单个 `.mng`**——一条命令盯整个工作区，改任意模板都自动处理。

## 形态

- 配置住模块根的 `mng.toml`（极小 key=value 子集，自解析、零依赖）：

  ```toml
  [dev]
  templates = ["examples/showcase"]   # 递归扫 *.mng，跳过 _build / .mooncakes
  build = "moon build ./examples/showcase"
  run = ""                            # 可省：跑一次 build 后从 Artifacts 抓可执行路径
  app-id = ""                         # 可省：由 moon.mod 的 name 派生「作者.工程名」
  poll-ms = 300
  ```

- `mng dev` 无参：向上找 `mng.toml`；没有就按 `moon.mod` / `moon.work` 推默认值（模板目录 = 模块根递归、build = `moon build`）。
- 生成码落到**模板自己所在的包目录**（不再要 `--out-dir`）。
- 一拍内多个改动合并成一次 build / 重启；HOT 的逐个推补丁。
- 单页过滤是可选参数（`mng dev <某个 .mng>`），不是主形态。
- `mng_cli init` 在模块根写一份带注释的 `mng.toml` 样板。

## 两种生成模式（同一个 `<stem>.gen.mbt`）

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

- **状态保活**：script 段在 `mng_dev_page` 外执行一次（建状态），模板树放进 `build` 闭包里捕获这一代状态；补丁到达时只重建 `build()` 的树并原位替换 holder 的子节点，**页内状态不重置**（与手写演示页的实际行为一致）。
- 登记键沿用 IR 现状：动态文本/参数 `t:行:列`（ui-text 的 `:text` 与插值文本取元素/文本子节点坐标，通用组件参数取属性坐标）、条件 `c:行:列`、事件与状态用名字。
- 热更边界：class / `<style>` 值 / 受限表达式（字面量、Store、运算、if、`@shared.tx`·`tr`、插值）走 HOT；自定义组件、children 形组件、v-for、script、文法外表达式走 COLD，不强行登记。

## 应用侧通用件

`shared/mng_dev.mbt`（应用自己的 shared 包）提供 `mng_dev_page(page, reg, build)`：登记注册表与 holder、把 `build()` 的树挂进 holder 并记为现役代。applier（按 `page` 键控的注册表 + IR 构树 + 整袋退订）不变。

## 落地状态

- **A**：编译器 dev 档、`mng_dev_page`、showcase 演示页改调生成页（手写注册表删除）、`mng dev` 产 dev 形态。
- **B**：`mng.toml` 与 `mng dev` 无参（向上找配置、递归扫模板、生成码落模板所在包、一拍改动合并重启、app-id 派生、`run` 留空时从 build 的 `Artifacts` 按模块名挑可执行、默认 `moon build .` 只建本包）、撞名按包聚合、`mng_cli init` 样板；模板文件与用它的页面同包（演示页模板已移进 `examples/showcase/pages/`）。

## 后续

- 命令改名 `mng`（现为 `mng_cli`）。
- VS Code「MNG: dev」入口（拉起 `mng dev` 并复用现有 lsp 诊断/补全）。
- 上游 native 热重载落地后，IR 通道升格真代码热换。
