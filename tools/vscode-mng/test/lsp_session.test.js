// 协议级场景：拉起真的 `mng lsp` 子进程，按编辑器的说话方式演一遍会话。
// 覆盖的是 wbtest 到不了的那段——stdio JSON-RPC 循环、didOpen/didChange 的
// 诊断下发、didSave 起 moon check 后的 tick 轮询、退出握手。
// 需要 mng 可执行文件：MNG_BIN 指向它，或先 `moon build tools/native-gui-tools/mng --target native`。
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { Session, resolveBin } = require('./lsp_client.js');

const SKIP = resolveBin() ? false : '没有 mng 可执行文件（设 MNG_BIN 或先构建 mng）';

const BAD = [
  '<template>',
  '  <ui-col>',
  '    值 {{ qty',
  '  </ui-col>',
  '</template>',
].join('\n');

const GOOD = [
  '<script setup lang="moonbit">',
  'let qty : Int = 1',
  '</script>',
  '',
  '<template>',
  '  <ui-col>',
  '    值 {{ qty }}',
  '  </ui-col>',
  '</template>',
].join('\n');

let root = null;
let session = null;

function uriOf(rel) {
  const abs = path.join(root, rel).replace(/\\/g, '/');
  return 'file:///' + abs.replace(/^\//, '');
}

const LEGEND = [
  'namespace', 'type', 'class', 'enum', 'interface', 'struct', 'typeParameter',
  'parameter', 'variable', 'property', 'enumMember', 'event', 'function', 'method',
  'macro', 'label', 'comment', 'string', 'number', 'regexp', 'operator', 'keyword',
];

test.before(() => {
  if (SKIP) {
    return;
  }
  root = fs.mkdtempSync(path.join(os.tmpdir(), 'mng-lsp-'));
  fs.mkdirSync(path.join(root, 'pages'), { recursive: true });
  fs.writeFileSync(path.join(root, 'moon.mod'), 'name = "demo/app"\n');
  session = Session.start();
});

test.after(async () => {
  if (session) {
    session.kill();
  }
  if (root) {
    // didSave 起的 moon check 子进程可能还握着临时目录（Windows 上表现为 EBUSY）
    // ——清理失败不该把用例判红，重试几下就放手。
    try {
      fs.rmSync(root, { recursive: true, force: true, maxRetries: 10, retryDelay: 100 });
    } catch (e) {
      // 留给系统临时目录自己回收
    }
  }
});

test('握手：能力位与 legend 顺序对得上（VS Code 靠这份 legend 解令牌）', { skip: SKIP }, async () => {
  const r = await session.request('initialize', {
    processId: null,
    rootUri: null,
    capabilities: {},
  });
  const caps = r.result.capabilities;
  assert.strictEqual(caps.textDocumentSync, 1);
  assert.strictEqual(caps.hoverProvider, true);
  assert.strictEqual(caps.definitionProvider, true);
  assert.strictEqual(caps.semanticTokensProvider.full, true);
  // legend 顺序必须与插件 SEMANTIC_TYPES 逐字一致——错一位，编辑器上就整片错色
  assert.deepStrictEqual(caps.semanticTokensProvider.legend.tokenTypes, LEGEND);
  assert.strictEqual(r.result.serverInfo.name, 'mng');
});

test('诊断：坏模板当场下发，位置按 0 基行列', { skip: SKIP }, async () => {
  const uri = uriOf('pages/bad.mng');
  session.notify('textDocument/didOpen', {
    textDocument: { uri, languageId: 'mng', version: 1, text: BAD },
  });
  const d = await session.waitDiagnostics(uri);
  assert.strictEqual(d.params.diagnostics.length, 1);
  const one = d.params.diagnostics[0];
  assert.strictEqual(one.source, 'mng');
  assert.strictEqual(one.severity, 1);
  assert.match(one.message, /插值 \{\{ 未闭合/);
  // `{{ qty` 在第 3 行第 5 列（1 基）→ LSP 0 基
  assert.strictEqual(one.range.start.line, 2);
  assert.strictEqual(one.range.start.character, 4);
});

test('诊断：改回正确模板即清空（不发过期项）', { skip: SKIP }, async () => {
  const uri = uriOf('pages/bad.mng');
  session.notify('textDocument/didChange', {
    textDocument: { uri, version: 2 },
    contentChanges: [{ text: GOOD }],
  });
  const d = await session.waitDiagnostics(uri);
  assert.deepStrictEqual(d.params.diagnostics, []);
});

test('语义令牌：script 与插值里的同名标识符都按 variable 档发', { skip: SKIP }, async () => {
  const uri = uriOf('pages/good.mng');
  session.notify('textDocument/didOpen', {
    textDocument: { uri, languageId: 'mng', version: 1, text: GOOD },
  });
  await session.waitDiagnostics(uri);
  const r = await session.request('textDocument/semanticTokens/full', { textDocument: { uri } });
  const data = r.result.data;
  assert.ok(Array.isArray(data) && data.length > 0, '应发语义令牌');
  assert.strictEqual(data.length % 5, 0, '令牌按 5 元组编码');
  // 解 5 元组：dLine, dStart, len, type, modifiers
  const toks = [];
  let line = 0;
  let start = 0;
  for (let i = 0; i < data.length; i += 5) {
    line += data[i];
    start = data[i] === 0 ? start + data[i + 1] : data[i + 1];
    toks.push({ line, start, len: data[i + 2], type: LEGEND[data[i + 3]] });
  }
  const decl = toks.find((t) => t.line === 1 && t.start === 4);
  assert.ok(decl, 'script 段的 qty 声明应有令牌');
  assert.strictEqual(decl.type, 'variable');
  const inh = toks.find((t) => t.line === 6 && t.start === 9);
  assert.ok(inh, '插值里的 qty 应有令牌');
  assert.strictEqual(inh.type, 'variable');
  assert.ok(toks.some((t) => t.type === 'type'), 'Int 应是类型档');
});

test('hover：组件标签给参数表', { skip: SKIP }, async () => {
  const uri = uriOf('pages/good.mng');
  const r = await session.request('textDocument/hover', {
    textDocument: { uri },
    position: { line: 5, character: 4 },
  });
  assert.ok(r.result, 'hover 应有内容');
  assert.match(r.result.contents.value, /<ui-col>/);
});

test('保存：didSave 拉起一次 moon check，tick 轮询不打断会话，退出握手干净', { skip: SKIP }, async () => {
  const uri = uriOf('pages/good.mng');
  session.notify('textDocument/didSave', { textDocument: { uri } });
  for (let i = 0; i < 25; i++) {
    session.notify('$/mng/checkTick', {});
  }
  // 轮询期间会话必须还能应答（不能卡在 check 上）
  const r = await session.request('textDocument/hover', {
    textDocument: { uri },
    position: { line: 5, character: 4 },
  });
  assert.ok(r.result, 'check 期间 hover 仍应应答');
  // 临时工程里 moon check 必然失败（无依赖），服务端只该静默，不该崩
  assert.strictEqual(session.exited, null, `服务端不该退出；stderr=${session.stderr}`);
  const code = await session.stop();
  assert.strictEqual(code, 0);
});
