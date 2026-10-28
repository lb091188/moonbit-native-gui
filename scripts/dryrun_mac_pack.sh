#!/bin/zsh
# 干跑 release-bin.yml 的 darwin 收集分支(本机版):产物路径与 CI 相同,
# 打包动作一致;末尾用 otool 静态回证所有 @rpath 依赖都落在 staging。
# 注意:audio/video 若走了 brew 的 pkg-config 路,链接的是绝对路径,回证会红——
# CI runner 上无 brew ffmpeg 必走 vendor 归档路(产物为 @rpath),本地想复现
# CI 口径用受限 PATH 重链:PATH="$HOME/.moon/bin:/usr/bin:/bin" moon build ...
set -e
cd "$(dirname "$0")/.."
names=(hello showcase browser audio video)
stage="staging"
rm -rf "$stage" && mkdir -p "$stage"
for name in $names; do
  src="_build/native/release/build/NoahLiu/native-gui-examples-$name/native-gui-examples-$name.exe"
  [[ -f "$src" ]] || { echo "产物缺失: $src"; exit 1; }
  cp "$src" "$stage/$name"
  echo "打包: $name ($(stat -f%z "$src") bytes)"
done
cp docs/THIRD-PARTY-NOTICES.md "$stage/"

dylib_dir="modules/ffmpeg-mbt/vendor/mac/lib"
dylibs=("$dylib_dir"/*.dylib)
[[ -e "${dylibs[1]}" ]] || { echo "FFmpeg dylib 缺失: $dylib_dir"; exit 1; }
for dylib in $dylibs; do cp "$dylib" "$stage/"; done
echo "FFmpeg dylib 随包: $#dylibs 个"

for name in $names; do
  bin_path="$stage/$name"
  install_name_tool -add_rpath @executable_path "$bin_path" 2>/dev/null || true
  codesign --force --sign - "$bin_path"
done

echo "=== otool 静态回证 ==="
fail=0
for name in $names; do
  bin_path="$stage/$name"
  deps=$(otool -L "$bin_path" | awk 'NR>1 {print $1}')
  for dep in ${(f)deps}; do
    case "$dep" in
      @rpath/*)
        base="${dep#@rpath/}"
        [[ -f "$stage/$base" ]] || { echo "✗ $name: $dep 解析不到 staging"; fail=1; }
        ;;
      @executable_path/*|/usr/lib/*|/System/*) ;;
      *)
        echo "✗ $name: 非标准依赖 $dep(非 @rpath/系统路径——八成是 brew 路的绝对路径,分发必断)"
        fail=1
        ;;
    esac
  done
  rp=$(otool -l "$bin_path" | awk '/LC_RPATH/{getline; getline; print $2}')
  echo "$name: rpath=[$rp]"
done
[[ $fail -eq 0 ]] && echo "回证通过: 所有 @rpath 依赖均落在 staging" || exit 1
