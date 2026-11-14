# 打包与自动更新实施方案·A1/A2/A3

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
| D7 | 信任模型 v1 = HTTPS + SHA256,防损坏不防源沦陷,Ed25519 进 v1.5 | 不引签名依赖拖首发;字段位已留 |
| D8 | 打包验收载体 = `examples/showcase` | 有真实资源/依赖闭包,当发布样例与文档示例 |

- AppImage: Linux 单文件免安装应用格式,双击即跑、自带依赖。
- DMG: mac 磁盘映像安装包,双击打开拖装。
- SHA256: 对文件算固定长度指纹,内容差一个字节指纹就变,用来校验下载完整。
- Ed25519: 现代数字签名算法,私钥签名、公钥验真伪。
- GITHUB_TOKEN: CI 环境自带的 GitHub 凭据变量,授权流水线自动操作发布页。
- draft release: GitHub 上未对外可见的草稿发布页,先传产物、确认后再正式发。

## 一、可复用资产·现状盘点

- `mng` 子命令分发是 main.mbt 的 if-else 链,加 `package` / `publish` 两分支;dev 已会「从 moon build Artifacts 抓可执行路径」,package 复用同一段,见 `project.mbt`。
- `mng.toml` 解析器已有,现含 `[dev]` 节,`[package]` 节同源扩。
- release-bin.yml 的 CI 内联逻辑——mac `.app` 组装、`install_name_tool` 补 rpath、adhoc 重签、win dll 随包、mac vendor dylib 随包、THIRD-PARTY-NOTICES——D5 上收目标。
  - install_name_tool: mac 自带的二进制修补命令,改写动态库搜索路径。
  - rpath: 可执行文件内记录的动态库搜索路径清单。
  - adhoc: 不挂开发者身份的最简 mac 代码签名,只证包未被改动。
- `gui/sys`:procrun、fsx、json、envx——更新器库侧地基。
  - procrun: `gui/sys` 的子进程运行封装,对外入口名 pr_run,库内起外部命令统一走它。
- 工具缓存:用户级 `~/.mng/tools/`,makensis 与 appimagetool 落这,跨项目共享;项目临时仍走 `.mng/`。
  - makensis: NSIS 的编译器,把 `.nsi` 安装脚本编成 Windows 安装器。
  - NSIS: Windows 开源安装器制作系统。
  - appimagetool: 把 AppDir 目录封成 AppImage 单文件的官方工具。

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

签名两层口径,别混:`[package.sign]` 是**代码签名证书**,做产物签名与公证,给 Gatekeeper 与 SmartScreen 看;更新清单的 Ed25519 签名,即 `signature`/`sig_alg` 字段,是**更新信任签名**,防更新源沦陷,照 D7 进 v1.5。mac 有 identity 自动加 `--options runtime`,这是公证前提;公证链 = `notarytool submit --wait` + `stapler staple`,任一步失败报错不撤已出产物。
  - Gatekeeper: macOS 对下载来源应用的安全审查机制,未签名未公证会被拦。
  - SmartScreen: Windows 对下载来源程序的信誉审查,无签名会弹警告。
  - 公证: 把产物提交 Apple 服务器扫描、通过后系统放行的流程。
  - notarytool / stapler: Apple 公证的提交与票据钉附命令,staple 把公证票据钉到 DMG 上。

- 深链/文件关联字段 schemes / file_exts 本批**只留 schema 不实现**,A3 后置批再消费——字段先不进文档站。
  - 深链: 从外部经自定义网址协议直接唤起应用,如 `myapp://open`。
- 校验:id 反域名格式、version 三段、icon 存在且为 png,错则报行号——mng CLI 双语文案同现状。

## 三、产物与制作·每平台布局与工具链

### macOS(`dmg` 腿)

- **.app**:`Contents/MacOS/<bin>` + `Contents/Resources/{icon.icns, assets…}` + `Info.plist`,plist 写 CFBundleIdentifier/Name/Executable/IconFile/ShortVersionString/LSMinimumSystemVersion 各键;dylib 随包与 `@executable_path/../../../lib` rpath 沿 release-bin 现口径;`codesign --force -` adhoc,Developer ID 经 `--sign` 留口。
  - Info.plist: mac 应用包的配置清单文件,声明身份、图标、最低系统版本等。
  - codesign: mac 自带的代码签名命令。
- **icns**:源 png → sips 批量缩放出 iconset,16…1024 全档 → `iconutil -c icns`,皆系统自带、零下载。
  - icns: mac 应用图标的容器格式。
  - iconset: 装各尺寸 PNG 的图标目录,iconutil 把它转成 icns。
  - sips / iconutil: mac 自带的图片缩放与图标容器命令。
- **DMG**:`hdiutil create -format UDZO`,卷内 `.app` + `Applications` 符号链接;自定义背景/坐标布局 v2 再说。
  - hdiutil: mac 自带的磁盘映像命令行工具,制 DMG 用它。
  - UDZO: hdiutil 的压缩 DMG 格式参数。
  - 符号链接: 指向另一路径的快捷文件,卷内放 Applications 链接即「拖进去安装」。
- **更新载体 zip**:`<id>-<ver>-darwin-aarch64.zip`,装 .app 整树。

### Windows(`setup` 腿)

- **NSIS setup**:mng 内嵌模板生成 `.nsi`——unicode true、`InstallDir $LOCALAPPDATA\Programs\<id>`,per-user 免管理员、File 递归、开始菜单快捷方式、`WriteUninstaller`、HKCU 卸载注册键使应用进「应用与功能」、静默档 `/S`。
  - per-user: 装进当前用户目录,不需要管理员权限。
  - HKCU: Windows 注册表的当前用户根键 HKEY_CURRENT_USER,per-user 安装的卸载登记记这里。
  - 注册表: Windows 的系统级配置数据库。
- **makensis**:PATH 探测 → 缺失自动下载 NSIS zip,官方 release、sha256 校验 → `~/.mng/tools/nsis/`。
- **ico**:源 png 多尺寸压成 ICO 容器**自写**——Windows Vista 起支持 ICO 内嵌 PNG 帧,容器头几十行,mngkit 侧纯函数 + wbtest。
  - ICO: Windows 图标容器格式,一个文件装多尺寸图标。
  - wbtest: 本仓白盒测试形式,直接测包内纯函数。
- **更新载体 zip**:裸 `exe + dll + 资源`。

### Linux(`deb` + `appimage` 腿)

- **deb**:目录树 `data/usr/bin/<bin>`、`usr/share/applications/<id>.desktop`、`usr/share/icons/hicolor/<n>/apps/<id>.png`、`DEBIAN/control`,依赖段留空——本库动态库均随包——外加 md5sums;`dpkg-deb --build` 打包,deb 系自带、CI ubuntu 腿已跑通。
  - deb: Debian/Ubuntu 系的软件包格式,系统包管理器可直接装卸。
  - desktop entry: Linux 桌面登记应用的入口文件,出菜单项、图标与文件关联。
  - mime: 文件类型标识字符串,系统靠它决定某类文件用哪个应用打开。
- **AppImage**:手组 AppDir,内含自写极简 shell `AppRun` 做 setup env + exec、`<id>.desktop`、`usr/bin` + `usr/lib` + 图标 → `appimagetool` 封装,AppImage runtime 内嵌;appimagetool 从 AppImageKit GitHub releases 下载、sha256 校验,无 FUSE 环境走 `--appimage-extract-and-run`。
  - AppDir: AppImage 的源目录,按约定摆好可执行文件、动态库与桌面登记文件。
  - AppRun: AppDir 的启动入口脚本,应用每次被拉起先走它。
  - AppImage runtime: 附在 AppImage 文件头部的执行器,负责挂载自身。
  - FUSE: Linux 用户态文件系统挂载机制,AppImage 双击运行依赖它。
- **更新载体**:AppImage 本体即载体,无额外产物。
- 桌面登记:desktop entry 必有 Name/Exec/Icon/Categories/Type 各键,MimeType 槽位留给 A3。

### 产物命名·全平台统一

```
<slug>-<ver>-<target>.{dmg,exe,deb,AppImage}   # 安装包
<slug>-<ver>-<target>.zip                       # mac/win 更新载体
```
target 三元组:`darwin-aarch64` / `windows-x86_64` / `linux-x86_64`,mac 只 Apple Silicon、对齐支持面。

## 四、更新协议 v1

### 清单 `update.json`·D3

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

### 库侧更新器·分层

| 层 | 位置 | 内容 |
|---|---|---|
| 纯逻辑 | `gui/sys/update.mbt` | 清单拉取走 pr_run curl、HTTPS 强制并解析;semver 三段比较为纯函数配 wbtest;下载到临时;SHA256 校验按平台走 pr_run shasum/sha256sum;替换计划生成 |
| 平台替换桩 | `gui/sys` 平台分派 | win:新文件落 `.new` → 旧 rename `.old` → `.new` 落位 → relaunch → 新进程启动清 `.old`;mac:zip 解压走 pr_run unzip → 旧 `.app` rename → 新落位 → relaunch → 启动清残留;linux:新 AppImage 落 `.new` → chmod +x → rename swap → relaunch |
| relaunch | `gui/sys` | pr_run 起自身路径不等待 + 进程退出;pr_run 无 detached 参数则实现时补 |
| UI | `gui/widget` `update_dialog` | 状态机 Idle→Checking→Available 显版本与 notes→Downloading 进度为 fsx 轮询已下字节/size、500ms 一查→Installing→Relaunch;缺省关闭/出错诚实报 |

- relaunch: 更新收尾自动重启应用自身,新进程接续运行。
- rename swap: 运行中的 Windows exe 不能直接覆盖,先改旧名让位、新文件顶上原名的替换手法。
- semver: 语义化版本号,三段 `主.次.补丁`,逐段比大小。
- 应用侧接线:`mng new` 脚手架「设置页·检查更新」按钮 + `Store` 记「下次提醒」;定时检查,间隔 24h,脚手架可选开,库不强加。
- `deb` 档检测到新版:不出自替换,出「去下载」引导打开 url——系统目录不可写。

## 五、发布流

- **CI**:新独立 workflow `release-app.yml`,与「Binaries」示例线互不干扰,tag `app-v*` 触发 → 三平台矩阵 `moon build --release --strip` → `mng package` → 上传产物 → 汇总腿 ubuntu 算 sha256/size 生成 `update.json` → `gh release create --draft`,凭 GITHUB_TOKEN。工具缓存走 `actions/cache`,存 makensis 与 appimagetool。
  - gh: GitHub 官方命令行工具,这里用它建 draft release。
- **`mng publish` 本地版**:读本机产物目录 → 生成/更新 `update.json` → 探测 `gh` 走 pr_run,有则 draft 上传,无则打印产物与清单路径 + 手动指引。双语文案。

## 六、A3 登记面分档

- **本批 v1 落**:desktop entry 全量键、Info.plist 基础键 CFBundleIdentifier/Name 等——打包必带,无额外工作。
- **后置批**:深链 schemes,注册走 plist CFBundleURLTypes / win 注册表 / mime;文件关联,扩展名→mime 映射;外加最近文档写侧 + jumplist;`mng.toml` schema 已留,唤起事件经单实例通道回投。
  - CFBundleURLTypes: Info.plist 里声明应用可处理哪些 URL 协议的键。
  - jumplist: Windows 任务栏右键菜单里应用专属的快捷项列表。
  - 单实例通道: 二次启动不另开进程、把请求转交已运行实例的机制。

## 七、执行拆项·对齐 TODO 队列·一项一提交

1. **方案定稿**,即本文档
2. **A1 mac 腿**:`mng package` 子命令骨架,含 TOML `[package]` 解析、Artifacts 抓路径、D5 上收 .app 组装,外加 icns 派生 + DMG + 更新载体 zip
3. **A1 win 腿**:.nsi 模板 + makensis 探测/自动下载 + ICO 容器自写配 wbtest + setup 产出
4. **A1 linux 腿**:deb 组装 + AppDir/AppRun + appimagetool 探测下载 + AppImage
5. **A2 更新器 v1**:sys 纯逻辑,比较/校验配 wbtest → 平台替换桩 → relaunch → `update_dialog` + 脚手架接线
6. **A2 mng publish + CI**:release-app.yml + 清单生成 + draft
7. **A3 最小登记面**:desktop entry / plist 基础键随各腿落,实际并进 2-4 各腿,独立项只做深链 schema 占位与文档

## 八、真机验收清单·归用户·不远程驱动

- mac:DMG 打开拖装 → 运行,首次 Gatekeeper 右键放行、ad-hoc 已知 → 卸载;更新流程:装 1.0 → 发 1.1 draft → 应用内检查 → 下载/替换/relaunch → 版本读数变 1.1、`.old` 清理
- win:setup 安装,per-user、应用与功能可卸载 → SmartScreen 提示,无签已知;注意本机 `mng package` 现产的 exe **没有 MOTW**,无 `Zone.Identifier` 备用数据流,本机双击不弹——要复现真实下载路径,从 Release 下载或自己给文件打 `ZoneId=3`,与 mac 的 quarantine 同理 → 更新:exe rename swap + relaunch + `.old` 清理
  - MOTW: Windows 的网络下载标记,浏览器下载的文件会带上,系统据此加强审查。
  - Zone.Identifier: MOTW 的载体,NTFS 文件上的备用数据流,记录来源网址。
  - quarantine: macOS 给下载文件打的隔离标记,首次打开弹确认。
- linux:deb 装/卸走 dpkg、desktop entry 出菜单;AppImage 双击可跑,FUSE 缺环境时提示 extract-and-run,自更新替换
  - dpkg: Debian 系的包管理命令,装 deb 用它。
- 通用:断网/清单 404/校验不符三种失败路径的 UI 诚实报错

## 九、风险与坑预警

- **NSIS 下载源稳定性**:SourceForge 直链常变——钉 GitHub mirror + sha256,失败打印手动指引,同 vendor 双镜像套路。
- **mac 更新替换的 quarantine**:curl 下载不带 com.apple.quarantine,浏览器下载才打,解压后签名属性应保持——真机验「更新后直接能开」,不通则补 `xattr -dr`。
  - xattr: mac 的扩展属性命令,`-dr` 递归清除,兜底清隔离标记用。
- **win rename swap 时序**:`.old` 清理放新进程启动早期;崩溃残留 `.old`/`.new` 启动时全清。
- **AppImage FUSE**:无 FUSE 环境,部分 Wayland 容器与 CI,用 `--appimage-extract-and-run`,AppRun 自写不受影响。
  - Wayland: Linux 新一代窗口显示协议。
- **更新进度轮询**:curl 后台下载 + fsx stat 轮询是 v1 简化,大文件超 100MB 体验一般——v2 换分段或回调。
- **shasum 平台名**:mac `shasum -a 256`、linux `sha256sum`、win `certutil -hashfile … SHA256`——三臂都要接,wbtest 只测纯函数段。
