# 应用与历史

应用查找与各类本机使用记录的只读读取。统一 `Result` 语义与支持矩阵见[系统能力总览](sys.md)。

## 应用查找

两部分：已装应用清单与应用二进制查找。Linux 扫描 XDG `.desktop` 条目（用户目录覆盖系统目录）；Windows 递归扫描开始菜单（用户级 + 全机级）的 `.lnk`，条目的 exec 为 lnk 全路径（ShellExecute 可直接启动）、categories 标 `StartMenu`；macOS 扫 `/System/Applications`、`/Applications`（各带 `Utilities` 一层）与 `~/Applications` 下的 `.app` 包，读 `Contents/Info.plist` 的公开键：`name` 取 CFBundleDisplayName → CFBundleName → 包目录名，`id` 取 CFBundleIdentifier（缺则包名），`exec` 是 `Contents/MacOS/<CFBundleExecutable>`，`icon` 是 `Contents/Resources/<CFBundleIconFile>`（无扩展名补 `.icns`，无该键给空串）；二进制 plist 或读不到的包按包名给条目，不从清单里消失。macOS 侧两个字段是空的：`categories`（没有 desktop Categories 的对等物）与本地化名（在 `.lproj` 里，公开 plist 键给不到，`locale_name` 与 `name` 同值）。

| 函数 | 说明 |
|---|---|
| `appfind_installed() -> Result[Array[AppEntry], AppFindError]` | 已装应用清单；全部扫描目录都不存在给 `NoScanDir` |
| `appfind_installed_with(list_dir) -> Result[Array[AppEntry], AppFindError]` | 同上，目录枚举由调用方注入（供无 fsx 层的调用方与测试；仅 Linux 分支） |
| `appfind_executable(name) -> Result[String, AppFindError]` | Linux 在 `~/.local/bin`、`/usr/local/bin`、`/usr/bin`、`/bin`、`/usr/sbin`、`/sbin` 按序找；Windows 按 `PATH` 各目录找 name / name.exe；macOS 先按 `PATH` 各段（`:` 分隔，取绝对路径）再补 `~/.local/bin`、`/usr/local/bin`、`/opt/homebrew/{bin,sbin}`、`/usr/bin`、`/bin`、`/usr/sbin`、`/sbin`；找不到给 `NotFound` |

`AppEntry{ id, name, locale_name, exec, icon, categories }`：id 为 desktop id（.desktop 文件名去扩展名），name 为显示名，locale_name 为本地化名（`Name[zh_CN]` 优先回退 Name），exec / icon 原样，categories 按分号拆分。结果按 desktop id 去重（用户目录覆盖系统目录）、按 name 排序；Type 非 Application、NoDisplay=true、缺 Name 的条目已滤除。

```moonbit
// 已装清单:注入目录列举函数(如自有的 readdir 封装)
match @sys.appfind_installed_with(fn(dir) { my_list_dir(dir) }) {
  Ok(apps) => for a in apps {
      println("\{a.locale_name}  \{a.exec}")
    }
  Err(e) => println("不可用：\{e}")
}
// 二进制查找
match @sys.appfind_executable("code") {
  Ok(path) => println("code 位于 \{path}")
  Err(@sys.AppFindError::NotFound(_)) => println("未安装")
  Err(_) => println("平台不支持")
}
```

## VS Code 本地历史与最近工作区

读取本机 VS Code 用户数据：文件的本地历史快照列表（`User/History`）与最近工作区。三平台路径均已实现，各按其用户数据目录定位。

| 函数 | 说明 |
|---|---|
| `vsc_supported() -> Bool` | 本机是否具备可读的 VS Code 用户数据 |
| `vsc_local_history(file_path) -> Result[Array[VscHistoryEntry], VscodeError]` | 某文件的历史快照（时间倒序）；传绝对路径或 `file://` URI 均可，无历史记录返回空数组 |
| `vsc_recent() -> Result[Array[String], VscodeError]` | 最近打开的工作区 / 文件夹路径（最近活动的在最前）；无窗口状态返回空数组 |

`VscHistoryEntry{ path, timestamp }`：path 为快照文件绝对路径，即该时刻文件全文；timestamp 为 Unix 毫秒，`timestamp_seconds()` 换算秒。错误 `VscodeError`：`Unsupported`（无法定位用户数据目录）/ `StorageUnavailable`（VS Code 从未在本机运行过）/ `StorageCorrupted(String)` / `HistoryCorrupted(String)`。

```moonbit
match @sys.vsc_local_history("/home/me/proj/src/main.mbt") {
  Ok(snaps) => for s in snaps {
      println("\{s.timestamp_seconds()}  \{s.path}")
    }
  Err(e) => println("不可用：\{e}")
}
match @sys.vsc_recent() {
  Ok(paths) => if paths.length() > 0 {
      println("最近工作区：\{paths[0]}")
    }
  Err(e) => println("不可用：\{e}")
}
```

## 浏览器历史与下载记录

只读读取 Chrome / Chromium / Edge / Brave 的 History 库；自动探测全部 profile（Default 与 Profile 1..24）。仅实现 Linux 路径探测，其余平台 `BhUnsupported`。

| 函数 | 说明 |
|---|---|
| `bh_supported() -> Bool` | 当前平台是否支持 |
| `bh_browsers() -> Result[Array[BrowserProfile], BrowserHistoryError]` | 列出有可读 History 库的 profile；无可读库给 `BhNoBrowser` |
| `bh_history(limit? = 200) -> Result[Array[HistoryItem], BrowserHistoryError]` | 浏览历史（聚合全部 profile，按最近访问时间降序，hidden 重定向条目已滤除）；limit ≤ 0 取全部 |
| `bh_downloads(limit? = 50) -> Result[Array[DownloadItem], BrowserHistoryError]` | 下载记录（按开始时间降序） |
| `bh_search(keyword, limit? = 50) -> Result[Array[HistoryItem], BrowserHistoryError]` | url 或 title 子串搜索（ASCII 大小写不敏感）；keyword 为空匹配一切 |
| `bh_download_state_name(state) -> String` | 下载状态数值 → 名称（进行中 / 完成 / 已取消 / 中断） |

`BrowserProfile{ browser, profile, history_path }`：browser 为 google-chrome / chromium / microsoft-edge / brave，profile 为目录名（Default 或 Profile N）。`HistoryItem{ url, title, visit_count, last_visit_time }`（时间为 Unix 毫秒，未知为 0）；`DownloadItem{ target_path, received_bytes, total_bytes, start_time, end_time, state }`。错误 `BrowserHistoryError`：`BhUnsupported` / `BhNoConfigDir` / `BhNoBrowser` / `BhIoFailed(String)`（单 profile 读失败跳过，全部失败才报错）。

```moonbit
match @sys.bh_history(limit=6) {
  Ok(items) => for it in items {
      let title = if it.title == "" { "(无标题)" } else { it.title }
      println("[\{it.visit_count}次] \{title}\n  \{it.url}")
    }
  Err(e) => println("不可用：\{e}")
}
match @sys.bh_downloads(limit=3) {
  Ok(ds) => for d in ds {
      println("\{d.target_path}  \{@sys.bh_download_state_name(d.state)}")
    }
  Err(_) => ()
}
let _ = @sys.bh_search("moonbit", limit=10)
```

## 浏览器书签（Chrome 系）

只读解析 Chrome / Chromium / Edge / Brave 的 `Bookmarks` JSON 文件。JSON 解析复用同包手写解析器——Chrome 的 date_added 等以数值字符串存储，整数字段保持 Int64 精度，微秒值换算为 Unix 毫秒；自动探测全部 profile（Default 与 Profile 1..24）。

| 函数 | 说明 |
|---|---|
| `bm_supported() -> Bool` | Linux（仅实现 Linux 路径探测） |
| `bm_browsers() -> Result[Array[BookmarkProfile], BookmarkError]` | 列出有可读 Bookmarks 文件的 profile |
| `bm_bookmarks(browser) -> Result[BookmarkNode, BookmarkError]` | 指定浏览器的首个可读书签树（浏览器标识取 "google-chrome"/"chromium"/"microsoft-edge"/"brave"，profile 取 Default 优先、其次 Profile 1..24） |

`BookmarkProfile{ browser, profile, bookmarks_path }`；`BookmarkNode{ name, url?, children, added, root }`（added 为 Unix 毫秒，root 标注所属根 bookmark_bar / other / synced）。返回虚拟根树（名称 `"<浏览器>/<profile>"`，children 为三根合并），`BookmarkNode::is_folder()` / `is_url()` 分类，`bm_flatten(node)` 给先序扁平 url 书签列表。错误 `BookmarkError`：`BmUnsupported` / `BmNoConfigDir` / `BmNoBrowser` / `BmIoFailed(String)`。

```moonbit
match @sys.bm_bookmarks("google-chrome") {
  Ok(root) =>
    for n in @sys.bm_flatten(root) {
      println("\{n.name}  →  \{n.url}")
    }
  Err(e) => println("读不到：\{e}")
}
```

## Firefox 浏览历史

读取 `~/.mozilla/firefox/` 下各 profile 的 `places.sqlite`（`moz_places` 表）。条目复用 `browser_history.mbt` 的 `HistoryItem`，时间按 Unix 纪元微秒 → 毫秒换算；排序 / 截断 / 取列复用同文件导出的纯函数。

| 函数 | 说明 |
|---|---|
| `ffx_supported() -> Bool` | profiles.ini 定位已实现 Linux / macOS / Windows |
| `ffx_profiles() -> Result[Array[FirefoxProfile], FirefoxHistoryError]` | 列出有可读 places.sqlite 的 profile |
| `ffx_history(limit? = 200) -> Result[Array[HistoryItem], FirefoxHistoryError]` | 浏览历史（聚合全部已探测 profile，按最近访问时间降序）；limit ≤ 0 取全部 |

`FirefoxProfile{ profile, places_path }`（profile 为 profiles.ini 的 `Path=` 目录名，绝对路径取末段）。hidden 条目已滤除；单 profile 读失败跳过，全部失败给 `FfxIoFailed`。错误 `FirefoxHistoryError`：`FfxUnsupported` / `FfxNoProfile`（未安装或从未启动 Firefox）/ `FfxIoFailed(String)`。profiles.ini 缺失时回退固定候选名（default / default-release / default-esr / default-nightly / dev-edition-default），随机前缀命名的 profile 目录收不到。

```moonbit
match @sys.ffx_history(limit=10) {
  Ok(items) => for it in items { println("\{it.title}  \{it.url}") }
  Err(e) => println("读不到：\{e}")
}
```

## 最近文件（GTK recently-used.xbel）

解析 freedesktop 的 `recently-used.xbel`——GTK 应用经 `GtkRecentManager` / xdg-desktop-portal-gtk 写入此清单，Thunar / Nautilus / GIO 打开文件均追加其中。文件位置 `$XDG_DATA_HOME/recently-used.xbel`（缺省 `$HOME/.local/share/`）。XML 解析为手写薄扫描器：只取 bookmark 节点与 `bookmark:application` / `mime:mime-type` 子节点属性，属性值做 XML 实体解码，href 的 `file://` URI 做百分号解码；时间戳 ISO 8601 → Unix 毫秒。

| 函数 | 说明 |
|---|---|
| `rf_supported() -> Bool` | Linux 且文件可读 |
| `rf_recent(limit? = 100) -> Result[Array[RecentItem], RecentError]` | 最近文件列表（modified 倒序，并列按 path 升序）；limit ≤ 0 取全部 |
| `rf_by_app(name, limit? = 100) -> Result[Array[RecentItem], RecentError]` | 按应用名过滤（`bookmark:application` 的 name 精确匹配），同样倒序 |

`RecentItem{ uri, path, mime, added, modified, app_count }`：path 为 href 去 `file://` 前缀并百分号解码后的本地路径（非 file:// 方案给空串）、mime 为 MIME 类型（无此节点给 None）、added / modified 为 Unix 毫秒（缺失或非法为 0）、app_count 为记录过该文件的应用个数。错误 `RecentError`：`RfUnsupported` / `RfNoDataDir` / `RfNoFile` / `RfParseFailed(String)`。解码与换算纯函数：`rf_xml_unescape` / `rf_percent_decode` / `rf_uri_to_path` / `rf_iso_to_unix_ms` / `rf_sort_recent`。

```moonbit
match @sys.rf_recent(limit=8) {
  Ok(items) => for it in items { println("\{it.path}  (\{it.modified})") }
  Err(e) => println("读不到：\{e}")
}
```
