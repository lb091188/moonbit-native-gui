import { defineConfig } from 'vitepress'
import { emitLlms } from './llms.mjs'

const gh = 'https://github.com/lb091188/moonbit-native-gui'
const apiRef = 'https://mooncakes.io/docs/NoahLiu/native-gui'

// 落地页语言自动选择:首次访问根路径时,浏览器语言为中文则跳转 /zh/,
// 其余语言留在默认英文;用户手动切换过语言(localStorage 有记录)后不再跳转。
const langDetect = `(function () {
  try {
    if (localStorage.getItem('docs-lang')) return
    if (location.pathname !== '/' && location.pathname !== '/index.html') return
    var langs = navigator.languages && navigator.languages.length
      ? navigator.languages
      : [navigator.language || '']
    for (var i = 0; i < langs.length; i++) {
      if (String(langs[i]).toLowerCase().indexOf('zh') === 0) {
        localStorage.setItem('docs-lang', 'zh')
        location.replace('zh/')
        return
      }
    }
  } catch (e) {}
})()`

// Minimal TextMate grammar so ```moonbit blocks get keyword/string/number
// highlighting instead of falling back to plain text.
const moonbitGrammar = {
  name: 'moonbit',
  scopeName: 'source.moonbit',
  patterns: [{ include: '#expression' }],
  repository: {
    expression: {
      patterns: [
        { include: '#comments' },
        { include: '#strings' },
        { include: '#numbers' },
        { include: '#keywords' },
      ],
    },
    comments: {
      patterns: [
        { name: 'comment.line.double-slash.moonbit', match: '//.*$' },
      ],
    },
    strings: {
      patterns: [
        { name: 'string.quoted.double.moonbit', begin: '"', end: '"' },
      ],
    },
    numbers: {
      patterns: [
        { name: 'constant.numeric.moonbit', match: '\\b\\d[\\d_]*(?:\\.[\\d_]+)?\\b' },
      ],
    },
    keywords: {
      patterns: [
        {
          name: 'keyword.control.moonbit',
          match: '\\b(?:fn|let|mut|const|type|struct|enum|trait|impl|pub|priv|if|else|match|while|for|loop|return|break|continue|true|false|raise|try|catch|test|using|as|extern|derive|guard|Self)\\b',
        },
      ],
    },
  },
}

// ---- 侧边栏:按顶部导航分区,每区一份(zh) ----
const zhGuideSidebar = [
  {
    text: '开始',
    items: [
      { text: '五分钟上手', link: '/zh/guide/tutorial' },
      { text: '先跑起来看看', link: '/zh/guide/experience' },
      { text: '应用开发者体验', link: '/zh/guide/dev-experience' },
      { text: '构建与运行', link: '/zh/guide/build' },
      { text: '打包与自动更新', link: '/zh/guide/publish' },
    ],
  },
  {
    text: '基础',
    items: [
      { text: '布局样式', link: '/zh/guide/layout' },
      { text: '声明式与响应式', link: '/zh/guide/declarative' },
    ],
  },
  {
    text: '画布与自绘',
    items: [
      { text: '画布', link: '/zh/guide/canvas' },
      { text: '自绘与键鼠', link: '/zh/guide/custom-draw' },
    ],
  },
  {
    text: '场景速查',
    items: [
      { text: '场景总览', link: '/zh/cookbook/' },
      { text: '布局场景', link: '/zh/cookbook/layout' },
      { text: '交互场景', link: '/zh/cookbook/interaction' },
      { text: '样式与主题场景', link: '/zh/cookbook/theme' },
      { text: '系统能力场景', link: '/zh/cookbook/system' },
    ],
  },
]

const zhComponentsSidebar = [
  { text: '总览', link: '/zh/components/' },
  {
    text: '基础',
    items: [
      { text: '布局与容器', link: '/zh/components/containers' },
      { text: '文本与基础控件', link: '/zh/components/basics' },
    ],
  },
  {
    text: '表单与日期',
    items: [
      { text: '表单控件', link: '/zh/components/form' },
      { text: '日期与时间', link: '/zh/components/date' },
    ],
  },
  {
    text: '数据',
    items: [
      { text: '数据展示', link: '/zh/components/display' },
      { text: '表格与虚拟列表', link: '/zh/components/table' },
    ],
  },
  {
    text: '导航与浮层',
    items: [
      { text: '导航', link: '/zh/components/navigation' },
      { text: '浮层与消息', link: '/zh/components/overlay' },
    ],
  },
  {
    text: '交互与响应式',
    items: [
      { text: '拖放、悬停与窗口事件', link: '/zh/components/interaction' },
      { text: '响应式控制', link: '/zh/components/reactive' },
    ],
  },
]

const zhCapabilitySidebar = [
  {
    text: '系统能力',
    items: [
      { text: '总览', link: '/zh/capability/sys' },
      { text: '音量与媒体', link: '/zh/capability/media' },
      { text: '应用与历史', link: '/zh/capability/apps-history' },
      { text: '桌面与显示', link: '/zh/capability/desktop' },
      { text: '系统服务', link: '/zh/capability/service' },
    ],
  },
  { text: '图表', link: '/zh/capability/chart' },
  { text: 'Markdown 视图', link: '/zh/capability/mdview' },
  { text: '页面路由', link: '/zh/capability/router' },
  { text: '多语言', link: '/zh/capability/i18n' },
  { text: '内嵌 webview', link: '/zh/capability/webview' },
]

const zhReferenceSidebar = [
  {
    text: '参考',
    items: [
      { text: '包结构', link: '/zh/reference/packages' },
      { text: 'API 参考', link: '/zh/reference/api' },
      { text: '对外路线图', link: '/zh/reference/roadmap' },
    ],
  },
  { text: '文档索引', link: '/zh/README' },
]

// ---- 侧边栏(英文,结构镜像) ----
const enGuideSidebar = [
  {
    text: 'Start',
    items: [
      { text: 'Five-minute start', link: '/guide/tutorial' },
      { text: 'Try the demos', link: '/guide/experience' },
      { text: 'App developer experience', link: '/guide/dev-experience' },
      { text: 'Build & run', link: '/guide/build' },
      { text: 'Packaging & auto-update', link: '/guide/publish' },
    ],
  },
  {
    text: 'Basics',
    items: [
      { text: 'Layout & styling', link: '/guide/layout' },
      { text: 'Declarative & reactivity', link: '/guide/declarative' },
    ],
  },
  {
    text: 'Canvas & custom drawing',
    items: [
      { text: 'Canvas drawing', link: '/guide/canvas' },
      { text: 'Custom draw & input', link: '/guide/custom-draw' },
    ],
  },
  {
    text: 'How-to guides',
    items: [
      { text: 'Overview', link: '/cookbook/' },
      { text: 'Layout recipes', link: '/cookbook/layout' },
      { text: 'Interaction recipes', link: '/cookbook/interaction' },
      { text: 'Theme recipes', link: '/cookbook/theme' },
      { text: 'System capability recipes', link: '/cookbook/system' },
    ],
  },
]

const enComponentsSidebar = [
  { text: 'Overview', link: '/components/' },
  {
    text: 'Basics',
    items: [
      { text: 'Layout & containers', link: '/components/containers' },
      { text: 'Text & basic controls', link: '/components/basics' },
    ],
  },
  {
    text: 'Forms & dates',
    items: [
      { text: 'Form controls', link: '/components/form' },
      { text: 'Date & time', link: '/components/date' },
    ],
  },
  {
    text: 'Data display',
    items: [
      { text: 'Data display', link: '/components/display' },
      { text: 'Tables & virtual lists', link: '/components/table' },
    ],
  },
  {
    text: 'Navigation & overlays',
    items: [
      { text: 'Navigation', link: '/components/navigation' },
      { text: 'Overlays & messages', link: '/components/overlay' },
    ],
  },
  {
    text: 'Interaction & reactivity',
    items: [
      { text: 'Drag, hover & window events', link: '/components/interaction' },
      { text: 'Reactive controls', link: '/components/reactive' },
    ],
  },
]

const enCapabilitySidebar = [
  {
    text: 'System capabilities',
    items: [
      { text: 'Overview', link: '/capability/sys' },
      { text: 'Volume & media', link: '/capability/media' },
      { text: 'Apps & history', link: '/capability/apps-history' },
      { text: 'Desktop & display', link: '/capability/desktop' },
      { text: 'System services', link: '/capability/service' },
    ],
  },
  { text: 'Charts', link: '/capability/chart' },
  { text: 'Markdown view', link: '/capability/mdview' },
  { text: 'Page routing', link: '/capability/router' },
  { text: 'i18n', link: '/capability/i18n' },
  { text: 'Embedded WebView', link: '/capability/webview' },
]

const enReferenceSidebar = [
  {
    text: 'Reference',
    items: [
      { text: 'Package layout', link: '/reference/packages' },
      { text: 'API reference', link: '/reference/api' },
      { text: 'Roadmap (Chinese)', link: '/zh/reference/roadmap' },
    ],
  },
  { text: 'Doc index', link: '/README' },
]

export default defineConfig({
  title: 'native-gui',
  description: 'MoonBit 原生跨平台桌面 GUI 库：统一观感 + 自定义主题',
  cleanUrls: true,
  // 路线图等页面会链进仓库内部目录（proposals/、experience/、测试文档/）。
  // 这些目录刻意不上文档站（README「对内工程记录」），链接只在仓库上下文
  // 可解析——豁免这些路径的死链检查，站内正常页面链接仍受保护。
  ignoreDeadLinks: [
    /proposals\//,
    /experience\/adaptation/,
    /测试文档/,
    /%E6%B5%8B%E8%AF%95%E6%96%87%E6%A1%A3/,
  ],
  lastUpdated: true,
  head: [
    ['script', {}, langDetect],
  ],
  markdown: {
    languages: [moonbitGrammar],
  },
  themeConfig: {
    search: { provider: 'local' },
  },
  locales: {
    root: {
      label: 'English',
      lang: 'en',
      themeConfig: {
        nav: [
          { text: 'Guide', link: '/guide/tutorial' },
          { text: 'Components', link: '/components/' },
          { text: 'Capabilities', link: '/capability/sys' },
          { text: 'API ↗', link: apiRef },
          { text: 'GitHub', link: gh },
        ],
        sidebar: {
          '/guide/': enGuideSidebar,
          '/cookbook/': enGuideSidebar,
          '/components/': enComponentsSidebar,
          '/capability/': enCapabilitySidebar,
          '/reference/': enReferenceSidebar,
        },
        docFooter: { prev: 'Previous', next: 'Next' },
        outline: { label: 'On this page' },
      },
    },
    zh: {
      label: '简体中文',
      lang: 'zh-CN',
      link: '/zh/',
      themeConfig: {
        nav: [
          { text: '指南', link: '/zh/guide/tutorial' },
          { text: '组件', link: '/zh/components/' },
          { text: '能力', link: '/zh/capability/sys' },
          { text: 'API ↗', link: apiRef },
          { text: '路线图', link: '/zh/reference/roadmap' },
          { text: 'GitHub', link: gh },
        ],
        sidebar: {
          '/zh/guide/': zhGuideSidebar,
          '/zh/cookbook/': zhGuideSidebar,
          '/zh/components/': zhComponentsSidebar,
          '/zh/capability/': zhCapabilitySidebar,
          '/zh/reference/': zhReferenceSidebar,
        },
        docFooter: { prev: '上一页', next: '下一页' },
        outline: { label: '页面目录' },
      },
    },
  },
  // A8 llms.txt:构建收尾把 docs/zh 与 docs 的 Markdown 源各聚成一份纯文本
  // 全集写进输出目录(llms.txt 中文 / llms-en.txt 英文),给 LLM 离线消费
  async buildEnd(siteConfig) {
    const r = emitLlms(siteConfig)
    console.log(`llms.txt: zh ${r.zhPages} 页 / en ${r.enPages} 页已聚合`)
  },
})
