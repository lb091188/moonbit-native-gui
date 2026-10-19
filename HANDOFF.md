# native-gui 0.1.1 重发与文档站善后 — 交接文档

> 交接时间:2026-10-15(GMT+8) · 交接方:Windows 工作机会话(文档收口 + 重发准备批) · 接收方:同仓库协作方 / 后续会话
> 交接范围:① mooncakes **重发执行**(yoga-mbt 0.1.1 → native-gui 0.1.1,可选首发 gui-media / gui-examples);② 文档站 **Cloudflare Pages 域名善后**;③ 交接时刻仓库状态与勿动项。
> 维护说明:发现本文与代码/事实不一致时**以代码为准**,并顺手把本文改成正确的;本文也受仓库「一批一提交一推送」纪律约束。

---

## 0. 三十秒速览

- **代码/文档侧已就绪**:0.1.1 相关改动全部已提交并推送(§3);剩下的是**执行动作**——mooncakes 重发(§1)与文档站部署/域名决定(§2)。
- **mooncakes 顺序**:先发 `yoga-mbt 0.1.1`,等构建转绿,再发 `native-gui 0.1.1`;可选首发布 `gui-media`、`gui-examples` 0.1.0。**必须在已登录 mooncakes 的环境执行**(Windows 工作机无凭据)。
- **文档站**:已迁至 **`moonbit-native-gui.pages.dev`**(2026-10-18 新建同名 Pages 项目,Git 集成推送 master 自动部署);旧项目(`moonbit-libyue.pages.dev`)已整体删除,名字与域名均已释放(§2)。
- **勿动**:工作区有进行中的未提交改动(拖拽实现与探针),不要 `git add -A`、不要清理(§4)。

## 1. mooncakes 重发(待执行)

### 1.1 为什么重发(归档级证据)

口径文档:`proposals/adaptation.md`「发布前预演与重发口径(2026-10-15 定)」。两个 0.1.0 归档的问题:

- `NoahLiu/yoga-mbt@0.1.0`:发布 zip 顶层已是新格式 `moon.mod`,但 `src/moon.pkg.json` 旧清单残留(包在仓内目录迁移前发布;注册表侧改不动)。
- `NoahLiu/native-gui@0.1.0`:zip 是仓库根时期快照(旧仓库 URL、旧描述)。

已发布版本**不可原地改写** → 只能递增版本号重发(0.1.0 → 0.1.1);仓内各模块钉版已同批改齐(`moon.work` 按「名 + 版本」匹配本地成员,漏改连本地都解不开)。

### 1.2 顺序与命令(在各自模块根执行)

| # | 目录 | mooncakes 名 | 版本 | 动作 | 说明 |
|---|------|--------------|------|------|------|
| 1 | `modules/yoga-mbt` | `NoahLiu/yoga-mbt` | 0.1.1 | **重发(先)** | 下游构建读它,先等转绿 |
| 2 | `gui` | `NoahLiu/native-gui` | 0.1.1 | **重发(后)** | 钉 `yoga-mbt@0.1.1` |
| 3 | `modules/gui-media` | `NoahLiu/gui-media` | 0.1.0 | 可选首发 | 钉 `ffmpeg-mbt@0.1.0`(已发布且归档干净) |
| 4 | `modules/gui-examples` | `NoahLiu/gui-examples` | 0.1.0 | 可选首发 | 与 #3 都发时先 3 后 4 |
| — | `modules/ffmpeg-mbt` | `NoahLiu/ffmpeg-mbt` | 0.1.0 | 无需动 | 注册表归档已核验干净 |

```sh
# 在已登录 mooncakes 的环境(此前发 0.1.0 的那台),先 git pull 到最新
cd modules/yoga-mbt && moon publish                 # 可先 moon publish --dry-run 空跑
# 等构建转绿:https://mooncakes.io/api/v0/builds/log?module=NoahLiu/yoga-mbt&version=0.1.1
cd gui && moon publish
# 转绿:https://mooncakes.io/api/v0/builds/log?module=NoahLiu/native-gui&version=0.1.1
# 可选首发:
cd modules/gui-media && moon publish
cd modules/gui-examples && moon publish
```

### 1.3 发布注意

- **就地发布**:`moon publish` 在模块根就地打包该模块内容;临时目录中转**不必要**(多一层拷贝反而引入漏文件风险;`moon.work` 只影响本地解析、不影响归档——定案见 1.1 所引口径条)。
- **先上游后下游**:yoga-mbt 构建转绿前不要发 native-gui。
- **预演归档**:仓库根 `_build/publish/`(本地,未入库)有本批 4 份预演 zip——`NoahLiu-yoga-mbt-0.1.1`、`NoahLiu-native-gui-0.1.1`、`NoahLiu-gui-media-0.1.0`、`NoahLiu-gui-examples-0.1.0`(另有 native-gui / yoga-mbt 的 **0.1.0 历史档**,别拿错)。核验口径 = 解包零 `.json` 旧清单、`moon.mod` / `moon.pkg` 就位。预演时点 `15afc5c`;其后仅 `1ea935f`(库侧零改动),结论仍有效,保险起见可在模块根重跑 `moon package` 再核对一次。
- **包页 README**:随发布呈现为 mooncakes 包页 README 的是 `gui/README.md` 扩写版。
- **凭据**:Windows 工作机 `.moon/credentials.json` 不存在,`moon publish --dry-run` 止步于凭据检查——发布会话必须在已登录环境。
- 发布后到 mooncakes 对应包页复核版本号、README 与依赖行。

## 2. 文档站(Cloudflare Pages)善后(待决定)

### 2.1 现状(2026-10-18 更新)

- 线上:**`https://moonbit-native-gui.pages.dev/`**(中文在 `/zh/`);新项目 `moonbit-native-gui` 走 **Git 集成(路线 A)**:Root directory = `docs`、框架预设 VitePress、输出 `.vitepress/dist`、生产分支 `master`,推送 master 自动部署。
- 旧项目(创建名 `moonbit-libyue`,后被改名为 `moonbit-native-gui` 占住新名,域名始终 `moonbit-libyue.pages.dev`)已于 2026-10-18 **整体删除**(522 条部署逐条清后删项目;活跃 Production 部署单条不可删,error 8000034,随项目删除一并消失)。**旧域名现为死链**。
- §2.4 的仓库链接同步已随本批完成;演示文本内的旧域名引用(`experiment/paint_probe/main.mbt:103`,§4 勿动项)现为死链,处理方式待定。
- 首次部署曾因 VitePress 死链构建失败:`THIRD-PARTY-NOTICES.md` 在 `docs/` 源目录外;已以副本入 `docs/public/`、中英 build.md 改链站点根修复(副本为有意双份,同 `VENDOR_BASES` 先例)。

### 2.2 为什么「改了项目名,域名没变」

`<项目名>.pages.dev` 子域在**创建项目时选定**,后台没有改名入口;重命名项目不会更换它(CF 文档 Custom domains 页表述为「创建项目时选定」;本仓已实测)。要域名叫 `native-gui` 风格,只有:

| 路线 | 做法 | 代价 / 备注 |
|------|------|-------------|
| **A 接受现域名** | 什么都不用改(仓库 5 处链接已指向它) | URL 与品牌不一致;其余零成本 |
| **B 新建目标名项目** | CF 新建 Pages 项目,项目名即域名(如 `native-gui` → `native-gui.pages.dev`),重新接一次部署 | 要同步仓库链接与部署配置(§2.4);旧项目**建议先留着**,外链不烂 |
| **C 挂自定义域** | 有自有域名时:按 CF 文档加 CNAME 指向 `<站点>.pages.dev`,并在项目里 Set up a domain | 需要自有域名 |

候选新名(`native-gui` / `native-gui-docs` / `moonbit-native-gui-docs`)此前探测均未解析(大概率未被占),最终以创建时 CF 校验为准。

### 2.3 部署方式(三选一,按原接法)

- **A. Git 集成(零 secret)**:项目接本仓库,Root directory = `docs`,build command = `npm install && npm run build`,output directory = `.vitepress/dist`;之后推送自动部署。
- **B. 仓库工作流**:GitHub → Actions → `Deploy docs to Cloudflare Pages` → Run workflow(project 填实际项目名);需仓库 Secrets 已配 `CLOUDFLARE_API_TOKEN`、`CLOUDFLARE_ACCOUNT_ID`。
- **C. 本地 wrangler**:`cd docs && npm install && npm run build && npx wrangler pages deploy .vitepress/dist --project-name=<实际项目名>`。

### 2.4 若换域名/新项目,仓库要同步的位置(已执行,2026-10-18)

1. `README.md` 第 81、105 行;`README_ZH.md` 第 81、105 行(文档站链接)
2. `gui/README.md` 第 43 行(**会进 mooncakes 包页 → 若换域名,理想顺序:先改链接、再发 native-gui,包页一次到位**)
3. `docs/wrangler.jsonc` 的 `"name"`(现 `moonbit-libyue`)
4. `.github/workflows/deploy-docs.yml` 默认 `project`(现 `moonbit-libyue-docs`,与 3 不一致,部署前先按 CF 实际统一)+ 头注释第 11 行

(演示文本假链接各 1 处:`examples/native-app/main.mbt:2461`、`experiment/paint_probe/main.mbt:103`,属示例内容,有意保留,可不动。)

## 3. 本批已入库改动(2026-10-15)

- `ef39dd9`【文档】重发前文档收口:显示名统一 native-gui、包清单补 style(14 包)、清亮度/默认应用残留、补重发链经验条(21 文件)。
- `15afc5c`【构建】重发准备:native-gui 与 yoga-mbt 递增 0.1.1、仓内钉版同批同步、showcase 版本号跟升、CI 补 style(8 文件)。
- `1ea935f`【修复】Windows 托盘挂菜单与左右键点击全失效(showcase 侧起表时机;库侧零改动;**真机复验归 S25**)。
- 当前 `master` = `origin/master` = `1ea935f`(推送已完成)。
- 版本快照:`gui/moon.mod` 0.1.1(钉 `yoga-mbt@0.1.1`)· `modules/yoga-mbt` 0.1.1 · `gui-media` / `gui-examples` 0.1.0(未发布过)· `ffmpeg-mbt` 0.1.0(干净)。
- GitHub 侧无待办:远端与全仓链接均为 `lb091188/moonbit-native-gui`(API 核验未改名);MoonBit 模块名 `NoahLiu/native-gui` 不变(既有 import 不受影响)。
- 门禁现状:全仓与 examples / gui-examples / gui-media / experiment / yoga-mbt 的 `moon check --deny-warn` 全绿(提交门槛);库全量测试未在 Windows 本机重跑(Windows 有已知测试基线红点,以 CI 为准);真机复验各批已全部通过。

## 4. 交接时刻的工作区快照(勿动项)

`git status` 实测(2026-10-15):有**进行中的未提交改动**(拖拽实现与探针,归属以用户 / 在途会话为准):

```
 M gui/core/app.mbt  gui/core/drag.mbt  gui/core/widget.mbt  gui/ui/drag.mbt  gui/ui/drag_wbtest.mbt  gui/win/ffi.mbt  gui/win/stub.c
?? gui/win/drag.mbt  experiment/drag_probe/  experiment/toast_probe/  showcase-prof.txt
```

- **不要 `git add -A`,不要清理/回退这些文件**;提交一律 `git add <显式路径>`。
- 有意保留的旧名引用(勿顺手改):黑客松申报文档、`modules/yoga-mbt/HANDOFF.md`、演示文本内 `moonbit-libyue.pages.dev`、`image_wbtest.mbt` 假路径、`TODO.md` 中 Linux 本地副本路径两处。
- 本机 git 身份已配(仓库级 `NoahLiu <lbpeter0911@163.com>`)。

## 5. 待决清单

- [ ] mooncakes 重发执行(§1;Windows 机发不了,换已登录环境)。
- [x] 文档站已迁新域名(2026-10-18):新建 `moonbit-native-gui` 项目(路线 A Git 集成)+ 删旧项目;§2.4 已同步。剩:演示文本内旧域名死链处理待定。
- [ ] 发布完成后:回写 `TODO.md` 的重发链条目,并把本文件的「待执行」状态改掉。

## 6. 参考

- 发布口径:`proposals/adaptation.md`「发布前预演与重发口径」。
- 重发链、过渡期收口:`TODO.md` 对应条目。
- CF 域名机制:Cloudflare 文档 Custom domains 页 <https://developers.cloudflare.com/pages/configuration/custom-domains/>。
- 交接范例:`modules/yoga-mbt/HANDOFF.md`(模块级;格式可参照)。
- 预演归档:仓库根 `_build/publish/`(本地,未入库)。
- 对外优化方向(上手门槛 / 可信度 / 内容 / 治理 四方向 + 待定决策 + 明确不做):`docs/zh/roadmap.md`(2026-10-15 新增,已挂文档站侧栏与中英索引)。
