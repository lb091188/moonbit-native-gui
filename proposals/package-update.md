# 打包与自动更新实施方案(A1/A2/A3)

2026-11-08 立项,方向见 [方向.md](方向.md);产物四件与 TODO 队列已钉死,本文档是待办第一项「实施方案定稿」。CPU 光栅最小闭环,不绑 GPU 线。

## 〇、定案速览

| # | 定案 | 理由 |
|---|---|---|
| D1 | **单平台打本平台包**,全平台产物走 CI 矩阵 | moon 交叉编译能力未证不赌;现有 CI 三平台矩阵与 release-bin 先例沿用 |
| D2 | **更新载体 ≠ 安装包**:mac/win 更新下载裸产物 zip,linux 直接用 AppImage | DMG/setup 不是可自替换格式;AppImage 单文件天然兼作 |
| D3 | 清单单份 `update.json` 含全平台 platforms 表,预留 `signature`/`sig_alg`/`deltas` 字段 | 一 URL 固定;v1.5 签名、v2 增量免破坏性变更 |
| D4 | 应用版本在 `mng.toml [package].version`,与 moon.mod 解耦 | moon.mod 的 version 是模块自己的,下游应用有独立版本节奏 |
| D5 | release-bin 的 mac `.app` 组装/资源随包逻辑**上收进 mng package**,CI 瘦身 | 同一段逻辑在 CI 内联 Python 与工具里双份必漂移 |
| D6 | v1 发布主路径 = CI 打包后自动 draft release;`mng publish` 本地版给清单生成 + gh 探测上传 | CI 有 GITHUB_TOKEN 天然可发;本地 gh 缺失时打印手动指引 |
| D7 | 信任模型 v1 = HTTPS + SHA256(防损坏不防源沦陷),Ed25519 进 v1.5 | 不引签名依赖拖首发;字段位已留 |
| D8 | 打包验收载体 = `examples/showcase` | 有真实资源/依赖闭包,当发布样例与文档示例 |

## 一、可复用资产(现状盘点)

- `mng` 子命令分发是 main.mbt 的 if-else 链,加 `package` / `publish` 两分支;dev 已会「从 moon build Artifacts 抓可执行路径」,package 复用同一段(`project.mbt`)。
- `mng.toml` 解析器已有(`[dev]` 节),`[package]` 节同源扩。
- release-bin.yml 的 CI 内联逻辑(mac `.app` 组装 + `install_name_tool` 补 rpath + adhoc 重签、win dll 随包、mac vendor dylib 随包、THIRD-PARTY-NOTICES)——D5 上收目标。
- `gui/sys`:procrun(pr_run)、fsx、json、envx——更新器库侧地基。
- 工具缓存:用户级 `~/.mng/tools/`(makensis / appimagetool 落这,跨项目共享);项目临时仍走 `.mng/`。

## 二、配置面:`mng.toml [package]` 节

```toml
[package]
id       = "com.example.myapp"   # 反域名:mac bundle id / deb 包名(点换减号) / win 注册键同源
name     = "My App"              # 显示名(标题栏/desktop entry/安装器)
version  = "1.2.0"               # 应用版本,semver 三段
bin      = ""                    # 包名(缺省从 moon.mod name 推)
icon     = "assets/icon.png"     # 源图标:1024×1024 PNG,派生 icns/ico/hicolor
resources = ["assets/"]          # 随包资源(递归)
targets  = ["dmg", "setup", "deb", "appimage"]  # 本平台可打的勾选,缺省全打

[package.linux]
categories = ["Utility"]         # desktop entry Categories
comment    = "…"                 # 可选

[package.update]                 # 全缺省 = 不接更新
url = "https://example.com/update.json"   # 清单地址(挂应用自己的发布面)

[package.sign]                   # 签名证书入口(2026-11-08 用户定):全空 = mac 走 adhoc、win 不签
mac_identity = "Developer ID Application: NAME (TEAMID)"   # codesign identity;缺省 "-"
notarize_profile = "my-profile"  # notarytool keychain profile;非空则 DMG 公证 + staple
win_cert = "cert.pfx"            # signtool 签 setup 与 exe(win 腿消费)
win_cert_pw_env = "SIGN_PW"      # 证书密码读环境变量,不落 toml
```

签名两层口径(别混):`[package.sign]` 是**代码签名证书**(产物签名/公证,给 Gatekeeper 与 SmartScreen 看);更新清单的 Ed25519 签名(`signature`/`sig_alg` 字段)是**更新信任签名**(防更新源沦陷),照 D7 进 v1.5。mac 有 identity 自动加 `--options runtime`(公证前提),公证链 = `notarytool submit --wait` + `stapler staple`,任一步失败报错不撤已出产物。

- 深链/文件关联字段(schemes / file_exts)本批**只留 schema 不实现**,A3 后置批再消费——字段先不进文档站。
- 校验:id 反域名格式、version 三段、icon 存在且为 png,错则报行号——mng CLI 双语文案同现状。

## 三、产物与制作(每平台布局 + 工具链)

### macOS(`dmg` 腿)

- **.app**:`Contents/MacOS/<bin>` + `Contents/Resources/{icon.icns, assets…}` + `Info.plist`(CFBundleIdentifier/Name/Executable/IconFile/ShortVersionString/LSMinimumSystemVersion);dylib 随包与 `@executable_path/../../../lib` rpath 沿 release-bin 现口径;`codesign --force -` adhoc(Developer ID 经 `--sign` 留口)。
- **icns**:源 png → sips 批量缩放出 iconset(16…1024 全档)→ `iconutil -c icns`(皆系统自带,零下载)。
- **DMG**:`hdiutil create -format UDZO`,卷内 `.app` + `Applications` 符号链接;自定义背景/坐标布局 v2 再说。
- **更新载体 zip**:`<id>-<ver>-darwin-aarch64.zip`(.app 整树)。

### Windows(`setup` 腿)

- **NSIS setup**:mng 内嵌模板生成 `.nsi`——unicode true、`InstallDir $LOCALAPPDATA\Programs\<id>`(per-user,免管理员)、File 递归、开始菜单快捷方式、`WriteUninstaller`、HKCU 卸载注册键(进「应用与功能」)、静默档 `/S`。
- **makensis**:PATH 探测 → 缺失自动下载 NSIS zip(官方 release,sha256 校验)→ `~/.mng/tools/nsis/`。
- **ico**:源 png 多尺寸压成 ICO 容器**自写**(Vista+ 支持 ICO 内嵌 PNG 帧,容器头几十行,mngkit 侧纯函数 + wbtest)。
- **更新载体 zip**:裸 `exe + dll + 资源`。

### Linux(`deb` + `appimage` 腿)

- **deb**:目录树 `data/usr/bin/<bin>`、`usr/share/applications/<id>.desktop`、`usr/share/icons/hicolor/<n>/apps/<id>.png`、`DEBIAN/control`(依赖段留空——本库动态库均随包)+ md5sums,`dpkg-deb --build`(deb 系自带;CI ubuntu 腿 ✓)。
- **AppImage**:手组 AppDir(`AppRun` 自写极简 shell:setup env + exec;`<id>.desktop`;`usr/bin` + `usr/lib` + 图标)→ `appimagetool` 封(runtime 内嵌);appimagetool 从 AppImageKit GitHub releases 下载(sha256),无 FUSE 环境走 `--appimage-extract-and-run`。
- **更新载体**:AppImage 本体即载体,无额外产物。
- 桌面登记:desktop entry 必有(Name/Exec/Icon/Categories/Type;MimeType 槽位留给 A3)。

### 产物命名(全平台统一)

```
<slug>-<ver>-<target>.{dmg,exe,deb,AppImage}   # 安装包
<slug>-<ver>-<target>.zip                       # mac/win 更新载体
```
target 三元组:`darwin-aarch64` / `windows-x86_64` / `linux-x86_64`(mac 只 Apple Silicon,对齐支持面)。

## 四、更新协议 v1

### 清单 `update.json`(D3)

```json
{
  "version": "1.3.0",
  "notes": "…",
  "pub_date": "2026-11-08T00:00:00Z",
  "platforms": {
    "darwin-aarch64":  { "url": "…zip", "size": 8123456, "sha256": "…" },
    "windows-x86_64":  { "url": "…zip", "size": 9234567, "sha256": "…" },
    "linux-x86_64":    { "url": "…AppImage", "size": 7654321, "sha256": "…" }
  },
  "signature": null, "sig_alg": null, "deltas": null
}
```

### 库侧更新器(分层)

| 层 | 位置 | 内容 |
|---|---|---|
| 纯逻辑 | `gui/sys/update.mbt` | 清单拉取(pr_run curl,HTTPS 强制)与解析、semver 三段比较(纯函数 + wbtest)、下载到临时、SHA256 校验(pr_run shasum/sha256sum 按平台)、替换计划生成 |
| 平台替换桩 | `gui/sys`(平台分派) | win:新文件落 `.new` → 旧 rename `.old` → `.new` 落位 → relaunch → 新进程启动清 `.old`;mac:zip 解压(pr_run unzip)→ 旧 `.app` rename → 新落位 → relaunch → 启动清残留;linux:新 AppImage 落 `.new` → chmod +x → rename swap → relaunch |
| relaunch | `gui/sys` | pr_run 起自身路径不等待 + 进程退出(pr_run 无 detached 参数则实现时补) |
| UI | `gui/widget` `update_dialog` | 状态机 Idle→Checking→Available(版本+notes)→Downloading(进度=fsx 轮询已下字节/size,500ms)→Installing→Relaunch;缺省关闭/出错诚实报 |

- 应用侧接线:`mng new` 脚手架「设置页·检查更新」按钮 + `Store` 记「下次提醒」;定时检查(24h)脚手架可选开,库不强加。
- `deb` 档检测到新版:不出自替换,出「去下载」引导(打开 url)——系统目录不可写。

## 五、发布流

- **CI**:新独立 workflow `release-app.yml`(与「Binaries」示例线互不干扰),tag `app-v*` 触发 → 三平台矩阵 `moon build --release --strip` → `mng package` → 上传产物 → 汇总腿(ubuntu)算 sha256/size 生成 `update.json` → `gh release create --draft`(GITHUB_TOKEN)。工具缓存 actions/cache(makensis/appimagetool)。
- **`mng publish`**(本地):读本机产物目录 → 生成/更新 `update.json` → 探测 `gh`(pr_run)有则 draft 上传,无则打印产物与清单路径 + 手动指引。双语文案。

## 六、A3 登记面分档

- **本批(v1)落**:desktop entry 全量键、Info.plist 基础键(CFBundleIdentifier/Name 等)——打包必带,无额外工作。
- **后置批**:深链 schemes(注册:plist CFBundleURLTypes / win 注册表 / mime)+ 文件关联(扩展名→mime)+ 最近文档写侧 + jumplist;`mng.toml` schema 已留,唤起事件经单实例通道回投。

## 七、执行拆项(对齐 TODO 队列,一项一提交)

1. **方案定稿**(本文档)
2. **A1 mac 腿**:`mng package` 子命令骨架(TOML `[package]` 解析 / Artifacts 抓路径 / D5 上收 .app 组装)+ icns 派生 + DMG + 更新载体 zip
3. **A1 win 腿**:.nsi 模板 + makensis 探测/自动下载 + ICO 容器自写(wbtest)+ setup 产出
4. **A1 linux 腿**:deb 组装 + AppDir/AppRun + appimagetool 探测下载 + AppImage
5. **A2 更新器 v1**:sys 纯逻辑(比较/校验 wbtest)→ 平台替换桩 → relaunch → `update_dialog` + 脚手架接线
6. **A2 mng publish + CI**:release-app.yml + 清单生成 + draft
7. **A3 最小登记面**:desktop entry / plist 基础键随各腿落(实际并进 2-4 各腿,独立项只做深链 schema 占位与文档)

## 八、真机验收清单(归用户,不远程驱动)

- mac:DMG 打开拖装 → 运行(首次 Gatekeeper 右键放行,ad-hoc 已知)→ 卸载;更新流程:装 1.0 → 发 1.1 draft → 应用内检查 → 下载/替换/relaunch → 版本读数变 1.1、`.old` 清理
- win:setup 安装(per-user,应用与功能可卸载)→ SmartScreen 提示(无签已知)→ 更新:exe rename swap + relaunch + `.old` 清理
- linux:deb 装/卸(dpkg)、desktop entry 出菜单;AppImage 双击可跑(FUSE 缺环境提示 extract-and-run)、自更新替换
- 通用:断网/清单 404/校验不符三种失败路径的 UI 诚实报错

## 九、风险与坑预警

- **NSIS 下载源稳定性**:SourceForge 直链常变——钉 GitHub mirror + sha256,失败打印手动指引(同 vendor 双镜像套路)。
- **mac 更新替换的 quarantine**:curl 下载不带 com.apple.quarantine(browser 才打),解压后签名属性应保持——真机验「更新后直接能开」,不通则补 `xattr -dr`。
- **win rename swap 时序**:`.old` 清理放新进程启动早期;崩溃残留 `.old`/`.new` 启动时全清。
- **AppImage FUSE**:无 FUSE 环境(部分 Wayland 容器/CI)用 `--appimage-extract-and-run`,AppRun 自写不受影响。
- **更新进度轮询**:curl 后台下载 + fsx stat 轮询是 v1 简化,大文件(>100MB)体验一般——v2 换分段或回调。
- **shasum 平台名**:mac `shasum -a 256`、linux `sha256sum`、win `certutil -hashfile … SHA256`——三臂都要接,wbtest 只测纯函数段。
