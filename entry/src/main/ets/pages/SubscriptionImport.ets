/**
 * 订阅导入页 —— 从 legado-Harmony SubscriptionImport.ets 精简移植
 * 支持：1) 粘贴订阅源 JSON 文本；2) 输入 URL 网络获取后解析；3) 选择本地文件导入。
 * 复用 RssSourcesUtils.parseRssSourcesFromJson / buildImportPreview / applyImport 与 AppDatabase 订阅 DAO。
 *
 * 修复记录（2026-10-02）：
 *  - 原简化版 confirmImport 直接 applyImport(parseResult, '订阅') 强制全量入库并覆盖 sourceGroup，
 *    丢失原版分组预览与新增/已有/更新比对校验 UI；且 SubscriptionTab 按 activeGroup 过滤 sourceGroup，
 *    当用户停留在非'全部'非'订阅'分组时，新导入源被过滤不可见（表现为"后续导入的源不显示"）。
 *  - 现在解析后先构建导入预览（按 sourceGroup 分组聚合 + 本地比对），弹窗勾选要导入的源、
 *    选择导入至分组（默认保留源分组），确认后按勾选批量入库并自增 rssSourcesVersion 触发列表刷新。
 */
import { router, promptAction } from '@kit.ArkUI';
import http from '@ohos.net.http';
import { picker, fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { rssSources, rssGroupList } from '../model/data/RssSource';
import rssSourcesUtil from '../utils/RssSourcesUtils';
import { RssSourceImportPreview } from '../utils/RssSourcesUtils';
import { appDb } from '../model/data/AppDatabase';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { ImmersiveBackButton } from '../components/ImmersiveBackButton';
import { syncSystemBars } from '../utils/SystemBars';

@Entry
@Component
struct SubscriptionImportPage {
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageLink('themeRevision') themeRevision: number = 0;
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navBarHeight') navBarHeight: number = 0;
  @State inputText: string = '';
  @State parseResult: rssSources[] = [];
  @State parseInfo: string = '';
  @State parsing: boolean = false;
  @State errorInfo: string = '';
  // 导入预览状态
  @State previewVisible: boolean = false;
  @State previewData: RssSourceImportPreview = {
    groupList: [],
    insertMap: {},
    alreadyNameMap: {},
    updateNameMap: {}
  } as RssSourceImportPreview;
  @State selectMap: Record<string, boolean> = {};
  @State selectCount: number = 0;
  @State importToGroup: string = '';
  @State importGroupOptions: string[] = [];
  @State importing: boolean = false;

  onPageShow(): void {
    syncSystemBars(getContext(this), this.appDarkMode);
  }

  onBackPress(): boolean {
    if (this.previewVisible) {
      this.previewVisible = false;
      return true;
    }
    router.back();
    return true;
  }

  async pickSubscriptionFile(): Promise<void> {
    try {
      const documentPicker = new picker.DocumentViewPicker();
      const result = await documentPicker.select({ maxSelectNumber: 1 });
      if (!result || result.length === 0) {
        return;
      }
      const uri = result[0];
      const file = fs.openSync(uri, fs.OpenMode.READ_ONLY);
      const stat = fs.statSync(file.fd);
      const buf = new ArrayBuffer(stat.size);
      fs.readSync(file.fd, buf);
      fs.closeSync(file);
      const text = util.TextDecoder.create('utf-8').decodeToString(new Uint8Array(buf));
      this.inputText = text;
      this.applyParseResult(rssSourcesUtil.parseRssSourcesFromJson(text));
    } catch (e) {
      this.errorInfo = '读取文件失败，请确认文件为 UTF-8 编码的 JSON 订阅源';
    }
  }

  async parseInput(): Promise<void> {
    const text = this.inputText.trim();
    if (text.length === 0) {
      promptAction.showToast({ message: '请输入订阅源 JSON 或 URL' });
      return;
    }
    if (text.startsWith('http://') || text.startsWith('https://')) {
      this.parsing = true;
      this.errorInfo = '';
      try {
        const resp = await this.fetchText(text);
        this.applyParseResult(rssSourcesUtil.parseRssSourcesFromJson(resp));
      } catch (e) {
        this.errorInfo = '网络获取失败，请检查 URL 后重试';
      }
      this.parsing = false;
      return;
    }
    this.applyParseResult(rssSourcesUtil.parseRssSourcesFromJson(text));
  }

  applyParseResult(list: rssSources[]): void {
    if (list.length === 0) {
      this.parseResult = [];
      this.parseInfo = '';
      promptAction.showToast({ message: '未解析到有效订阅源，请检查输入内容' });
      return;
    }
    this.parseResult = list;
    this.parseInfo = `解析到 ${list.length} 个订阅源，已弹出导入确认预览`;
    promptAction.showToast({ message: `解析到 ${list.length} 个订阅源，正在生成导入确认...` });
    // 解析完成后自动弹出确认导入预览弹窗，避免用户找不到确认入口
    this.buildPreview();
  }

  fetchText(url: string): Promise<string> {
    return new Promise<string>((resolve, reject) => {
      const httpRequest = http.createHttp();
      httpRequest.request(url, {
        method: http.RequestMethod.GET,
        connectTimeout: 15000,
        readTimeout: 30000
      }).then((response) => {
        if (response.responseCode === 200) {
          resolve(response.result as string);
        } else {
          reject(new Error('HTTP ' + response.responseCode));
        }
        httpRequest.destroy();
      }).catch((err: Error) => {
        httpRequest.destroy();
        reject(err);
      });
    });
  }

  // 构建导入预览：分组聚合 + 本地比对，生成勾选状态（默认全选新增/更新，不选纯已有）
  async buildPreview(): Promise<void> {
    const localList = await appDb.getRssSources();
    const preview = rssSourcesUtil.buildImportPreview(this.parseResult, localList ?? []);
    const selectMap: Record<string, boolean> = {};
    for (let i = 0; i < preview.groupList.length; i++) {
      const group = preview.groupList[i];
      for (let j = 0; j < group.list.length; j++) {
        const item = group.list[j];
        selectMap[item.sourceUrl] = !preview.alreadyNameMap[item.sourceUrl] || preview.updateNameMap[item.sourceUrl] === true;
      }
    }
    this.previewData = preview;
    this.selectMap = selectMap;
    this.refreshSelectCount();
    // 导入至分组：默认保留源分组（空 = 保留），同时列出已有分组 + 本批次来源分组
    const options: string[] = [];
    const seen: Record<string, boolean> = {};
    const groups = await rssSourcesUtil.getRssSourcesGroup();
    for (let i = 0; i < groups.length; i++) {
      if (!seen[groups[i]]) {
        seen[groups[i]] = true;
        options.push(groups[i]);
      }
    }
    for (let i = 0; i < preview.groupList.length; i++) {
      const title = preview.groupList[i].title;
      if (title && title.length > 0 && !seen[title]) {
        seen[title] = true;
        options.push(title);
      }
    }
    this.importGroupOptions = options;
    this.importToGroup = '';
    this.previewVisible = true;
  }

  refreshSelectCount(): void {
    let count = 0;
    const keys = Object.keys(this.selectMap);
    for (let i = 0; i < keys.length; i++) {
      if (this.selectMap[keys[i]]) {
        count++;
      }
    }
    this.selectCount = count;
  }

  toggleItem(url: string, checked: boolean): void {
    this.selectMap[url] = checked;
    this.refreshSelectCount();
  }

  toggleAll(checked: boolean): void {
    const keys = Object.keys(this.selectMap);
    for (let i = 0; i < keys.length; i++) {
      this.selectMap[keys[i]] = checked;
    }
    this.refreshSelectCount();
  }

  sourceStateLabel(item: rssSources): string {
    const url = item.sourceUrl;
    if (this.previewData.updateNameMap[url]) {
      return '更新';
    }
    if (this.previewData.alreadyNameMap[url]) {
      return '已有';
    }
    return '新增';
  }

  async confirmImport(): Promise<void> {
    if (this.parseResult.length === 0) {
      promptAction.showToast({ message: '请先解析订阅源' });
      return;
    }
    if (this.selectCount === 0) {
      promptAction.showToast({ message: '请至少勾选一个订阅源' });
      return;
    }
    this.importing = true;
    const selected = this.parseResult.filter(item => this.selectMap[item.sourceUrl] === true);
    const keepGroup = this.importToGroup.length === 0;
    let ok = false;
    if (keepGroup) {
      ok = await rssSourcesUtil.applyImport(selected, '', true);
    } else {
      ok = await rssSourcesUtil.applyImport(selected, this.importToGroup, false);
    }
    this.importing = false;
    if (ok) {
      promptAction.showToast({ message: `已导入 ${selected.length} 个订阅源` });
      AppStorage.setOrCreate('rssSourcesVersion', (AppStorage.get<number>('rssSourcesVersion') ?? 0) + 1);
      this.previewVisible = false;
      this.parseResult = [];
      this.parseInfo = '';
      this.inputText = '';
      this.selectMap = {};
      this.selectCount = 0;
    } else {
      promptAction.showToast({ message: '导入失败' });
    }
  }

  @Builder
  itemRow(item: rssSources, index: number) {
    Row({ space: 10 }) {
      Checkbox()
        .select(this.selectMap[item.sourceUrl] === true)
        .selectedColor('#007DFF')
        .onChange((val: boolean) => {
          this.toggleItem(item.sourceUrl, val);
        })
      Column({ space: 4 }) {
        Row({ space: 6 }) {
          Text(item.sourceName || '未命名源')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(ThemeRuntime.primaryTextColor(this.appDarkMode))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.sourceStateLabel(item))
            .fontSize(11)
            .fontColor('#FFFFFF')
            .backgroundColor(this.previewData.updateNameMap[item.sourceUrl] ? '#FF9800' :
              (this.previewData.alreadyNameMap[item.sourceUrl] ? '#9E9E9E' : '#4CAF50'))
            .borderRadius(8)
            .padding({ left: 6, right: 6, top: 1, bottom: 1 })
        }
        .width('100%')

        Text(item.sourceUrl)
          .fontSize(11)
          .fontColor(ThemeRuntime.subTextColor(this.appDarkMode))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding({ top: 6, bottom: 6 })
  }

  @Builder
  previewDialog() {
    Column({ space: 10 }) {
      Row() {
        Text('导入预览')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(ThemeRuntime.primaryTextColor(this.appDarkMode))
        Blank()
        Text(`已选 ${this.selectCount}/${this.parseResult.length}`)
          .fontSize(13)
          .fontColor('#007DFF')
      }
      .width('100%')

      Row({ space: 8 }) {
        Text('导入至')
          .fontSize(14)
          .fontColor(ThemeRuntime.primaryTextColor(this.appDarkMode))
        Text('保留源分组')
          .fontSize(14)
          .fontColor(this.importToGroup.length === 0 ? '#007DFF' : ThemeRuntime.subTextColor(this.appDarkMode))
          .padding({ left: 10, right: 10 })
          .backgroundColor(this.importToGroup.length === 0 ? 'rgba(0,125,255,0.12)' : ThemeRuntime.inputColor(this.appDarkMode))
          .borderRadius(14)
          .height(28)
          .onClick(() => {
            this.importToGroup = '';
          })
        ForEach(this.importGroupOptions, (group: string) => {
          Text(group)
            .fontSize(14)
            .fontColor(this.importToGroup === group ? '#007DFF' : ThemeRuntime.subTextColor(this.appDarkMode))
            .padding({ left: 10, right: 10 })
            .backgroundColor(this.importToGroup === group ? 'rgba(0,125,255,0.12)' : ThemeRuntime.inputColor(this.appDarkMode))
            .borderRadius(14)
            .height(28)
            .onClick(() => {
              this.importToGroup = group;
            })
        }, (group: string) => group)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Row() {
        Checkbox()
          .select(this.selectCount === this.parseResult.length && this.parseResult.length > 0)
          .selectedColor('#007DFF')
          .onChange((val: boolean) => {
            this.toggleAll(val);
          })
        Text(`全选（${this.selectCount}/${this.parseResult.length}）`)
          .fontSize(14)
          .fontColor(ThemeRuntime.primaryTextColor(this.appDarkMode))
        Blank()
        Text('新增=绿色 更新=橙色 已有=灰色')
          .fontSize(11)
          .fontColor(ThemeRuntime.subTextColor(this.appDarkMode))
      }
      .width('100%')

      Scroll() {
        Column() {
          ForEach(this.previewData.groupList, (group: rssGroupList) => {
            Column() {
              Text(`${group.title}（${group.list.length}）`)
                .fontSize(14)
                .fontWeight(FontWeight.Bold)
                .fontColor(ThemeRuntime.primaryTextColor(this.appDarkMode))
                .width('100%')
                .margin({ top: 6, bottom: 4 })
              ForEach(group.list, (item: rssSources, index: number) => {
                this.itemRow(item, index)
              }, (item: rssSources) => item.sourceUrl)
            }
            .width('100%')
          }, (group: rssGroupList) => group.title)
        }
        .width('100%')
        .padding({ bottom: 8 })
      }
      .layoutWeight(1)
      .width('100%')
      .align(Alignment.Top)

      Row({ space: 12 }) {
        Button('取消')
          .height(40)
          .fontSize(15)
          .layoutWeight(1)
          .backgroundColor(ThemeRuntime.inputColor(this.appDarkMode))
          .fontColor(ThemeRuntime.primaryTextColor(this.appDarkMode))
          .onClick(() => {
            this.previewVisible = false;
          })
        Button(this.importing ? '导入中...' : '确认导入')
          .height(40)
          .fontSize(15)
          .layoutWeight(1)
          .backgroundColor('#007DFF')
          .enabled(!this.importing && this.selectCount > 0)
          .onClick(() => {
            this.confirmImport();
          })
      }
      .width('100%')
      .margin({ top: 4 })
    }
    .width('100%')
    .height('100%')
    .padding(16)
    .backgroundColor(ThemeRuntime.pageColor(this.appDarkMode))
  }

  build() {
    Column() {
      Row() {
        ImmersiveBackButton({
          iconColor: ThemeRuntime.primaryTextColor(this.appDarkMode),
          darkMode: this.appDarkMode,
          buttonSize: 40,
          containerWidth: 56,
          materialScale: 0.83,
          onBack: () => router.back()
        })
        Text('订阅导入')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(ThemeRuntime.primaryTextColor(this.appDarkMode))
        Blank()
      }
      .width('100%')
      .height(56 + this.statusBarHeight)
      .padding({ left: 4, right: 16, top: this.statusBarHeight })
      .alignItems(VerticalAlign.Center)

      Scroll() {
        Column({ space: 12 }) {
          Text('粘贴订阅源 JSON、输入订阅源 URL 后自动获取，或从本地文件导入')
            .fontSize(13)
            .fontColor(ThemeRuntime.subTextColor(this.appDarkMode))
            .width('100%')

          TextArea({
            placeholder: '例如：[{"sourceName":"某某订阅","sourceUrl":"https://...","rssListRule":{...}}]',
            text: this.inputText
          })
            .onChange((value: string) => {
              this.inputText = value;
            })
            .width('100%')
            .height(220)
            .fontSize(14)
            .backgroundColor(ThemeRuntime.glassPanelColor(this.appDarkMode, '', 'panel'))
            .borderRadius(14)
            .padding(12)

          if (this.parsing) {
            Row() {
              LoadingProgress()
                .width(22)
                .height(22)
              Text('正在获取...')
                .fontSize(14)
                .fontColor(ThemeRuntime.subTextColor(this.appDarkMode))
                .margin({ left: 10 })
            }
            .width('100%')
            .justifyContent(FlexAlign.Center)
          }

          if (this.errorInfo.length > 0) {
            Text(this.errorInfo)
              .fontSize(13)
              .fontColor('#E53935')
              .width('100%')
          }

          if (this.parseInfo.length > 0) {
            Text(this.parseInfo)
              .fontSize(14)
              .fontColor(ThemeRuntime.primaryTextColor(this.appDarkMode))
              .width('100%')
          }

          Row({ space: 12 }) {
            Button('选择文件')
              .width(120)
              .height(40)
              .fontSize(15)
              .backgroundColor(ThemeRuntime.inputColor(this.appDarkMode))
              .fontColor(ThemeRuntime.primaryTextColor(this.appDarkMode))
              .onClick(() => {
                this.pickSubscriptionFile();
              })
            Button('解析')
              .width(100)
              .height(40)
              .fontSize(15)
              .onClick(() => {
                this.parseInput();
              })
            Button('确认导入')
              .width(120)
              .height(40)
              .fontSize(15)
              .backgroundColor('#007DFF')
              .enabled(this.parseResult.length > 0)
              .onClick(() => {
                this.buildPreview();
              })
          }
          .width('100%')
          .justifyContent(FlexAlign.Center)
          .margin({ top: 8 })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 8 })
      }
      .width('100%')
      .layoutWeight(1)
      .align(Alignment.Top)

      if (this.previewVisible) {
        Column() {
          this.previewDialog()
        }
        .width('100%')
        .height('100%')
        .backgroundColor(ThemeRuntime.pageColor(this.appDarkMode))
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(ThemeRuntime.pageColor(this.appDarkMode))
  }
}
