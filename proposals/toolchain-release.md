# 工具链三通道分发方案（P3）

2026-11-12 起草。目标：mng + mngui 两个可执行经 mooncakes / GitHub Releases / Gitee Releases 三通道可达，安装脚本一次装齐。

## 现状（2026-11-12 核实）

- 工具链模块 `tools/native-gui-tools`（`NoahLiu/native-gui-tools@0.1.0`），可执行包 `mng/` 与 `mngui/` 各自 `pkgtype(kind: "executable")`。
- **已实测**：`moon install` 按**可执行包**逐个装（Windows 上 `moon install ./tools/native-gui-tools/mng` 只装 mng.exe 一件）；装模块名报「not a main package」（adaptation.md 有实录，docs/zh/guide/mng.md 已写口径）。
- gui 库线上版 0.3.1，**发版缺口**：mngdev（scaffold 依赖，2026-11-07 进库）与 prebuild.mbtx（2026-11-11 进库）都在 0.3.1 之后——仓外新建工程跑 `mng dev` 必挂（TODO 已记「仓外腿挂起」）。
- 库发版方式：手工 `moon publish`，无脚本。注册表元数据教训：license 必填、manifest 须新格式 moon.mod/moon.pkg。
- Gitee 镜像独立手工维护，用户名与 GitHub 不同（gitee `noahliu0911` / GitHub `lb091188`）；已有 `GITEE_TOKEN` + API v5 附件上传先例（win-ffmpeg-vendor.yml）。
- 预构建示例二进制走「固定 tag 覆盖」模式（`bin` tag / Binaries Release）；app 发布线（app-v*）尚未首跑。

## 定案一：版本轴

两轴独立，不强行对齐：

| 轴 | 载体 | 现值 |
|---|---|---|
| gui 库 | `gui/moon.mod` + 全仓 13 处钉版 | 0.3.1 |
| 工具链 | `tools/native-gui-tools/moon.mod` + `MNG_VERSION`（mng --version） | 0.1.0 / 0.2.11 |

- 工具链自身两处（moon.mod 与 MNG_VERSION）**随同一次发版同步升**，避免「mng --version 与包版本对不上」。
- tools 对 gui 的依赖钉版随 gui 发版同批升。
- mngui 不设独立版本号（跟模块版本走）。

## 定案二：发版顺序（每步一个提交）

1. **gui 0.3.2**：`gui/moon.mod` 升版 + 13 处钉版同批升（脚本核对：`grep -rn 'native-gui@0.3.1' --include=moon.mod`）+ `scaffold/tpl.mbt` 的 `SCAFFOLD_GUI_FALLBACK` + roadmap 版本行。手工 `moon publish`（照 0.3.0 流程）。
2. **工具链 0.2.12**（或 0.3.0，见定案三争议）：moon.mod 与 MNG_VERSION 同批。不单独发 mooncakes（工具分发走二进制通道，见定案四）。
3. **Release 产物**：CI 出三平台 mng/mngui 二进制 → GitHub Releases + Gitee Releases。
4. **安装脚本**：`install.sh` / `install.ps1`（见定案五）。

## 定案三：GitHub Releases 形态

- tag：`tool-v<MNG_VERSION>`（如 `tool-v0.2.12`），**版本化 tag 不覆盖**（工具是用户要锁版本的东西，与示例预构建的 `bin` 固定 tag 覆盖模式区分；坏版本可删 tag 重发）。
- 资产命名对齐现有载体口径：
  - `mng-tool-<ver>-windows-x86_64.zip`（mng.exe + mngui.exe 两件）
  - `mng-tool-<ver>-darwin-aarch64.zip` / `mng-tool-<ver>-linux-x86_64.tar.gz`
- 每 zip/tar 内两件一起分发（mng + mngui），解压到 `~/.moon/bin`（或用户自选 PATH 目录）即完成安装——这个形态下「moon install 装不全」的问题天然绕开。
- 新 workflow `release-tool.yml`：tag 推送触发，三平台矩阵 `moon build --release`（windows 腿注释已言明「release 才是 moon install 发给用户的形态」，同口径）→ 汇总腿 `gh release create`。
- CI 加验证步：**装模块名是否装全两个可执行**——`moon install ./tools/native-gui-tools/mng && moon install ./tools/native-gui-tools/mngui` 之后 `mng --version && mngui --version`（后者要有输出）。哪天 moon install 支持按模块装全部可执行，脚本切回单命令。

## 定案四：Gitee 镜像

- 同包资产上传 Gitee Release（tag 同名）。复用 win-ffmpeg-vendor.yml 的同步步模式：`GITEE_TOKEN` secret + API v5；**附件接口无覆盖语义**——先删旧附件再传（同先例）。
- release 说明里贴镜像链接（同 release-bin.yml 的口径）。
- 未配 token 时该步跳过（同先例）。

## 定案五：安装脚本

`install.sh`（POSIX）与 `install.ps1`（Windows）：

1. 判 moon 在 PATH（不在则给 mooncakes 安装引导）。
2. `moon install NoahLiu/native-gui-tools/mng@<ver> && moon install NoahLiu/native-gui-tools/mngui@<ver>`（两次，已实测按包装单件）。
3. 校验 `mng --version` 输出含 `<ver>`；mngui 缺席则提示降级路径（下载 Release zip 手动放置）。
4. 裸 `mng` 首跑引导交给 ready 状态机（已有）。

脚本落 `scripts/install/`；文档站 mng.md「装」节与 README 指路。

## 争议待定

- 工具链版本跳 0.2.12（延续 MNG_VERSION 线）还是 0.3.0（对齐 gui 0.3.x 观感）——倾向 0.2.12：MNG_VERSION 是编辑器握手协议位（mng-schema 变更才动大版本），与 gui 版本观感无关。
- mooncakes 是否也发 tools 模块（`moon add` 用户可装源码形态）：倾向发（install 脚本兜底装两个包），但首版只做二进制通道验证，mooncakes 发 tools 放二期。

## 验收清单

- [ ] gui 0.3.2 发版后，仓外 `mng new demo && mng dev` 全链通（解「仓外腿挂起」）
- [ ] tool tag 推送 → 三平台资产齐 + Gitee 镜像齐
- [ ] install.sh / install.ps1 在干净机器装齐两件
- [ ] `mng --version` 与 moon.mod 版本一致
