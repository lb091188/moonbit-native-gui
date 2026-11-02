# 原生模板预编译（开发体验工程）

定位一句话：给原生路线补一层**模板语法预编译**——界面用声明式模板写，编译成现有声明层的回调与绑定代码，再走 `moon run/build`。本文是设想初稿，语法与工具细节待讨论（见文末开放问题）。

## 目标与边界

- 目标是**原生路线自己的开发体验**：模板把「界面结构」与「组件逻辑」分开，树形结构肉眼可读。不是对齐 Vue 或任何框架——指令形态以本仓坐标为准，Vue/Solid 只作为编译策略的参照物。
- 编译发生在 moon 之前：模板文件 → 生成 `.mbt` → `moon check` 照常零警告门禁。
- 只做作者侧工具，**不改运行时**：生成物落点全部是已实现的 API（bind 家族、受控组件、`Node{mount}`、ListStore keyed）。

## 动机

- 现有声明语法是构造器调用链（`vbox([...])` / `bind(...)`），嵌套一深可读性下降；树形结构的天然形态是模板。
- 双向绑定这类语法 MoonBit 语言层面表达不了，但它们本来就该是编译器糖——`v-model` 在 Vue 里也只是 `:value` + `@input` 的缩写。**语言特性不该是开发体验的天花板，缺的只是一层预编译。**
- 预编译后编译期校验全量保留：表达式原样拼进生成码，类型安全由 `moon check` 唯一门禁承担。

## 脱糖表（模板语法 → 现有 API 落点）

| 模板语法 | 生成产物 |
| --- | --- |
| `{expr}` 插值 | `bind_label` / 细粒度 text effect |
| `:attr="expr"` 动态属性 | 对应 `*_dyn` 入口 |
| `@event="handler"` 事件 | 回调接线 |
| 双向绑定指令（命名待定） | 受控组件 `value` + `on_change` 双接线 |
| 条件块 | `bind_node` 原位重建 |
| keyed 列表 | `ListStore` keyed diff / keyed_align |
| 组件标签 | 函数调用返回 `Node`（`Node{mount}` 组合） |
| 默认 slot | `mount_children` 投影 |

## 编译口径

- **Solid 式细粒度**：静态子树一次构建；动态槽各编译成独立 bind effect（改一个状态只推对应槽）；结构级（条件/列表）才走 `bind_node` / keyed 重建。与 Signal/Store 的细粒度架构同一哲学，也延续 mdview 的性能口径（不为整树重建付出布局抖动）。
- 表达式按字符串拼接，编译器**不做类型检查**；`moon check` 是唯一类型门禁。
- dev 档双产物：生产生成码之外旁路产出模板 IR 与 dev 注册表（热更新供给端，见「开发循环」二轮节）；生产构建不含任何 dev 产物。

## DX 生死线

1. **错误回映射**：CLI 解析 `moon check` 报错并映射回模板文件的行列坐标。做不到这条，工具就是玩具。
2. **生成码可读且确定**：确定性排序、`// GENERATED, DO NOT EDIT` 头、按组件一个 `.mbt`。生成物建议提交仓库——消费者 `moon add` 后零工具链依赖；配 CI 新鲜度门禁（`moon fmt --check` 同款套路：重生成后 diff 非空即失败）。
3. **v1 指令集克制**：插值、动态属性、事件、双向绑定、条件、keyed 列表、默认 slot。具名 slot / 动态组件留白，别一上来铺满。

## 落地顺序

1. **spike 先于编译器**：挑 showcase 一个页面，手写「目标模板版」+「它应该被编译成的 MoonBit 版」，两边对照钉死语法与产物契约。契约冻结前不写解析器。
2. **`build` 子命令**（住 `tools/`，workspace 成员现成）：解析器 + 拼接器 + 源映射——DX 生死线是错误回映射。**已落地**（2026-11-02，`tools/mngkit` 内核 + `tools/mng_cli` 终端：build / map-errors，golden 6/6、错误回映射端到端验通；按冻结契约生成，`v-for` 按记档收口报错）。
3. **Phase 0 探针（先于 IR 协议）**：手工 IR 补丁打进 showcase 单页，验证「init 建状态 → 按 IR 构树 → 沿 holder 原位重挂」亚秒可见、订阅整代退订干净——探针不过，IR 通道整体不发生。旁路小探针：moonbit native 能否出共享库（relink 小 .so + 起进程或可把回退档压到 ~1s，进程每次是新的、不碰 GC 互通）；不成立归并上游增量链接诉求。
4. **`dev` 子命令**：watch + 改动分类（表达式集合 ⊆ 注册表 → 推 IR 补丁；否则回退）+ 经单实例通道推 token/类变更；回退时 `moon build` → 杀旧进程 → 带参重启。**v1 已落地**（2026-11-02，`tools/mng_cli` dev：watch 内容对比 + 契约分类（`mngkit.contract_of`，script 逐字同且表达式集合 ⊆ 基线 → HOT）+ 回退编排直起进程；HOT 补丁推送与应用侧 dev 监听同批落地，本版打标不打断；配套 `@sys` 增 pr_spawn / pr_alive（僵尸收尸）/ pr_kill / pr_sleep_ms）。
5. **终态：独立工具二进制**（本路线的 Vite 位次）：一个自包含 native 可执行，`moon install` 分发；子命令 `dev` / `build`（纯生产产物，零 dev 痕迹）/ `new`（新 `.mng.html` 页样板脚手架）/ `preview`（独立预览窗：同一 applier + mock 状态）/ `lsp`。无侵入边界——只编排模板文件、token 文件、`moon build`、应用进程四样，应用侧 dev 面仅 theme/IR 两个监听，生产构建零痕迹；不做插件系统、不做 dev server（取 Vite 的一命令体验，不取其工程规模）。命名按路线门面标准起（开放问题 5）。**发布纪律**（2026-11-02 定）：工具独立于主包发布——MoonBit 发布单元是模块，住进 gui 会让所有应用白拉工具源码，而消费者只要提交在仓的生成码、只有作者 `moon install` 装；开发期 tools 留 workspace 同仓同 CI，终态齐活（dev/build/new/preview/lsp）再补 mooncakes 发布配置；`mngkit` 留 tools 内，待第三方单独消费编译器内核的场景出现再拆。版本协议：工具与 gui **同批配对发版**（内置组件表 ↔ `@ui.*` 签名、IR schema ↔ applier 是强耦合面；gui 破坏性改动同批重发工具），一致性由同仓 CI 钉住（组件签名变更即 showcase 生成码编不过）。
6. **灰度**：新页面用模板写，存量页面不迁移。

## Spike 契约（2026-11-01 冻结，showcase 表单页）

**语法总原则**：**对齐 Vue，不改语法**——只按平台能力限制收窄，每处收窄在此记档；Vue 开发者除 MoonBit 表达式本身外零学习成本。

**选页**：`examples/showcase/pages/form.mbt`——脱糖表 8 行覆盖 7 行（keyed 列表只钉语法、生成器 v1 收口），组件族最全（受控输入/步进/滑杆/开关/表单/校验）。

| 脱糖行 | spike 覆盖 |
| --- | --- |
| `{{ expr }}` 插值 | ✓ 文本节点（Vue 默认分隔符） |
| `:attr` 动态属性 | ✓（`placeholder` / `error`），Vue 简写原味 |
| `@event` 事件 | ✓（`@click`），Vue 简写原味 |
| `v-model` 双向绑定 | ✓ 语法原味；编译落点 = 值槽直传 Store（受控组件本来就吃 Store，无 setter/getter 二线制——语法对齐、落点从简） |
| `v-if` 条件 | ✓ 全家（`v-if` / `v-else-if` / `v-else`），表达式任意；`v-show` → `when` 显隐 |
| `v-for` 列表 | 语法钉死，生成器 v1 收口 |
| 组件标签 | ✓ `ui-*` 内置表 + script setup 的 `let` 绑定即暴露（对齐 setup 心智） |
| 默认 slot | ✓ 子元素 → children 数组（form / form_item / section） |

**能力限制收窄记档**（语法不为此改形，超范围编译报错提示）：

- `v-for` 的源限 Store/Signal 槽——字面量数组没有响应语义；
- 事件与 `v-model` 的修饰符（`.stop` / `.prevent` / `.lazy` / `.number`…）不支持；
- 模板根 v1 单根（Vue3 fragment 多根暂不支持）；
- 具名 slot 不支持（默认 slot 已覆盖），动态组件留 v2。

**语法落定**（已冻结）：

| 项 | 定 |
| --- | --- |
| 扩展名 | **两阶段**：现行 `.mng.html`——零插件白拿 HTML 高亮（编辑器 0 档，`.html` 兜底系统不会误判成图片）；自家 VS Code 扩展（1 档）落地即切裸 `.mng`——查证编辑器生态无占用（2026-11-01），MNG 图像格式已被 APNG/WebP 取代、浏览器早弃支持，仅剩文件管理器图片关联的残余噪音，接受。先例：`.ts`（TypeScript）与 MPEG-TS 视频流重名共存，媒体重名在开发语境无害，编辑器语言注册由自家扩展接管。`.mui` 一并排除：Windows MUI 本地化资源文件（`*.exe.mui`）系统级占用 + React 组件库 MUI（原 Material-UI）心智撞车，两个都是活物 |
| 文件结构 | `<script setup lang="moonbit">`（页状态与逻辑，MoonBit 原文）+ `<template>`（单根树），Vue SFC 形态 |
| 插值 | 文本节点 `{{ expr }}` |
| 表达式属性 | `:attr="expr"`；属性值可用单引号包 MoonBit 双引号串 |
| 静态属性 | 字面量按 MoonBit 字面量规则解析透传（`0` / `0.0` / `true` / 串） |
| 双向绑定 | `v-model="store"`；落点 = 直传 Store 对象到映射表条目声明的值槽参数 |
| 事件 | `@click="handler"`；事件名查映射表条目，未知 `@` 报错 |
| 结构条件 | `v-if` / `v-else-if` / `v-else` 表达式任意：词法提取响应源 → 单槽名直用其 signal、否则包 `computed` → `bind_node` 按 match 链原位重建；`v-show` → `when` 显隐 |
| keyed 列表 | `v-for="it in items" :key="it.id"` → ListStore keyed，`it` 即迭代元素 |
| 组件暴露 | script setup 的 `let` 绑定（值为函数引用，如 `let sh_section = @shared.section`）即可用作模板标签（对齐 setup 暴露心智；生成码解析到绑定的值直接调用，不经函数值）；`ui-*` → `@ui.*`（`-`→`_`）内置表兜底 |
| script 段 | MoonBit 原文进生成函数体前段（`let` / `fn` 均可） |
| 生成函数签名 | `fn <文件名去扩展>() -> @widget.Node`；app 注入挂开放问题 |
| 动态文本响应源 | 词法提取：表达式内 script 声明的槽名（裸引用或 `.get()`）即源；单源 `bind_label(store, fn(v){…})`、源本身是 Signal 用 `bind`、多源包 `computed`、零源 `@ui.text(expr)` |
| 文本节点 | 静态 → `@ui.text`；含 `{{ }}` → 上一行规则 |
| i18n | 编译器零魔法：要翻译的文案显式 `@shared.tx(...)`（与现仓习惯一致） |

**对照片段**（模板源 → 生成码；生成码全文落盘 `examples/showcase/template_spike_wbtest.mbt`，`moon check` 门禁验证「可读可编译可无头构造」）：

```html
<script setup lang="moonbit">
let sh_page = @shared.page
let sh_section = @shared.section

let qty : @base.Store[Int] = @base.Store::new(3)
let wifi_on : @base.Store[Bool] = @base.Store::new(true)
let nick : @base.Store[String] = @base.Store::new("")
let err_nick = @ui.validate(nick, @ui.all([@ui.required(), @ui.min_len(2)]))
let passed = @base.Signal::computed(fn() {
  if err_nick.get().length() == 0 { 1 } else { 0 }
})
fn on_reset() {
  qty.set(3)
  nick.set("")
}
</script>

<template>
  <sh-page>
    <sh-section :title='@shared.tx("数值")' :subtitle='@shared.tx("步进器 / 滑杆 / 评分")' desc="stepper 0..10 钳制。">
      <ui-stepper v-model="qty" min="0" max="10" step="1" />
      当前数量：{{ qty }}
    </sh-section>
    <sh-section :title='@shared.tx("开关")' subtitle="Checkbox" desc="开关驱动结构条件。">
      <ui-checkbox :label='@shared.tx("自动开启")' v-model="wifi_on" />
      <ui-text v-if="wifi_on" :text='@shared.tx("已开启")' />
      <ui-text v-else :text='@shared.tx("已关闭")' />
      <ui-button :text='@shared.tx("重置")' @click="on_reset" />
    </sh-section>
    <sh-section :title='@shared.tx("表单校验")' subtitle="Form" desc="规则即时重跑。">
      <ui-form :title='@shared.tx("注册资料")'>
        <ui-form-item :label='@shared.tx("昵称")' :error="err_nick">
          <ui-input v-model="nick" :placeholder='@shared.tx("至少 2 个字符")' width="200.0" />
        </ui-form-item>
      </ui-form>
      已通过校验 {{ passed }} 项
    </sh-section>
  </sh-page>
</template>
```

生成码（节选；全文见 wbtest）：

```moonbit
fn template_spike() -> @widget.Node {
  // —— script 段原文 ——
  let qty : @base.Store[Int] = @base.Store::new(3)
  // …（略）…
  fn on_reset() {
    qty.set(3)
    nick.set("")
  }
  // —— 模板树（let 绑定的组件解析到绑定的值直接调用）——
  @shared.page([
    @shared.section("数值", "步进器 / 滑杆 / 评分", "stepper 0..10 钳制。", [
      @ui.stepper(qty, min=0, max=10, step=1),
      @ui.bind_label(qty, fn(v) { "当前数量：\{v}" }),
    ]),
    @shared.section("开关", "Checkbox", "开关驱动结构条件。", [
      @ui.checkbox(@shared.tx("自动开启"), wifi_on),
      @widget.bind_node(wifi_on.signal(), fn(on) {
        if on {
          @ui.text(@shared.tx("已开启"))
        } else {
          @ui.text(@shared.tx("已关闭"))
        }
      }),
      @ui.button(@shared.tx("重置"), on_click=on_reset),
    ]),
    @shared.section("表单校验", "Form", "规则即时重跑。", [
      @ui.form(@shared.tx("注册资料"), [
        @ui.form_item(@shared.tx("昵称"), @ui.input(
            nick,
            placeholder=@shared.tx("至少 2 个字符"),
            width=200.0,
          ), error=err_nick),
      ]),
      @ui.bind(passed, fn(v) { "已通过校验 \{v} 项" }),
    ]),
  ])
}
```

生成码（节选；全文见 wbtest）：

```moonbit
fn template_spike() -> @widget.Node {
  // —— script 段原文 ——
  let qty : @base.Store[Int] = @base.Store::new(3)
  // …（略）…
  fn on_reset() {
    qty.set(3)
    nick.set("")
  }
  // —— 模板树 ——
  @shared.page([
    @shared.section("数值", "步进器 / 滑杆 / 评分", "stepper 0..10 钳制。", [
      @ui.stepper(qty, min=0, max=10, step=1),
      @ui.bind_label(qty, fn(v) { "当前数量：\{v}" }),
    ]),
    @shared.section("开关", "Checkbox", "开关驱动结构条件。", [
      @ui.checkbox(@shared.tx("自动开启"), wifi_on),
      @widget.bind_node(wifi_on.signal(), fn(on) {
        if on {
          @ui.text(@shared.tx("已开启"))
        } else {
          @ui.col([])
        }
      }),
      @ui.button(@shared.tx("重置"), on_click=on_reset),
    ]),
    @shared.section("表单校验", "Form", "规则即时重跑。", [
      @ui.form(@shared.tx("注册资料"), [
        @ui.form_item(@shared.tx("昵称"), @ui.input(
            nick,
            placeholder=@shared.tx("至少 2 个字符"),
            width=200.0,
          ), error=err_nick),
      ]),
      @ui.bind(passed, fn(v) { "已通过校验 \{v} 项" }),
    ]),
  ])
}
```

## 支持程度

- 上限 = MoonBit 表达式能写什么；类型安全由 `moon check` 全量保住。
- 到不了：运行期按字符串名动态拼组件、CSS 级联语义（仍走 token/class 槽）、真代码 HMR（运行中换已链接机器码）。模板**结构/样式**的亚秒热更不在其列——走 IR 通道与 token/类通道，见「开发循环」二轮节。

## 开发循环：热更新的边界与替代形态

模板编译器管「改得爽」，本节回答「看得快」：native 路线的热更新能到哪、不能到哪、用什么替代。（2026-11 讨论结论）

### 原理底座：AOT 与 JIT

- native target 是 AOT（运行前一次性编译成机器码，代码焊死在二进制里），全程一套编译口径——**「开发表现 = 生产表现」是本路线的白拿资产**。
- JIT（边跑边编）天然支持热替换（代码运行时生成、可现场换指针），但代价是 dev/prod 两套口径（Flutter 开发 JIT、发布 AOT）。不入选，正因违反「与生产一致」的验收标准。
- wasm/js target 的最终执行也有宿主引擎侧的 JIT 参与，但那是宿主的事，与工具链无关。

### 真 HMR（进程内热替换）为什么不可行

1. **机器码焊死**：运行中进程无法替换已链接代码。
2. **dylib 热换**（Rust hot-lib-reloader 式）死于两点：GC 堆不互通——跨边界只能传 C 扁平数据，Widget/Store/Signal 是 GC 对象过不去；类型布局漂移——UI 迭代期天天改结构体，旧堆对象被新代码按新布局解读即内存腐坏。共享堆需要 GC 支持多模块注册栈映射，是工具链级手术，不是应用层工具。
3. **字节边界 + 命令回放**（自建「第二引擎」，技术上唯一能跑通的设计：宿主持有状态快照，热换模块每次事件收「状态字节 + 事件」、输出 Painter 命令流、宿主回放）：像素层 100% 忠实，但焦点栈、IME 组合串、增量重排、订阅触发这些 retained 行为必然漂移——等于自建平行 UI 引擎且与生产互不背书。绘图 API 能统一「画」，统一不了「行为」；热替换换的是行为。
4. **立即模式 dev 层**（egui 生态热替换容易的真正原因：无保留树、每帧重跑）：retained 框架配 immediate dev 层 = 换范式重写组件层。

统一问题：命令流要升格为生产架构本身才不存在第二引擎，三条既名之路——立即模式（重写框架）、Server-Driven UI（自建解释器纯亏性能）、Flutter layer tree（依然不解决换码，其热重载靠 Dart VM JIT 而非 layer tree）——均不入选。

### 落点：三件自建基建 + 一条上游需求（2026-11 收敛版）

1. **样式 token 热更新（样式通道主形态）**：`theme_fingerprint` + `watch_theme` + 指纹变化重建绘制对象的机制现成；dev 工具经单实例通道向运行中应用发 `reload-theme`，应用侧 dev 档只留一个 theme reload 监听。不重启、亚秒可见、与生产同路径——调样式工作流的主力。配套硬约定：样式值进 token/class 槽才热，模板样式属性编译为 token/class 引用、不写内联字面量（二轮起升格为编译器强制规则，见样式章）。结构改动的主通道让位 IR 热应用（见下节）。
2. **dev 宿主（回退路径）**：瘦链接 + 启动直达——只挂 facade 核心、不链 chart/media/webview（构建 3–4s 档），吃 `--page` 等启动参数直接落在目标页。工具编排：模板重编译 → `moon build` → 杀旧进程 → 带参重启。二轮定位收窄：表达式/逻辑改动（闭包集合变化）时的自动回退，不再是结构改动的主力循环（见下节）。
3. **Painter 原型沙盒**：小 dev 应用直出绘图 API，原型自定义控件与画法（showcase 画布页为雏形）。原型工具，不承载热替换。
4. **向上游提需求**：native 目标的 hot reload / 运行时多模块支持（顺带诉求：native 增量链接——实测构建大头在链接）。moonbitlang 侧落地第一天，被砍的快照设计原样复活为状态迁移层。

快照式热重启已砍（2026-11 收敛）：实测构建占 5.8s、快照恢复仅省亚秒级重新导航，收益零头、成本周级（Store 注册表 + 编解码 + 版本字段 + 恢复次序），ROI 不成立。

进阶变体（记下不做）：多进程宿主持有状态（游戏编辑器模式），留给「状态重建很贵」的应用场景。

### 结构热更新：模板 IR 热应用（2026-11-01 二轮收敛，现行口径）

秒级验收线（保存即所见）否决一切重启式主形态：moon 自身地板 1.9s（hello 无改动实测）已超线，dev 宿主再瘦也过不了——只剩进程内应用一条路。同日拆解 Slint 1.13 Live-Preview 定下可行形态。

**Slint 1.13 机制拆解（照搬不可行的证据）**：编译期把 `.slint` 的原生 codegen 整体换成同名 API stub → 运行时从磁盘读源、走解释器建树、监听文件重载；状态保留 = 把应用 set 过的属性/模型/回调回放到新实例；生产仍 AOT。两根支柱——**解释器是产品的一部分**（同一前端两个后端）与**动态组件模型**（属性/模型/回调按名寻址）——本栈都没有：模板表达式是原样拼接的 MoonBit，运行时无物可求值。整体照搬 = 自建第二套求值语义，落上一节第二引擎成本类，不选。

**绕开第二引擎的三个落点**：

1. **结构 ≠ 表达式**：结构编辑时表达式集合不变。IR 里的绑定按哈希/名字引用**已编译闭包**，运行时不求值任何新文本。
2. **状态不迁移**：进程活着，Signal/Store 原地，重挂的只有视图子树。全局 Store（建窗期）天然存活，页内状态随补丁重置——与 `remount_all` 切语言同款语义，快照设计继续不做。
3. **applier = 脱糖表的可执行版**：codegen 与 applier 是同一张契约表的两个编码器，漂移不靠自觉——golden 夹具钉死（同模板两边产出 widget 树逐节点断言，进 `moon test`）。

**路由考察（执行机关现成，零新机制）**：`Router::unmount`（slot_resets → sub_bag 整袋退订 → `remove_child` → `purge_built`）、`mount_into_holder`（构造+挂载同一订阅袋窗口）、`remount_all`（切语言/换皮肤天天真机在跑的整树原地热替换）、`bind_node`（子树级原位替换，回归测试钉住）、`theme_fingerprint`（样式侧）。缺的只有**供给端**：新结构定义进进程。

**供给端四件套**：

1. **IR**：模板编译器第二产物——结构树 + 静态属性 + 按哈希/名字引用的 expression/state/handler；随构建落盘，应用内一份供 applier 校验 rev。
2. **注册表**（dev 档 codegen 生成）：expr 哈希 → 闭包；state 名 → get/set；handler 名 → 闭包；组件 `init` thunk（script 段：建页内状态）。
3. **通道**：复用 `@shell` 单实例 socket——token 指纹与 IR 补丁同一条管子。
4. **applier + 挂载登记**：组件挂载时登记「组件 id → holder」；补丁到达 = `init` 建状态 → 按 IR 构树（表达式走注册表）→ 原位重挂。

**循环与分类**：保存 → 工具重解析 → 判「表达式集合 ⊆ 应用注册表键集」（握手：应用报键集）→ 是：推 IR 补丁，亚秒；否（新表达式文本 / script 段改动）：自动回退 dev 宿主重启。工具每笔保存告知走了哪条路，不给假预期。

**v1 边界**：补丁粒度 = 整组件（不做树 diff）；页内状态随补丁重置；keyed 列表行模板当不透明单元（行内结构编辑回退，列表数据变化走既有 keyed 机制本就热）。

**v2 三方向（按实测痛感排队，不按愿景补齐）**：

| 方向 | 补掉的 v1 边界 | 新风险 | 触发条件 |
| --- | --- | --- | --- |
| v2a 受限表达式求值器 | 表达式文本热改 | 双求值语义（dev 解释 / prod codegen），golden 钉平 | 回退日志中表达式改动占比高 |
| v2b 子树对账 + 状态保活 | 整组件重挂、页内状态重置 | applier 变对账器（真正复杂度大头） | 状态重置在真实迭代里碍事 |
| v2c 列表行模板热编辑 | 行内结构回退 | 依赖 v2b 的状态下放 | 列表密集页成迭代主战场 |

**覆盖面速查**：

| 改动 | v1 | v2 |
| --- | --- | --- |
| 样式值 | 亚秒（token/类通道） | 亚秒 |
| 结构加减挪、绑定换目标 | 亚秒（IR） | 亚秒 |
| 表达式文本（受限文法内） | 回退 3–4s | 亚秒 |
| 列表行内结构 | 回退 | 亚秒 |
| script / 逻辑 | 回退（与 Slint 改 Rust 持平） | 回退 |

**终态**：`dev` / `build` / `preview` / `lsp` 四子命令（见「工具与编辑器支持」）；单面编排到底——native 面一个底座（2026-11-02 定案不做第二壳，web 内容经 gui-webview 组件嵌入、其开发循环归前端自己的 Vite，不经本工具链）；上游汇合点——moonbitlang native 热重载落地当天，IR 通道升格真代码热换、快照设计原样复活、全部回退路径消失。

**HOT 补丁通道落地（2026-11-02）**：编译器第二产物 IR（`mngkit.ir_of`，JSON：结构树 + 参数三态 lit/expr/state + 动态槽坐标键 `t:行:列` / `c:行:列` + requires 清单）；dev 子命令 HOT 分支产 IR 经单实例通道 `instance_wake(app_id, ["--mng-hot", 路径])` 推送；应用侧 applier（showcase「模板 Dev」页 `shared/mng_dev.mbt`：类型化注册表手写登记 + JSON 构树 + sub_bag 原位替换）——无头 wbtest 钉死「构树必须在订阅袋窗口内」（computed 的依赖订阅发生在构造时，只包挂载会泄漏，探针口径的产品化复现）；v1 补丁边界：col/row/text/dyn/if/button/checkbox/switch/stepper/input，v-for / v-else-if / 自定义组件 / children 形组件转 COLD。**待真机**：dev 循环端到端 GUI 验证（TODO 有步骤清单）。

**Phase 0 探针结果（2026-11-01，`experiment/ir_probe`，无头）**：手工 IR + 注册表 + applier v0（落点全为生产 API），200 轮 v1↔v2 结构交替热替换——单次「摘+建+挂」**10.4 ms**（验收线 1000 ms 的 1/75）；旧代订阅整袋退订干净（渲染不叠加、订阅数跨代恒定）；受控组件（stepper/slider）自身订阅计入现役代属正确口径。**探针通过，IR 通道主假设成立。**

### 探测结论（2026-11-01，Windows 开发机、showcase、native）

- **构建基线**：无改动增量 1.9s、改一个叶子页面 `moon check` 0.5s / `moon build` 5.8s、改 facade ui 层 10.6s——编译近乎免费，**大头是 AOT 链接**（≈3.4s）加 moon 自身地板（1.9s，与应用大小无关，hello 无改动 1.5–2.6s）。这是 AOT 换「开发表现 = 生产表现」的固定税，应用层唯一杠杆是 dev 宿主瘦链接；亚秒级只有换口径（已否）或工具链原生支持（上游需求）。
- **watch 循环**：`moon` 无 `watch` 子命令，衔接方式定为工具自转——监听源码变更，逐次 spawn `moon build`，构建成功即触发重启。
- **dev 重启时序**：先确认旧进程退出再起新进程，单实例锁即自然释放（快照砍除后重启不再有状态迁移，只剩这条时序要求）。

### 与双面架构的收拢（2026-11-02 修订：收拢取消）

Web 主面壳形态不做（roadmap「明确不做」）。原生面是唯一主面：样式 token/类通道 + 模板 IR 通道（双亚秒）+ dev 宿主回退。应用里需要 web 内容时，**gui-webview 组件填满窗口即兼容方案**——该场景下前端侧 HMR 归 Vite（web 项目自己的循环），本工具链不编排第二底座。

## 样式章：`<style>` 段与布局属性样式化（2026-11-01）

- **`<style>` 段编译期摊平**：类选择器 → `define_class` 注册条目；元素 `class="a b"` → 生成 `class = class_of(["a","b"])`。支持子集：类选择器、一层后代、`var(--token)` 引主题令牌、深浅变体编译成两份值。不做运行时级联/特异性/继承链/伪类——冲突编译期报错，不静默仲裁（vanilla-extract / CSS Modules 套路：级联在 build 期算完，运行时零新机制）。
- **硬约定升格为编译规则**：「样式值进 token/class 槽才热」由编译器强制——`<style>` 段与 `class` 引用之外出现样式字面量即编译报错。
- **布局属性样式化（现状已查证）**：`@style` 的 `Style` 已含布局全量（flex_direction / justify_content / align_items / align_self / flex / 双向 gap / padding×4 / margin×4 / 宽高 min/max / border / display），`apply` 分流口径本就是「布局走 Yoga、外观进槽」。此前「居中不随主题热」的真因是构造参数 build 期焊死、不进类注册表，不是系统缺能力。口径收紧三条：
  1. 构造参数 = 默认值，类槽 = 覆盖（合并序沿 registry「散写匿名块优先级高、排尾」成文）；
  2. 结构性例外留结构侧：children、事件、键、row/col 选型（`flex_direction` 虽在 Style，行列构造选择仍是结构决定，样式只做覆盖微调）；
  3. 收益：gap / 对齐这类高频布局微调从重启档进亚秒档（类是 Style 数据，指纹重建 + 类重 apply 现成路径）。
- 口径收紧**独立于模板有价值**（存量代码受益），可作先行小步。

## 工具与编辑器支持（2026-11-01）

四档各带触发条件。关键认知：LSP 最贵的数据源全部在已规划基建里——source map（错误回映射副产品）、dev 注册表、类注册表；插件不是独立工程，是工具二进制的子命令 + 薄壳（Slint 同构：`slint-lsp` 住主仓 `tools/lsp`）。

| 档 | 内容 | 成本 / 触发 |
| --- | --- | --- |
| 0 档：零插件 | HTML 可关联扩展名（`.mng.html`）+ `files.associations` 白拿高亮；`tasks.json` + problemMatcher 把错误回映射接进 Problems 面板 | 零成本，随模板 v1；1 档落地后文件切裸 `.mng`（终态名） |
| 1 档：轻插件 | 静态贡献包：associations 打包 + TextMate injection（属性值 MoonBit 表达式着色；官方 vscode-moonbit grammar 复用待查 license）+ snippets | 一两天，v1 期间顺手 |
| 2 档：LSP | 工具 `lsp` 子命令：诊断推送、组件/状态/handler/token/类名补全、模板 ↔ 生成码 ↔ MoonBit 跳转（复用 source map） | 触发：v1 用出真痛感；语法/注册表稳定前不动工 |
| 3 档：预览集成 | LSP 拉起预览窗（Slint LSP preview 模式对位），对应终态 `preview` 子命令 | 挂终态 |

## 与既有规划的关系

- 与模块拆分（[module-split.md](module-split.md)）**正交**：消费拆分后的声明层，互不阻塞。
- 与 gui-webview 组件**互补**：原生面自编译模板是唯一主面；web 内容（含整窗 webview）是兼容嵌入，不构成第二渲染底座。
- 遵循 roadmap「不为对齐而补」：本工程立项理由是原生路线自身的可读性诉求与双向绑定缺位，不是框架兼容。
- 热更新供给端复用 `@shell` 单实例通道与路由挂载机关（`unmount` / `mount_into_holder` / `remount_all`），运行时零新机制。

## 开放问题（待讨论）

1. ~~语法细节~~：**已冻结**（2026-11-01）——语法对齐 Vue：`{{ }}`、`:attr`、`@event`、`v-model`（落点直传 Store）、`v-if` 全家 + `v-show`、`v-for`、`ui-*` 内置表 + script setup `let` 绑定暴露；收窄项见「Spike 契约」记档。
2. ~~单文件格式与扩展名~~：**已定 `.mng.html`**（`.mng` 与图像格式 MNG 重名，按「无重名才换」规则保留 `.html` 后缀）；script 段原文进生成函数体前段、模板树进后段。
3. 生成物提交 or 忽略（本方案倾向提交 + CI 校验新鲜度）。
4. spike 已选 showcase 表单页；生成函数签名 v1 定 `fn <文件名去扩展>() -> @widget.Node`——app 注入需求与组件 props 类型化（带参组件）留 v2。
5. 工具命名——按路线门面标准起：终态是本路线的 Vite 位次，对外 DX 的第一入口。
6. LSP hover 能从 `moon check` 借到多少类型信息（决定 hover 档做不做）。
7. 布局属性样式化口径收紧：优先级规则落点与存量构造参数的迁移策略（独立于模板先行时就要定）。
8. IR / 注册表 rev 握手协议细节（键集上报格式、rev 对不上时的降级口径）。
