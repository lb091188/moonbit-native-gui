#!/usr/bin/env bash
# mng 应用侧场景（进程级）：脚手架 → 构建 → dev 热更/重启编排 → 生产构建
# → showcase 热更全覆盖（18 标签样本页：样式值 / 容器 children / options / script 回退）。
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

# 清上一轮残留：硬杀过的应用会留单实例套接字，不清会让新实例误判「已有实例」秒退；
# dev 的 COLD 重启进程不在 DEV_PID 跟踪内，退出时按名字兜底清一次
sweep_leftovers() {
  pkill -9 -f "$APP_NAME" 2>/dev/null || true
  rm -f "${TMPDIR:-/tmp}"/moonbit-instance-local_"$APP_NAME".*.sock 2>/dev/null || true
}

cleanup() {
  if [ -n "${DEV_PID:-}" ] && kill -0 "$DEV_PID" 2>/dev/null; then
    kill -TERM "$DEV_PID" 2>/dev/null || true
    for _ in 1 2 3 4 5 6 7 8 9 10; do
      kill -0 "$DEV_PID" 2>/dev/null || break
      sleep 0.3
    done
    kill -9 "$DEV_PID" 2>/dev/null || true
  fi
  # showcase 段的 dev 与应用一并清（SHOW_PID 未定义时各函数自兜底）
  sweep_showcase
  restore_showcase
  sweep_leftovers
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
    echo "  保留现场：${APP_DIR}（moon.work 未还原）"
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
      ok "${what}（${pat}）"
      return 0
    fi
    sleep 0.25
    i=$((i + 1))
  done
  bad "${what} 超时（等 ${pat}，${secs}s）"
  echo "  ---- dev 日志尾部 ----"
  tail -25 "$DEV_LOG" 2>/dev/null | sed 's/^/    /'
  echo "  ---- 应用日志尾部 ----"
  tail -25 "$APP_DIR/.mng/logs/local.$APP_NAME.log" 2>/dev/null | sed 's/^/    /'
  echo "  ---- 应用进程与回执现场 ----"
  pgrep -af "$APP_NAME" 2>/dev/null | sed 's/^/    /' || echo "    （应用进程已退出）"
  ls -la "$APP_DIR/.mng/ir/pages/" 2>/dev/null | sed 's/^/    /'
  return 1
}

# showcase 段的日志定位（同套路，指向 showcase 自己的 dev 日志）
SHOW_MARK=0
mark_show() { SHOW_MARK=$(wc -l <"$SHOW_LOG" 2>/dev/null || echo 0); }
since_show() { tail -n +"$((SHOW_MARK + 1))" "$SHOW_LOG" 2>/dev/null; }

wait_show() { # <固定串> <秒> <说明>
  local pat="$1" secs="$2" what="$3" i=0
  local n=$((secs * 4))
  while [ "$i" -lt "$n" ]; do
    if since_show | grep -qF -- "$pat"; then
      ok "${what}（${pat}）"
      return 0
    fi
    sleep 0.25
    i=$((i + 1))
  done
  bad "${what} 超时（等 ${pat}，${secs}s）"
  echo "  ---- showcase dev 日志尾部 ----"
  tail -25 "$SHOW_LOG" 2>/dev/null | sed 's/^/    /'
  echo "  ---- showcase 应用日志尾部 ----"
  tail -25 "$SHOW_DIR/.mng/logs/local.showcase.log" 2>/dev/null | sed 's/^/    /'
  return 1
}

echo "== mng 应用侧场景 =="
mkdir -p "$WORK"
sweep_leftovers

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
(cd "$APP_DIR" && exec "$MNG" dev >"$DEV_LOG" 2>&1) &
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
s = s.replace("let count : @base.Store[Int32] = @base.Store::new(0)",
              "let count : @base.Store[Int32] = @base.Store::new(0)\nfn extra() -> Int32 { 7 }")
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
# 等 NEW 拍构建完成再删：模板删除与 dev 的 build 抢跑时，moon 会报输入缺失
wait_for "[COLD] 应用已重启" 120 "NEW 拍构建完成"
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

# ---- 5. showcase 热更全覆盖（仓内 18 标签样本页） ---------------------------
# showcase 本就是 workspace 成员，不动 moon.work；combo.mng 改前备份、退场还原。
SHOW_DIR="$ROOT/examples/showcase"
SHOW_LOG="$WORK/showcase-dev.log"
SHOW_PID=""

sweep_showcase() {
  if [ -n "${SHOW_PID:-}" ] && kill -0 "$SHOW_PID" 2>/dev/null; then
    kill -TERM "$SHOW_PID" 2>/dev/null || true
    for _ in 1 2 3 4 5 6 7 8 9 10; do
      kill -0 "$SHOW_PID" 2>/dev/null || break
      sleep 0.3
    done
    kill -9 "$SHOW_PID" 2>/dev/null || true
  fi
  SHOW_PID=""
  pkill -9 -f "showcase/showcase" 2>/dev/null || true
  rm -f "${TMPDIR:-/tmp}"/moonbit-instance-local_showcase.*.sock 2>/dev/null || true
}

restore_showcase() {
  # 用备份副本还原（不 git checkout——用户可能有未提交改动）；生成码按还原后的
  # 模板重出 dev 形态，避免还原后生成码与模板不同步
  [ -f "$WORK/combo.mng.orig" ] || return 0
  if ! diff -q "$WORK/combo.mng.orig" "$SHOW_DIR/pages/combo.mng" >/dev/null 2>&1; then
    cp "$WORK/combo.mng.orig" "$SHOW_DIR/pages/combo.mng"
  fi
  if [ -n "${MNG:-}" ] && [ -x "$MNG" ]; then
    (cd "$SHOW_DIR" && "$MNG" gen pages/combo.mng -o pages/combo.gen.mbt >/dev/null 2>&1)
  fi
}

cp "$SHOW_DIR/pages/combo.mng" "$WORK/combo.mng.orig"
sweep_showcase
: >"$SHOW_LOG"
(cd "$SHOW_DIR" && exec "$MNG" dev >"$SHOW_LOG" 2>&1) &
SHOW_PID=$!

if wait_show "DEV 起应用 pid=" 180 "showcase dev 首轮启动"; then
  # 5a. 样式值：hero 圆角字面量 → HOT
  mark_show
  sed -i.bak 's/border-radius: 6px;/border-radius: 10px;/' "$SHOW_DIR/pages/combo.mng" 2>/dev/null ||
    sed -i '' 's/border-radius: 6px;/border-radius: 10px;/' "$SHOW_DIR/pages/combo.mng"
  rm -f "$SHOW_DIR/pages/combo.mng.bak"
  wait_show "[HOT] 补丁已应用" 20 "样式值改动走 HOT"

  # 5b. 结构：hero 里加一行 ui-view 容器（children 形） → HOT
  mark_show
  "$PY" - "$SHOW_DIR/pages/combo.mng" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
old = '<ui-view class="divider" />'
new = '<ui-view class="extra"><ui-text text="scenario" /></ui-view>\n      <ui-view class="divider" />'
if old in s:
    s = s.replace(old, new, 1)
    open(p, "w", encoding="utf-8").write(s)
PY
  wait_show "[HOT] 补丁已应用" 20 "容器加行走 HOT"

  # 5c. select options 数组字面量加一项 → HOT
  mark_show
  "$PY" - "$SHOW_DIR/pages/combo.mng" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
old = '["简洁", "标准", "详细"]'
new = '["简洁", "标准", "详细", "极简"]'
if old in s:
    s = s.replace(old, new, 1)
    open(p, "w", encoding="utf-8").write(s)
PY
  wait_show "[HOT] 补丁已应用" 20 "options 数组字面量走 HOT"

  # 5d. script 段加新函数 → COLD 重启回页
  mark_show
  "$PY" - "$SHOW_DIR/pages/combo.mng" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
old = "fn clear_input() {"
new = "fn scenario_extra() -> Int32 { 7 }\n\nfn clear_input() {"
if old in s:
    s = s.replace(old, new, 1)
    open(p, "w", encoding="utf-8").write(s)
PY
  wait_show "[HOT→COLD]" 30 "script 新函数转 COLD"
  wait_show "[COLD] 应用已重启" 120 "COLD 重启应用"
  wait_show "[COLD] 已请求回到模板页" 30 "COLD 后回改动页"
fi

sweep_showcase
restore_showcase

echo
echo "== 结果：$PASS 过 / $FAIL 红 =="
[ "$FAIL" -eq 0 ]
