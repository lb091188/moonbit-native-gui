// llms.txt 聚合(A8):VitePress buildEnd 调用,把 docs/zh 与 docs 的 Markdown
// 源各聚成一份纯文本全集,落进构建输出目录——`llms.txt`(中文,本站主语)与
// `llms-en.txt`。给 LLM 离线消费:不跑 JS、不解析侧边栏,纯源文档拼接。
//
// 处理口径:剥 YAML frontmatter;页与页之间插「=== 源路径 ===」分隔行便于
// 定位;目录排序 index/README 在前、其余按路径字典序;不解释 VitePress 专有
// 语法(代码块与原文保持一致)。
import fs from 'node:fs'
import path from 'node:path'

/** 剥 YAML frontmatter(`---` 开头到下一行 `---`) */
function stripFrontmatter(text) {
  if (!text.startsWith('---')) return text
  const end = text.indexOf('\n---', 3)
  if (end < 0) return text
  return text.slice(text.indexOf('\n', end + 1) + 1)
}

/** 收集 dir 下全部 .md(递归);同层 index/README 排最前,其余按路径字典序 */
function collectMd(dir) {
  const out = []
  const walk = d => {
    let entries = []
    try {
      entries = fs.readdirSync(d, { withFileTypes: true })
    } catch {
      return
    }
    for (const e of entries) {
      const p = path.join(d, e.name)
      if (e.isDirectory()) walk(p)
      else if (e.isFile() && e.name.endsWith('.md')) out.push(p)
    }
  }
  walk(dir)
  const rank = p => {
    const n = path.basename(p).toLowerCase()
    return n === 'index.md' || n === 'readme.md' ? 0 : 1
  }
  return out.sort((a, b) => {
    const da = path.dirname(a) === dir ? 0 : 1
    const db = path.dirname(b) === dir ? 0 : 1
    if (da !== db) return da - db
    if (rank(a) !== rank(b)) return rank(a) - rank(b)
    return a.localeCompare(b)
  })
}

/** 一份源文件清单 → 全集文本 */
function assemble(title, note, root, files) {
  const parts = [`# ${title}`, '', `> ${note}`, '> 页与页之间以「=== 源路径 ===」分隔。', '']
  for (const p of files) {
    const rel = path.relative(root, p).split(path.sep).join('/')
    const text = stripFrontmatter(fs.readFileSync(p, 'utf-8')).trim()
    if (text.length === 0) continue
    parts.push(`=== ${rel} ===`, '', text, '')
  }
  return parts.join('\n') + '\n'
}

/** buildEnd 入口:siteConfig 给 srcDir(docs/ 本体)与 outDir */
export function emitLlms(siteConfig) {
  const root = siteConfig.srcDir
  const out = siteConfig.outDir
  const zhFiles = collectMd(path.join(root, 'zh'))
  const enFiles = collectMd(root).filter(p => !p.split(path.sep).includes('zh'))
  const zh = assemble(
    'NoahLiu/native-gui 文档全集(中文)',
    '本文件由 VitePress build 自动聚合生成,给 LLM 离线消费;不要手编。',
    root,
    zhFiles,
  )
  const en = assemble(
    'NoahLiu/native-gui documentation (English)',
    'Aggregated by the VitePress build for offline LLM consumption; do not edit by hand.',
    root,
    enFiles,
  )
  fs.writeFileSync(path.join(out, 'llms.txt'), zh)
  fs.writeFileSync(path.join(out, 'llms-en.txt'), en)
  return { zhPages: zhFiles.length, enPages: enFiles.length }
}
