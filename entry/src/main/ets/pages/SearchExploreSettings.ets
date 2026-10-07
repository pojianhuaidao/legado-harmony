import { router, promptAction } from '@kit.ArkUI';
import { AppDatabase } from '../model/data/AppDatabase';
import { syncSystemBars } from '../utils/SystemBars';
import { SearchExploreSettings, SearchExploreSettingsStore } from '../utils/SearchExploreSettingsStore';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { ImmersiveBackButton } from '../components/ImmersiveBackButton';
import { AdRuleUpdater, AdRulesBundle } from '../utils/AdRuleUpdater';

@Entry
@Component
struct SearchExploreSettingsPage {
  @StorageLink('searchExploreShowResultCover') searchExploreShowResultCover: boolean = true;
  @StorageLink('searchExploreAdBlockEnabled') searchExploreAdBlockEnabled: boolean = true;
  @StorageLink('searchExploreUseBookshelfCoverGallery') searchExploreUseBookshelfCoverGallery: boolean = false;
  @StorageLink('searchExploreShowResultTags') searchExploreShowResultTags: boolean = true;
  @StorageLink('searchExploreAggregateResults') searchExploreAggregateResults: boolean = true;
  @StorageLink('searchExplorePromptAddToShelfOnBack') searchExplorePromptAddToShelfOnBack: boolean = true;
  @StorageLink('searchExploreExactSearch') searchExploreExactSearch: boolean = false;
  @StorageLink('searchExploreExactSearchMatchAuthor') searchExploreExactSearchMatchAuthor: boolean = true;
  @StorageLink('searchExploreShowSearchProgress') searchExploreShowSearchProgress: boolean = true;
  @StorageLink('searchExploreSearchConcurrency') searchExploreSearchConcurrency: number = 6;
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageLink('themeRevision') themeRevision: number = 0;
  @StorageLink('appLightButtonColor') appLightButtonColor: string = '#007DFF';
  @StorageLink('appDarkButtonColor') appDarkButtonColor: string = '#3F8CFF';
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navBarHeight') navBarHeight: number = 0;
  @State adRuleUpdating: boolean = false;
  @State adRuleInfo: string = '';

  aboutToAppear(): void {
    this.reloadSettings();
    this.syncBars();
    this.loadAdRulesAsync();
  }

  onPageShow(): void {
    this.reloadSettings();
    this.syncBars();
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Scroll() {
        Column() {
          this.sectionTitle('订阅源浏览器')
          Column() {
          this.switchItem('去广告', '开启后拦截订阅源网页中的广告请求与广告弹窗；书山等订阅源自身的更新公告弹窗不受影响',
            this.searchExploreAdBlockEnabled, (value: boolean) => {
              this.searchExploreAdBlockEnabled = value;
              this.onSettingChanged();
            })
          this.actionItem('更新广告规则', '从 AdGuard / EasyList 规则源抓取并解析，写入本地拦截规则（域名黑名单 / 白名单 / CSS 选择器）',
            this.adRuleUpdating ? '更新中…' : '更新规则',
            () => { this.updateAdRules(); })
          }
          .width('calc(100% - 24vp)')
          .margin({ left: 12, right: 12 })
          .borderRadius(16)
          .clip(true)
          .backgroundColor(this.cardColor())

          this.sectionTitle('结果展示')
          Column() {
          this.switchItem('显示结果封面', '开启后搜索和发现结果展示书籍封面',
            this.searchExploreShowResultCover, (value: boolean) => {
              this.searchExploreShowResultCover = value;
              this.onSettingChanged();
            })
          if (this.searchExploreShowResultCover) {
            this.switchItem('使用书架图集', '开启后结果列表封面使用书架封面设置的浅色/深色图集',
              this.searchExploreUseBookshelfCoverGallery, (value: boolean) => {
                this.searchExploreUseBookshelfCoverGallery = value;
                this.onSettingChanged();
              })
          }
          this.switchItem('显示结果标签', '开启后搜索和发现结果展示书籍标签',
            this.searchExploreShowResultTags, (value: boolean) => {
              this.searchExploreShowResultTags = value;
              this.onSettingChanged();
            })
          }
          .width('calc(100% - 24vp)')
          .margin({ left: 12, right: 12 })
          .borderRadius(16)
          .clip(true)
          .backgroundColor(this.cardColor())

          this.sectionTitle('书架提示')
          Column() {
            this.switchItem('返回提示加入书架', '从搜索或发现详情点击阅读后，返回时询问是否加入书架',
              this.searchExplorePromptAddToShelfOnBack, (value: boolean) => {
                this.searchExplorePromptAddToShelfOnBack = value;
                this.onSettingChanged();
              })
          }
          .width('calc(100% - 24vp)')
          .margin({ left: 12, right: 12 })
          .borderRadius(16)
          .clip(true)
          .backgroundColor(this.cardColor())

          this.sectionTitle('搜索设置')
          Column() {
          this.switchItem('精准搜索', '开启后仅保留书名与关键词完全匹配的搜索结果',
            this.searchExploreExactSearch, (value: boolean) => {
              this.searchExploreExactSearch = value;
              this.onSettingChanged();
            })
          this.switchItem('匹配作者', '精准搜索开启时，关键词同时匹配作者',
            this.searchExploreExactSearchMatchAuthor, (value: boolean) => {
              this.searchExploreExactSearchMatchAuthor = value;
              this.onSettingChanged();
            })
          this.switchItem('显示搜索进度', '开启后搜索过程中显示已搜索书源数量和结果数量',
            this.searchExploreShowSearchProgress, (value: boolean) => {
              this.searchExploreShowSearchProgress = value;
              this.onSettingChanged();
            })
          this.switchItem('聚合同名结果', '开启后同名书籍合并展示，点击后查看各个书源结果',
            this.searchExploreAggregateResults, (value: boolean) => {
              this.searchExploreAggregateResults = value;
              this.onSettingChanged();
            })
          this.numberSettingItem('搜索并发数', '控制书籍检索、书源校验和换源同时并发请求的数量',
            this.searchExploreSearchConcurrency, 1, 12, (value: number) => {
              this.searchExploreSearchConcurrency = SearchExploreSettingsStore.normalizeSearchConcurrency(value);
              this.onSettingChanged();
            })
          }
          .width('calc(100% - 24vp)')
          .margin({ left: 12, right: 12 })
          .borderRadius(16)
          .clip(true)
          .backgroundColor(this.cardColor())

          this.sectionTitle('访问记录')
          Column() {
            this.deleteVisitRecordsItem()
          }
          .width('calc(100% - 24vp)')
          .margin({ left: 12, right: 12 })
          .borderRadius(16)
          .clip(true)
          .backgroundColor(this.cardColor())

        }
        .width('100%')
        .padding({ top: 56 + this.statusBarHeight, bottom: 32 + this.navBarHeight })
      }
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .width('100%')
      .height('100%')
      .align(Alignment.TopStart)

      this.titleBar()
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.pageColor())
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  async reloadSettings(): Promise<void> {
    try {
      const settings = await SearchExploreSettingsStore.load(getContext(this));
      this.searchExploreShowResultCover = settings.showResultCover;
      this.searchExploreAdBlockEnabled = settings.adBlockEnabled;
      this.searchExploreUseBookshelfCoverGallery = settings.useBookshelfCoverGallery;
      this.searchExploreShowResultTags = settings.showResultTags;
      this.searchExploreAggregateResults = settings.aggregateSearchResults;
      this.searchExplorePromptAddToShelfOnBack = settings.promptAddToShelfOnBack;
      this.searchExploreExactSearch = settings.exactSearch;
      this.searchExploreExactSearchMatchAuthor = settings.exactSearchMatchAuthor;
      this.searchExploreShowSearchProgress = settings.showSearchProgress;
      this.searchExploreSearchConcurrency = settings.searchConcurrency;
    } catch (e) {
      console.warn('重新加载搜索/发现配置失败:', e);
    }
  }

  onSettingChanged(): void {
    SearchExploreSettingsStore.load(getContext(this)).then((settings: SearchExploreSettings) => {
      settings.showResultCover = this.searchExploreShowResultCover;
      settings.adBlockEnabled = this.searchExploreAdBlockEnabled;
      settings.useBookshelfCoverGallery = this.searchExploreUseBookshelfCoverGallery;
      settings.showResultTags = this.searchExploreShowResultTags;
      settings.aggregateSearchResults = this.searchExploreAggregateResults;
      settings.promptAddToShelfOnBack = this.searchExplorePromptAddToShelfOnBack;
      settings.exactSearch = this.searchExploreExactSearch;
      settings.exactSearchMatchAuthor = this.searchExploreExactSearchMatchAuthor;
      settings.showSearchProgress = this.searchExploreShowSearchProgress;
      settings.searchConcurrency = SearchExploreSettingsStore.normalizeSearchConcurrency(this.searchExploreSearchConcurrency);
      SearchExploreSettingsStore.applyToStorage(settings);
      return SearchExploreSettingsStore.save(getContext(this), settings);
    }).catch((e: Error) => {
      console.warn('保存搜索/发现配置失败:', e);
    });
  }

  async loadAdRulesAsync(): Promise<void> {
    // 仅确保本地拦截规则已加载（供 Web 拦截生效），不把旧统计文本回填到按钮上；
    // 统计提示只在点击"更新规则"成功后才通过 toast 展示。
    try {
      await AdRuleUpdater.ensureLoaded(getContext(this));
    } catch (e) {
      this.adRuleInfo = '';
    }
  }

  async updateAdRules(): Promise<void> {
    if (this.adRuleUpdating) {
      return;
    }
    this.adRuleUpdating = true;
    this.adRuleInfo = '更新中…';
    try {
      const bundle = await AdRuleUpdater.update(getContext(this));
      this.adRuleInfo = this.describeBundle(bundle);
      promptAction.showToast({ message: `广告规则已更新（${this.adRuleInfo}）` });
    } catch (e) {
      this.adRuleInfo = '更新失败，请检查网络';
      promptAction.showToast({ message: '广告规则更新失败，请检查网络后重试' });
    } finally {
      this.adRuleUpdating = false;
    }
  }

  describeBundle(bundle: AdRulesBundle): string {
    return `${bundle.hostSuffixes.length} 域名 / ${bundle.cssSelectors.length} 样式 / ${bundle.whitelistSuffixes.length} 白名单`;
  }

  pageColor(): string {
    return ThemeRuntime.pageColor(this.appDarkMode);
  }

  cardColor(): string {
    return ThemeRuntime.cardColor(this.appDarkMode);
  }

  primaryTextColor(): string {
    return ThemeRuntime.primaryTextColor(this.appDarkMode);
  }

  subTextColor(): string {
    return ThemeRuntime.subTextColor(this.appDarkMode);
  }

  buttonColor(): string {
    return ThemeRuntime.buttonColor(this.appDarkMode);
  }

  syncBars(): void {
    syncSystemBars(getContext(this), this.appDarkMode, this.pageColor());
  }

  @Builder
  titleBar() {
    Row() {
      ImmersiveBackButton({ iconColor: this.primaryTextColor(), darkMode: this.appDarkMode,
        buttonSize: 40, containerWidth: 56, materialScale: 0.83, compactLayout: true,
        onBack: () => router.back() })
      Text('源设置')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.primaryTextColor())
        .layoutWeight(1)
    }
    .width('100%')
    .height(56 + this.statusBarHeight)
    .padding({ top: this.statusBarHeight })
    .backgroundColor(ThemeRuntime.topBarColor(this.appDarkMode))
    .backdropBlur(ThemeRuntime.topBarBlur())
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  sectionTitle(title: string) {
    Text(title)
      .fontSize(13)
      .fontColor(this.subTextColor())
      .width('100%')
      .padding({ left: 16, right: 16, top: 20, bottom: 8 })
  }

  @Builder
  switchItem(title: string, desc: string, value: boolean, onChange: (value: boolean) => void) {
    Row() {
      Column() {
        Text(title)
          .fontSize(16)
          .fontColor(this.primaryTextColor())
        Text(desc)
          .fontSize(12)
          .fontColor(this.subTextColor())
          .margin({ top: 4 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Toggle({ type: ToggleType.Switch, isOn: value })
        .selectedColor(this.buttonColor())
        .onChange((checked: boolean) => {
          onChange(checked);
        })
    }
    .width('calc(100% - 32vp)')
    .constraintSize({ minHeight: 64 })
    .padding({ left: 0, right: 0, top: 10, bottom: 10 })
    .margin({ left: 16, right: 16 })
    .backgroundColor(Color.Transparent)
    .border({ width: { bottom: 0.5 }, color: this.appDarkMode ? '#24FFFFFF' : '#14000000' })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  actionItem(title: string, desc: string, status: string, action: () => void) {
    Row() {
      Column() {
        Text(title)
          .fontSize(16)
          .fontColor(this.primaryTextColor())
        Text(desc)
          .fontSize(12)
          .fontColor(this.subTextColor())
          .margin({ top: 4 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Text(status)
        .fontSize(12)
        .fontColor(this.adRuleUpdating ? this.buttonColor() : this.subTextColor())
        .margin({ right: 4 })
    }
    .width('calc(100% - 32vp)')
    .constraintSize({ minHeight: 64 })
    .padding({ left: 0, right: 0, top: 10, bottom: 10 })
    .margin({ left: 16, right: 16 })
    .backgroundColor(Color.Transparent)
    .border({ width: { bottom: 0.5 }, color: this.appDarkMode ? '#24FFFFFF' : '#14000000' })
    .alignItems(VerticalAlign.Center)
    .onClick(() => { action(); })
  }

  @Builder
  numberSettingItem(title: string, desc: string, value: number, minValue: number, maxValue: number, onChange: (value: number) => void) {
    Row() {
      Column() {
        Text(title)
          .fontSize(16)
          .fontColor(this.primaryTextColor())
        Text(desc)
          .fontSize(12)
          .fontColor(this.subTextColor())
          .margin({ top: 4 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Row() {
        Text('−')
          .fontSize(18)
          .fontColor(this.primaryTextColor())
          .width(30)
          .height(30)
          .textAlign(TextAlign.Center)
          .onClick(() => {
            onChange(Math.max(minValue, this.searchExploreSearchConcurrency - 1));
          })

        Text(`${this.searchExploreSearchConcurrency}`)
          .fontSize(15)
          .fontColor(this.primaryTextColor())
          .width(42)
          .textAlign(TextAlign.Center)

        Text('+')
          .fontSize(18)
          .fontColor(this.primaryTextColor())
          .width(30)
          .height(30)
          .textAlign(TextAlign.Center)
          .onClick(() => {
            onChange(Math.min(maxValue, this.searchExploreSearchConcurrency + 1));
          })
      }
      .height(30)
      .alignItems(VerticalAlign.Center)
    }
    .width('calc(100% - 32vp)')
    .constraintSize({ minHeight: 64 })
    .padding({ left: 0, right: 0, top: 10, bottom: 10 })
    .margin({ left: 16, right: 16 })
    .backgroundColor(Color.Transparent)
    .border({ width: { bottom: 0.5 }, color: this.appDarkMode ? '#24FFFFFF' : '#14000000' })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  navItem(title: string, desc: string, url: string) {
    Row() {
      Column() {
        Text(title)
          .fontSize(16)
          .fontColor(this.primaryTextColor())
        Text(desc)
          .fontSize(12)
          .fontColor(this.subTextColor())
          .margin({ top: 4 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(18)
        .fontColor([this.subTextColor()])
    }
    .width('calc(100% - 32vp)')
    .height(64)
    .padding({ left: 0, right: 0 })
    .margin({ left: 16, right: 16 })
    .backgroundColor(Color.Transparent)
    .border({ width: { bottom: 0.5 }, color: this.appDarkMode ? '#24FFFFFF' : '#14000000' })
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      router.pushUrl({ url: url });
    })
  }

  @Builder
  deleteVisitRecordsItem() {
    Row() {
      Text('删除访问记录')
        .fontSize(16)
        .fontColor(this.accentColor())
        .layoutWeight(1)
      Text('清空订阅源的最近使用记录')
        .fontSize(12)
        .fontColor(this.subTextColor())
        .margin({ right: 8 })
    }
    .width('calc(100% - 32vp)')
    .constraintSize({ minHeight: 64 })
    .padding({ left: 0, right: 0, top: 12, bottom: 12 })
    .margin({ left: 16, right: 16 })
    .backgroundColor(Color.Transparent)
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      this.confirmDeleteVisitRecords();
    })
  }

  confirmDeleteVisitRecords(): void {
    promptAction.showDialog({
      title: '删除访问记录',
      message: '确定清空订阅源的全部最近使用记录吗？',
      buttons: [
        { text: '取消', color: this.subTextColor() },
        { text: '删除', color: this.accentColor() }
      ]
    }).then((result: promptAction.ShowDialogSuccessResponse) => {
      if (result.index === 1) {
        this.deleteVisitRecords();
      }
    }).catch(() => {
    });
  }

  deleteVisitRecords(): void {
    AppDatabase.getInstance().clearRssSourcesHistory().then((ok: boolean) => {
      if (ok) {
        const version = AppStorage.get<number>('rssSourcesVersion') ?? 0;
        AppStorage.setOrCreate('rssSourcesVersion', version + 1);
        promptAction.showToast({ message: '已清空访问记录' });
      } else {
        promptAction.showToast({ message: '操作失败' });
      }
    }).catch(() => {
      promptAction.showToast({ message: '操作失败' });
    });
  }

  accentColor(): string {
    return ThemeRuntime.accentColor(this.appDarkMode);
  }
}
