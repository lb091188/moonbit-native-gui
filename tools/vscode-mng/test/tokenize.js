// TextMate 分词夹具：拿仓库自己的 grammar 给一段 .mng 分词，供用例断言 scope。
// 不启 VS Code、不连 LSP——着色回归（正则文法那层）在这里钉住。
const fs = require('fs');
const path = require('path');
const vsctm = require('vscode-textmate');
const onig = require('vscode-oniguruma');

const GRAMMAR = path.join(__dirname, '..', 'syntaxes', 'mng.tmLanguage.json');
const WASM = path.join(__dirname, '..', 'node_modules', 'vscode-oniguruma', 'release', 'onig.wasm');

let ready = null;

async function loadGrammar() {
  const wasmBin = fs.readFileSync(WASM).buffer;
  await onig.loadWASM(wasmBin);
  const registry = new vsctm.Registry({
    onigLib: Promise.resolve({
      createOnigScanner: (sources) => new onig.OnigScanner(sources),
      createOnigString: (s) => new onig.OnigString(s),
    }),
    loadGrammar: async (scopeName) => {
      if (scopeName !== 'source.mng') {
        return null;
      }
      return vsctm.parseRawGrammar(fs.readFileSync(GRAMMAR, 'utf8'), GRAMMAR);
    },
  });
  const g = await registry.loadGrammar('source.mng');
  if (!g) {
    throw new Error('grammar 没加载上：source.mng');
  }
  return g;
}

/// 每行分词结果拍平成 [{line, start, end, text, scopes}]（scopes 由外到内）。
async function tokenize(text) {
  if (!ready) {
    ready = loadGrammar();
  }
  const grammar = await ready;
  const lines = text.split('\n');
  const out = [];
  let stack = vsctm.INITIAL;
  for (let i = 0; i < lines.length; i++) {
    const r = grammar.tokenizeLine(lines[i], stack);
    for (const t of r.tokens) {
      out.push({
        line: i,
        start: t.startIndex,
        end: t.endIndex,
        text: lines[i].slice(t.startIndex, t.endIndex),
        scopes: t.scopes.slice(),
      });
    }
    stack = r.ruleStack;
  }
  return out;
}

/// 找某行里第一次出现的 needle 的分词结果（按行内字符位置定位，
/// 而不是按 token 文本切分——一个词可能被切成多段）。
function tokenAt(tokens, line, needle) {
  const onLine = tokens.filter((t) => t.line === line);
  const lineText = onLine.map((t) => t.text).join('');
  const col = lineText.indexOf(needle);
  if (col < 0) {
    throw new Error(`第 ${line + 1} 行找不到 ${JSON.stringify(needle)}：${JSON.stringify(lineText)}`);
  }
  const hit = onLine.find((t) => col >= t.start && col < t.end);
  if (!hit) {
    throw new Error(`第 ${line + 1} 行第 ${col} 列没有 token`);
  }
  return hit;
}

/// 最深一层的 scope（着色实际取的那一档）
function deepest(token) {
  return token.scopes[token.scopes.length - 1];
}

module.exports = { tokenize, tokenAt, deepest };
