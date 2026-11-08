#!/usr/bin/env bash
# mng 应用侧场景（进程级）：脚手架 → 构建 → dev 热更/重启编排 → 生产构建。
#
# 断言的是「真进程跑起来之后发生什么」——单元用例（mngkit / mng / mngdev）
# 覆盖纯函数与产物，覆盖不到 watch 循环、单实例通道、重启与回页。
#
# 需要：moon 在 PATH；有显示服务（Linux CI 用 xvfb-run 包一层，mac 直接跑）。
# 用法：scripts/mng_scenario.sh [--keep]     （--keep 保留临时工程便于排查）
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1

APP_NAME="mng_scenario_demo"
APP_DIR="$ROOT/$APP_NAME"
WORK="$ROOT/.mng-scenario"
DEV_LOG="$WORK/dev.log"
KEEP=0
[ "${1:-}" = "--keep" ] && KEEP=1

PASS=0
FAIL=0
ok() { echo "  OK   $*"; PASS=$((PASS + 1)); }
bad() { echo "  FAIL $*"; FAIL=$((FAIL + 1)); }

cleanup() {
  if [ -n "${DEV_PID:-}" ] && kill -0 "$DEV_PID" 2>/dev/null; then
    kill -TERM "$DEV_PID" 2>/dev/null || true
    for _ in 1 2 3 4 5 6 7 8 9 10; do
      kill -0 "$DEV_PID" 2>/dev/null || break
      sleep 0.3
    done
    kill -9 "$DEV_PID" 2>/dev/null || true
  fi
  if [ "$KEEP" = "0" ]; then
    # 先还原 moon.work 再删现场：备份就在 $WORK 里，删早了没得还原
    restore_workfile
    rm -rf "$APP_DIR" "$WORK" 2>/dev/null
    # 某些环境把 rm 劫持成「移入回收站」，失败会留下现场——用 python 兜一手
    if [ -d "$APP_DIR" ] || [ -d "$WORK" ]; then
      [ -n "$PY" ] && "$PY" -c 'import shutil,sys
for d in sys.argv[1:]:
    shutil.rmtree(d, ignore_errors=True)' "$APP_DIR" "$WORK"
    fi
  else
    echo "  保留现场：$APP_DIR（moon.work 未还原）"
  fi
}
trap cleanup EXIT

PY=""
for c in python3 python; do
  command -v "$c" >/dev/null 2>&1 && { PY="$c"; break; }
done

restore_workfile() {
  if [ -f "$WORK/moon.work.bak" ]; then
    cp "$WORK/moon.work.bak" "$ROOT/moon.work"
  fi
}

# 脚手架生成的模块要进 workspace，否则按注册表版本解析（仓外腿，线上还没有 mngdev）
add_to_workfile() {
  [ -n "$PY" ] || { bad "没有 python，改不了 moon.work"; return 1; }
  cp "$ROOT/moon.work" "$WORK/moon.work.bak"
  "$PY" - "$ROOT/moon.work" "$APP_NAME" <<'PY'
import sys
path, name = sys.argv[1], sys.argv[2]
s = open(path, encoding="utf-8").read()
if f'"{name}"' not in s:
    s = s.replace("members = [", 'members = [\n  "%s",' % name, 1)
    open(path, "w", encoding="utf-8").write(s)
PY
}

# ---- 日志定位 ---------------------------------------------------------------
# 每拍都往后写，跨阶段要「从某处之后」找，避免复用到上一阶段的行。
MARK=0
mark() { MARK=$(wc -l <"$DEV_LOG" 2>/dev/null || echo 0); }
since() { tail -n +"$((MARK + 1))" "$DEV_LOG" 2>/dev/null; }

wait_for() { # <固定串> <秒> <说明>
  local pat="$1" secs="$2" what="$3" i=0
  local n=$((secs * 4))
  while [ "$i" -lt "$n" ]; do
    if since | grep -qF -- "$pat"; then
      ok "$what（$pat）"
      return 0
    fi
    sleep 0.25
    i=$((i + 1))
  done
  bad "$what 超时（等 $pat，${secs}s）"
  echo "  ---- dev 日志尾部 ----"
  tail -25 "$DEV_LOG" 2>/dev/null | sed 's/^/    /'
  return 1
}

echo "== mng 应用侧场景 =="
mkdir -p "$WORK"

# ---- 1. mng 可执行文件 ------------------------------------------------------
MNG="${MNG_BIN:-}"
if [ -z "$MNG" ]; then
  moon build tools/native-gui-tools/mng --target native >/dev/null 2>&1
  for cand in \
    "_build/native/debug/build/NoahLiu/native-gui-tools/mng/mng.exe" \
    "_build/native/debug/build/NoahLiu/native-gui-tools/mng/mng"; do
    [ -x "$cand" ] && MNG="$ROOT/$cand" && break
  done
fi
if [ -z "$MNG" ] || [ ! -x "$MNG" ]; then
  bad "找不到 mng 可执行文件（先 moon build tools/native-gui-tools/mng --target native）"
  exit 1
fi
ok "mng: $MNG"

# ---- 2. 脚手架 --------------------------------------------------------------
rm -rf "$APP_DIR"
(cd "$ROOT" && "$MNG" new "$APP_NAME" >"$WORK/new.log" 2>&1) || {
  bad "mng new $APP_NAME 失败"
  sed 's/^/    /' "$WORK/new.log"
  exit 1
}
missing=""
for f in moon.mod moon.pkg main.mbt mng.toml pages/home.mng pages/home.gen.mbt pages/moon.pkg; do
  [ -f "$APP_DIR/$f" ] || missing="$missing $f"
done
if [ -n "$missing" ]; then
  bad "脚手架缺文件：$missing"
else
  ok "脚手架文件齐全（moon.mod / moon.pkg / main.mbt / mng.toml / pages 两件）"
fi
# 生成码应是 dev 形态（登记语句引 @mngdev），否则热更起不来
if grep -q "@mngdev" "$APP_DIR/pages/home.gen.mbt"; then
  ok "脚手架生成码是 dev 形态（引 @mngdev）"
else
  bad "脚手架生成码不是 dev 形态（没有 @mngdev 引用）"
fi

add_to_workfile || exit 1
ok "已把 $APP_NAME 加进 moon.work（跑完还原）"

# ---- 3. dev 循环 ------------------------------------------------------------
: >"$DEV_LOG"
(cd "$APP_DIR" && "$MNG" dev >"$DEV_LOG" 2>&1) &
DEV_PID=$!

if ! wait_for "DEV 起应用 pid=" 180 "dev 首轮启动（构建 + 起应用）"; then
  echo "  ---- 提示：GUI 起不来时先看 dev 日志里 [COLD] build 的结果 ----"
  exit 1
fi

# 3a. 字面量改动 → HOT（亚秒）
mark
sed -i.bak 's/Hello, \.mng!/Hello, HOT!/' "$APP_DIR/pages/home.mng" 2>/dev/null ||
  sed -i '' 's/Hello, \.mng!/Hello, HOT!/' "$APP_DIR/pages/home.mng"
rm -f "$APP_DIR/pages/home.mng.bak"
wait_for "[HOT] 补丁已应用" 20 "字面量改动走 HOT"

# 3b. script 段加新符号 → COLD（受限文法外）
mark
"$PY" - "$APP_DIR/pages/home.mng" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
s = s.replace("let count : @base.Store[Int] = @base.Store::new(0)",
              "let count : @base.Store[Int] = @base.Store::new(0)\nfn extra() -> Int { 7 }")
# 顺手把新符号用起来：不然生成码里是 unused_value 警告，会给 COLD 的构建日志添噪
s = s.replace("{{ count }}", "{{ count + extra() }}")
open(p, "w", encoding="utf-8").write(s)
PY
wait_for "[HOT→COLD]" 30 "新符号走受限文法外 → COLD"
wait_for "[COLD] 应用已重启" 120 "COLD 重启应用"
wait_for "[COLD] 已请求回到模板页" 30 "COLD 后回改动页"

# 3c. 新建页面 → [NEW]；删掉 → [GONE]
mark
(cd "$APP_DIR" && "$MNG" new page pages/about >/dev/null 2>&1)
wait_for "[NEW]" 20 "新建 .mng 被扫到"
mark
rm -f "$APP_DIR/pages/about.mng"
wait_for "[GONE]" 20 "删除 .mng 清生成码"

# 3d. 改源码 → [SRC]
mark
printf '\n// scenario: touch\n' >>"$APP_DIR/main.mbt"
wait_for "[SRC]" 20 "改 main.mbt 触发 SRC"

# ---- 4. 停 dev，跑生产构建 --------------------------------------------------
kill -TERM "$DEV_PID" 2>/dev/null
wait "$DEV_PID" 2>/dev/null
DEV_PID=""
if (cd "$APP_DIR" && "$MNG" build >"$WORK/build.log" 2>&1); then
  ok "mng build（无参，项目级生产形态）通过"
  if grep -q "@mngdev" "$APP_DIR/pages/home.gen.mbt"; then
    bad "生产形态生成码仍引 @mngdev（应切回生产形态）"
  else
    ok "生成码已切生产形态"
  fi
else
  bad "mng build 失败"
  tail -20 "$WORK/build.log" | sed 's/^/    /'
fi

echo
echo "== 结果：$PASS 过 / $FAIL 红 =="
[ "$FAIL" -eq 0 ]
