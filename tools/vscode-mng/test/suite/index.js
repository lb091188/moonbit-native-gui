// 真 VS Code 里的场景用例（由 test/run_vscode.js 通过 @vscode/test-electron 拉起）。
// 这里断言的是「扩展装进真编辑器之后」才会暴露的事：激活是否走完、语义令牌
// 有没有真的挂上、诊断是否落进 Problems 通道、命令面的实体动作能否跑通。
//
// 跑法：npm run test:vscode（需要 mng 可执行文件与一次 VS Code 下载）
const vscode = require('vscode');
const assert = require('assert');
const fs = require('fs');
const path = require('path');

const ROOT = process.env.MNG_FIXTURE;

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

function sleep(ms) {
  return new Promise((r) => setTimeout(r, ms));
}

/// 用例跳过（环境不具备，不算红）
function skip(why) {
  const e = new Error(why);
  e.name = 'SkipCase';
  throw e;
}

/// 轮询直到 fn() 返回真值（LSP 推诊断是异步的）
async function until(fn, timeoutMs, what) {
  const deadline = Date.now() + timeoutMs;
  for (;;) {
    const v = await fn();
    if (v) {
      return v;
    }
    if (Date.now() > deadline) {
      throw new Error('等 ' + what + ' 超时（' + timeoutMs + 'ms）');
    }
    await sleep(100);
  }
}

async function run() {
  const passed = [];
  const failed = [];
  const skipped = [];
  const t = async (name, fn) => {
    try {
      await fn();
      passed.push(name);
      console.log('  PASS ' + name);
    } catch (e) {
      if (e && e.name === 'SkipCase') {
        skipped.push(name + '（' + e.message + '）');
        console.log('  SKIP ' + name + '（' + e.message + '）');
        return;
      }
      failed.push({ name, msg: (e && e.message) || String(e) });
      console.error('  FAIL ' + name + '\n        ' + ((e && e.message) || e));
    }
  };

  const ext = vscode.extensions.getExtension('lb091188.mng-vscode');
  assert.ok(ext, '扩展应从 extensionDevelopmentPath 装载');

  await t('激活：扩展 activate 走完全程（不再中途夭折）', async () => {
    await ext.activate();
    assert.strictEqual(ext.isActive, true);
  });

  await t('着色链路：grammar 注册进真编辑器', async () => {
    const langs = await vscode.languages.getLanguages();
    assert.ok(langs.includes('mng'), '.mng 语言 id 应已注册');
  });

  const goodUri = vscode.Uri.file(path.join(ROOT, 'pages', 'good.mng'));
  const badUri = vscode.Uri.file(path.join(ROOT, 'pages', 'bad.mng'));

  await t('语义令牌：编辑器侧能取到语义档（registerDocumentSemanticTokensProvider 真的挂上）', async () => {
    const doc = await vscode.workspace.openTextDocument(goodUri);
    await vscode.window.showTextDocument(doc);
    const cmds = await vscode.commands.getCommands(true);
    const id = cmds.find((c) => /semantic/i.test(c) && /execute/i.test(c));
    if (!id) {
      // 这一档的守门员在别处：`tsc --checkJs` 抓「API 名不存在」，
      // 协议级用例抓「legend 顺序 / 令牌内容」。编辑器不给内部命令就跳过。
      skip('本构建没有 execute*SemanticTokens* 内部命令');
    }
    const toks = await until(
      async () => vscode.commands.executeCommand(id, goodUri),
      20000,
      '语义令牌',
    );
    assert.ok(toks && toks.data && toks.data.length > 0, '应取到语义令牌 data');
  });

  await t('诊断：坏模板落进 Problems（source=mng）', async () => {
    const doc = await vscode.workspace.openTextDocument(badUri);
    await vscode.window.showTextDocument(doc);
    const hit = await until(
      () => vscode.languages.getDiagnostics(badUri).find((d) => d.source === 'mng'),
      20000,
      '模板诊断',
    );
    assert.match(hit.message, /插值 \{\{ 未闭合/);
    assert.strictEqual(hit.range.start.line, 2, '行号应回投到模板第 3 行（0 基 2）');
  });

  await t('hover：组件标签给参数表', async () => {
    const hovers = await vscode.commands.executeCommand(
      'vscode.executeHoverProvider',
      goodUri,
      new vscode.Position(5, 4),
    );
    assert.ok(Array.isArray(hovers) && hovers.length > 0, '应有 hover');
    const text = hovers
      .map((h) => (Array.isArray(h.contents) ? h.contents : [h.contents]).map((c) => (typeof c === 'string' ? c : c.value)).join('\n'))
      .join('\n');
    assert.match(text, /<ui-col>/);
  });

  await t('命令面：新建页面落地并打开（newPageAt 实体动作）', async () => {
    const api = ext.exports;
    assert.strictEqual(typeof api.newPageAt, 'function', '扩展应导出 newPageAt 供集成用例调用');
    const file = await api.newPageAt(ROOT, 'pages/t1');
    assert.ok(fs.existsSync(file), '应生成 ' + file);
    const text = fs.readFileSync(file, 'utf8');
    assert.match(text, /<template>/);
    const doc = await vscode.workspace.openTextDocument(vscode.Uri.file(file));
    assert.ok(doc.getText().length > 0);
  });

  console.log(`\n  编辑器场景：${passed.length} 过 / ${failed.length} 红 / ${skipped.length} 跳过`);
  if (failed.length > 0) {
    throw new Error(
      '失败用例：\n' + failed.map((f) => '  - ' + f.name + '：' + f.msg).join('\n'),
    );
  }
}

module.exports = { run };
