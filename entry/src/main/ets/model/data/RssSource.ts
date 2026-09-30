/**
 * 订阅源(RSS)数据实体 —— 从 legado-Harmony 移植
 *
 * 适配点：
 *  1) 移除 @Observed 装饰器：目标项目数据层不使用状态装饰器，UI 层自行观察列表；
 *  2) GSON 工具替换为标准 JSON.parse / JSON.stringify；
 *  3) rssSourceDb 由 Omit 泛型改为显式接口（ArkTS 合规）；
 *  4) 可选字段统一使用类型默认值，避免 undefined 写入数据库列。
 */

export class rssListRule {
  // 列表规则
  ruleArticles: string = ''
  // 翻页规则
  ruleNextPage: string = ''
  // 标题规则
  ruleTitle: string = ''
  // 时间规则
  rulePubDate: string = ''
  // 描述规则
  ruleDescription: string = ''
  // 图片规则
  ruleImage: string = ''
  // 链接规则
  ruleLink: string = ''
}

export class rssWebViewRule {
  // 启用 JavaScript
  enableJs: boolean = true
  // 加载 BaseUrl
  loadWithBaseUrl: boolean = true
  // 内容规则
  ruleContent: string = ''
  // 样式规则
  style: string = ''
  // 注入规则
  injectJs: string = ''
  // 白名单
  contentWhitelist: string = ''
  // 黑名单
  contentBlacklist: string = ''
  // 链接拦截
  shouldOverrideUrlLoading: string = ''
}

// 订阅源分组类别
export const SUBSCRIPTION_GROUP_TYPE: Record<number, string> = {
  0: '小说',
  1: '漫画',
  2: '影视',
  3: '资讯',
  4: '收藏夹'
}

// 订阅源类型：0.常规网站 1.订阅源
export const SUBSCRIPTION_TYPE: Record<number, string> = {
  0: '常规网站',
  1: '订阅源'
}

export const WEB_USER_AGENT: string[] = [
  'Mozilla/5.0 (Linux; Android 13; Pixel 5) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/92.0.4515.159 Mobile Safari/537.36',
  'Mozilla/5.0 (iPhone; CPU iPhone OS 14_7_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/14.1.2 Mobile/15E148 Safari/604.1',
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/92.0.4515.159 Safari/537.36',
  'Mozilla/5.0 (Custom Device; Custom OS 1.0; Custom Build) AppleWebKit/537.36 (KHTML, like Gecko) CustomBrowser/1.0 CustomSafari/537.36'
]

/**
 * 订阅源数据库行：规则字段以 JSON 字符串存储。
 */
export interface rssSourceDb {
  id?: number
  // 订阅源类型 0.常规网站 1.订阅源
  sourceType: number
  // 名称
  sourceName: string
  // 地址 url
  sourceUrl: string
  // 图标
  sourceIcon: string
  // 图标是否使用链接
  sourceIconIsUrl: boolean
  // 分组
  sourceGroup: string
  // 源注解
  sourceComment?: string
  // 是否启用
  enabled: boolean
  // 自定义变量说明
  variableComment?: string
  // js 库
  jsLib?: string
  // 启用 okhttp CookieJar 自动保存每次请求的 cookie
  enabledCookieJar: boolean
  // 并发率
  concurrentRate?: string
  // 请求头
  header?: string
  // 登录地址
  loginUrl?: string
  // 登录 UI
  loginUi?: string
  // 登录检测 js
  loginCheckJs?: string
  // 封面解密 js
  coverDecodeJs?: string
  // 分类地址
  sortUrl?: string
  // 单 URL
  singleUrl: boolean
  // 文章样式
  articleStyle?: string
  // 最后更新时间
  lastUpdateTime: number
  // 排序编号
  customOrder: number
  // 设置源变量
  variable?: string
  // 是否新增或更新点击过
  showRecentIcon: boolean
  // 自动补全
  autoComplete: boolean
  // 自定义文字
  customizeTitle: string
  // 列表规则 JSON 字符串
  rssListRule?: string
  // webView 规则 JSON 字符串
  rssWebViewRule?: string
}

export class rssSources {
  id?: number
  // 订阅源类型 0.常规网站 1.订阅源
  sourceType: number = 0
  // 名称
  sourceName: string = ''
  // 地址 url
  sourceUrl: string = ''
  // 图标
  sourceIcon: string = ''
  // 图标是否使用链接
  sourceIconIsUrl: boolean = false
  // 分组
  sourceGroup: string = SUBSCRIPTION_GROUP_TYPE[4]
  // 源注解
  sourceComment: string = ''
  // 是否启用
  enabled: boolean = true
  // 自定义变量说明
  variableComment: string = ''
  // js 库
  jsLib: string = ''
  // 启用 okhttp CookieJar 自动保存每次请求的 cookie
  enabledCookieJar: boolean = false
  // 并发率
  concurrentRate: string = ''
  // 请求头
  header: string = ''
  // 登录地址
  loginUrl: string = ''
  // 登录 UI
  loginUi: string = ''
  // 登录检测 js
  loginCheckJs: string = ''
  // 封面解密 js
  coverDecodeJs: string = ''
  // 分类地址
  sortUrl: string = ''
  // 单 URL
  singleUrl: boolean = true
  // 文章样式
  articleStyle: string = ''
  // 最后更新时间
  lastUpdateTime: number = 0
  // 排序编号
  customOrder: number = 0
  // 设置源变量
  variable: string = ''
  // 是否新增或更新点击过
  showRecentIcon: boolean = true
  // 自动补全
  autoComplete: boolean = true
  // 自定义文字
  customizeTitle: string = ''
  // 列表规则
  rssListRule?: rssListRule
  // webView 规则
  rssWebViewRule?: rssWebViewRule
}

export interface rssGroupList {
  title: string
  list: rssSources[]
}

export class rssArticles {
  origin: string = ''
  sort: string = ''
  title: string = ''
  order: number = 0
  link: string = ''
  pubDate: string = ''
  description: string = ''
  content: string = ''
  image: string = ''
  read: number = 0
  variable: string = ''
}

export class rssReadRecords {
  record: string = ''
  read: number = 0
}

export class rssStars {
  origin: string = ''
  sort: string = ''
  title: string = ''
  starTime?: Date
  link: string = ''
  pubDate: string = ''
  description: string = ''
  content: string = ''
  image: string = ''
  read: number = 0
  variable: string = ''
}

export class RssSourceGroup {
  rssGroupId?: number
  // 分组名称
  rssGroupName: string = ''
  // 排序
  groupSort?: number
  // 是否置顶
  isTop: boolean = false
  // 是否允许删除
  isDelete: boolean = true
}

export class rssSourcesHistory {
  // 订阅源类型 0.常规网站 1.订阅源
  sourceType: number = 0
  // 名称
  sourceName: string = ''
  // 地址 url
  sourceUrl: string = ''
  // 图标
  sourceIcon: string = ''
  // 图标是否使用链接
  sourceIconIsUrl: boolean = false
  // 分组
  sourceGroup: string = SUBSCRIPTION_GROUP_TYPE[0]
  // 最后更新时间
  lastUpdateTime: number = 0
  // 是否新增或更新点击过
  showRecentIcon: boolean = true
  // 自定义文字
  customizeTitle: string = ''
}

export class rssSourcesPart {
  // 名称
  sourceName: string = ''
  // 地址 url
  sourceUrl: string = ''
  // 分组
  sourceGroup: string = ''
  // 是否启用
  enabled: boolean = true
  // 自定义变量说明
  variableComment: string = ''
  // 分类地址
  sortUrl: string = ''
  // 单 URL
  singleUrl: boolean = true
  // 最后更新时间
  lastUpdateTime: number = 0
  // 排序编号
  customOrder: number = 0
  // 设置源变量
  variable: string = ''
  // 订阅源类型 0.常规网站 1.订阅源
  sourceType: number = 1
  // 是否新增或更新点击过
  showRecentIcon: boolean = true
}

export interface rssSourcesTypeParams {
  // 搜索关键词
  searchKey?: string
  // 是否启用
  enabled?: boolean
}

const serializeRule = (rule: rssListRule | rssWebViewRule | undefined): string => {
  if (!rule) {
    return ''
  }
  return JSON.stringify(rule)
}

const deserializeRule = (text: string): rssListRule | undefined => {
  if (!text || text.length === 0) {
    return undefined
  }
  try {
    const parsed = JSON.parse(text) as rssListRule
    if (!parsed) {
      return undefined
    }
    return parsed
  } catch (e) {
    return undefined
  }
}

const deserializeWebViewRule = (text: string): rssWebViewRule | undefined => {
  if (!text || text.length === 0) {
    return undefined
  }
  try {
    const parsed = JSON.parse(text) as rssWebViewRule
    if (!parsed) {
      return undefined
    }
    return parsed
  } catch (e) {
    return undefined
  }
}

export const ToRssSources = (rssSourceDbRow: rssSourceDb): rssSources => {
  const rssSourcesRow: rssSources = {
    id: rssSourceDbRow.id,
    sourceType: rssSourceDbRow.sourceType,
    sourceName: rssSourceDbRow.sourceName,
    sourceUrl: rssSourceDbRow.sourceUrl,
    sourceIcon: rssSourceDbRow.sourceIcon,
    sourceIconIsUrl: rssSourceDbRow.sourceIconIsUrl,
    sourceGroup: rssSourceDbRow.sourceGroup,
    sourceComment: rssSourceDbRow.sourceComment || '',
    enabled: rssSourceDbRow.enabled,
    variableComment: rssSourceDbRow.variableComment || '',
    jsLib: rssSourceDbRow.jsLib || '',
    enabledCookieJar: rssSourceDbRow.enabledCookieJar,
    concurrentRate: rssSourceDbRow.concurrentRate || '',
    header: rssSourceDbRow.header || '',
    loginUrl: rssSourceDbRow.loginUrl || '',
    loginUi: rssSourceDbRow.loginUi || '',
    loginCheckJs: rssSourceDbRow.loginCheckJs || '',
    coverDecodeJs: rssSourceDbRow.coverDecodeJs || '',
    sortUrl: rssSourceDbRow.sortUrl || '',
    singleUrl: rssSourceDbRow.singleUrl,
    articleStyle: rssSourceDbRow.articleStyle || '',
    lastUpdateTime: rssSourceDbRow.lastUpdateTime,
    customOrder: rssSourceDbRow.customOrder,
    variable: rssSourceDbRow.variable || '',
    autoComplete: rssSourceDbRow.autoComplete,
    showRecentIcon: rssSourceDbRow.showRecentIcon,
    customizeTitle: rssSourceDbRow.customizeTitle,
    rssListRule: deserializeRule(rssSourceDbRow.rssListRule || ''),
    rssWebViewRule: deserializeWebViewRule(rssSourceDbRow.rssWebViewRule || '')
  }
  return rssSourcesRow
}

export const ToRssSourcesDb = (rssSource: rssSources): rssSourceDb => {
  const rssSourcesDbRow: rssSourceDb = {
    id: rssSource.id,
    sourceType: rssSource.sourceType,
    sourceName: rssSource.sourceName,
    sourceUrl: rssSource.sourceUrl,
    sourceIcon: rssSource.sourceIcon,
    sourceIconIsUrl: rssSource.sourceIconIsUrl,
    sourceGroup: rssSource.sourceGroup,
    sourceComment: rssSource.sourceComment || '',
    enabled: rssSource.enabled,
    variableComment: rssSource.variableComment || '',
    jsLib: rssSource.jsLib || '',
    enabledCookieJar: rssSource.enabledCookieJar,
    concurrentRate: rssSource.concurrentRate || '',
    header: rssSource.header || '',
    loginUrl: rssSource.loginUrl || '',
    loginUi: rssSource.loginUi || '',
    loginCheckJs: rssSource.loginCheckJs || '',
    coverDecodeJs: rssSource.coverDecodeJs || '',
    sortUrl: rssSource.sortUrl || '',
    singleUrl: rssSource.singleUrl,
    articleStyle: rssSource.articleStyle || '',
    lastUpdateTime: rssSource.lastUpdateTime,
    customOrder: rssSource.customOrder,
    variable: rssSource.variable || '',
    autoComplete: rssSource.autoComplete,
    showRecentIcon: rssSource.showRecentIcon,
    customizeTitle: rssSource.customizeTitle,
    rssListRule: serializeRule(rssSource.rssListRule),
    rssWebViewRule: serializeRule(rssSource.rssWebViewRule)
  }
  return rssSourcesDbRow
}
