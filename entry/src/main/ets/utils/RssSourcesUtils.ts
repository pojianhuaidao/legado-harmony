/**
 * 订阅源(RSS)工具类 —— 从 legado-Harmony 移植
 *
 * 适配点：
 *  1) 依赖的 rssSourceGroupDao / rssSourcesHistoryDao 单例替换为目标项目 appDb 方法；
 *  2) 源 SubscriptionImport 页面中的纯数据解析逻辑（分组、比对、批量导入）抽离为
 *     本工具方法，UI 层后续可直接复用；
 *  3) showMessage 等 UI 提示已移除：重复分组等失败场景通过返回值表达，由 UI 层提示。
 */
import { appDb } from '../model/data/AppDatabase';
import { rssSources, rssSourcesHistory, rssGroupList, rssListRule, rssWebViewRule } from '../model/data/RssSource';

export interface RssSourceImportPreview {
  groupList: rssGroupList[]
  insertMap: Record<string, boolean>
  alreadyNameMap: Record<string, boolean>
  updateNameMap: Record<string, boolean>
}

export class RssSourcesUtils {
  async pushRssSourcesHistory(item: rssSources | rssSourcesHistory): Promise<void> {
    const history: rssSourcesHistory = {
      sourceType: item.sourceType,
      sourceName: item.sourceName,
      sourceUrl: item.sourceUrl,
      sourceIcon: item.sourceIcon || '',
      sourceIconIsUrl: item.sourceIconIsUrl,
      sourceGroup: item.sourceGroup,
      lastUpdateTime: Date.now(),
      showRecentIcon: item.showRecentIcon,
      customizeTitle: item.customizeTitle || ''
    }
    await appDb.insertRssSourcesHistory(history)
  }

  async addGroupType(newGroupType: string): Promise<boolean> {
    const group = await this.getRssSourcesGroup()
    let isInsert = false
    for (let i = 0; i < group.length; i++) {
      if (group[i] === newGroupType) {
        isInsert = true
        break
      }
    }
    if (isInsert) {
      return false
    }
    await this.insertRssSourceGroup(newGroupType)
    return true
  }

  // 获取订阅分组
  async getRssSourcesGroup(): Promise<string[]> {
    const rssSourcesGroup = await appDb.getRssSourceGroups()
    const rssSourcesGroupName: string[] = []
    for (let i = 0; i < rssSourcesGroup.length; i++) {
      rssSourcesGroupName.push(rssSourcesGroup[i].rssGroupName)
    }
    return rssSourcesGroupName
  }

  // 新增分组
  async insertRssSourceGroup(rssGroupName: string): Promise<boolean> {
    return await appDb.insertRssSourceGroup(rssGroupName)
  }

  private parseRuleObject(value: string | object | undefined): object | undefined {
    if (!value) {
      return undefined
    }
    if (typeof value === 'string') {
      const text = value as string
      if (text.length === 0) {
        return undefined
      }
      try {
        return JSON.parse(text) as object
      } catch (e) {
        return undefined
      }
    }
    return value as object
  }

  /**
   * 解析订阅源导入文本（粘贴 JSON / 网络返回体），规范化后返回 rssSources 列表。
   * 与源项目 SubscriptionIndex 的 localImport / pasteAnalyze 数据部分等价。
   */
  parseRssSourcesFromJson(text: string): rssSources[] {
    const result: rssSources[] = []
    if (!text || text.length === 0) {
      return result
    }
    let rawList: rssSources[]
    try {
      const parsed = JSON.parse(text) as object
      if (!parsed || !Array.isArray(parsed)) {
        return result
      }
      rawList = parsed as rssSources[]
    } catch (e) {
      return result
    }
    for (let i = 0; i < rawList.length; i++) {
      const raw = rawList[i]
      if (!raw) {
        continue
      }
      const rawUrl = raw.sourceUrl
      if (typeof rawUrl !== 'string' || rawUrl.length === 0) {
        continue
      }
      const source = new rssSources()
      source.sourceType = 1
      source.sourceName = raw.sourceName ?? ''
      source.sourceUrl = rawUrl
      source.sourceIcon = raw.sourceIcon ?? ''
      source.sourceIconIsUrl = raw.sourceIconIsUrl === true
      source.sourceGroup = raw.sourceGroup ?? ''
      source.sourceComment = raw.sourceComment ?? ''
      source.enabled = raw.enabled !== false
      source.variableComment = raw.variableComment ?? ''
      source.jsLib = raw.jsLib ?? ''
      source.enabledCookieJar = raw.enabledCookieJar === true
      source.concurrentRate = raw.concurrentRate ?? ''
      source.header = raw.header ?? ''
      source.loginUrl = raw.loginUrl ?? ''
      source.loginUi = raw.loginUi ?? ''
      source.loginCheckJs = raw.loginCheckJs ?? ''
      source.coverDecodeJs = raw.coverDecodeJs ?? ''
      source.sortUrl = raw.sortUrl ?? ''
      source.singleUrl = raw.singleUrl !== false
      source.articleStyle = raw.articleStyle ?? ''
      source.customOrder = typeof raw.customOrder === 'number' ? raw.customOrder : 0
      source.variable = raw.variable ?? ''
      source.showRecentIcon = raw.showRecentIcon !== false
      source.autoComplete = raw.autoComplete !== false
      source.customizeTitle = raw.customizeTitle ?? ''
      const listRule = this.parseRuleObject(raw.rssListRule)
      if (listRule !== undefined) {
        source.rssListRule = listRule as rssListRule
      }
      const webViewRule = this.parseRuleObject(raw.rssWebViewRule)
      if (webViewRule !== undefined) {
        source.rssWebViewRule = webViewRule as rssWebViewRule
      }
      result.push(source)
    }
    return result
  }

  /**
   * 构建导入预览：按 sourceGroup 分组 + 与本地订阅源比对（新增 / 已有 / 需更新）。
   * 与源项目 SubscriptionImport.getGroupList 的纯数据逻辑等价。
   */
  buildImportPreview(importList: rssSources[], localList: rssSources[]): RssSourceImportPreview {
    const groupMap: Record<string, rssGroupList> = {}
    const insertMap: Record<string, boolean> = {}
    const alreadyNameMap: Record<string, boolean> = {}
    const updateNameMap: Record<string, boolean> = {}
    for (let k = 0; k < importList.length; k++) {
      const item = importList[k]
      const title = item.sourceGroup
      item.sourceType = 1
      if (title && title.length > 0) {
        if (!groupMap[title]) {
          groupMap[title] = { title: title, list: [] }
        }
        groupMap[title].list.push(item)
      } else {
        if (!groupMap['其他']) {
          groupMap['其他'] = { title: '其他', list: [] }
        }
        groupMap['其他'].list.push(item)
      }
      for (let i = 0; i < localList.length; i++) {
        const localItem = localList[i]
        if (localItem.sourceUrl === item.sourceUrl) {
          alreadyNameMap[item.sourceUrl] = true
          if (localItem.sourceName !== item.sourceName ||
            localItem.sourceUrl !== item.sourceUrl ||
            (localItem.rssListRule !== undefined && item.rssListRule !== undefined &&
              localItem.rssListRule.ruleTitle !== item.rssListRule.ruleTitle) ||
            (localItem.rssWebViewRule !== undefined && item.rssWebViewRule !== undefined &&
              localItem.rssWebViewRule.ruleContent !== item.rssWebViewRule.ruleContent)) {
            insertMap[item.sourceUrl] = true
            updateNameMap[item.sourceUrl] = true
          }
          break
        }
      }
    }
    const groupList: rssGroupList[] = []
    const keys = Object.keys(groupMap)
    for (let i = 0; i < keys.length; i++) {
      groupList.push(groupMap[keys[i]])
    }
    return {
      groupList: groupList,
      insertMap: insertMap,
      alreadyNameMap: alreadyNameMap,
      updateNameMap: updateNameMap
    }
  }

  /**
   * 执行导入：统一目标分组、强制图标走链接，随后批量入库。
   * 与源项目 SubscriptionImport 确认按钮的数据逻辑等价。
   */
  async applyImport(importList: rssSources[], targetGroup: string): Promise<boolean> {
    for (let i = 0; i < importList.length; i++) {
      const item = importList[i]
      item.sourceGroup = targetGroup
      item.sourceIconIsUrl = true
    }
    return await appDb.batchInsertRssSources(importList)
  }
}

const rssSourcesUtil = new RssSourcesUtils()
export default rssSourcesUtil
