# MoonBit native runtime 的 `SYS_pidfd_open`：向官方求证的记录

目的：native-gui 在做 Linux 发行版兼容验证，这台 deepin 20 上 `moon build --target native` 编不过工具链自带的 runtime C 源。定位到根因在上游（判据与符号不同源），本文件存证据与两条可直接粘贴的问稿（长版 / 5 行短版）。

## 已提 issue（2026-11-07）

- <https://github.com/moonbitlang/moonbit-native-runtime/issues/8>（中文，精简版：问题 / 依据 / 复现；以 moon 0.1.20261104 随发 runtime 取证，行号与 20261023 相同；同批指出 `posix_spawn_file_actions_addchdir_np` 无 glibc 护栏与 `moonbitlang/async` 同款写法）。

## 环境读数

| 项 | 值 |
|---|---|
| 发行版 | deepin 20（Debian 10 基线） |
| glibc | 2.28 |
| linux-libc-dev | 5.18.17-amd64-desktop-hwe（已是该机源里最新） |
| gcc / g++ | 8.3 |
| moon | 0.1.20261023 |
| python3 / python | 3.7.3 / 2.7.16 |

## 现象

prebuild 与本库的 C/C++ 桩全部编过，到 runtime 才红：

```
~/.moon/lib/runtime/process.c:127:23: error: 'SYS_pidfd_open' undeclared
~/.moon/lib/runtime/thread_pool.c:1529:26: error: 'SYS_pidfd_open' undeclared
warning: implicit declaration of function 'posix_spawn_file_actions_addchdir_np'
```

## 定位

两处代码形状相同（`process.c` 124-138、`thread_pool.c` 1522-1530）：

```c
#if LINUX_VERSION_CODE >= KERNEL_VERSION(5, 4, 0)   // 判据来自内核头（linux-libc-dev）
  int pidfd = syscall(SYS_pidfd_open, pid, 0);      // 符号来自 glibc 的 sys/syscall.h
```

判据与符号**不同源**：`SYS_*` 表在 glibc 构建期冻结（glibc 2.28 对着 4.18 时代的头生成，表里没有 `SYS_pidfd_open`），而这台机器内核头是 5.18，判据照样放行 → 编译失败。机器内核（5.18）实际支持 `pidfd_open`（5.3 引入），缺的只是宏名，升 `linux-libc-dev` 也补不上（已是最新）。

fallback 路径上游已存在：`thread_pool.c` 1523-1528 的注释写明 pidfd 拿不到时 `wait_pid` 退化为工作线程里阻塞 `waitpid`（实现在 1588 附近）——所以改用 `__NR_pidfd_open` 是**运行时零差别**的改名，不是关掉功能。

## 待官方确认

1. 判据与符号不同源算不算 bug。
2. 修法：改用 `__NR_pidfd_open`（随内核头同步），或判据换成 `#if defined(__NR_pidfd_open)`。
3. native 目标是否有官方系统下限（最低 glibc / 内核头），文档里没找到。
4. 临时用 `MOON_CC` 包一层补 `-DSYS_pidfd_open=434`（x86_64 号）在官方口径里是否安全。

## 为什么值得修

统信 UOS V20 与 deepin 20 同一条基线（Debian 10 / glibc 2.28），政企桌面装机量口径为百万套级，全是「老 glibc + 新内核」，撞同一条。改一个宏名的收益不止 deepin 20。

## 复现

任意 native 目标工程，在一台 glibc < 2.31 且 linux-libc-dev ≥ 5.4 的机器上 `moon build --target native`，不需要本库参与。

## 微信问稿（长版）

```
【想问一个 MoonBit native runtime 的编译问题，附定位】

我在做 MoonBit 的跨平台桌面 GUI 库 native-gui（github.com/lb091188/moonbit-native-gui，
mooncakes 上 NoahLiu/native-gui），三平台自绘窗口 + 原生 FFI，链接参数由 prebuild 托管。
现在在做 Linux 发行版兼容验证，手上这台是 deepin 20，卡在一个编译期问题上，
定位到是 runtime 自带 C 源里的，想确认是不是 bug、以及官方对系统版本的下限口径。

一、现象
在这台机器上跑任意 moon build --target native，prebuild 和本库的 C/C++ 桩都能编过，
到工具链自带的 runtime 就红：
  ~/.moon/lib/runtime/process.c:127:23: error: 'SYS_pidfd_open' undeclared
  ~/.moon/lib/runtime/thread_pool.c:1529:26: error: 'SYS_pidfd_open' undeclared
（另有一处 warning: implicit declaration of 'posix_spawn_file_actions_addchdir_np'）

二、环境读数
deepin 20（Debian 10 基线）
glibc 2.28
linux-libc-dev 5.18.17-amd64-desktop-hwe —— 已是该机源里的最新版
gcc / g++ 8.3
moon 0.1.20261023
python3 3.7.3（python 是 2.7.16，这条已自查自修，见第四点）

三、定位
两处代码形状相同（process.c 124-138、thread_pool.c 1522-1530）：

  #if LINUX_VERSION_CODE >= KERNEL_VERSION(5, 4, 0)   // 判据来自内核头 linux-libc-dev
    int pidfd = syscall(SYS_pidfd_open, pid, 0);      // 符号来自 glibc 的 sys/syscall.h

问题是这两个来源不同步：SYS_* 那张表是 glibc 构建期冻结的，glibc 2.28 对着 4.18 时代的
头生成，表里没有 SYS_pidfd_open；而这台机器内核头是 5.18，判据照样放行，于是编译失败。
也就是说这台机器的内核（5.18）实际是支持 pidfd_open 的（5.3 引入），缺的只是一个宏名，
升 linux-libc-dev 也补不上（已经是最新）。

想确认三点：
1) 这个判据与符号不同源，算不算 bug？
2) 修法上是不是把符号换成 __NR_pidfd_open（在 asm/unistd.h 里，跟内核头同源，
   与判据一致），或者把判据改成 #if defined(__NR_pidfd_open) 更稳？
   这两者运行时行为应当完全一致（同一个 syscall 号 434），不改变功能。
3) 官方对 native 目标有没有系统下限口径（最低 glibc / 内核头版本）？
   文档里我没找到，用户只能靠踩。

补充：为什么这条值得修而不只是我们本地绕——统信 UOS V20 与 deepin 20 同一条基线
（Debian 10 / glibc 2.28），政企桌面装机量口径是百万套级，这批机器都是「老 glibc + 新内核」，
会撞上同一条。改一个宏名的收益不止 deepin 20。

临时绕法我这边试的是 MOON_CC 包一层给编译器补 -DSYS_pidfd_open=434，
想确认这个做法在官方口径里安全吗，还是有推荐的姿势。

四、顺带反馈两条（都是我们这边已经自修的，供参考）
1) moon 执行 .py prebuild 时不看 shebang，按 PATH 里 python → python3 取第一个，
   这台机器 python 是 2.7，起手就报 pep-0263 SyntaxError；
   MOON_PYTHON_OVERRIDE=python3 能绕（实测有效），但默认顺序对 Py3-only 脚本不太友好。
2) 我们的 prebuild 脚本用了 Path.unlink(missing_ok=True)（3.8+ 才有的参数），
   在 3.7.3 上报 TypeError，已改成 exists()+unlink() 等价写法，
   并把「脚本必须跑在 Python 3.7」定成仓库口径。

复现方式：找一台 glibc < 2.31 且 linux-libc-dev >= 5.4 的机器（deepin 20 / UOS V20 最典型），
任意一个 native 目标工程 moon build --target native 即可，不需要本库参与。
```

## 微信问稿（5 行短版）

```
请教一个 MoonBit native runtime 的编译问题：
在 glibc 2.28 + 内核头 5.18 的机器（deepin 20 / UOS V20 基线）上，任意工程 moon build --target native 都报
  ~/.moon/lib/runtime/process.c:127 与 thread_pool.c:1529: 'SYS_pidfd_open' undeclared
定位：判据用 LINUX_VERSION_CODE>=5.4（来自内核头），符号 SYS_pidfd_open 却来自 glibc 构建期冻结的 syscall 表，两者不同源——内核其实支持 pidfd_open，缺的只是宏名，升 linux-libc-dev 也补不上；改用 __NR_pidfd_open 或 #if defined(__NR_pidfd_open) 应当运行时零差别。
想确认：这算不算 bug、能否这样修，native 目标有没有官方最低 glibc/内核头口径，以及临时用 MOON_CC 补 -DSYS_pidfd_open=434 是否安全。
```
