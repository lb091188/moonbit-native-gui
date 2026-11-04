#!/usr/bin/env node
// 文档站索引守卫：docs/ 下每个 .md 都必须出现在 config.mts 的侧边栏里
// （或白名单），新增页面漏挂侧边栏/索引时本脚本非零退出。
// 反向校验：侧边栏里的每个 link 都必须有对应文件，防手滑写错路径。
//
// 用法：node tools/check-docs-index.mjs   （仓库根执行）
import { readdirSync, readFileSync, statSync, existsSync } from 'node:fs'
import { join, relative, dirname, basename } from 'node:path'
import { fileURLToPath } from 'node:url'

const root = join(dirname(fileURLToPath(import.meta.url)), '..')
const docsDir = join(root, 'docs')
const configPath = join(docsDir, '.vitepress', 'config.mts')

// 白名单：站点首页（langDetect 分流目标）与只在 README 索引表里链的页面
const ALLOWLIST = new Set([
  '/',            // docs/index.md 落地页
  '/zh/',         // docs/zh/index.md 落地页
  '/THIRD-PARTY-NOTICES', // 授权页：两份 README 索引表链它，不进侧边栏
])

function walk(dir, out = []) {
  for (const name of readdirSync(dir)) {
    if (name === 'node_modules' || name === '.vitepress' || name === 'dist') continue
    const p = join(dir, name)
    const st = statSync(p)
    if (st.isDirectory()) walk(p, out)
    else if (name.endsWith('.md')) out.push(p)
  }
  return out
}

// 文件路径 → 站点 URL（cleanUrls 口径：去 .md，index.md 落到目录根）
function fileToUrl(file) {
  let rel = relative(docsDir, file).replace(/\\/g, '/').replace(/\.md$/, '')
  if (rel === 'index') return '/'
  if (rel.endsWith('/index')) rel = rel.slice(0, -'/index'.length)
  return '/' + rel
}

// 站点 URL → 期望文件（反向校验用）
function urlToFile(url) {
  const path = url.replace(/^\//, '').replace(/\/+$/, '')
  if (path === '' || url.endsWith('/')) {
    return join(docsDir, path, 'index.md')
  }
  return join(docsDir, path + '.md')
}

const config = readFileSync(configPath, 'utf8')
const links = new Set([...config.matchAll(/link:\s*'([^']+)'/g)].map((m) => m[1]))
const norm = (s) => (s === '/' ? '/' : s.replace(/\/+$/, '') === '' ? '/' : s.replace(/\/+$/, ''))

const sidebarLinks = new Set([...links].map(norm))

const problems = []

for (const file of walk(docsDir)) {
  const url = norm(fileToUrl(file))
  if (ALLOWLIST.has(url) || ALLOWLIST.has(url + '/')) continue
  if (!sidebarLinks.has(url)) {
    problems.push(`未挂入口: ${relative(root, file)}  →  ${url}   （加进 config.mts 侧边栏或 ALLOWLIST）`)
  }
}

for (const link of links) {
  const url = norm(link)
  if (url.startsWith('http')) continue
  const f = urlToFile(link)
  if (!existsSync(f)) {
    problems.push(`侧边栏死链: ${link}   （期望文件 ${relative(root, f)} 不存在）`)
  }
}

if (problems.length > 0) {
  console.error('文档索引守卫失败：')
  for (const p of problems) console.error('  - ' + p)
  process.exit(1)
}
console.log(`文档索引守卫通过：${walk(docsDir).length} 个页面全部有入口，${links.size} 个侧边栏链接全部有文件。`)
