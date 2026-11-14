# 平台适配·发行版

收发行版层面的实测坑与自救：deepin 20 构建链实测、Ubuntu 24.04 主链路依赖、其他发行版移植起点。

## 构建链·deepin 20 实测与自救

- **moon 执行 `.py` prebuild 不看 shebang，按 PATH 里 `python` → `python3` 取第一个，`python` 还是 2.7 的机器整条 native 链起手红**：现象是 `File "scripts/prebuild.py", line 2` + `SyntaxError: Non-ASCII character '\xe7' ... but no encoding declared (pep-0263)`，紧跟 `Failed to run prebuild script for module NoahLiu/native-gui-experiment`——报错处是脚本开头的中文文档串，Python 2 无编码声明即拒读文件。机理：`crates/moon/src/rr_build/prebuild.rs` 的 `run_script_cmd` 对 `.py` 用 `BINARIES.python = optional_executable(&["python", "python3"], "MOON_PYTHON_OVERRIDE")`（`crates/moonutil/src/binaries.rs:196`），**候选顺序 `python` 在前，shebang 完全不参与**；deepin 20 的 `/usr/bin/python` 是 2.7.16，于是每个 prebuild 脚本都交给 2.7 跑。三条口径：①本仓五个 prebuild 脚本全按 Py3 写——f-string、`subprocess.run(capture_output=)`、`Path`——补 `# -*- coding: utf-8 -*-` 救不回来：过了读文件这一关还会在 `print(..., file=sys.stderr)` 上炸；②`moon check` **不跑** prebuild——判据 `run_prebuild = cx.action != RunMode::Check && backend.is_native()`，且 wasm 目标也跳过，所以「check 全绿、build 起手红」就是这条链的指纹；③moon 对**整个模块图**里带 prebuild 的模块逐个跑——`prebuild.rs:63` 遍历 `all_modules_and_id()`、任一失败即整体失败——故在 `examples/hello` 里 `moon run .` 也会炸在 experiment 的脚本上，删探针模块治不了，gui 自己那份同样 Py3-only。用户侧两条修法：`MOON_PYTHON_OVERRIDE=python3`——本机 moon 0.1.20261023 实测该变量真被读：指到不存在的路径即报 `failed to spawn ... No such file or directory`；或把 `~/.local/bin/python` 软链到 python3——注意 Debian 系只在**登录时**由 `~/.profile` 把该目录前置进 PATH，目录当时不存在就不进，桌面起的终端也不重读 `.profile`，建完必须重开终端并用 `command -v python` 复核。仓库侧根治的引导壳记在 TODO。
  - 时间：2026-10-28
  - 来源：deepin 20 报障
  - 取证：机理取证于 moon 源码
- **换到 python3 后接着炸在 3.8+ 专属参数：prebuild 脚本口径定为 ≥3.7**：`MOON_PYTHON_OVERRIDE=python3` 生效后，`gui/scripts/prebuild.py:96` 报 `TypeError: unlink() got an unexpected keyword argument 'missing_ok'`——`Path.unlink(missing_ok=)` 是 3.8 才加的，deepin 20 的 python3 是 3.7.3。修法：四处——`gui/scripts/prebuild.py` 两支、`modules/gui-webview/prebuild.py` 两支——改 `if lib.exists(): lib.unlink()`，语义等价：这几处只是「建归档前清掉旧档」，不在并发路径上。**口径**：五个 prebuild 脚本只用 3.7 就有的面——f-string、`subprocess.run(capture_output=)`、`Path`——不用海象、`missing_ok`、`dirs_exist_ok`、`removeprefix` 一类 3.8+ 参数；低版本发行版——Debian 10 基线——能直接构建是这条口径的存在理由，对外写进 `docs/zh/build.md` §2「低版本发行版」与 §6 表。复查手段：`grep -rnE "missing_ok|dirs_exist_ok|:=|removeprefix|removesuffix|Literal|cached_property|math\.prod|importlib\.resources|is_relative_to|functools\.cache\b" --include="*.py" gui experiment modules scripts tools`，加 `python3 -m py_compile` 一遍。mac 侧回归：touch 三支桩强制重编——走 `exists()+unlink()` 那条——58 任务全链通过、无 `stub:` 报错；**3.7.3 上的 prebuild 链已在 deepin 20 实测跑通**——workspace 模式一路走到编译阶段，五个 prebuild 全过。复查补记，2026-11-07：本条定案之后新写的 `modules/gui-gpu/prebuild.py` 又带入三处 `missing_ok=True`，deepin 20 复现同款 `TypeError`——已改 `rm_quiet()`，先判存在再删；**每次新增 prebuild 脚本都必须过上面那条 grep 复查**，不能只修当时现存的那几份。
  - 时间：2026-10-28，deepin 20 同批实测
- **workspace 成员连坐：`examples/hello` 会被不相干成员的 prebuild 挡住，绕法是 `MOON_WORK=off`**：承上条——moon 对模块图里每个带 prebuild 的模块逐个跑脚本，而 workspace 成员全在图里，于是同一句 `cd examples/hello && moon run .` 依次撞上 ① experiment 的脚本——Py2 读不了；② `ffmpeg-mbt` 缺 `libav*-dev` 的 `return 1` 硬失败——Windows / macOS 分支降级为空 link_configs，Linux 独硬；③ `gui-media` 起手去 GitHub 拉 4 MB 的 `miniaudio.h`。绕法 `MOON_WORK=off`——`MOON_NO_WORKSPACE` 已弃用且会打警告；`MOON_WORK=<路径>` 可钉定 workspace 文件——本机实测 `cd examples/hello && MOON_WORK=off moon build --target native` 只跑 gui 的 prebuild、57 任务链成。**代价要说清**：这一跑吃的是注册表里已发布的 `NoahLiu/native-gui@0.2.0`，不是工作区里的改动——改库自测仍须留在 workspace，那就得把开发包装全，含媒体那五个 `-dev`。对外写进 `docs/zh/build.md` §4「两种跑法」与 §6 表、README 快速开始。
  - 时间：2026-10-28
  - 取证：deepin 20 连续三轮实测；开关语义取证于 moon 源码 `crates/moonutil/src/dirs.rs`
- **deepin 20 走到编译最后一层：地板在 MoonBit 工具链自带的 runtime C 源，本库侧已无阻塞**：prebuild 链降到 3.7 口径后，同一句 `cd examples/hello && moon run .` 依次露出两处环境缺项。① `cc: error trying to exec 'cc1plus'`——`gui/text/moon.pkg` 的 native-stub 带 `dwrite_text.cpp`，**三平台都要编**——非 Windows 编成空 TU 防与归档双定义——故 C++ 编译器是硬前置，`build-essential` 没真把 g++ 带上就报这条；② `~/.moon/lib/runtime/process.c:127` 与 `thread_pool.c:1529` 报 `'SYS_pidfd_open' undeclared`——MoonBit native runtime 的 C 源要较新内核头 / glibc 才有的 syscall 常量，Debian 10 基线没有，**属工具链地板不在本库**——此时本库的桩与五个 prebuild 全已过。判据口径：报错文件在 `~/.moon/lib/runtime/` 下一律先怀疑发行版太老，别翻库代码。兜底——未实测、且是补工具链不是补库：`MOON_CC` 包一层给编译器补 `-DSYS_pidfd_open=434`，x86_64 号。同轮两条正面读数：镜像竞速真起作用——GitHub 那路 60 秒预算内无产出，Gitee 路取到 `miniaudio.h` 且 sha256 校验通过；`webkit2gtk-4.1` 在 Debian 10 只有 4.0，按设计退占位实现——探测报不可用——不挡构建。对外写进 `docs/zh/build.md` §2「低版本发行版」与 §6 表、README 平台表。
  - 时间：2026-10-28 实测
  - **同轮后续读数：`linux-libc-dev` 已是该机最新——5.18.17-amd64-desktop-hwe，「内核头太老」的初判被证伪**：`SYS_*` 宏不随内核头走，它由 glibc 构建期生成的 syscall 表提供——该机 glibc 2.28，对着 4.18 时代的头生成——所以 `__NR_pidfd_open` 在 5.18 头里有、`SYS_pidfd_open` 却没有，**升内核头补不上**；正解在上游——改用 `__NR_pidfd_open`，或 `#ifdef` 兜底。推断，未在该机 grep 取证。**支持决定**：deepin 20 移出支持目标——判据不是份额——本包注册表 downloads=6、仓库 4 star / 0 issue，百分比在这个样本量上没有意义——而是「墙在工具链、库侧已无待做」，按人数算受影响者当前只有报障者本人；README 平台表标 ❌、roadmap 摘出「规划测试发行版」，坑与自救留在 `docs/zh/build.md` §2/§6 与 README 行内。库侧两条低成本资产保留：prebuild 的 **Python 3.7 口径**与 **g++ 硬前置**——对 CentOS 7 / Debian 10 上 glibc 较新的机器仍有效。
    - 时间：2026-10-28
- **`MOON_WORK=off` 吃的是发布归档，prebuild 脚本也在其中：仓库修好的脚本要重新发包才到消费方**：同一台机器同一句命令，workspace 模式——默认——走本地工作区，五个 prebuild 全过、进到编译；加 `MOON_WORK=off` 后解析注册表 `NoahLiu/native-gui@0.2.0`，同一处 `TypeError: unlink() got an unexpected keyword argument 'missing_ok'` 又回来了——报错的 `scripts/prebuild.py` 是 `.mooncakes` 里 0.2.0 归档那份，改仓库不动注册表。与「已发布包迁不动」同一条规律，见上文 mooncakes 构建器条：**prebuild 脚本随包发布，属对外 API 面的一部分，改了就是一次版本发布**，不能指望消费方拉 master。判据：报错路径里的模块带 `@<版本>` 且写着 `(local ...)` 之外，先看是不是 `.mooncakes` 下的归档。取证，本机实测：`cd examples/hello && MOON_WORK=off moon build --target native` 之后，`grep -n missing_ok examples/hello/.mooncakes/NoahLiu/native-gui/scripts/prebuild.py` 仍打出 `96:` 与 `147:` 两处——与工作区修好的那份行号一致，即 deepin 那台机器报的 `line 96` 就是这份归档。
  - 时间：2026-10-28，deepin 20 同机对照实测

### 发行版

#### Ubuntu 24.04 ✅ 主链路

- 系统依赖:`build-essential cmake pkg-config libgtk-3-dev libpango1.0-dev libfontconfig1-dev libx11-dev libwebkit2gtk-4.1-dev`。
- AppIndicator 运行库已移除,libyue 内置托盘不可用 → 用 `yue/traybus/`(纯 MoonBit SNI 直连面板)替代。
- webkit2gtk 包名 4.0 / 4.1 因发行版而异,prepare.py 以 pkg-config 探测,任一存在即可。

#### 其他发行版 ❓ 未实测

- 移植第一步:核对依赖的 pkg-config 名称,再跑 prepare.py。

