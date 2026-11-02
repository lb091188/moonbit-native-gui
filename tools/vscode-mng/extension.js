// MNG VS Code 扩展：静态贡献（语法/片段/语言注册）+ 手写 LSP 客户端。
// 语义全部来自 mng_cli lsp（stdio JSON-RPC）；本文件只做编解码与注册。
// 握手：启动时跑 `mng_cli --version`，读到 `mng-schema 1` 才接语义，否则降级为
// 「只着色 + snippets」并在状态栏提示一次。

const vscode = require('vscode');
const cp = require('child_process');
const fs = require('fs');
const path = require('path');

const SCHEMA = '1';
let client = null;
let status = null;
let warned = false;

function outputChannel() {
  if (!outputChannel._ch) {
    outputChannel._ch = vscode.window.createOutputChannel('MNG');
  }
  return outputChannel._ch;
}

// ---- 定位 mng_cli ----

function findInPath(name) {
  const exts = process.platform === 'win32' ? ['.exe', '.cmd', ''] : [''];
  const dirs = (process.env.PATH || '').split(path.delimiter).filter(Boolean);
  for (const dir of dirs) {
    for (const ext of exts) {
      const p = path.join(dir, name + ext);
      try {
        if (fs.existsSync(p) && fs.statSync(p).isFile()) {
          return p;
        }
      } catch (_) {
        // 忽略不可读目录
      }
    }
  }
  return null;
}

function resolveCli() {
  const cfg = vscode.workspace.getConfiguration('mng').get('cliPath', 'mng_cli');
  if (cfg && (cfg.includes('/') || cfg.includes('\\'))) {
    return fs.existsSync(cfg) ? cfg : null;
  }
  return findInPath(cfg || 'mng_cli');
}

function handshake(cli) {
  try {
    const out = cp.execFileSync(cli, ['--version'], { encoding: 'utf8', timeout: 5000 });
    const line = out
      .split('\n')
      .map((s) => s.trim())
      .find((s) => s.startsWith('mng-schema'));
    if (!line) {
      return { ok: false, why: '--version 未报 mng-schema 位' };
    }
    const got = line.split(/\s+/)[1];
    if (got !== SCHEMA) {
      return { ok: false, why: `schema ${got} ≠ 期望 ${SCHEMA}` };
    }
    const ver = (out.split('\n')[0] || '').trim();
    return { ok: true, version: ver };
  } catch (e) {
    return { ok: false, why: e.message };
  }
}

// ---- 极简 LSP 客户端（stdio 帧）----

class MngClient {
  constructor(cli, onDiagnostics) {
    this.cli = cli;
    this.onDiagnostics = onDiagnostics;
    this.nextId = 1;
    this.pending = new Map();
    this.buf = Buffer.alloc(0);
    this.expected = -1;
    this.proc = null;
    this.opened = new Set();
    this.stopped = false;
  }

  start(rootUri) {
    this.proc = cp.spawn(this.cli, ['lsp'], { stdio: ['pipe', 'pipe', 'pipe'] });
    this.proc.stdout.on('data', (d) => this._feed(d));
    this.proc.stderr.on('data', (d) => outputChannel().append(d.toString()));
    this.proc.on('exit', (code) => {
      this.stopped = true;
      for (const [, p] of this.pending) {
        p.reject(new Error('mng_cli lsp 退出 code=' + code));
      }
      this.pending.clear();
      outputChannel().appendLine(`[lsp] 进程退出 code=${code}`);
    });
    return this.request('initialize', {
      processId: process.pid,
      rootUri: rootUri || null,
      capabilities: {
        textDocument: {
          synchronization: { dynamicRegistration: false },
          completion: { completionItem: { snippetSupport: true } },
          hover: { contentFormat: ['markdown', 'plaintext'] },
          definition: {},
          publishDiagnostics: {},
        },
      },
      clientInfo: { name: 'mng-vscode', version: '0.2.0' },
    }).then((res) => {
      this.notify('initialized', {});
      return res;
    });
  }

  _write(obj) {
    if (!this.proc || this.stopped) {
      return;
    }
    const body = Buffer.from(JSON.stringify(obj), 'utf8');
    this.proc.stdin.write(`Content-Length: ${body.length}\r\n\r\n`);
    this.proc.stdin.write(body);
  }

  _feed(chunk) {
    this.buf = Buffer.concat([this.buf, chunk]);
    for (;;) {
      if (this.expected < 0) {
        const idx = this.buf.indexOf('\r\n\r\n');
        if (idx < 0) {
          return;
        }
        const head = this.buf.slice(0, idx).toString('utf8');
        const m = /Content-Length:\s*(\d+)/i.exec(head);
        if (!m) {
          this.buf = this.buf.slice(idx + 4);
          continue;
        }
        this.expected = parseInt(m[1], 10);
        this.buf = this.buf.slice(idx + 4);
      }
      if (this.buf.length < this.expected) {
        return;
      }
      const body = this.buf.slice(0, this.expected).toString('utf8');
      this.buf = this.buf.slice(this.expected);
      this.expected = -1;
      let msg;
      try {
        msg = JSON.parse(body);
      } catch (_) {
        continue;
      }
      this._dispatch(msg);
    }
  }

  _dispatch(msg) {
    if (msg.id !== undefined && msg.method === undefined) {
      const p = this.pending.get(msg.id);
      if (p) {
        this.pending.delete(msg.id);
        if (msg.error) {
          p.reject(new Error(msg.error.message || 'lsp error'));
        } else {
          p.resolve(msg.result);
        }
      }
      return;
    }
    if (msg.method === 'textDocument/publishDiagnostics' && msg.params) {
      this.onDiagnostics(msg.params.uri, msg.params.diagnostics || []);
    }
  }

  request(meth, params) {
    if (!this.proc || this.stopped) {
      return Promise.reject(new Error('mng_cli lsp 未就绪'));
    }
    const id = this.nextId++;
    return new Promise((resolve, reject) => {
      this.pending.set(id, { resolve, reject });
      this._write({ jsonrpc: '2.0', id, method: meth, params });
      setTimeout(() => {
        if (this.pending.has(id)) {
          this.pending.delete(id);
          reject(new Error('lsp 超时：' + meth));
        }
      }, 5000);
    });
  }

  notify(meth, params) {
    this._write({ jsonrpc: '2.0', method: meth, params });
  }

  didOpen(doc) {
    this.opened.add(doc.uri.toString());
    this.notify('textDocument/didOpen', {
      textDocument: {
        uri: doc.uri.toString(),
        languageId: 'mng',
        version: doc.version,
        text: doc.getText(),
      },
    });
  }

  didClose(doc) {
    const uri = doc.uri.toString();
    if (this.opened.delete(uri)) {
      this.notify('textDocument/didClose', { textDocument: { uri } });
    }
  }

  dispose() {
    try {
      this.notify('shutdown', {});
      this.notify('exit', {});
    } catch (_) {
      // 进程可能已退出
    }
    if (this.proc) {
      setTimeout(() => {
        try {
          this.proc.kill();
        } catch (_) {
          // 已退出
        }
      }, 300);
    }
    this.stopped = true;
  }
}

// ---- 结果映射 ----

function toKind(k) {
  switch (k) {
    case 2:
      return vscode.CompletionItemKind.Method;
    case 3:
      return vscode.CompletionItemKind.Function;
    case 4:
      return vscode.CompletionItemKind.Constructor;
    case 5:
      return vscode.CompletionItemKind.Field;
    case 6:
      return vscode.CompletionItemKind.Variable;
    case 7:
      return vscode.CompletionItemKind.Class;
    case 8:
      return vscode.CompletionItemKind.Interface;
    case 9:
      return vscode.CompletionItemKind.Module;
    case 13:
      return vscode.CompletionItemKind.Enum;
    case 14:
      return vscode.CompletionItemKind.Keyword;
    case 15:
      return vscode.CompletionItemKind.Snippet;
    case 21:
      return vscode.CompletionItemKind.Constant;
    case 22:
      return vscode.CompletionItemKind.Struct;
    default:
      return vscode.CompletionItemKind.Text;
  }
}

function toRange(r) {
  if (!r) {
    return new vscode.Range(0, 0, 0, 0);
  }
  return new vscode.Range(
    r.start ? r.start.line : 0,
    r.start ? r.start.character : 0,
    r.end ? r.end.line : 0,
    r.end ? r.end.character : 0
  );
}

function registerProviders(ctx) {
  ctx.subscriptions.push(
    vscode.languages.registerCompletionItemProvider(
      'mng',
      {
        provideCompletionItems: async (doc, pos) => {
          if (!client) {
            return undefined;
          }
          try {
            const res = await client.request('textDocument/completion', {
              textDocument: { uri: doc.uri.toString() },
              position: { line: pos.line, character: pos.character },
            });
            const items = (res && res.items) || [];
            return items.map((it) => {
              const ci = new vscode.CompletionItem(it.label, toKind(it.kind));
              if (it.detail) {
                ci.detail = it.detail;
              }
              return ci;
            });
          } catch (_) {
            return undefined;
          }
        },
      },
      '<',
      ':',
      '@',
      '{',
      ' ',
      '"',
      '.',
      '-'
    )
  );

  ctx.subscriptions.push(
    vscode.languages.registerHoverProvider('mng', {
      provideHover: async (doc, pos) => {
        if (!client) {
          return undefined;
        }
        try {
          const res = await client.request('textDocument/hover', {
            textDocument: { uri: doc.uri.toString() },
            position: { line: pos.line, character: pos.character },
          });
          if (!res || !res.contents) {
            return undefined;
          }
          const value =
            typeof res.contents === 'string'
              ? res.contents
              : res.contents.value || '';
          return new vscode.Hover(new vscode.MarkdownString(value));
        } catch (_) {
          return undefined;
        }
      },
    })
  );

  ctx.subscriptions.push(
    vscode.languages.registerDefinitionProvider('mng', {
      provideDefinition: async (doc, pos) => {
        if (!client) {
          return undefined;
        }
        try {
          const res = await client.request('textDocument/definition', {
            textDocument: { uri: doc.uri.toString() },
            position: { line: pos.line, character: pos.character },
          });
          const arr = Array.isArray(res) ? res : [];
          return arr.map((loc) => new vscode.Location(vscode.Uri.parse(loc.uri), toRange(loc.range)));
        } catch (_) {
          return undefined;
        }
      },
    })
  );
}

function collectDocuments(client) {
  for (const doc of vscode.workspace.textDocuments) {
    if (doc.languageId === 'mng') {
      client.didOpen(doc);
    }
  }
}

function startClient(ctx, cli, diagnostics) {
  const folder = vscode.workspace.workspaceFolders && vscode.workspace.workspaceFolders[0];
  const rootUri = folder ? folder.uri.toString() : null;
  client = new MngClient(cli, (uri, diags) => {
    const vd = diags.map((d) => {
      const item = new vscode.Diagnostic(
        toRange(d.range),
        d.message || '',
        d.severity === 1
          ? vscode.DiagnosticSeverity.Error
          : d.severity === 2
          ? vscode.DiagnosticSeverity.Warning
          : vscode.DiagnosticSeverity.Information
      );
      item.source = d.source || 'mng';
      return item;
    });
    diagnostics.set(vscode.Uri.parse(uri), vd);
  });
  client.start(rootUri).then(() => {
    if (status) {
      status.text = '$(check) MNG';
      status.tooltip = 'mng_cli lsp 已连接';
    }
    collectDocuments(client);
    outputChannel().appendLine('[lsp] 已连接');
  }).catch((e) => {
    outputChannel().appendLine('[lsp] 启动失败：' + e.message);
    if (status) {
      status.text = '$(warning) MNG（补全降级）';
    }
  });

  // 文档同步（全量）
  ctx.subscriptions.push(
    vscode.workspace.onDidOpenTextDocument((doc) => {
      if (doc.languageId === 'mng' && client) {
        client.didOpen(doc);
      }
    }),
    vscode.workspace.onDidChangeTextDocument((e) => {
      if (e.document.languageId === 'mng' && client) {
        const uri = e.document.uri.toString();
        if (!client.opened.has(uri)) {
          client.didOpen(e.document);
          return;
        }
        client.notify('textDocument/didChange', {
          textDocument: { uri, version: e.document.version },
          contentChanges: [{ text: e.document.getText() }],
        });
      }
    }),
    vscode.workspace.onDidCloseTextDocument((doc) => {
      if (doc.languageId === 'mng' && client) {
        client.didClose(doc);
      }
    })
  );
}

function stopClient() {
  if (client) {
    client.dispose();
    client = null;
  }
}

function activate(ctx) {
  status = vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Right, 100);
  status.show();
  ctx.subscriptions.push(status);

  const diagnostics = vscode.languages.createDiagnosticCollection('mng');
  ctx.subscriptions.push(diagnostics);

  const enable = vscode.workspace.getConfiguration('mng').get('enableLsp', true);
  if (!enable) {
    status.text = '$(circle-slash) MNG';
    status.tooltip = 'mng.enableLsp=false：只保留着色与 snippets';
    return;
  }

  const cli = resolveCli();
  if (!cli) {
    status.text = '$(warning) MNG';
    status.tooltip = '未找到 mng_cli';
    if (!warned) {
      warned = true;
      vscode.window
        .showWarningMessage(
          'MNG：未找到 mng_cli（补全/诊断不可用，着色与 snippets 照用）。装法：在仓库根执行 moon install ./tools/native-gui-tools/mng_cli，或在设置 mng.cliPath 指向可执行文件。',
          '打开设置'
        )
        .then((pick) => {
          if (pick === '打开设置') {
            vscode.commands.executeCommand('workbench.action.openSettings', 'mng.cliPath');
          }
        });
    }
    return;
  }

  const hs = handshake(cli);
  if (!hs.ok) {
    status.text = '$(warning) MNG（补全降级）';
    status.tooltip = '握手失败：' + hs.why;
    vscode.window.showWarningMessage(
      'MNG：mng_cli 握手失败（' + hs.why + '），补全降级为空，着色与 snippets 照用。'
    );
    return;
  }

  status.text = '$(sync~spin) MNG';
  status.tooltip = hs.version;
  registerProviders(ctx);
  startClient(ctx, cli, diagnostics);

  ctx.subscriptions.push(
    vscode.workspace.onDidChangeConfiguration((e) => {
      if (e.affectsConfiguration('mng')) {
        stopClient();
        vscode.window.showInformationMessage('MNG：配置已改，重载窗口后生效。');
      }
    })
  );
}

function deactivate() {
  stopClient();
}

module.exports = { activate, deactivate };
