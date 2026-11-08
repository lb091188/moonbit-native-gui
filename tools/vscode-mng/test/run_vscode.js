// 真 VS Code 场景的启动器：备一个最小工程当工作区，拉起编辑器宿主，
// 由 test/suite/index.js 在编辑器里跑断言。需要一次 VS Code 下载（首次）。
const fs = require('fs');
const os = require('os');
const path = require('path');
const { runTests } = require('@vscode/test-electron');
const { resolveBin } = require('./lsp_client.js');

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

(async () => {
  // 从 Electron 系宿主（某些 IDE 的 CLI）里起测试时，这个变量会让 Code.exe
  // 退化成 node 跑（报一串 `bad option: --…`）。启动前摘掉。
  delete process.env.ELECTRON_RUN_AS_NODE;

  const bin = resolveBin();
  if (!bin) {
    console.error('没有 mng 可执行文件：设 MNG_BIN，或先 `moon build tools/native-gui-tools/mng --target native`');
    process.exit(2);
  }

  const fixture = fs.mkdtempSync(path.join(os.tmpdir(), 'mng-vsc-'));
  fs.mkdirSync(path.join(fixture, 'pages'), { recursive: true });
  fs.mkdirSync(path.join(fixture, '.vscode'), { recursive: true });
  fs.writeFileSync(path.join(fixture, 'moon.mod'), 'name = "demo/app"\n');
  fs.writeFileSync(path.join(fixture, 'pages', 'good.mng'), GOOD);
  fs.writeFileSync(path.join(fixture, 'pages', 'bad.mng'), BAD);
  // 扩展的 cliPath 走工作区设置：扩展在真编辑器里不读 MNG_BIN 环境变量
  fs.writeFileSync(
    path.join(fixture, '.vscode', 'settings.json'),
    JSON.stringify({ 'mng.cliPath': bin.replace(/\\/g, '/') }, null, 2),
  );

  const extRoot = path.join(__dirname, '..');
  let code = 1;
  try {
    code = await runTests({
      extensionDevelopmentPath: extRoot,
      extensionTestsPath: path.join(__dirname, 'suite', 'index.js'),
      extensionTestsEnv: {
        MNG_BIN: bin,
        MNG_FIXTURE: fixture,
      },
      launchArgs: [
        // 开窗参数一律带 `--`，工作区用 --folder-uri 传：把裸目录当第一个参数
        // 会被 Electron 当成脚本入口去 require（Cannot find module <目录>）。
        '--folder-uri=' + require('url').pathToFileURL(fixture).toString(),
        '--disable-extensions',
        '--disable-gpu',
        '--disable-workspace-trust',
        '--skip-welcome',
        '--skip-release-notes',
      ],
    });
  } finally {
    fs.rmSync(fixture, { recursive: true, force: true, maxRetries: 5, retryDelay: 200 });
  }
  process.exit(code);
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
