#!/bin/sh
# make_mac_ffmpeg_vendor.sh —— 制作 macOS 的 ffmpeg-mbt vendor dev 归档。
#
# 产物：dist/ffmpeg-macos-$(uname -m)-<版本>-lgpl-shared.tar.gz（+ .sha256）
# 归档顶层目录 ffmpeg-macos-<arch>-<版本>-lgpl-shared/，内含：
#   include/   五个库的头（libav* / libsw*）
#   lib/       动态库 + 版本 symlink，id/依赖全部 @rpath 化并 ad-hoc 重签
#   LICENSE.txt 与 COPYING.* —— 许可全文
# prebuild.py 的 Darwin 回退路按 sha256 下载解包，rpath 指向解包 lib 目录。
#
# 为什么自编而不用 brew 的 ffmpeg：brew 默认构建带 x264/x265（GPL），依赖闭包
# 还会拖进 openssl/libvpx/svt-av1 等十几支 formula——许可口径与 Windows 的
# BtbN lgpl-shared 不一致，且归档必须捆绑整个闭包才能离机运行。自编 LGPL
# （--disable-autodetect 隔离 brew）闭包只有系统库，五支 dylib 自持。
#
# 用法：scripts/make_mac_ffmpeg_vendor.sh [ffmpeg 版本]（默认 9.0.2）
# 要求：Xcode Command Line Tools（clang）。全程 env -i 净化 PATH，
# 不依赖也不触碰 brew；configure 后逐库 otool 断言闭包，破断言即失败。
set -eu

VER=${1:-9.0.2}
ARCH=$(uname -m)
NAME="ffmpeg-macos-${ARCH}-${VER}-lgpl-shared"

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
# macOS 的 TMPDIR 带尾斜杠，mktemp 展开出 `T//ffvendor.xxx`（双斜杠）；链接器
# 会把 install_name 里的路径规范化成单斜杠写进 Mach-O，而 grep 仍拿双斜杠的
# $WORK 做模式——永不匹配。pwd -P 统一成物理路径，杜绝这族分裂。
WORK=$(cd "$(mktemp -d "${TMPDIR:-/tmp}/ffvendor.XXXXXX")" && pwd -P)
trap 'rm -rf "$WORK"' EXIT
DIST="$ROOT/dist"
mkdir -p "$DIST"

echo "==> 下载 ffmpeg $VER 源码"
curl -fsSL "https://ffmpeg.org/releases/ffmpeg-${VER}.tar.xz" -o "$WORK/src.tar.xz"
tar -xJf "$WORK/src.tar.xz" -C "$WORK"
cd "$WORK/ffmpeg-${VER}"

echo "==> configure（LGPLv3，闭包隔离，无程序无文档）"
# env -i：PATH 只留系统目录，PKG_CONFIG_PATH 清空——brew 的库进不来，
# 这是「闭包自持」的第一道闸；第二道是 install 后的 otool 断言。
env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin HOME="$HOME" \
  ./configure --prefix="$WORK/prefix" \
  --enable-shared --disable-static \
  --enable-version3 --disable-nonfree \
  --disable-programs --disable-doc --disable-debug \
  --disable-autodetect \
  --enable-zlib --enable-videotoolbox --enable-audiotoolbox
# 许可注：configure 默认即 LGPL（--enable-gpl 才升级 GPL），这里只加
# --enable-version3 升到 LGPLv3；没有「--enable-lgpl」这个选项。

echo "==> make"
env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin HOME="$HOME" \
  make -j"$(sysctl -n hw.ncpu)"
env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin HOME="$HOME" \
  make install

echo "==> 收集 include/ 与 lib/（tar 保 symlink）"
STAGE="$WORK/$NAME"
mkdir -p "$STAGE/include" "$STAGE/lib"
for d in "$WORK/prefix/include"/libav* "$WORK/prefix/include"/libsw*; do
  cp -R "$d" "$STAGE/include/"
done
(cd "$WORK/prefix/lib" && find . -name 'lib*dylib*' -print | tar -cf - -T -) \
  | (cd "$STAGE/lib" && tar xf -)
[ -n "$(find "$STAGE/lib" -name 'libavformat*')" ] || { echo "lib/ 收集为空"; exit 1; }

echo "==> @rpath 化 + ad-hoc 重签 + 闭包断言"
for dylib in "$STAGE"/lib/*.dylib; do
  [ ! -L "$dylib" ] || continue
  base=$(basename "$dylib")
  install_name_tool -id "@rpath/$base" "$dylib"
  # 先把 ffmpeg 内部互依赖（configure 时写的绝对 prefix 路径）改成 @rpath
  while :; do
    dep=$(otool -L "$dylib" | sed 1d | awk '{print $1}' | grep "$WORK/prefix" | head -1 || true)
    [ -n "$dep" ] || break
    install_name_tool -change "$dep" "@rpath/$(basename "$dep")" "$dylib"
  done
  # 再断言：剩下的非 @rpath 依赖只许是 /usr/lib 与 /System（系统库 dyld 自给）
  stray=$(otool -L "$dylib" | sed 1d | awk '{print $1}' \
    | grep -v '^@rpath/' | grep -v '^/usr/lib/' | grep -v '^/System/' | head -1 || true)
  if [ -n "$stray" ]; then
    echo "闭包断言失败：$base 依赖非系统库 $stray"
    echo "（自编 LGPL 的 dylib 只许依赖 /usr/lib 与 /System，请检查 configure）"
    exit 1
  fi
  codesign -f -s - "$dylib"
done

echo "==> 许可文件与打包"
cat > "$STAGE/LICENSE.txt" <<'EOF'
FFmpeg 构建（macOS，LGPL v3）：本归档由 ffmpeg 源码以 --enable-lgpl
--enable-version3 配置构建，依 GNU Lesser General Public License version 3
分发（LGPLv3 = LGPLv2.1 + GPLv3 补充条款，随附 COPYING.LGPLv2.1 与
COPYING.GPLv3）。动态链接你的程序不必开源；修改本库则须依 LGPL 开放。
EOF
cp COPYING.LGPLv2.1 COPYING.GPLv3 "$STAGE/" 2>/dev/null || true

# COPYFILE_DISABLE=1：macOS 自带 bsdtar 默认把 xattr 打成 ._* AppleDouble
# 兄弟文件混进归档，解包侧会多出一树垃圾（判据不受影响但脏）。
COPYFILE_DISABLE=1 tar -C "$WORK" -czf "$DIST/$NAME.tar.gz" "$NAME"
# 校验行只写 <hash>  <文件名>（相对名、LF 行尾）：对绝对路径算 shasum 会把
# CI 机器的 /Users/runner/... 写进第二列，别的机器 shasum -c 必然找不到文件。
# 与 win-ffmpeg-vendor.yml 的 WriteAllText 口径一致。
(cd "$DIST" && shasum -a 256 "$NAME.tar.gz") | tee "$DIST/$NAME.tar.gz.sha256"

echo "==> 完成：$DIST/$NAME.tar.gz"
echo "    上传（征得维护者确认后）："
echo "      gh release upload vendor-v1 $DIST/$NAME.tar.gz --clobber"
echo "    然后把 sha256 回填 modules/ffmpeg-mbt/prebuild.py 的 MAC_VENDOR_TARBALLS"
