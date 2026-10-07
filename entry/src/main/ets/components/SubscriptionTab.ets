/**
 * 订阅源(RSS)列表组件 —— 从 legado-Harmony 移植，按爱·阅读风格重写
 *
 * 双模式：
 *  1) Tab 模式（pageMode=false）：主界面底部 Tab「订阅」直接内嵌，无返回按钮；
 *  2) 页面模式（pageMode=true）：书源管理「订阅管理」入口路由到 SubscriptionIndex，
 *     顶部显示返回按钮与「订阅管理」标题。
 *
 * 数据层复用：RssSource.ts / RssSourcesUtils.ts / RssSourcesDataSources.ets /
 *             AppDatabase 订阅 DAO（getRssSources / insertRssSource / updateRssSource /
 *             deleteRssSources / deleteRssSourcesList / getRssSourcesHistory 等）。
 */
import { router, promptAction } from '@kit.ArkUI';
import { AppDatabase } from '../model/data/AppDatabase';
import {
  rssSources,
  RssSourceGroup,
  rssSourcesHistory,
  SUBSCRIPTION_GROUP_TYPE,
  SUBSCRIPTION_TYPE
} from '../model/data/RssSource';
import rssSourcesUtil from '../utils/RssSourcesUtils';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { ImmersiveBackButton } from '../components/ImmersiveBackButton';

@Component
export struct SubscriptionTab {
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageLink('themeRevision') themeRevision: number = 0;
  @StorageLink('appLightAccentColor') appLightAccentColor: string = '#007DFF';
  @StorageLink('appDarkAccentColor') appDarkAccentColor: string = '#4E9BFF';
  @StorageLink('appLightButtonColor') appLightButtonColor: string = '#007DFF';
  @StorageLink('appDarkButtonColor') appDarkButtonColor: string = '#3F8CFF';
  @StorageProp('statusBarHeight') statusBarHeightProp: number = 0;
  @StorageProp('navBarHeight') navBarHeightProp: number = 0;
  @Prop statusBarHeight: number = 0;
  @Prop navBarHeight: number = 0;
  @Prop isActive: boolean = true;
  @Prop pageMode: boolean = false;

  @State sources: rssSources[] = [];
  @State visibleSources: rssSources[] = [];
  @State groupNames: string[] = [];
  @State activeGroup: string = '__all__';
  @State searchText: string = '';
  @State history: rssSourcesHistory[] = [];
  @State loading: boolean = true;
  @State selectionMode: boolean = false;
  @State selectedUrls: Record<string, boolean> = {};
  @State showAddMenu: boolean = false;
  @StorageLink('subscriptionLayoutMode') layoutMode: string = 'list';
  @State showLayoutMenu: boolean = false;
  @State showNewGroupDialog: boolean = false;
  @State newGroupName: string = '';
  @State showItemMenu: boolean = false;
  @State menuSourceUrl: string = '';
  @State menuSourceIndex: number = -1;
  @State showMoveGroupDialog: boolean = false;
  @State moveGroupTarget: string = '';
  @State showDeleteDialog: boolean = false;
  @State showHistory: boolean = true;
  @State listVersion: number = 0;
  @State showEditDialog: boolean = false;
  @State showRenameDialog: boolean = false;
  @State renameSourceName: string = '';
  @State editSourceId: number = 0;
  @State editSourceUrl: string = '';
  @State editSourceName: string = '';
  @State editSourceGroup: string = '';
  @State editSourceType: number = 0;
  @State editSourceIcon: string = '';
  @State editSourceIconIsUrl: boolean = true;
  @State editSourceEnabled: boolean = true;
  @State editCustomizeTitle: string = '';
  @State editSourceComment: string = '';
  @StorageLink('rssSourcesVersion') @Watch('onRssSourcesVersionChanged') rssSourcesVersion: number = 0;

  aboutToAppear(): void {
    AppStorage.setOrCreate('subscriptionLayoutMode', 'list');
    this.refresh();
  }

  onRssSourcesVersionChanged(): void {
    this.refresh();
  }

  refresh(): void {
    this.loading = true;
    AppDatabase.getInstance().getRssSources().then((list: rssSources[]) => {
      this.sources = list;
      this.rebuildGroups();
      this.applyFilter();
      this.loading = false;
      this.loadHistory();
    }).catch(() => {
      this.sources = [];
      this.applyFilter();
      this.loading = false;
    });
  }

  loadHistory(): void {
    AppDatabase.getInstance().getRssSourcesHistory().then((list: rssSourcesHistory[]) => {
      this.history = list;
    }).catch(() => {
      this.history = [];
    });
  }

  rebuildGroups(): void {
    const names: string[] = [];
    for (let i = 0; i < this.sources.length; i++) {
      const g = this.sources[i].sourceGroup;
      if (g.length > 0 && !names.includes(g)) {
        names.push(g);
      }
    }
    this.groupNames = names;
  }

  applyFilter(): void {
    const kw = this.searchText.trim();
    const filtered: rssSources[] = [];
    for (let i = 0; i < this.sources.length; i++) {
      const item = this.sources[i];
      if (this.activeGroup !== '__all__' && item.sourceGroup !== this.activeGroup) {
        continue;
      }
      if (kw.length > 0 && item.sourceName.indexOf(kw) < 0 && item.sourceUrl.indexOf(kw) < 0) {
        continue;
      }
      filtered.push(item);
    }
    this.visibleSources = filtered;
    this.listVersion++;
  }

  enterSelectionMode(): void {
    this.selectionMode = true;
    this.selectedUrls = {};
  }

  exitSelectionMode(): void {
    this.selectionMode = false;
    this.selectedUrls = {};
  }

  toggleSelect(url: string): void {
    const next: Record<string, boolean> = {};
    for (const key of Object.keys(this.selectedUrls)) {
      next[key] = this.selectedUrls[key];
    }
    next[url] = !(this.selectedUrls[url] ?? false);
    this.selectedUrls = next;
  }

  selectedCount(): number {
    let count = 0;
    for (const key of Object.keys(this.selectedUrls)) {
      if (this.selectedUrls[key]) {
        count++;
      }
    }
    return count;
  }

  selectedAll(): boolean {
    if (this.visibleSources.length === 0) {
      return false;
    }
    return this.selectedCount() >= this.visibleSources.length;
  }

  toggleSelectAll(): void {
    const next: Record<string, boolean> = {};
    const all = !this.selectedAll();
    for (let i = 0; i < this.visibleSources.length; i++) {
      next[this.visibleSources[i].sourceUrl] = all;
    }
    this.selectedUrls = next;
  }

  openSource(item: rssSources): void {
    const record = new rssSourcesHistory();
    record.sourceType = item.sourceType;
    record.sourceName = item.sourceName;
    record.sourceUrl = item.sourceUrl;
    record.sourceIcon = item.sourceIcon;
    record.sourceIconIsUrl = item.sourceIconIsUrl;
    record.sourceGroup = item.sourceGroup;
    record.lastUpdateTime = item.lastUpdateTime;
    record.showRecentIcon = item.showRecentIcon;
    record.customizeTitle = item.customizeTitle;
    rssSourcesUtil.pushRssSourcesHistory(record);
    const upd = item;
    upd.showRecentIcon = false;
    upd.lastUpdateTime = Date.now();
    AppDatabase.getInstance().updateRssSourceRecentIcon(upd).then(() => {
      this.refresh();
    }).catch(() => {
    });
    router.pushUrl({
      url: 'pages/SubscriptionWebView',
      params: {
        sourceUrl: item.sourceUrl,
        sourceName: item.sourceName,
        sourceIcon: item.sourceIcon,
        sourceIconIsUrl: item.sourceIconIsUrl ? 'true' : 'false',
        sourceGroup: item.sourceGroup,
        customizeTitle: item.customizeTitle
      }
    });
  }

  openHistory(item: rssSourcesHistory): void {
    router.pushUrl({
      url: 'pages/SubscriptionWebView',
      params: {
        sourceUrl: item.sourceUrl,
        sourceName: item.sourceName,
        sourceIcon: item.sourceIcon,
        sourceIconIsUrl: item.sourceIconIsUrl ? 'true' : 'false',
        sourceGroup: item.sourceGroup,
        customizeTitle: item.customizeTitle
      }
    });
  }

  toggleEnabled(item: rssSources): void {
    const upd = item;
    upd.enabled = !upd.enabled;
    AppDatabase.getInstance().updateRssSource(upd).then(() => {
      this.refresh();
    }).catch(() => {
      promptAction.showToast({ message: '状态更新失败' });
    });
  }

  batchSetEnabled(enabled: boolean): void {
    const targets: rssSources[] = [];
    for (let i = 0; i < this.visibleSources.length; i++) {
      const item = this.visibleSources[i];
      if (this.selectedUrls[item.sourceUrl] ?? false) {
        const upd = item;
        upd.enabled = enabled;
        targets.push(upd);
      }
    }
    if (targets.length === 0) {
      promptAction.showToast({ message: '请先选择订阅源' });
      return;
    }
    const db = AppDatabase.getInstance();
    let chain: Promise<boolean> = Promise.resolve(true);
    for (let i = 0; i < targets.length; i++) {
      const item = targets[i];
      chain = chain.then(() => db.updateRssSource(item));
    }
    chain.then(() => {
      this.refresh();
      this.exitSelectionMode();
      promptAction.showToast({ message: `已${enabled ? '启用' : '禁用'} ${targets.length} 个订阅源` });
    }).catch(() => {
      promptAction.showToast({ message: '批量操作失败' });
    });
  }

  batchDelete(): void {
    const targets: rssSources[] = [];
    for (let i = 0; i < this.visibleSources.length; i++) {
      const item = this.visibleSources[i];
      if (this.selectedUrls[item.sourceUrl] ?? false) {
        targets.push(item);
      }
    }
    if (targets.length === 0) {
      promptAction.showToast({ message: '请先选择订阅源' });
      return;
    }
    AppDatabase.getInstance().deleteRssSourcesList(targets).then((ok: boolean) => {
      if (ok) {
        this.refresh();
        this.exitSelectionMode();
        promptAction.showToast({ message: `已删除 ${targets.length} 个订阅源` });
      } else {
        promptAction.showToast({ message: '删除失败' });
      }
    }).catch(() => {
      promptAction.showToast({ message: '删除失败' });
    });
  }

  openItemMenu(item: rssSources, index: number): void {
    this.menuSourceUrl = item.sourceUrl;
    this.menuSourceIndex = index;
    this.showItemMenu = true;
  }

  menuItemSource(): rssSources | null {
    for (let i = 0; i < this.visibleSources.length; i++) {
      if (this.visibleSources[i].sourceUrl === this.menuSourceUrl) {
        return this.visibleSources[i];
      }
    }
    return null;
  }

  deleteMenuItem(): void {
    const item = this.menuItemSource();
    if (!item) {
      return;
    }
    AppDatabase.getInstance().deleteRssSources(item).then((ok: boolean) => {
      this.showItemMenu = false;
      if (ok) {
        this.refresh();
        promptAction.showToast({ message: '删除成功' });
      } else {
        promptAction.showToast({ message: '删除失败' });
      }
    }).catch(() => {
      this.showItemMenu = false;
      promptAction.showToast({ message: '删除失败' });
    });
  }

  openMoveGroupDialog(): void {
    this.showItemMenu = false;
    this.showMoveGroupDialog = true;
  }

  openEditDialog(): void {
    const item = this.menuItemSource();
    if (!item) {
      return;
    }
    this.editSourceId = item.id ?? 0;
    this.editSourceUrl = item.sourceUrl;
    this.editSourceName = item.sourceName;
    this.editSourceGroup = item.sourceGroup;
    this.editSourceType = item.sourceType;
    this.editSourceIcon = item.sourceIcon;
    this.editSourceIconIsUrl = item.sourceIconIsUrl;
    this.editSourceEnabled = item.enabled;
    this.editCustomizeTitle = item.customizeTitle;
    this.editSourceComment = item.sourceComment;
    this.showItemMenu = false;
    this.showEditDialog = true;
  }

  confirmEdit(): void {
    const name = this.editSourceName.trim();
    const url = this.editSourceUrl.trim();
    if (name.length === 0) {
      promptAction.showToast({ message: '请输入源名称' });
      return;
    }
    if (url.length === 0) {
      promptAction.showToast({ message: '请输入源地址' });
      return;
    }
    const item = this.menuItemSource();
    if (!item) {
      promptAction.showToast({ message: '源不存在或已变更' });
      return;
    }
    const upd = item;
    upd.sourceName = name;
    upd.sourceUrl = url;
    upd.sourceGroup = this.editSourceGroup.trim();
    upd.sourceType = this.editSourceType;
    upd.sourceIcon = this.editSourceIcon.trim();
    upd.sourceIconIsUrl = this.editSourceIconIsUrl;
    upd.enabled = this.editSourceEnabled;
    upd.customizeTitle = this.editCustomizeTitle;
    upd.sourceComment = this.editSourceComment.trim();
    AppDatabase.getInstance().updateRssSource(upd).then((ok: boolean) => {
      this.showEditDialog = false;
      if (ok) {
        AppStorage.setOrCreate('rssSourcesVersion', (AppStorage.get<number>('rssSourcesVersion') ?? 0) + 1);
        promptAction.showToast({ message: '保存成功' });
      } else {
        promptAction.showToast({ message: '保存失败' });
      }
    }).catch(() => {
      this.showEditDialog = false;
      promptAction.showToast({ message: '保存失败' });
    });
  }

  batchMoveToGroup(): void {
    const targets: rssSources[] = [];
    for (let i = 0; i < this.visibleSources.length; i++) {
      const item = this.visibleSources[i];
      if (this.selectedUrls[item.sourceUrl] ?? false) {
        targets.push(item);
      }
    }
    if (targets.length === 0) {
      promptAction.showToast({ message: '请先选择订阅源' });
      return;
    }
    this.moveGroupTarget = '';
    this.showMoveGroupDialog = true;
  }

  confirmMoveGroup(): void {
    if (this.moveGroupTarget.length === 0) {
      promptAction.showToast({ message: '请选择分组' });
      return;
    }
    if (this.selectionMode) {
      const targets: rssSources[] = [];
      for (let i = 0; i < this.visibleSources.length; i++) {
        const item = this.visibleSources[i];
        if (this.selectedUrls[item.sourceUrl] ?? false) {
          const upd = item;
          upd.sourceGroup = this.moveGroupTarget;
          targets.push(upd);
        }
      }
      if (targets.length === 0) {
        promptAction.showToast({ message: '请先选择订阅源' });
        return;
      }
      const db = AppDatabase.getInstance();
      let chain: Promise<boolean> = Promise.resolve(true);
      for (let i = 0; i < targets.length; i++) {
        const item = targets[i];
        chain = chain.then(() => db.updateRssSource(item));
      }
      chain.then(() => {
        this.showMoveGroupDialog = false;
        this.moveGroupTarget = '';
        this.refresh();
        this.exitSelectionMode();
        promptAction.showToast({ message: `已移动 ${targets.length} 个订阅源` });
      }).catch(() => {
        this.showMoveGroupDialog = false;
        promptAction.showToast({ message: '移动失败' });
      });
      return;
    }
    const item = this.menuItemSource();
    if (!item) {
      promptAction.showToast({ message: '源不存在或已变更' });
      return;
    }
    const upd = item;
    upd.sourceGroup = this.moveGroupTarget;
    AppDatabase.getInstance().updateRssSource(upd).then((ok: boolean) => {
      this.showMoveGroupDialog = false;
      this.moveGroupTarget = '';
      if (ok) {
        this.refresh();
        promptAction.showToast({ message: '移动成功' });
      } else {
        promptAction.showToast({ message: '移动失败' });
      }
    }).catch(() => {
      this.showMoveGroupDialog = false;
      promptAction.showToast({ message: '移动失败' });
    });
  }

  createNewGroup(): void {
    const name = this.newGroupName.trim();
    if (name.length === 0) {
      promptAction.showToast({ message: '请输入分组名称' });
      return;
    }
    if (this.groupNames.includes(name)) {
      promptAction.showToast({ message: '分组名称已存在' });
      return;
    }
    rssSourcesUtil.addGroupType(name).then((ok: boolean) => {
      this.showNewGroupDialog = false;
      this.newGroupName = '';
      if (ok) {
        this.rebuildGroups();
        promptAction.showToast({ message: '新建分组成功' });
      } else {
        promptAction.showToast({ message: '新建分组失败' });
      }
    }).catch(() => {
      this.showNewGroupDialog = false;
      promptAction.showToast({ message: '新建分组失败' });
    });
  }

  openRenameDialog(): void {
    const item = this.menuItemSource();
    if (!item) {
      return;
    }
    this.renameSourceName = item.sourceName;
    this.showItemMenu = false;
    this.showRenameDialog = true;
  }

  confirmRenameSource(): void {
    const name = this.renameSourceName.trim();
    if (name.length === 0) {
      promptAction.showToast({ message: '请输入收藏名' });
      return;
    }
    const item = this.menuItemSource();
    if (!item) {
      promptAction.showToast({ message: '源不存在或已变更' });
      return;
    }
    const upd = item;
    upd.sourceName = name;
    AppDatabase.getInstance().updateRssSource(upd).then((ok: boolean) => {
      this.showRenameDialog = false;
      if (ok) {
        this.refresh();
        promptAction.showToast({ message: '已修改收藏名' });
      } else {
        promptAction.showToast({ message: '修改失败' });
      }
    }).catch(() => {
      this.showRenameDialog = false;
      promptAction.showToast({ message: '修改失败' });
    });
  }

  confirmDeleteHistoryItem(sourceUrl: string): void {
    promptAction.showDialog({
      title: '删除访问记录',
      message: '确定删除该条最近使用记录吗？',
      buttons: [
        { text: '取消', color: this.secondaryTextColor() },
        { text: '删除', color: this.accentColor() }
      ]
    }).then((result: promptAction.ShowDialogSuccessResponse) => {
      if (result.index === 1) {
        this.deleteHistoryItemNow(sourceUrl);
      }
    }).catch(() => {
    });
  }

  deleteHistoryItemNow(sourceUrl: string): void {
    AppDatabase.getInstance().deleteRssSourcesHistory(sourceUrl).then((ok: boolean) => {
      if (ok) {
        this.refreshHistory();
        promptAction.showToast({ message: '已删除该条记录' });
      } else {
        promptAction.showToast({ message: '删除失败' });
      }
    }).catch(() => {
      promptAction.showToast({ message: '删除失败' });
    });
  }

  refreshHistory(): void {
    AppDatabase.getInstance().getRssSourcesHistory().then((rows: rssSourcesHistory[]) => {
      this.history = rows;
    }).catch(() => {
    });
  }

  confirmClearHistory(): void {
    promptAction.showDialog({
      title: '清空访问记录',
      message: '确定清空最近使用记录吗？',
      buttons: [
        { text: '取消', color: this.secondaryTextColor() },
        { text: '清空', color: ThemeRuntime.dangerColor(this.appDarkMode) }
      ]
    }).then((result: promptAction.ShowDialogSuccessResponse) => {
      if (result.index === 1) {
        this.clearHistoryNow();
      }
    }).catch(() => {
    });
  }

  clearHistoryNow(): void {
    AppDatabase.getInstance().clearRssSourcesHistory().then((ok: boolean) => {
      if (ok) {
        this.history = [];
        promptAction.showToast({ message: '已清空访问记录' });
      } else {
        promptAction.showToast({ message: '清空失败' });
      }
    }).catch(() => {
      promptAction.showToast({ message: '清空失败' });
    });
  }

  statusBarTop(): number {
    return this.statusBarHeight > 0 ? this.statusBarHeight : this.statusBarHeightProp;
  }

  navBarBottom(): number {
    return this.navBarHeight > 0 ? this.navBarHeight : this.navBarHeightProp;
  }

  pageColor(): string {
    return ThemeRuntime.pageColor(this.appDarkMode);
  }

  cardColor(): string {
    return ThemeRuntime.cardColor(this.appDarkMode);
  }

  inputColor(): string {
    return ThemeRuntime.inputColor(this.appDarkMode);
  }

  glassCardColor(): string {
    return ThemeRuntime.cardColor(this.appDarkMode);
  }

  glassBorderColor(): string {
    return this.appDarkMode ? '#262A31' : '#FFFFFF';
  }

  glassShadowColor(): string {
    return '#00000000';
  }

  primaryTextColor(): string {
    return ThemeRuntime.primaryTextColor(this.appDarkMode);
  }

  secondaryTextColor(): string {
    return ThemeRuntime.subTextColor(this.appDarkMode);
  }

  accentColor(): string {
    return ThemeRuntime.accentColor(this.appDarkMode);
  }

  buttonColor(): string {
    return ThemeRuntime.buttonColor(this.appDarkMode);
  }

  placeholderTextColor(): string {
    return this.appDarkMode ? 'rgba(255,255,255,0.32)' : 'rgba(0,0,0,0.32)';
  }

  enabledColor(): string {
    return this.appDarkMode ? '#24B277' : '#1A9E6B';
  }

  sourceBadgeColor(sourceType: number): string {
    return sourceType === 1 ? '#24B277' : '#4E9BFF';
  }

  initialOf(name: string): string {
    if (name.length === 0) {
      return 'R';
    }
    return name.substring(0, 1);
  }

  avatarBg(seed: string): string {
    const palette: string[] = ['#5B8DEF', '#24B277', '#E67E22', '#9B59B6', '#E74C3C', '#16A085', '#F39C12', '#8E44AD'];
    let h = 0;
    for (let i = 0; i < seed.length; i++) {
      h = (h * 31 + seed.charCodeAt(i)) % 997;
    }
    return palette[h % palette.length];
  }

  @Builder
  headerBar() {
    Row() {
      if (this.pageMode) {
        ImmersiveBackButton({
          iconColor: this.primaryTextColor(),
          darkMode: this.appDarkMode,
          buttonSize: 40,
          containerWidth: 56,
          materialScale: 0.83,
          compactLayout: true,
          onBack: () => router.back()
        })
      }

      if (this.selectionMode) {
        Text(this.selectedAll() ? '取消全选' : '全选')
          .fontSize(15)
          .fontColor(this.primaryTextColor())
          .width(64)
          .height(40)
          .textAlign(TextAlign.Center)
          .onClick(() => this.toggleSelectAll())
        Blank()
        Text(`已选 ${this.selectedCount()} 项`)
          .fontSize(14)
          .fontColor(this.secondaryTextColor())
        Blank()
        Text('完成')
          .fontSize(15)
          .fontColor(this.accentColor())
          .width(64)
          .height(40)
          .textAlign(TextAlign.Center)
          .onClick(() => this.exitSelectionMode())
      } else {
        Text(this.pageMode ? '订阅管理' : '订阅')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.primaryTextColor())
          .layoutWeight(1)

        Row({ space: 2 }) {
          SymbolGlyph(this.layoutMode === 'tile' ? $r('sys.symbol.square_grid_2x2') : $r('sys.symbol.list_bullet'))
            .fontSize(21)
            .fontColor([this.primaryTextColor()])
            .width(40)
            .height(40)
            .accessibilityText('切换排版')
            .onClick(() => {
              this.showLayoutMenu = !this.showLayoutMenu;
            })
          SymbolGlyph($r('sys.symbol.timer'))
            .fontSize(21)
            .fontColor([this.primaryTextColor()])
            .width(40)
            .height(40)
            .accessibilityText('最近使用')
            .onClick(() => {
              this.showHistory = !this.showHistory;
            })
          SymbolGlyph($r('sys.symbol.plus'))
            .fontSize(22)
            .fontColor([this.accentColor()])
            .width(44)
            .height(44)
            .accessibilityText('添加订阅')
            .onClick(() => {
              this.showAddMenu = true;
            })
        }
      }
    }
    .width('100%')
    .height(56 + this.statusBarTop())
    .padding({ left: this.pageMode ? 0 : 16, right: 16, top: this.statusBarTop() })
    .backgroundColor(ThemeRuntime.topBarColor(this.appDarkMode))
    .backdropBlur(ThemeRuntime.topBarBlur())
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  searchBar() {
    Row() {
      if (!this.selectionMode) {
        Row() {
          SymbolGlyph($r('sys.symbol.magnifyingglass'))
            .fontSize(16)
            .fontColor([this.secondaryTextColor()])
          TextInput({ placeholder: '搜索订阅', text: this.searchText })
            .layoutWeight(1)
            .height(40)
            .fontSize(15)
            .fontColor(this.primaryTextColor())
            .placeholderColor(this.placeholderTextColor())
            .backgroundColor('#00000000')
            .onChange((value: string) => {
              this.searchText = value;
              this.applyFilter();
            })
          if (this.searchText.length > 0) {
            SymbolGlyph($r('sys.symbol.xmark_circle_fill'))
              .fontSize(16)
              .fontColor([this.secondaryTextColor()])
              .onClick(() => {
                this.searchText = '';
                this.applyFilter();
              })
          }
        }
        .layoutWeight(1)
        .height(40)
        .padding({ left: 12, right: 12 })
        .borderRadius(20)
        .backgroundColor(this.inputColor())
        .alignItems(VerticalAlign.Center)
      } else {
        Text(`已选 ${this.selectedCount()} 项`)
          .fontSize(14)
          .fontColor(this.secondaryTextColor())
        Blank()
        Text('完成')
          .fontSize(15)
          .fontColor(this.accentColor())
          .onClick(() => this.exitSelectionMode())
      }
    }
    .width('100%')
    .height(52)
    .padding({ left: 16, right: 16 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  groupBar() {
    Scroll() {
      Row({ space: 8 }) {
        this.groupChip('__all__', '全部', this.activeGroup === '__all__')
        ForEach(this.groupNames, (name: string) => {
          this.groupChip(name, name, this.activeGroup === name)
        })
        Row({ space: 4 }) {
          SymbolGlyph($r('sys.symbol.plus'))
            .fontSize(14)
            .fontColor([this.accentColor()])
          Text('分组')
            .fontSize(13)
            .fontColor(this.accentColor())
        }
        .height(32)
        .padding({ left: 12, right: 12 })
        .borderRadius(16)
        .backgroundColor(this.inputColor())
        .alignItems(VerticalAlign.Center)
        .onClick(() => {
          this.showNewGroupDialog = true;
        })
      }
      .padding({ left: 16, right: 16 })
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .height(44)
    .align(Alignment.Start)
  }

  @Builder
  groupChip(key: string, label: string, active: boolean) {
    Text(label)
      .fontSize(13)
      .fontWeight(active ? FontWeight.Medium : FontWeight.Regular)
      .fontColor(active ? '#FFFFFF' : this.primaryTextColor())
      .height(32)
      .padding({ left: 14, right: 14 })
      .borderRadius(16)
      .backgroundColor(active ? this.accentColor() : this.inputColor())
      .textAlign(TextAlign.Center)
      .onClick(() => {
        this.activeGroup = key;
        this.applyFilter();
      })
  }

  @Builder
  historyStrip() {
    if (this.history.length > 0 && !this.selectionMode) {
      Column({ space: 8 }) {
        Row() {
          Text('最近使用')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.primaryTextColor())
          Blank()
          Row({ space: 4 }) {
            SymbolGlyph($r('sys.symbol.trash'))
              .fontSize(14)
              .fontColor([this.secondaryTextColor()])
            Text('清空')
              .fontSize(13)
              .fontColor(this.secondaryTextColor())
          }
          .padding({ left: 10, right: 10, top: 4, bottom: 4 })
          .borderRadius(12)
          .backgroundColor(this.inputColor())
          .onClick(() => {
            this.confirmClearHistory();
          })
        }
        .width('100%')

        Scroll() {
          Row({ space: 12 }) {
            ForEach(this.history, (item: rssSourcesHistory) => {
              Column({ space: 6 }) {
                Stack({ alignContent: Alignment.Center }) {
                  Circle()
                    .width(44)
                    .height(44)
                    .fill(this.avatarBg(item.sourceUrl))
                  Text(this.initialOf(item.sourceName))
                    .fontSize(16)
                    .fontWeight(FontWeight.Medium)
                    .fontColor('#FFFFFF')
                }
                Text(item.sourceName)
                  .fontSize(11)
                  .fontColor(this.secondaryTextColor())
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .width(60)
                  .textAlign(TextAlign.Center)
              }
              .onClick(() => this.openHistory(item))
              .gesture(LongPressGesture().onAction(() => {
                this.confirmDeleteHistoryItem(item.sourceUrl);
              }))
            })
          }
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 4, bottom: 8 })
    }
  }

  @Builder
  sourceList() {
    if (this.loading) {
      Column({ space: 12 }) {
        LoadingProgress()
          .width(44)
          .height(44)
          .color(this.accentColor())
        Text('加载中...')
          .fontSize(13)
          .fontColor(this.secondaryTextColor())
      }
      .width('100%')
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
    } else if (this.visibleSources.length === 0) {
      Column({ space: 10 }) {
        SymbolGlyph($r('sys.symbol.bookshelf'))
          .fontSize(52)
          .fontColor([this.secondaryTextColor()])
        Text('暂无订阅源')
          .fontSize(15)
          .fontColor(this.primaryTextColor())
        Text('点击右上角 + 添加订阅')
          .fontSize(13)
          .fontColor(this.secondaryTextColor())
        Button('添加订阅')
          .height(38)
          .fontSize(14)
          .backgroundColor(this.buttonColor())
          .fontColor('#FFFFFF')
          .margin({ top: 8 })
          .onClick(() => {
            this.showAddMenu = true;
          })
      }
      .width('100%')
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
    } else if (this.layoutMode === 'tile') {
      Grid() {
        ForEach(this.visibleSources, (item: rssSources, index: number) => {
          GridItem() {
            this.sourceTile(item, index)
          }
        })
      }
      .columnsTemplate('1fr 1fr')
      .columnsGap(10)
      .rowsGap(10)
      .width('100%')
      .layoutWeight(1)
      .padding({ left: 16, right: 16, top: 4, bottom: this.navBarBottom() })
      .scrollBar(BarState.Off)
    } else {
      List({ space: 10 }) {
        ForEach(this.visibleSources, (item: rssSources, index: number) => {
          ListItem() {
            this.sourceRow(item, index)
          }
        })
      }
      .width('100%')
      .layoutWeight(1)
      .padding({ left: 16, right: 16, top: 4, bottom: this.navBarBottom() })
      .scrollBar(BarState.Off)
    }
  }

  @Builder
  sourceRow(item: rssSources, index: number) {
    Row({ space: 12 }) {
      if (this.selectionMode) {
        SymbolGlyph(this.selectedUrls[item.sourceUrl] ?? false ? $r('sys.symbol.checkmark_circle_fill') :
          $r('sys.symbol.circle'))
          .fontSize(22)
          .fontColor([this.selectedUrls[item.sourceUrl] ?? false ? this.accentColor() : this.secondaryTextColor()])
          .onClick(() => this.toggleSelect(item.sourceUrl))
      } else {
        Stack({ alignContent: Alignment.Center }) {
          Circle()
            .width(42)
            .height(42)
            .fill(this.avatarBg(item.sourceUrl))
          if (item.sourceIconIsUrl && item.sourceIcon.length > 0) {
            Image(item.sourceIcon)
              .width(38)
              .height(38)
              .borderRadius(19)
              .objectFit(ImageFit.Cover)
          } else {
            Text(this.initialOf(item.sourceName))
              .fontSize(17)
              .fontWeight(FontWeight.Medium)
              .fontColor('#FFFFFF')
          }
          if (item.enabled) {
            Circle()
              .width(10)
              .height(10)
              .fill(this.enabledColor())
              .position({ x: 32, y: 32 })
              .border({ width: 1.5, color: this.cardColor() })
          }
        }
      }

      Column({ space: 3 }) {
        Row({ space: 6 }) {
          Text(item.sourceName.length > 0 ? item.sourceName : item.sourceUrl)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.primaryTextColor())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(SUBSCRIPTION_TYPE[item.sourceType] ?? '订阅源')
            .fontSize(10)
            .fontColor('#FFFFFF')
            .height(18)
            .padding({ left: 6, right: 6 })
            .borderRadius(9)
            .backgroundColor(this.sourceBadgeColor(item.sourceType))
            .textAlign(TextAlign.Center)
        }
        .width('100%')

        Text(item.sourceUrl)
          .fontSize(12)
          .fontColor(this.secondaryTextColor())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      if (this.selectionMode) {
        Text('选中')
          .fontSize(12)
          .fontColor(this.selectedUrls[item.sourceUrl] ?? false ? this.accentColor() : this.secondaryTextColor())
      } else {
        Toggle({ type: ToggleType.Switch, isOn: item.enabled })
          .selectedColor(this.enabledColor())
          .width(40)
          .height(24)
          .onChange((on: boolean) => {
            const upd = item;
            upd.enabled = on;
            AppDatabase.getInstance().updateRssSource(upd).then(() => {
              this.refresh();
            }).catch(() => {
              promptAction.showToast({ message: '状态更新失败' });
            });
          })
      }
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 12, bottom: 12 })
    .borderRadius(ThemeRuntime.glassCornerRadius(14, 'card'))
    .backgroundColor(this.glassCardColor())
    .border({ width: ThemeRuntime.glassBorderWidth('card'), color: this.glassBorderColor() })
    .shadow({
      radius: ThemeRuntime.glassShadowRadius('card'),
      color: this.glassShadowColor(),
      offsetX: ThemeRuntime.glassShadowOffsetX('card'),
      offsetY: ThemeRuntime.glassShadowOffsetY('card')
    })
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      if (this.selectionMode) {
        this.toggleSelect(item.sourceUrl);
      } else {
        this.openSource(item);
      }
    })
    .gesture(
      LongPressGesture({ repeat: false, duration: 450 })
        .onAction(() => {
          if (!this.selectionMode) {
            this.openItemMenu(item, index);
          }
        })
    )
  }

  @Builder
  sourceTile(item: rssSources, index: number) {
    Column({ space: 8 }) {
      Row() {
        if (this.selectionMode) {
          SymbolGlyph(this.selectedUrls[item.sourceUrl] ?? false ? $r('sys.symbol.checkmark_circle_fill') :
            $r('sys.symbol.circle'))
            .fontSize(22)
            .fontColor([this.selectedUrls[item.sourceUrl] ?? false ? this.accentColor() : this.secondaryTextColor()])
            .onClick(() => this.toggleSelect(item.sourceUrl))
        } else {
          Toggle({ type: ToggleType.Switch, isOn: item.enabled })
            .selectedColor(this.enabledColor())
            .width(40)
            .height(24)
            .onChange((on: boolean) => {
              const upd = item;
              upd.enabled = on;
              AppDatabase.getInstance().updateRssSource(upd).then(() => {
                this.refresh();
              }).catch(() => {
                promptAction.showToast({ message: '状态更新失败' });
              });
            })
        }
      }
      .width('100%')
      .height(26)
      .alignItems(VerticalAlign.Center)

      Stack({ alignContent: Alignment.Center }) {
        Circle()
          .width(52)
          .height(52)
          .fill(this.avatarBg(item.sourceUrl))
        if (item.sourceIconIsUrl && item.sourceIcon.length > 0) {
          Image(item.sourceIcon)
            .width(46)
            .height(46)
            .borderRadius(23)
            .objectFit(ImageFit.Cover)
        } else {
          Text(this.initialOf(item.sourceName))
            .fontSize(20)
            .fontWeight(FontWeight.Medium)
            .fontColor('#FFFFFF')
        }
        if (item.enabled) {
          Circle()
            .width(11)
            .height(11)
            .fill(this.enabledColor())
            .position({ x: 40, y: 40 })
            .border({ width: 1.5, color: this.cardColor() })
        }
      }

      Column({ space: 4 }) {
        Row({ space: 4 }) {
          Text(item.sourceName.length > 0 ? item.sourceName : item.sourceUrl)
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.primaryTextColor())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          Text(SUBSCRIPTION_TYPE[item.sourceType] ?? '订阅源')
            .fontSize(10)
            .fontColor('#FFFFFF')
            .height(18)
            .padding({ left: 6, right: 6 })
            .borderRadius(9)
            .backgroundColor(this.sourceBadgeColor(item.sourceType))
            .textAlign(TextAlign.Center)
        }
        .width('100%')

        Text(item.sourceUrl)
          .fontSize(11)
          .fontColor(this.secondaryTextColor())
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding(14)
    .borderRadius(ThemeRuntime.glassCornerRadius(14, 'card'))
    .backgroundColor(this.glassCardColor())
    .border({ width: ThemeRuntime.glassBorderWidth('card'), color: this.glassBorderColor() })
    .shadow({
      radius: ThemeRuntime.glassShadowRadius('card'),
      color: this.glassShadowColor(),
      offsetX: ThemeRuntime.glassShadowOffsetX('card'),
      offsetY: ThemeRuntime.glassShadowOffsetY('card')
    })
    .alignItems(HorizontalAlign.Center)
    .onClick(() => {
      if (this.selectionMode) {
        this.toggleSelect(item.sourceUrl);
      } else {
        this.openSource(item);
      }
    })
    .gesture(
      LongPressGesture({ repeat: false, duration: 450 })
        .onAction(() => {
          if (!this.selectionMode) {
            this.openItemMenu(item, index);
          }
        })
    )
  }

  @Builder
  addMenu() {
    Column({ space: 4 }) {
      this.menuItem('新建订阅', () => {
        this.showAddMenu = false;
        router.pushUrl({ url: 'pages/SubscriptionImport' });
      })
      this.menuItem('从 URL / 文本导入', () => {
        this.showAddMenu = false;
        router.pushUrl({ url: 'pages/SubscriptionImport', params: { mode: 'import' } });
      })
      this.menuItem('批量管理', () => {
        this.showAddMenu = false;
        this.enterSelectionMode();
      })
      this.menuItem('分组管理', () => {
        this.showAddMenu = false;
        this.showNewGroupDialog = true;
      })
    }
    .margin({ top: 132, right: 16 })
    .width(168)
    .padding(6)
    .borderRadius(ThemeRuntime.glassCornerRadius(14, 'menu'))
    .backgroundColor(ThemeRuntime.dropdownPanelColor(this.appDarkMode, '', 'menu'))
    .backdropBlur(ThemeRuntime.glassBlur('menu', 22))
    .border({ width: ThemeRuntime.glassBorderWidth('menu'), color: ThemeRuntime.glassBorderColor(this.appDarkMode, 'menu') })
    .shadow({
      radius: ThemeRuntime.glassShadowRadius('menu'),
      color: ThemeRuntime.glassShadowColor(this.appDarkMode, 'menu'),
      offsetX: ThemeRuntime.glassShadowOffsetX('menu'),
      offsetY: ThemeRuntime.glassShadowOffsetY('menu')
    })
  }

  @Builder
  menuItem(label: string, action: () => void) {
    Row({ space: 10 }) {
      Text(label)
        .fontSize(14)
        .fontColor(this.primaryTextColor())
    }
    .width('100%')
    .height(40)
    .padding({ left: 12, right: 12 })
    .borderRadius(10)
    .alignItems(VerticalAlign.Center)
    .onClick(() => action())
  }

  @Builder
  layoutMenu() {
    Column({ space: 4 }) {
      this.layoutMenuItem('列表', 'list', $r('sys.symbol.list_bullet'))
      this.layoutMenuItem('平铺', 'tile', $r('sys.symbol.square_grid_2x2'))
    }
    .margin({ top: 112, right: 16 })
    .width(132)
    .padding(6)
    .borderRadius(ThemeRuntime.glassCornerRadius(14, 'menu'))
    .backgroundColor(ThemeRuntime.dropdownPanelColor(this.appDarkMode, '', 'menu'))
    .backdropBlur(ThemeRuntime.glassBlur('menu', 22))
    .border({ width: ThemeRuntime.glassBorderWidth('menu'), color: ThemeRuntime.glassBorderColor(this.appDarkMode, 'menu') })
    .shadow({
      radius: ThemeRuntime.glassShadowRadius('menu'),
      color: ThemeRuntime.glassShadowColor(this.appDarkMode, 'menu'),
      offsetX: ThemeRuntime.glassShadowOffsetX('menu'),
      offsetY: ThemeRuntime.glassShadowOffsetY('menu')
    })
  }

  @Builder
  layoutMenuItem(label: string, mode: string, icon: Resource) {
    Row({ space: 10 }) {
      SymbolGlyph(icon)
        .fontSize(17)
        .fontColor([this.layoutMode === mode ? this.accentColor() : this.secondaryTextColor()])
      Text(label)
        .fontSize(14)
        .fontWeight(this.layoutMode === mode ? FontWeight.Medium : FontWeight.Regular)
        .fontColor(this.layoutMode === mode ? this.accentColor() : this.primaryTextColor())
        .layoutWeight(1)

      if (this.layoutMode === mode) {
        SymbolGlyph($r('sys.symbol.checkmark'))
          .fontSize(14)
          .fontColor([this.accentColor()])
      }
    }
    .width('100%')
    .height(38)
    .padding({ left: 10, right: 10 })
    .borderRadius(10)
    .backgroundColor(this.layoutMode === mode ? this.inputColor() : '#00000000')
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      this.layoutMode = mode;
      this.showLayoutMenu = false;
    })
  }

  @Builder
  itemMenuSheet() {
    Column({ space: 4 }) {
      Text('订阅源操作')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.primaryTextColor())
        .width('100%')
        .padding({ left: 16, right: 16, top: 8, bottom: 8 })

      this.sheetItem('修改收藏名', () => this.openRenameDialog())
      this.sheetItem('编辑', () => this.openEditDialog())
      this.sheetItem('移动至分组', () => this.openMoveGroupDialog())
      this.sheetItem('批量管理', () => {
        this.showItemMenu = false;
        this.enterSelectionMode();
      })
      this.sheetItem('删除', () => this.deleteMenuItem())

      Row() {
        Text('取消')
          .fontSize(15)
          .fontColor(this.secondaryTextColor())
          .width('100%')
          .height(44)
          .textAlign(TextAlign.Center)
      }
      .width('100%')
      .onClick(() => {
        this.showItemMenu = false;
      })
    }
    .width('100%')
  }

  @Builder
  sheetItem(label: string, action: () => void) {
    Text(label)
      .fontSize(15)
      .fontColor(this.primaryTextColor())
      .width('100%')
      .height(46)
      .padding({ left: 16, right: 16 })
      .onClick(() => action())
  }

  @Builder
  moveGroupSheet() {
    Column({ space: 4 }) {
      Text('移动至分组')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.primaryTextColor())
        .width('100%')
        .padding({ left: 16, right: 16, top: 8, bottom: 8 })

      Scroll() {
        Column({ space: 4 }) {
          ForEach(this.groupNames, (name: string) => {
            Row() {
              Text(name)
                .fontSize(15)
                .fontColor(this.moveGroupTarget === name ? this.accentColor() : this.primaryTextColor())
                .layoutWeight(1)
              if (this.moveGroupTarget === name) {
                SymbolGlyph($r('sys.symbol.checkmark'))
                  .fontSize(15)
                  .fontColor([this.accentColor()])
              }
            }
            .width('100%')
            .height(44)
            .padding({ left: 16, right: 16 })
            .onClick(() => {
              this.moveGroupTarget = name;
            })
          })
        }
      }
      .width('100%')
      .height(220)
      .scrollBar(BarState.Off)

      Row({ space: 12 }) {
        Button('取消')
          .layoutWeight(1)
          .height(40)
          .fontSize(15)
          .backgroundColor(this.inputColor())
          .fontColor(this.primaryTextColor())
          .onClick(() => {
            this.showMoveGroupDialog = false;
            this.moveGroupTarget = '';
          })
        Button('确认')
          .layoutWeight(1)
          .height(40)
          .fontSize(15)
          .backgroundColor(this.buttonColor())
          .fontColor('#FFFFFF')
          .onClick(() => this.confirmMoveGroup())
      }
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 12 })
    }
    .width('100%')
  }

  @Builder
  editSheet() {
    Column({ space: 8 }) {
      Text('编辑订阅源')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.primaryTextColor())
        .width('100%')
        .padding({ left: 16, right: 16, top: 8, bottom: 4 })

      Scroll() {
        Column({ space: 10 }) {
          this.editField('源名称', this.editSourceName, (v: string) => { this.editSourceName = v })
          this.editField('源地址', this.editSourceUrl, (v: string) => { this.editSourceUrl = v })
          this.editField('分组', this.editSourceGroup, (v: string) => { this.editSourceGroup = v })
          this.editField('图标链接', this.editSourceIcon, (v: string) => { this.editSourceIcon = v })
          this.editField('自定义标题', this.editCustomizeTitle, (v: string) => { this.editCustomizeTitle = v })
          this.editField('备注', this.editSourceComment, (v: string) => { this.editSourceComment = v })

          Row() {
            Text('源类型')
              .fontSize(14)
              .fontColor(this.secondaryTextColor())
              .width(90)
            Blank()
            Row({ space: 8 }) {
              Text('常规网站')
                .fontSize(13)
                .fontColor(this.editSourceType === 0 ? '#FFFFFF' : this.primaryTextColor())
                .height(30)
                .padding({ left: 12, right: 12 })
                .borderRadius(15)
                .backgroundColor(this.editSourceType === 0 ? this.accentColor() : this.inputColor())
                .onClick(() => {
                  this.editSourceType = 0;
                })
              Text('订阅源')
                .fontSize(13)
                .fontColor(this.editSourceType === 1 ? '#FFFFFF' : this.primaryTextColor())
                .height(30)
                .padding({ left: 12, right: 12 })
                .borderRadius(15)
                .backgroundColor(this.editSourceType === 1 ? this.accentColor() : this.inputColor())
                .onClick(() => {
                  this.editSourceType = 1;
                })
            }
          }
          .width('100%')

          Row() {
            Text('图标用链接')
              .fontSize(14)
              .fontColor(this.secondaryTextColor())
              .layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.editSourceIconIsUrl })
              .selectedColor(this.enabledColor())
              .width(40)
              .height(24)
              .onChange((on: boolean) => {
                this.editSourceIconIsUrl = on;
              })
          }
          .width('100%')

          Row() {
            Text('启用')
              .fontSize(14)
              .fontColor(this.secondaryTextColor())
              .layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.editSourceEnabled })
              .selectedColor(this.enabledColor())
              .width(40)
              .height(24)
              .onChange((on: boolean) => {
                this.editSourceEnabled = on;
              })
          }
          .width('100%')
        }
        .width('100%')
        .padding({ left: 16, right: 16 })
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)

      Row({ space: 12 }) {
        Button('取消')
          .layoutWeight(1)
          .height(40)
          .fontSize(15)
          .backgroundColor(this.inputColor())
          .fontColor(this.primaryTextColor())
          .onClick(() => {
            this.showEditDialog = false;
          })
        Button('保存')
          .layoutWeight(1)
          .height(40)
          .fontSize(15)
          .backgroundColor(this.buttonColor())
          .fontColor('#FFFFFF')
          .onClick(() => this.confirmEdit())
      }
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 12 })
    }
    .width('100%')
  }

  @Builder
  editField(label: string, value: string, onChange: (v: string) => void) {
    Row({ space: 10 }) {
      Text(label)
        .fontSize(14)
        .fontColor(this.secondaryTextColor())
        .width(90)
      TextInput({ placeholder: `请输入${label}`, text: value })
        .layoutWeight(1)
        .height(38)
        .fontSize(14)
        .fontColor(this.primaryTextColor())
        .placeholderColor(this.placeholderTextColor())
        .backgroundColor(this.inputColor())
        .borderRadius(10)
        .onChange((v: string) => {
          onChange(v)
        })
    }
    .width('100%')
  }

  @Builder
  renameSourceDialog() {
    Column({ space: 12 }) {
      Text('修改收藏名')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.primaryTextColor())
        .width('100%')
        .textAlign(TextAlign.Center)

      TextInput({ placeholder: '请输入收藏名', text: this.renameSourceName })
        .width('100%')
        .height(44)
        .fontSize(15)
        .fontColor(this.primaryTextColor())
        .placeholderColor(this.placeholderTextColor())
        .backgroundColor(this.inputColor())
        .borderRadius(10)
        .onChange((value: string) => {
          this.renameSourceName = value;
        })

      Row({ space: 12 }) {
        Button('取消')
          .layoutWeight(1)
          .height(40)
          .fontSize(15)
          .backgroundColor(this.inputColor())
          .fontColor(this.primaryTextColor())
          .onClick(() => {
            this.showRenameDialog = false;
          })
        Button('确认')
          .layoutWeight(1)
          .height(40)
          .fontSize(15)
          .backgroundColor(this.accentColor())
          .fontColor('#FFFFFF')
          .onClick(() => this.confirmRenameSource())
      }
      .width('100%')
      .margin({ top: 8 })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 20, bottom: 20 })
  }

  @Builder
  newGroupDialog() {
    Column({ space: 12 }) {
      Text('新建分组')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.primaryTextColor())
        .width('100%')
        .textAlign(TextAlign.Center)

      TextInput({ placeholder: '请输入分组名称', text: this.newGroupName })
        .width('100%')
        .height(44)
        .fontSize(15)
        .fontColor(this.primaryTextColor())
        .placeholderColor(this.placeholderTextColor())
        .backgroundColor(this.inputColor())
        .borderRadius(10)
        .onChange((value: string) => {
          this.newGroupName = value;
        })

      Row({ space: 12 }) {
        Button('取消')
          .layoutWeight(1)
          .height(40)
          .fontSize(15)
          .backgroundColor(this.inputColor())
          .fontColor(this.primaryTextColor())
          .onClick(() => {
            this.showNewGroupDialog = false;
            this.newGroupName = '';
          })
        Button('确认')
          .layoutWeight(1)
          .height(40)
          .fontSize(15)
          .backgroundColor(this.buttonColor())
          .fontColor('#FFFFFF')
          .onClick(() => this.createNewGroup())
      }
      .width('100%')
    }
    .width('100%')
  }

  @Builder
  batchActionBar() {
    Row({ space: 8 }) {
      Button('启用')
        .layoutWeight(1)
        .height(42)
        .fontSize(14)
        .backgroundColor(this.buttonColor())
        .fontColor('#FFFFFF')
        .onClick(() => this.batchSetEnabled(true))
      Button('禁用')
        .layoutWeight(1)
        .height(42)
        .fontSize(14)
        .backgroundColor(this.inputColor())
        .fontColor(this.primaryTextColor())
        .onClick(() => this.batchSetEnabled(false))
      Button('移动')
        .layoutWeight(1)
        .height(42)
        .fontSize(14)
        .backgroundColor(this.buttonColor())
        .fontColor('#FFFFFF')
        .onClick(() => this.batchMoveToGroup())
      Button('删除')
        .layoutWeight(1)
        .height(42)
        .fontSize(14)
        .backgroundColor(ThemeRuntime.dangerColor(this.appDarkMode))
        .fontColor('#FFFFFF')
        .onClick(() => this.batchDelete())
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 10, bottom: 12 })
    .backgroundColor(this.glassCardColor())
    .border({ width: ThemeRuntime.glassBorderWidth('card'), color: this.glassBorderColor() })
  }

  build() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      Column() {
        this.headerBar()
        this.searchBar()
        if (this.selectionMode) {
          this.batchActionBar()
        }
        if (!this.selectionMode) {
          this.groupBar()
          this.historyStrip()
        }
        this.sourceList()
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.pageColor())

      if (this.showLayoutMenu) {
        Stack({ alignContent: Alignment.TopEnd }) {
          Column()
            .width('100%')
            .height('100%')
            .backgroundColor('#33000000')
            .onClick(() => {
              this.showLayoutMenu = false;
            })
          this.layoutMenu()
        }
        .width('100%')
        .height('100%')
      }

      if (this.showAddMenu) {
        Stack({ alignContent: Alignment.TopEnd }) {
          Column()
            .width('100%')
            .height('100%')
            .backgroundColor('#33000000')
            .onClick(() => {
              this.showAddMenu = false;
            })
          this.addMenu()
        }
        .width('100%')
        .height('100%')
      }
    }
    .width('100%')
    .height('100%')
    .onClick(() => {
      if (this.showAddMenu) {
        this.showAddMenu = false;
      }
      if (this.showLayoutMenu) {
        this.showLayoutMenu = false;
      }
    })
    .bindSheet($$this.showItemMenu, this.itemMenuSheet(), {
      height: 230,
      dragBar: false,
      showClose: false,
      backgroundColor: ThemeRuntime.dropdownPanelColor(this.appDarkMode, '', 'overlay'),
      onDisappear: () => {
        this.showItemMenu = false;
      }
    })
    .bindSheet($$this.showMoveGroupDialog, this.moveGroupSheet(), {
      height: 380,
      dragBar: false,
      showClose: false,
      backgroundColor: ThemeRuntime.dropdownPanelColor(this.appDarkMode, '', 'overlay'),
      onDisappear: () => {
        this.showMoveGroupDialog = false;
        this.moveGroupTarget = '';
      }
    })
    .bindSheet($$this.showEditDialog, this.editSheet(), {
      height: 560,
      dragBar: false,
      showClose: false,
      backgroundColor: ThemeRuntime.dropdownPanelColor(this.appDarkMode, '', 'overlay'),
      onDisappear: () => {
        this.showEditDialog = false;
      }
    })
    .bindSheet($$this.showRenameDialog, this.renameSourceDialog(), {
      height: 260,
      dragBar: false,
      showClose: false,
      backgroundColor: ThemeRuntime.dropdownPanelColor(this.appDarkMode, '', 'overlay'),
      onDisappear: () => {
        this.showRenameDialog = false;
        this.renameSourceName = '';
      }
    })
    .bindSheet($$this.showNewGroupDialog, this.newGroupDialog(), {
      height: 300,
      dragBar: false,
      showClose: false,
      backgroundColor: ThemeRuntime.dropdownPanelColor(this.appDarkMode, '', 'overlay')
    })
  }
}
