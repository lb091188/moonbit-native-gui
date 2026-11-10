#!/usr/bin/env python3
# 本地更新服务:扫打包产物目录起一个本机 HTTP 服务,供应用内「检查更新(本地服务)」
# 在免 CI、免 GitHub 发布的条件下走「检查 → 下载 → SHA256 校验 → 安装重启」全链路。
# 用法(仓库根):
#   python3 scripts/update_local_server.py --version 0.2.0
#   python3 scripts/update_local_server.py --dir examples/showcase/.mng/dist --version 0.2.0 --port 8765
# 配套:showcase「系统集成 → 应用自更新」的「检查更新(本地服务)」按钮
# (清单地址 http://127.0.0.1:8765/update.json,库侧 update_check 需 allow_http=true)。
# 仓库口径:Python 3.7(不用 3.8+ 语法与参数)。

import argparse
import hashlib
import json
import os
import re
import sys
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer

# 与 release-app CI 汇总腿同一套产物名解析与载体口径
ART_RE = re.compile(
    r"^(.+)-(\d+\.\d+\.\d+)-(darwin-aarch64|windows-x86_64|linux-x86_64)\.(dmg|zip|exe|deb|AppImage)$"
)
CARRIERS = {("darwin-aarch64", "zip"), ("windows-x86_64", "zip"), ("linux-x86_64", "AppImage")}


def sha256_of(path):
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def scan_carriers(dist, version):
    """扫 dist 里版本一致的载体文件 → [(文件名, target, size, sha256)]。"""
    out = []
    for name in sorted(os.listdir(dist)):
        m = ART_RE.match(name)
        if not m:
            continue
        _slug, ver, target, ext = m.groups()
        if ver != version:
            print("跳过版本不符: %s" % name)
            continue
        if (target, ext) not in CARRIERS:
            continue
        full = os.path.join(dist, name)
        out.append((name, target, os.path.getsize(full), sha256_of(full)))
    return out


def build_manifest(dist, version, notes):
    carriers = scan_carriers(dist, version)
    platforms = {}
    for name, target, size, sha in carriers:
        platforms[target] = {
            "url": "http://127.0.0.1:%d/%s" % (PORT, name),
            "size": size,
            "sha256": sha,
        }
    return {
        "version": version,
        "notes": notes,
        "pub_date": "",
        "platforms": platforms,
        "signature": None,
        "sig_alg": None,
        "deltas": None,
    }


class LocalUpdateHandler(SimpleHTTPRequestHandler):
    """/update.json 每次现算(重新打包后不用重启服务),其余路径静态服务 dist。"""

    def do_GET(self):
        path = self.path.split("?")[0]
        if path == "/update.json":
            body = json.dumps(
                build_manifest(DIST, VERSION, NOTES),
                indent=2,
                ensure_ascii=False,
            ).encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        SimpleHTTPRequestHandler.do_GET(self)


def main():
    ap = argparse.ArgumentParser(description="本地更新服务(测试链路)")
    default_dist = os.path.join(
        os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
        "examples", "showcase", ".mng", "dist",
    )
    ap.add_argument("--dir", default=default_dist, help="打包产物目录(默认 examples/showcase/.mng/dist)")
    ap.add_argument("--version", default="", help="要当「新版」发的版本(缺省取载体里版本号最高的)")
    ap.add_argument("--port", type=int, default=8765, help="监听端口(默认 8765,与 showcase 本地服务地址同源)")
    ap.add_argument("--notes", default="", help="update.json 的 notes(缺省 Release <版本>)")
    args = ap.parse_args()

    global DIST, VERSION, NOTES, PORT
    DIST = os.path.abspath(args.dir)
    PORT = args.port
    if not os.path.isdir(DIST):
        sys.exit("产物目录不存在: %s(先跑 mng package)" % DIST)
    VERSION = args.version or max_version_in(DIST)
    if not VERSION:
        sys.exit("目录里没解析出任何载体(*.zip/*.AppImage): %s" % DIST)
    NOTES = args.notes or ("Release %s(本地更新服务)" % VERSION)

    # 静态服务以 cwd 为根——切到产物目录,载体文件才能按名取到
    os.chdir(DIST)
    server = ThreadingHTTPServer(("127.0.0.1", PORT), LocalUpdateHandler)
    print("本地更新服务: http://127.0.0.1:%d/update.json" % PORT)
    print("产物目录: %s" % DIST)
    print("清单版本: %s" % VERSION)
    print("载体: %s" % (", ".join(n for n, _, _, _ in scan_carriers(DIST, VERSION)) or "(无)"))
    print("Ctrl+C 退出")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass


def max_version_in(dist):
    """目录里载体版本号的最高值(semver 逐段比较);没有载体给空串。"""
    best = None
    for name in os.listdir(dist):
        m = ART_RE.match(name)
        if not m or (m.group(3), m.group(4)) not in CARRIERS:
            continue
        v = tuple(int(x) for x in m.group(2).split("."))
        if best is None or v > best:
            best = v
    if best is None:
        return ""
    return ".".join(str(x) for x in best)


if __name__ == "__main__":
    main()
