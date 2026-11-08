// 着色场景（TextMate 层）：用仓库自己的 grammar 给一段 .mng 分词，逐条断言 scope。
// 这里钉的是「正则文法给对了档」，最终颜色由主题决定，不在断言范围。
// 每条对应一次真实修过的着色缺陷，改文法时先看这些用例红不红。
const test = require('node:test');
const assert = require('node:assert');
const { tokenize, tokenAt, deepest } = require('./tokenize.js');

const FIXTURE = [
  '<script setup lang="moonbit">', // 0
  'let qty : @base.Store[Int] = @base.Store::new(0)', // 1
  'fn on_reset() -> Unit {', // 2
  '  qty.set(0)', // 3
  '}', // 4
  '</script>', // 5
  '', // 6
  '<style>', // 7
  '.card { color: var(--text_primary); padding: 14px; }', // 8
  '.card:hover { border-radius: 8px; }', // 9
  '</style>', // 10
  '', // 11
  '<template>', // 12
  '  <ui-col class="card" :text="@shared.tx(\'hi\')" @click="on_reset">', // 13
  '    值 {{ qty }}', // 14
  '    <text text="COLD words here">静态</text>', // 15
  '  </ui-col>', // 16
  '</template>', // 17
];

let tokens = null;
test.before(async () => {
  tokens = await tokenize(FIXTURE.join('\n'));
});

function scopeOf(line, needle) {
  return tokenAt(tokens, line, needle);
}

test('script 段：关键字 / 变量 / 类型 / 包名 / 访问符分档', () => {
  assert.strictEqual(deepest(scopeOf(1, 'let')), 'storage.type.moonbit');
  assert.strictEqual(deepest(scopeOf(1, 'qty')), 'variable.other.moonbit');
  // @ 与包名同 scope（此前的缺陷：@ 单独一色）
  assert.strictEqual(deepest(scopeOf(1, '@')), 'entity.name.namespace.moonbit');
  assert.strictEqual(deepest(scopeOf(1, 'base')), 'entity.name.namespace.moonbit');
  assert.strictEqual(deepest(scopeOf(1, 'Store')), 'entity.name.type.class.moonbit');
  assert.strictEqual(deepest(scopeOf(1, 'Int')), 'entity.name.type.class.moonbit');
  assert.strictEqual(deepest(scopeOf(1, '::')), 'punctuation.accessor.moonbit');
  assert.strictEqual(deepest(scopeOf(1, 'new')), 'entity.name.function.moonbit');
  assert.strictEqual(deepest(scopeOf(1, '0')), 'constant.numeric.moonbit');
});

test('script 段：fn 名与体内方法调用', () => {
  assert.strictEqual(deepest(scopeOf(2, 'fn')), 'storage.type.moonbit');
  assert.strictEqual(deepest(scopeOf(2, 'on_reset')), 'entity.name.function.moonbit');
  assert.strictEqual(deepest(scopeOf(2, 'Unit')), 'entity.name.type.class.moonbit');
  assert.strictEqual(deepest(scopeOf(3, 'qty')), 'variable.other.moonbit');
  assert.strictEqual(deepest(scopeOf(3, 'set')), 'entity.name.function.moonbit');
});

test('style 段：类选择器 / 伪类 / 属性名 / 令牌 / 数值单位', () => {
  // 类选择器行：`.` 补了标点 scope（此前的缺陷：整行只有一个类名色）
  assert.strictEqual(deepest(scopeOf(8, '.')), 'punctuation.definition.entity.css');
  assert.strictEqual(deepest(scopeOf(8, 'card')), 'entity.other.attribute-name.class.css');
  assert.strictEqual(deepest(scopeOf(8, 'color')), 'support.type.property-name.css');
  // var(--令牌)：变量名单独一档，`var(--` 与 `)` 同色
  assert.strictEqual(deepest(scopeOf(8, 'text_primary')), 'support.constant.custom-property-name.css');
  assert.strictEqual(deepest(scopeOf(8, '14')), 'constant.numeric.css');
  assert.strictEqual(deepest(scopeOf(8, 'px')), 'keyword.other.unit.css');
  assert.strictEqual(deepest(scopeOf(9, ':hover')), 'entity.other.attribute-name.pseudo-class.css');
  assert.strictEqual(deepest(scopeOf(9, 'border-radius')), 'support.type.property-name.css');
});

test('模板：组件标签与普通标签分开，块级尖括号统一标点色', () => {
  assert.strictEqual(deepest(scopeOf(13, 'ui-col')), 'support.class.component.mng');
  assert.strictEqual(deepest(scopeOf(13, '<')), 'punctuation.definition.tag.begin.html');
  assert.strictEqual(deepest(scopeOf(15, 'text')), 'entity.name.tag.html');
  // 开 / 闭标签的 `</` 同档（块级四角尖括号统一标点色）
  assert.strictEqual(deepest(scopeOf(16, '</')), 'punctuation.definition.tag.begin.html');
  assert.strictEqual(deepest(scopeOf(17, 'template')), 'entity.name.tag.template.html');
});

test('模板：class 值、:动态属性、@事件各走各的档', () => {
  // class 值单独一档（不按表达式文法染）
  assert.strictEqual(deepest(scopeOf(13, 'card')), 'entity.name.class.mng');
  // :text —— 冒号是指令标记，属性名仍是属性名
  assert.strictEqual(deepest(scopeOf(13, ':')), 'punctuation.definition.directive.mng');
  assert.strictEqual(deepest(scopeOf(13, 'text')), 'entity.other.attribute-name.html');
  // @click —— @ 是指令标记，click 是事件名，值是表达式
  assert.strictEqual(deepest(scopeOf(13, '@click')), 'punctuation.definition.event.mng');
  assert.strictEqual(deepest(scopeOf(13, 'click')), 'entity.name.function.event.mng');
  assert.strictEqual(deepest(scopeOf(13, 'on_reset')), 'variable.other.moonbit');
});

test('模板：插值 {{ }} 两组括号同档，值走 script 段同一套规则', () => {
  assert.ok(tokenAt(tokens, 14, '值').scopes.includes('text.html.mng'));
  assert.strictEqual(deepest(scopeOf(14, '{{')), 'punctuation.section.interpolation.begin.mng');
  assert.strictEqual(deepest(scopeOf(14, 'qty')), 'variable.other.moonbit');
  assert.strictEqual(deepest(scopeOf(14, '}}')), 'punctuation.section.interpolation.end.mng');
});

test('静态属性字符串整串一色：串里的英文词不再被二次喂给表达式文法', () => {
  // 曾经的缺陷：`text="…COLD…"` 里的 COLD 被染成类型色、words 染成变量色
  const t = scopeOf(15, 'COLD words here');
  assert.strictEqual(t.text, 'COLD words here');
  assert.strictEqual(deepest(t), 'string.quoted.mng');
});

test('表达式里的字符串与数字不被模板文法吞掉', () => {
  assert.strictEqual(deepest(scopeOf(13, "'hi'")), 'string.quoted.single.moonbit');
});
