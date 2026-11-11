# mng 命令与配置

`mng` 是 native-gui 的开发工具链门面：建工程、写 `.mng` 页面、热更循环、打包发布、环境体检、语言服务都从它进。文法见[单文件组件（.mng）](./sfc)，热更与编辑器见[热更与编辑器](./mng-dev)，发布叙事见[打包与更新](./publish)。

## 装

工具随仓库分发，`moon install` 按**可执行包**逐个装（装模块路径会报「not a main package」）：

```sh
moon install ./tools/native-gui-tools/mng      # CLI 门面
moon install ./tools/native-gui-tools/mngui    # GUI 向导（裸 mng 自动拉起）
mng --version   # 应打印 mng 版本与 mng-schema 位
```

裸敲 `mng` 的入口状态机：

- `~/.mng/ready` 不存在（首跑，或 mng 升级后版本行不符）→ 自动跑一轮[环境体检](#mng-doctor)，全绿写 ready 继续；红项列清单给修复命令退出。
- ready 有效 → 拉起 `mngui` 向导（同目录 / `~/.moon/bin` 查找）；没装会给安装提示。
- 无显示服务（SSH/CI）或向导退出码 3 → 回 usage。
- 状态机只门**无参裸跑**这一条交互入口；`mng dev` 等子命令与 CI 永不受 ready 影响。

## 命令参考

| 命令 | 作用 |
|---|---|
| `mng new <名>` | 生成可跑最小工程（`new app <名>` 显式同义） |
| `mng new page <路径>` | 生成单页 `.mng` 样板（父目录不存在现建） |
| `mng init` | 既有工程接模板：模块根写 `mng.toml` 样板（已有不覆盖） |
| `mng dev` | watch + 热更 + 回退编排（详见[热更与编辑器](./mng-dev)）；`-h` 看细目 |
| `mng build` | 无参按 `mng.toml` 生成全工程**生产形态**生成码；`mng build <in.mng> -o <out.mbt>` 编译单文件 |
| `mng package` | 打包本平台应用产物（详见[打包与更新](./publish)）；`-h` 看细目 |
| `mng publish` | 扫 `.mng/dist/` 生成 update.json 并经 gh 上传 draft Release |
| `mng doctor [-f]` | 环境体检；全绿写 `~/.mng/ready`，`-f` 强制重检 |
| `mng lsp` | 语言服务（stdio JSON-RPC，VS Code 扩展的引擎） |
| `mng ir <in.mng>` | 打印模板 IR 补丁（调试热更通道用） |
| `mng map-errors --map <map> <log>` | 把 `moon check` 日志里的生成码行列映射回模板行列 |
| `mng gen <in.mng> -o <out.mbt>` | dev 形态编译单个模板（dev 循环内部用） |

命令面提示与错误随 `LC_ALL` / `LC_MESSAGES` / `LANG` 中英切换（`zh` 前缀走中文）；子命令加 `-h` 看详细说明。

## mng.toml

`mng init` / `mng new` 生成；`mng dev` / `mng build` 无参时向上找它，找不到按 `moon.mod` / `moon.work` 推默认。

### [dev]

| 键 | 缺省 | 说明 |
|---|---|---|
| `templates` | `["."]` | 递归扫 `*.mng` 的目录（相对本文件）；跳过 `_build` / `.mooncakes` / 点目录 |
| `build` | `"moon build ."` | 构建命令 |
| `run` | `""` | 启动命令；留空 = 跑一次 build 后从 Artifacts 输出抓可执行路径 |
| `app-id` | `""` | 单实例唤起 id；留空 = 由 moon.mod 的 name 派生（裸名自动垫 `local.` 命名空间） |
| `poll-ms` | `300` | 文件轮询间隔（毫秒） |
| `theme` | （无） | 主题 JSON 路径；存盘即热重载（不走重启） |

### [package]

打包声明（`mng package` 在项目根读；本平台打本平台包）：

| 键 | 缺省 | 说明 |
|---|---|---|
| `id` | `""` | 反域名 id：mac bundle id / 产物短名同源 |
| `name` | `""` | 显示名（.app / DMG 卷名 / 安装器标题） |
| `version` | `"0.1.0"` | 应用版本，三段数字；与 moon.mod 模块版本无关。**改版本只改这里**——`mng dev/build/package` 会同步生成 `appmeta/` 叶子包，应用自报版本单源 |
| `bin` | `""` | 可执行名；留空 = 从构建产物抓 |
| `icon` | `""` | 源图标 1024×1024 PNG，派生 icns/ico（向导「图标步」会自动接线） |
| `resources` | `[]` | 随包资源（递归拷进 Contents/Resources / 安装目录） |
| `maintainer` | `""` | deb control 的 Maintainer（`"名 <邮箱>"`） |

### [package.sign]

| 键 | 说明 |
|---|---|
| `mac_identity` | codesign identity，如 `"Developer ID Application: NAME (TEAMID)"`；留空 = adhoc |
| `notarize_profile` | notarytool keychain profile；非空则公证 + staple |

## 生成码纪律

- 生成码 `<stem>.gen.mbt` 落模板同包，带 `// GENERATED … DO NOT EDIT` 头，**建议提交仓库**（消费者零工具链依赖）。
- dev 与生产形态共用同一条文件，会互相覆盖——提交前选一种并保持一致。
- CI 对两形态各比一遍新鲜度：重生成后 diff 非空即红（改了模板忘重生成会被拦）。
- 报「生成码与重生成不一致」就重跑 `mng dev`（dev 形态）或 `mng build`（生产形态）再提交。

## mng doctor

探测 moon / C·C++ 编译器 /（Linux）GTK 开发包（Python 降为可选提示——构建已改用 MoonBit prebuild），末尾跑一次 **moon native 构建探针**（`~/.mng/doctor/probe/` 落最小 hello 工程真编译一遍，以成败为判据）；Windows 的 MSVC 判据即探针成败（vswhere 查到只做免跑快路）。可选项（WebView、媒体库）缺失只提示不拦。

- 全绿写 `~/.mng/ready`（内容为 mng 版本行，mng 升级自动重检）；`-f` 强制重检。
- 修复行 GUI 链接优先（官方下载页在前、包管理器在后）；探针日志在 `~/.mng/doctor/`。
