# 打包与自动更新

从「`moon run` 起窗」到「用户安装、自动收更新」的完整链路：`mng.toml` 里声明打包配置 → `mng package` 本机出安装包与更新载体 → 推 `app-v*` 标签让 CI 三平台矩阵出全量产物并发 draft Release → 应用内用 `@ui.update_dialog` 检查、下载、安装重启。

方案全貌与决策记录见 `proposals/package-update.md`。

## 产物口径

| 平台 | 安装包（随 Release 分发） | 更新载体（应用自替换） |
| --- | --- | --- |
| macOS (Apple Silicon) | `.dmg` | `.zip`（内含 `.app`） |
| Windows x64 | NSIS `setup.exe` | `.zip`（内含裸 exe 与同目录文件） |
| Linux x64 | `.deb` | `.AppImage`（单文件自替换） |

安装包不是更新载体——更新走「全量下载 + SHA256 校验 + 原子替换」，不依赖系统包管理器。

## 打包声明（mng.toml）

```toml
[package]
id = "com.example.myapp"   # 反向域名，桌面登记与更新标识用
name = "MyApp"             # 显示名（.app / 安装器 / desktop entry）
version = "0.1.0"          # 应用版本，三段 semver；与 moon.mod 的库版本无关
icon = "assets/icon.png"   # 源图标（1024 PNG 最好；各平台尺寸自动派生）
resources = ["assets"]     # 随包资源目录/文件（相对 mng.toml）

[package.sign]
# 可选；不配则 mac 跳过 codesign/notarize、win 跳过 signtool
notarize_profile = "myapp-notary"      # mac 公证（xcrun notarytool 的 profile 名）
win_cert = "cert.pfx"                  # Windows 证书文件
win_cert_pw_env = "WIN_CERT_PW"        # 证书口令读这个环境变量（不进仓库）
```

## 本机打包：`mng package`

在工程根（有 `mng.toml`）跑：

```sh
moon run path/to/mng -- package
```

内部自跑 `moon build . --target native --release --strip`，产物落 `.mng/dist/`。交叉编译不可行（native 后端调本机 C 工具链），**本机只出本平台的包**——三平台产物的唯一通道是 CI 矩阵。

各平台依赖（都是系统自带或自动处理）：

- **macOS**：`sips` / `iconutil` 出 icns、`hdiutil` 出 DMG、`codesign` 签名、`ditto` 出更新 zip
- **Windows**：NSIS（`makensis`，PATH 或 choco 装）；ICO 单帧自建；`signtool` 可选
- **Linux**：`dpkg-deb` 出 deb；`appimagetool` 缺失时自动下载到 `~/.mng/tools`

## CI 发布：推 `app-v*` 标签

`.github/workflows/release-app.yml` 在推 `app-v<版本>` 标签时三平台并跑 `mng package`，汇总腿现算 SHA256/体积生成 `update.json`，发 **draft Release**（人工核过再 publish）。`workflow_dispatch` 可只验证矩阵不发版。

版本一致性：标签里的版本必须与 `mng.toml` 的 `version` 一致，不符产物会被清单生成器跳过并打日志。

## 本地发布：`mng publish`

CI 不可用或只要本平台时，`mng package` 之后在工程根跑：

```sh
moon run path/to/mng -- publish            # --tag 默认 app-v<版本>，--repo 默认 gh 探测
moon run path/to/mng -- publish --no-upload --repo owner/name   # 只生成 update.json 不上传
```

行为：扫 `.mng/dist/` 里版本一致的产物 → 算 SHA256/体积 → 生成 `update.json`（更新载体进 `platforms`，安装包只随 Release 分发）→ 经 `gh` 建 draft Release 并上传（已存在则补传 `--clobber`）。需要本机装好 [gh](https://cli.github.com/) 并 `gh auth login`。

跨平台拼清单：把别处出的产物（比如从 CI artifact 下载的另两平台包）拷进 `.mng/dist/` 一起发——解析器按文件名全收。发布时间戳不填（`pub_date` 空串），以 Release 页显示为准。

## 本地更新服务（测试）

免 CI、免 GitHub 发布，本机走完「检查 → 下载 → 校验 → 安装重启」全链路：

```sh
cd examples/showcase && moon run ../../tools/native-gui-tools/mng -- package
python3 scripts/update_local_server.py --version 0.2.0
```

服务起在 `http://127.0.0.1:8765`，`/update.json` 每次请求现扫产物目录算 SHA256——重新 `mng package` 后不用重启服务。装一个旧版本应用（比如 0.1.0 的 DMG），进「系统集成 → 应用自更新」点「检查更新(本地服务)」，对着的 0.2.0 载体走全链路（下载 → 安装重启 → 版本变 0.2.0，旧 `.app` 旁的 `.mng-old` 由下次启动清掉）。

- 明文 `http://` 是显式开口：`update_check` / `sys_update_actions` 需传 `allow_http=true`（默认仍强制 HTTPS），只用于本地测试链路
- 载体口径与 CI 一致：mac/win 的 zip、linux 的 AppImage 进清单；安装包只静态服务、不进清单
- `--version` 缺省取载体里版本号最高的；改端口用 `--port`（showcase 的本地服务地址固定 8765，改端口需同步改代码里的 `LOCAL_UPDATE_URL`）

## 应用内更新

最短接法三件套（showcase「系统集成 → 应用自更新」有演示/真实清单/本地服务三棵对话框）：

```moonbit
let open : @base.Store[Bool] = @base.Store::new(false)
let flow = @ui.make_update_flow()
let actions = @ui.sys_update_actions(
  flow,
  "https://github.com/<owner>/<repo>/releases/latest/download/update.json",
  "0.1.0",                    // 与 mng.toml version 同源
  quit=fn() { host.quit() },  // 安装成功：relaunch 已发起，立刻退
)
// 界面树里挂一棵（0 高锚点，开时进浮层图层）
@ui.update_dialog(open, flow, actions, current_version="0.1.0")
```

组件与执行的分工：`update_dialog` 只管状态机与视图，「检查 / 下载 / 安装」三个动作由 `UpdateActions` 闭包注入——按钮先标状态（Loading 立刻可见）再触发闭包，闭包完成后把结果喂回 `flow.report_check / report_download / report_install`。`sys_update_actions` 是直连 `@sys.update_*` 的默认装配；要自己的调度（后台线程、进度回调、取消）就换掉三个闭包，组件面不动。

应用启动早期建议调一次 `@sys.update_cleanup()`（清上次更新留下的 `*.mng-old` 残留）。

## update.json 格式

```json
{
  "version": "0.2.0",
  "notes": "Release 0.2.0",
  "pub_date": "2026-11-08T00:00:00Z",
  "platforms": {
    "darwin-aarch64":  { "url": "…zip", "size": 123456, "sha256": "…" },
    "windows-x86_64":  { "url": "…zip", "size": 123456, "sha256": "…" },
    "linux-x86_64":    { "url": "…AppImage", "size": 123456, "sha256": "…" }
  },
  "signature": null,
  "sig_alg": null,
  "deltas": null
}
```

`signature` / `sig_alg` / `deltas` 是预留位（v1 恒 `null`）：v1.5 启 Ed25519 签名、v2 启增量更新，格式不变、免破坏性变更。

## 信任模型（v1）

HTTPS 强制（`http://` 明文清单直接拒，本地测试可显式 `allow_http=true` 放行，见「本地更新服务」）+ SHA256 校验（防损坏，不防源沦陷）。Ed25519 清单签名随 v1.5 落地。

## 已知取舍（v1）

- **同步下载**：`@sys` 走子进程同步执行，大文件下载期间界面停摆（`sys_update_actions` 把动作错一拍，Loading 至少先画出来）；异步执行器随平台线程批
- **无下载进度百分比 / 无取消**：sys 暂无文件尺寸原语，进度与取消随异步执行器批
- **替换按自身路径落位**：更新替换的是「自己旁边」那份应用——直接从挂载的 DMG 卷里运行时位置只读，会报「把 .app 拖进应用程序」的可读错误；mac 解压失败会回滚（旧 `.app` 先挪 `.mng-old`，解压不成搬回来）
