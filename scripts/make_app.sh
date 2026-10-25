#!/usr/bin/env bash
# macOS 打包：把 `moon build` 产出的裸二进制包成一扇 .app。
#
# 为什么需要：mac 的一批系统面**只认从 bundle 里跑的进程**——通知最典型，
# 裸二进制里 `NSUserNotificationCenter deliverNotification:` 会被系统静默丢弃
# （连 delegate 的 didDeliver/didFail 都不回调），同一个二进制放进带
# `CFBundleIdentifier` 的 .app 里就正常投递。判据与探针记录见
# `proposals/adaptation.md` 的 macOS 通知条。托盘/ Dock 图标/ 应用菜单同属
# 这一族，所以打包这一步一次做好。
#
# 用法：
#   moon build examples/showcase --target native
#   scripts/make_app.sh showcase                 # 产 _build/apps/Showcase.app
#   open _build/apps/Showcase.app
# 非 mac 平台直接退出（Win/GTK 不需要这一步）。
set -euo pipefail

name="${1:?用法: make_app.sh <包名（examples/ 下的目录名）> [显示名]}"
title="${2:-$name}"
mode="${MOON_MODE:-debug}"
bundle_id="${BUNDLE_ID:-com.moonbitlibyue.${name}}"

repo="$(cd "$(dirname "$0")/.." && pwd)"
src="$repo/_build/native/$mode/build/NoahLiu/native-gui-examples-$name/native-gui-examples-$name.exe"
if [[ ! -f "$src" ]]; then
  echo "找不到 $src —— 先跑：moon build examples/$name --target native" >&2
  exit 1
fi
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "非 macOS，不需要打包（当前 $(uname -s)）" >&2
  exit 0
fi

app_name="$(printf '%s' "${name:0:1}" | tr '[:lower:]' '[:upper:]')${name:1}"
out="$repo/_build/apps/${app_name}.app"
exec_name="$name"

rm -rf "$out"
mkdir -p "$out/Contents/MacOS" "$out/Contents/Resources"
cp "$src" "$out/Contents/MacOS/$exec_name"
chmod +x "$out/Contents/MacOS/$exec_name"

cat > "$out/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>$exec_name</string>
  <key>CFBundleIdentifier</key><string>$bundle_id</string>
  <key>CFBundleName</key><string>$app_name</string>
  <key>CFBundleDisplayName</key><string>$title</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.1</string>
  <key>LSMinimumSystemVersion</key><string>11.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# ad-hoc 签名：通知线要的是「有稳定身份的可签名进程」，本机自测用 ad-hoc 足够
# （分发给别人要换真证书，否则对方机器按 Gatekeeper 拦）。
codesign -s - --force "$out" >/dev/null

echo "已产出 $out"
echo "跑它：open \"$out\"   （或直接执行 ${out}/Contents/MacOS/${exec_name}）"
