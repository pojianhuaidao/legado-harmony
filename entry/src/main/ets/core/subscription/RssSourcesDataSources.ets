/**
 * 订阅源(RSS)懒加载数据源 —— 从 legado-Harmony 移植
 *
 * 适配点：
 *  1) 源项目继承 BasicDataSource，此处改为直接实现 IDataSource（与目标项目
 *     ShelfDataSources 风格一致），保留 totalCount/getData/replace 核心接口；
 *  2) 数据对象为 rssGroupList[]（按分组聚合的订阅源列表）。
 */
import { rssGroupList } from '../../model/data/RssSource';

export class RssSourcesDataSource implements IDataSource {
  private dataArray: rssGroupList[] = []
  private listeners: DataChangeListener[] = []

  totalCount(): number {
    return this.dataArray.length
  }

  getData(index: number): rssGroupList {
    return this.dataArray[index]
  }

  getListData(): rssGroupList[] {
    return this.dataArray
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (!this.listeners.includes(listener)) {
      this.listeners.push(listener)
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const i = this.listeners.indexOf(listener)
    if (i >= 0) {
      this.listeners.splice(i, 1)
    }
  }

  // 整体替换（导入 / 删除 / 分组变更后使用）
  replace(data: rssGroupList[], force: boolean = false): void {
    if (!force && this.dataArray.length === data.length) {
      let same = true
      for (let i = 0; i < data.length; i++) {
        if (this.dataArray[i] !== data[i]) {
          same = false
          break
        }
      }
      if (same) {
        return
      }
    }
    this.dataArray = data.slice()
    for (const listener of this.listeners) {
      listener.onDataReloaded()
    }
  }

  // 追加一条分组（源 BasicDataSource 兼容接口）
  appendData(data: rssGroupList): void {
    this.dataArray.push(data)
    for (const listener of this.listeners) {
      listener.onDataAdd(this.dataArray.length - 1)
    }
  }

  // 批量追加（源 BasicDataSource 兼容接口）
  pushAllData(data: rssGroupList[]): void {
    for (let i = 0; i < data.length; i++) {
      this.dataArray.push(data[i])
      for (const listener of this.listeners) {
        listener.onDataAdd(this.dataArray.length - 1)
      }
    }
  }
}
