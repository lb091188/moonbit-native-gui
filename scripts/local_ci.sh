#!/usr/bin/env bash
# 本地三平台门禁:mac 本机 + company Linux 容器 + company win10 VM
#
# 用法:bash scripts/local_ci.sh [mac|linux|win|sync|all]
#   sync  同步工作树到两个远端(company Linux 容器挂载点 + win10 C:\natigui\repo)
#   mac   本机腿:check 零警告 + 测试全名单 + tools + webview + 构建 + 桩语法门禁 + 文档站
#   linux company 容器腿:CI linux job 同款(check/test/build/xvfb 冒烟)
#   win   company win10 VM 腿:CI windows job 同款(check/test/build --release)
#   all   sync + mac + linux + win(默认)
#
# 环境前提(一次性搭好):
#   ssh company / ssh win10 免密可达(win10 走 ProxyJump company,见 ~/.ssh/config)
#   company 容器 natigui-linux 就绪(重建脚本:company:~/natigui/setup-container.sh)
#   win10 已装 moon + VS Build Tools 2022(仓库 C:\natigui\repo)
#   ffmpeg 媒体包测试三腿均未纳入(win 腿缺 BtbN dll,linux 腿容器已含开发包可后补)
set -u
cd "$(dirname "$0")/.."
ROOT="$PWD"

COMPANY_HOST="${NATIGUI_COMPANY:-company}"
WIN_HOST="${NATIGUI_WIN10:-win10}"
CONTAINER="${NATIGUI_CONTAINER:-natigui-linux}"

GUI_TEST_PKGS="base shell widget ui render text theme icons sys input win dbus wayland chart mdview style router uitest mngdev inspector"
WIN_TEST_PKGS="base shell widget ui render text theme icons input win chart mdview style router uitest mngdev"

PASS=(); FAIL=()
note() { printf '\n\033[36m==> %s\033[0m\n' "$*"; }
ok()   { PASS+=("$1"); printf '\033[32m[PASS]\033[0m %s\n' "$1"; }
bad()  { FAIL+=("$1"); printf '\033[31m[FAIL]\033[0m %s\n' "$1"; }

# 零警告断言:moon check 输出带 "(N warnings" 即警告非零
check_zero_warn() { # $1=日志文件
  if grep -qE '[1-9][0-9]* warnings' "$1"; then
    grep -E 'Warning' "$1" | head -5
    return 1
  fi
  return 0
}

# ---------------------------------------------------------------- sync
do_sync() {
  note "sync:同步工作树到远端"
  rsync -a --delete \
    --exclude='_build' --exclude='.mooncakes' --exclude='.git' \
    --exclude='node_modules' --exclude='target' --exclude='._*' \
    "$ROOT/" "$COMPANY_HOST:natigui/repo/" >/dev/null \
    && ok "sync:company Linux 挂载点" || bad "sync:company Linux 挂载点"

  # win10 无 rsync:tar 增量覆盖 + 删除项清单兜底 + 屏蔽 mac AppleDouble 伴生文件
  local tgz=/tmp/natigui-sync.tgz
  COPYFILE_DISABLE=1 tar czf "$tgz" \
    --exclude='_build' --exclude='.mooncakes' --exclude='.git' \
    --exclude='node_modules' --exclude='target' --exclude='._*' \
    . 2>/dev/null
  rsync -ain --delete \
    --exclude='_build' --exclude='.mooncakes' --exclude='.git' \
    --exclude='node_modules' --exclude='target' --exclude='._*' \
    "$ROOT/" "$COMPANY_HOST:natigui/repo/" 2>/dev/null \
    | grep '^deleting ' | sed 's/^deleting //' > /tmp/natigui-deleted.txt || true
  scp -q "$tgz" "$WIN_HOST:C:/natigui/sync.tgz" \
    && ssh -o BatchMode=yes "$WIN_HOST" \
      "tar -xzf C:/natigui/sync.tgz -C C:/natigui/repo; Remove-Item C:/natigui/sync.tgz -ErrorAction SilentlyContinue" \
    && ok "sync:win10 仓库" || bad "sync:win10 仓库"
  if [ -s /tmp/natigui-deleted.txt ]; then
    while IFS= read -r f; do
      case "$f" in */|'') continue ;; esac
      ssh -o BatchMode=yes "$WIN_HOST" "powershell -NoProfile -Command \"Remove-Item -Force -Recurse 'C:/natigui/repo/$f' -ErrorAction SilentlyContinue\"" || true
    done < /tmp/natigui-deleted.txt
    ok "sync:win10 删除项对齐($(wc -l < /tmp/natigui-deleted.txt | tr -d ' ')项)"
  fi
}

# ---------------------------------------------------------------- mac 腿
do_mac() {
  note "mac 腿"
  ( cd "$ROOT/gui" && moon check ) > /tmp/lc-mac-check.log 2>&1 \
    && check_zero_warn /tmp/lc-mac-check.log \
    && ok "mac:gui moon check 零警告" || bad "mac:gui moon check 零警告"

  ( cd "$ROOT/gui" && moon test $GUI_TEST_PKGS ) > /tmp/lc-mac-test.log 2>&1 \
    && ok "mac:gui 测试全名单" || { bad "mac:gui 测试全名单"; tail -5 /tmp/lc-mac-test.log; }

  ( cd "$ROOT/tools/native-gui-tools" && moon check \
    && moon test mng mngkit proc inst ) > /tmp/lc-mac-tools.log 2>&1 \
    && ok "mac:tools check+test" || { bad "mac:tools check+test"; tail -5 /tmp/lc-mac-tools.log; }

  ( cd "$ROOT/modules/gui-webview" && moon test webview ) > /tmp/lc-mac-wv.log 2>&1 \
    && ok "mac:gui-webview 测试" || bad "mac:gui-webview 测试"

  ( cd "$ROOT/gui" && moon build base shell widget ui render text theme icons sys input win chart mdview style router --target native \
    && cd "$ROOT" && moon build examples/hello examples/audio examples/video --target native ) \
    > /tmp/lc-mac-build.log 2>&1 \
    && ok "mac:库构建 + 示例链接" || { bad "mac:库构建 + 示例链接"; tail -5 /tmp/lc-mac-build.log; }

  # 桩语法门禁(照 ci.yml macOS 腿 gate 函数:同串 clang 旗标改 -fsyntax-only)
  ( cd "$ROOT/gui"
    xcrun clang -fsyntax-only -O2 -x objective-c -fobjc-arc -DWM_STUB_MAC win/stub.c \
    && xcrun clang -fsyntax-only -O2 -x objective-c -fobjc-arc -DWM_STUB_MAC render/stub.c \
    && xcrun clang -fsyntax-only -O2 -x objective-c -fobjc-arc -DWM_STUB_MAC text/stub.c \
    && xcrun clang -fsyntax-only -O2 -x objective-c -fobjc-arc -DWB_HAVE_WKWEBVIEW ../modules/gui-webview/webview/webkit_stub.c \
    && xcrun clang -fsyntax-only -O2 -x c sys/sys_stub.c \
    && xcrun clang -fsyntax-only -O2 -x c inspector/stub.c ) \
    > /tmp/lc-mac-stub.log 2>&1 \
    && ok "mac:六桩语法门禁" || { bad "mac:六桩语法门禁"; tail -8 /tmp/lc-mac-stub.log; }

  if [ "${NATIGUI_SKIP_DOCS:-0}" != "1" ]; then
    ( cd "$ROOT/docs" && npm run build --silent ) > /tmp/lc-mac-docs.log 2>&1 \
      && ( cd "$ROOT" && node tools/check-docs-index.mjs ) >> /tmp/lc-mac-docs.log 2>&1 \
      && ok "mac:文档站构建 + 索引守卫" || { bad "mac:文档站构建 + 索引守卫"; tail -5 /tmp/lc-mac-docs.log; }
  fi
}

# ---------------------------------------------------------------- linux 腿
do_linux() {
  note "linux 腿(company 容器 $CONTAINER)"
  # 整条远程命令用单引号包成 bash -c 的单个参数;SSH 会在远端 shell 重拼参数,
  # 不用变量封装 ssh 命令(那样 bash -c 后的命令会碎成 $0 + 宿主机执行的 && 段)。

  ssh -o BatchMode=yes "$COMPANY_HOST" "docker exec $CONTAINER bash -c 'cd /work/repo/gui && moon check'" \
    > /tmp/lc-linux-check.log 2>&1 \
    && check_zero_warn /tmp/lc-linux-check.log \
    && ok "linux:gui moon check 零警告" || bad "linux:gui moon check 零警告"

  ssh -o BatchMode=yes "$COMPANY_HOST" "docker exec $CONTAINER bash -c 'cd /work/repo/gui && dbus-run-session -- moon test $GUI_TEST_PKGS'" \
    > /tmp/lc-linux-test.log 2>&1 \
    && ok "linux:gui 测试全名单(dbus 会话)" || { bad "linux:gui 测试全名单(dbus 会话)"; tail -8 /tmp/lc-linux-test.log; }

  ssh -o BatchMode=yes "$COMPANY_HOST" "docker exec $CONTAINER bash -c 'cd /work/repo/gui && moon build --target native && cd /work/repo && moon build examples/hello --target native'" \
    > /tmp/lc-linux-build.log 2>&1 \
    && ok "linux:库构建 + hello 链接" || { bad "linux:库构建 + hello 链接"; tail -8 /tmp/lc-linux-build.log; }

  ssh -o BatchMode=yes "$COMPANY_HOST" "docker exec $CONTAINER bash -c 'cd /work/repo && MNG_WGPU_LIB=off timeout 20s xvfb-run -a moon run examples/hello >/dev/null 2>&1; code=\$?; exit \$(( code == 124 ? 0 : 1 ))'" \
    > /tmp/lc-linux-smoke.log 2>&1 \
    && ok "linux:xvfb 冒烟(存活 20s)" || bad "linux:xvfb 冒烟(存活 20s)"
}

# ---------------------------------------------------------------- win 腿
do_win() {
  note "win 腿(company win10 VM)"
  # VM 没开就先开(跑完不自动关,频繁开关更伤)
  ssh -o BatchMode=yes "$COMPANY_HOST" \
    "virsh --connect qemu:///system domstate win10 | grep -q running || virsh --connect qemu:///system start win10 >/dev/null" \
    || { bad "win:VM 启动"; return; }
  sleep 8

  ssh -o BatchMode=yes "$WIN_HOST" "powershell -NoProfile -ExecutionPolicy Bypass -File C:/natigui/gate-check.ps1" \
    > /tmp/lc-win-check.log 2>&1 && grep -q "check exit: 0" /tmp/lc-win-check.log \
    && ok "win:gui moon check 零警告" || { bad "win:gui moon check 零警告"; tail -5 /tmp/lc-win-check.log; }

  ssh -o BatchMode=yes "$WIN_HOST" "powershell -NoProfile -ExecutionPolicy Bypass -File C:/natigui/gate-test.ps1" \
    > /tmp/lc-win-test.log 2>&1 && grep -q "test exit: 0" /tmp/lc-win-test.log \
    && ok "win:gui 测试(CI windows 名单)" || { bad "win:gui 测试(CI windows 名单)"; tail -8 /tmp/lc-win-test.log; }

  ssh -o BatchMode=yes "$WIN_HOST" "powershell -NoProfile -ExecutionPolicy Bypass -File C:/natigui/gate-build.ps1" \
    > /tmp/lc-win-build.log 2>&1 && grep -q "build exit: 0" /tmp/lc-win-build.log \
    && ok "win:库构建 + mng --release 链接" || { bad "win:库构建 + mng --release 链接"; tail -8 /tmp/lc-win-build.log; }
}

# ---------------------------------------------------------------- 入口
case "${1:-all}" in
  sync)  do_sync ;;
  mac)   do_mac ;;
  linux) do_linux ;;
  win)   do_win ;;
  all)   do_sync; do_mac; do_linux; do_win ;;
  *) echo "用法:bash scripts/local_ci.sh [mac|linux|win|sync|all]"; exit 2 ;;
esac

printf '\n======== 本地门禁汇总 ========\n'
for p in "${PASS[@]:-}"; do [ -n "$p" ] && printf '  PASS %s\n' "$p"; done
for f in "${FAIL[@]:-}"; do [ -n "$f" ] && printf '  FAIL %s\n' "$f"; done
[ ${#FAIL[@]} -eq 0 ] && exit 0 || exit 1
