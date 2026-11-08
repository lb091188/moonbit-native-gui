// 真 mng lsp 子进程的 JSON-RPC 客户端（Content-Length 帧）。
// 场景测试用它演一遍编辑器会说的话——和 VS Code 走的是同一条 stdio 循环，
// 只是不启编辑器。
const cp = require('child_process');
const fs = require('fs');
const path = require('path');

/// mng 可执行文件：MNG_BIN 优先，其次仓库内 debug 构建产物。
function resolveBin() {
  if (process.env.MNG_BIN) {
    return fs.existsSync(process.env.MNG_BIN) ? process.env.MNG_BIN : null;
  }
  const name = process.platform === 'win32' ? 'mng.exe' : 'mng';
  const p = path.join(
    __dirname, '..', '..', '..',
    '_build', 'native', 'debug', 'build', 'NoahLiu', 'native-gui-tools', 'mng', name,
  );
  return fs.existsSync(p) ? p : null;
}

class Session {
  constructor(child) {
    this.child = child;
    this.buf = Buffer.alloc(0);
    this.queue = [];
    this.waiters = [];
    this.id = 0;
    this.stderr = '';
    this.exited = null;
    child.stdout.on('data', (d) => this._feed(d));
    child.stderr.on('data', (d) => {
      this.stderr += d.toString();
    });
    child.on('exit', (code) => {
      this.exited = code;
      this._flushWaiters();
    });
  }

  static start() {
    const bin = resolveBin();
    if (!bin) {
      return null;
    }
    return new Session(cp.spawn(bin, ['lsp'], { stdio: ['pipe', 'pipe', 'pipe'] }));
  }

  _feed(chunk) {
    this.buf = Buffer.concat([this.buf, chunk]);
    for (;;) {
      const sep = this.buf.indexOf('\r\n\r\n');
      if (sep < 0) {
        return;
      }
      const head = this.buf.slice(0, sep).toString('ascii');
      const m = /Content-Length:\s*(\d+)/i.exec(head);
      if (!m) {
        this.buf = this.buf.slice(sep + 4);
        continue;
      }
      const len = Number(m[1]);
      const bodyStart = sep + 4;
      if (this.buf.length < bodyStart + len) {
        return;
      }
      const body = this.buf.slice(bodyStart, bodyStart + len).toString('utf8');
      this.buf = this.buf.slice(bodyStart + len);
      let msg = null;
      try {
        msg = JSON.parse(body);
      } catch (e) {
        continue;
      }
      this.queue.push(msg);
      this._flushWaiters();
    }
  }

  _flushWaiters() {
    const keep = [];
    for (const w of this.waiters) {
      const hit = this.queue.findIndex(w.match);
      if (hit >= 0) {
        const msg = this.queue.splice(hit, 1)[0];
        w.resolve(msg);
      } else if (this.exited !== null) {
        w.reject(new Error(`lsp 进程已退出（code=${this.exited}）${this.stderr ? '\nstderr: ' + this.stderr : ''}`));
      } else {
        keep.push(w);
      }
    }
    this.waiters = keep;
  }

  _wait(match, timeoutMs, what) {
    return new Promise((resolve, reject) => {
      const w = { match, resolve };
      w.reject = reject;
      this.waiters.push(w);
      this._flushWaiters();
      const timer = setTimeout(() => {
        this.waiters = this.waiters.filter((x) => x !== w);
        reject(new Error(`等 ${what} 超时（${timeoutMs}ms）${this.stderr ? '\nstderr: ' + this.stderr : ''}`));
      }, timeoutMs);
      const wrap = w.resolve;
      w.resolve = (m) => {
        clearTimeout(timer);
        wrap(m);
      };
    });
  }

  write(obj) {
    const body = Buffer.from(JSON.stringify(obj), 'utf8');
    this.child.stdin.write(`Content-Length: ${body.length}\r\n\r\n`);
    this.child.stdin.write(body);
  }

  request(method, params, timeoutMs = 15000) {
    const id = ++this.id;
    this.write({ jsonrpc: '2.0', id, method, params });
    return this._wait((m) => m.id === id, timeoutMs, `${method} 的回包`);
  }

  notify(method, params) {
    this.write({ jsonrpc: '2.0', method, params });
  }

  /// 等一条 publishDiagnostics（uri 匹配才收）。
  waitDiagnostics(uri, timeoutMs = 15000) {
    return this._wait(
      (m) => m.method === 'textDocument/publishDiagnostics' && m.params && m.params.uri === uri,
      timeoutMs,
      `${uri} 的诊断`,
    );
  }

  async stop() {
    if (this.exited !== null) {
      return this.exited;
    }
    try {
      this.write({ jsonrpc: '2.0', method: 'shutdown' });
      const wait = this._wait(() => this.exited !== null, 5000, '进程退出');
      this.write({ jsonrpc: '2.0', method: 'exit' });
      await wait;
    } catch (e) {
      this.child.kill();
    }
    return this.exited;
  }

  kill() {
    if (this.exited === null) {
      this.child.kill();
    }
  }
}

module.exports = { Session, resolveBin };
