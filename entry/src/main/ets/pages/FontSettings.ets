import { router, promptAction } from '@kit.ArkUI';
import http from '@ohos.net.http';
import { syncSystemBars } from '../utils/SystemBars';
import { ReaderSettingsStore } from '../utils/ReaderSettingsStore';
import { ReaderFontHelper, ReaderFontItem } from '../utils/ReaderFontHelper';
import { ReaderSystemFontHelper } from '../utils/ReaderSystemFontHelper';
import { AppDataPaths } from '../utils/AppDataPaths';
import fs from '@ohos.file.fs';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { ImmersiveBackButton } from '../components/ImmersiveBackButton';
import { ImmersiveMaterialRuntime } from '../utils/ImmersiveMaterialRuntime';

class ReaderCustomFontItem {
  familyName: string = '';
  filePath: string = '';
  sourceName: string = '';
}

class ReaderCustomFontData {
  fonts: ReaderCustomFontItem[] = [];
}

// 二开改造：在线字体源描述
class OnlineFontSource {
  id: string = '';
  title: string = '';
  desc: string = '';
  url: string = '';
  fileName: string = '';
  sizeHint: string = '';
}

class OnlineFontStatus {
  state: string = 'idle'; // idle | downloading | done | error
  progress: number = 0;
  filePath: string = '';
  error: string = '';
}

function makeOnlineFontSource(id: string, title: string, desc: string, url: string,
  fileName: string, sizeHint: string): OnlineFontSource {
  const source = new OnlineFontSource();
  source.id = id;
  source.title = title;
  source.desc = desc;
  source.url = url;
  source.fileName = fileName;
  source.sizeHint = sizeHint;
  return source;
}

// 二开改造：内置免费开源字体下载源（Google Fonts 官方仓库 + jsDelivr 国内可用镜像）
const ONLINE_FONT_SOURCES: OnlineFontSource[] = [
  makeOnlineFontSource(
    'noto-sans-sc',
    '思源黑体',
    'Noto Sans SC 可变字重',
    'https://cdn.jsdelivr.net/gh/google/fonts@main/ofl/notosanssc/NotoSansSC%5Bwght%5D.ttf',
    'online_noto_sans_sc.ttf',
    '约 10 MB'
  ),
  makeOnlineFontSource(
    'noto-serif-sc',
    '思源宋体',
    'Noto Serif SC 可变字重',
    'https://raw.githubusercontent.com/google/fonts/main/ofl/notoserifsc/NotoSerifSC%5Bwght%5D.ttf',
    'online_noto_serif_sc.ttf',
    '约 25 MB'
  ),
  makeOnlineFontSource(
    'zcool-kuaile',
    '站酷快乐体',
    'ZCOOL KuaiLe 标题字体',
    'https://raw.githubusercontent.com/google/fonts/main/ofl/zcoolkuaile/ZCOOLKuaiLe-Regular.ttf',
    'online_zcool_kuaile.ttf',
    '约 2 MB'
  ),
  makeOnlineFontSource(
    'ma-shan-zheng',
    '马善政楷书',
    'Ma Shan Zheng 毛笔楷书',
    'https://raw.githubusercontent.com/google/fonts/main/ofl/mashanzheng/MaShanZheng-Regular.ttf',
    'online_ma_shan_zheng.ttf',
    '约 2 MB'
  ),
  makeOnlineFontSource(
    'zcool-qkhy',
    '站酷庆科黄油体',
    'ZCOOL QingKe HuangYou 圆润标题',
    'https://raw.githubusercontent.com/google/fonts/main/ofl/zcoolqingkehuangyou/ZCOOLQingKeHuangYou-Regular.ttf',
    'online_zcool_qkhy.ttf',
    '约 1 MB'
  ),
  makeOnlineFontSource(
    'lxgw-wenkai',
    '霞鹜文楷',
    'LXGW WenKai 开源楷体',
    'https://raw.githubusercontent.com/google/fonts/main/ofl/lxgw-wenkai/LXGWWenKai-Regular.ttf',
    'online_lxgw_wenkai.ttf',
    '约 10 MB'
  )
];

@Entry
@Component
struct FontSettingsPage {
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageLink('themeRevision') themeRevision: number = 0;
  @StorageLink('readerFontFamily') readerFontFamily: string = '';
  @StorageLink('readerFontFilePath') readerFontFilePath: string = '';
  @StorageLink('readerFontSourceName') readerFontSourceName: string = '系统默认';
  @StorageLink('readerFontMode') readerFontMode: string = 'system';
  @StorageLink('readerSystemFontFamily') readerSystemFontFamily: string = '';
  @StorageLink('readerCustomFontsRaw') readerCustomFontsRaw: string = '';
  @StorageLink('readerActiveFontFamily') readerActiveFontFamily: string = '';
  @StorageLink('readerFontRegistered') readerFontRegistered: boolean = false;
  @StorageLink('appLightAccentColor') appLightAccentColor: string = '#007DFF';
  @StorageLink('appDarkAccentColor') appDarkAccentColor: string = '#4E9BFF';
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navBarHeight') navBarHeight: number = 0;
  @State customFonts: ReaderCustomFontItem[] = [];
  @State onlineFontStates: OnlineFontStatus[] = [];
  private onlineFontSources: OnlineFontSource[] = ONLINE_FONT_SOURCES;
  private downloadingOnlineFontIndex: number = -1;

  aboutToAppear(): void {
    this.refreshSystemFontFamily();
    this.reloadCustomFonts();
    this.initOnlineFontStates();
    this.syncBars();
  }

  onPageShow(): void {
    this.refreshSystemFontFamily();
    this.reloadCustomFonts();
    this.initOnlineFontStates();
    this.syncBars();
  }

  refreshSystemFontFamily(): string {
    const family = ReaderSystemFontHelper.applyToStorage(this.getUIContext());
    this.readerSystemFontFamily = family;
    return family;
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Scroll() {
        Column() {
          this.sectionTitle('全局字体设置')
          Column() {
            this.fontSettingPanel()
            this.customFontEntryItem()
          }
          .width('calc(100% - 24vp)')
          .margin({ left: 12, right: 12 })
          .borderRadius(16)
          .clip(true)
          .backgroundColor(this.cardColor())
          // 二开改造：内置免费在线字体下载与管理
          this.sectionTitle('在线字体')
          Column() {
            ForEach(this.onlineFontSources, (source: OnlineFontSource, index: number) => {
              this.onlineFontItem(source, index)
            }, (source: OnlineFontSource) => source.id)
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

  async reloadCustomFonts(): Promise<void> {
    this.loadCustomFonts();
    try {
      await this.scanCustomFontDir();
    } catch (e) {
      console.warn('扫描自定义字体失败:', e);
    }
    this.syncSelectedCustomFont();
    this.registerCustomFonts();
  }

  loadCustomFonts(): void {
    const raw = (this.readerCustomFontsRaw || '').trim();
    if (!raw) {
      this.customFonts = [];
      return;
    }
    try {
      const parsed = JSON.parse(raw) as ReaderCustomFontData | ReaderCustomFontItem[];
      const source = Array.isArray(parsed) ? parsed as ReaderCustomFontItem[] : ((parsed as ReaderCustomFontData).fonts || []);
      this.customFonts = this.cleanCustomFonts(source);
      this.saveCustomFonts(this.customFonts);
    } catch (e) {
      this.customFonts = [];
    }
  }

  saveCustomFonts(fonts?: ReaderCustomFontItem[]): void {
    const data = new ReaderCustomFontData();
    data.fonts = this.cleanCustomFonts(fonts ?? this.customFonts);
    this.customFonts = data.fonts;
    this.readerCustomFontsRaw = JSON.stringify(data);
    this.saveFontSettings();
  }

  cleanCustomFonts(source: ReaderCustomFontItem[]): ReaderCustomFontItem[] {
    const result: ReaderCustomFontItem[] = [];
    for (const item of source) {
      if (!item || !item.filePath || !this.fontFileExists(item.filePath)) {
        continue;
      }
      const fontItem = new ReaderCustomFontItem();
      fontItem.filePath = (item.filePath || '').trim();
      fontItem.sourceName = ReaderFontHelper.resolveDisplayName(item.sourceName, fontItem.filePath);
      fontItem.familyName = this.normalizedFontFamily(fontItem.filePath);
      if (fontItem.familyName && fontItem.filePath && !this.hasCustomFont(result, fontItem.familyName, fontItem.filePath)) {
        result.push(fontItem);
      }
    }
    return result;
  }

  async scanCustomFontDir(): Promise<void> {
    const dir = AppDataPaths.dir('reader_fonts');
    let names: string[] = [];
    try {
      names = await fs.listFile(dir);
    } catch (e) {
      return;
    }
    names.sort();
    const next = this.customFonts.slice();
    let changed = false;
    for (const name of names) {
      if (!this.isFontFile(name)) {
        continue;
      }
      const migratedName = this.ensureAsciiStoredFontName(dir, name);
      const filePath = `${dir}/${migratedName}`;
      const familyName = this.familyNameForPath(filePath);
      const existingIndex = this.findCustomFontIndexByFilePath(next, filePath);
      if (familyName && existingIndex >= 0 && next[existingIndex].familyName !== familyName) {
        next[existingIndex].familyName = familyName;
        if (this.readerFontFilePath === filePath) {
          this.readerFontFamily = familyName;
        }
        changed = true;
      } else if (existingIndex >= 0) {
        const displayName = ReaderFontHelper.resolveDisplayName(next[existingIndex].sourceName, filePath);
        if (next[existingIndex].sourceName !== displayName) {
          next[existingIndex].sourceName = displayName;
          changed = true;
        }
      } else if (familyName && !this.hasCustomFont(next, familyName, filePath)) {
        const item = new ReaderCustomFontItem();
        item.familyName = familyName;
        item.filePath = filePath;
        item.sourceName = ReaderFontHelper.resolveDisplayName(name, filePath);
        next.push(item);
        changed = true;
      }
    }
    if (changed) {
      this.saveCustomFonts(next);
    }
  }

  registerCustomFonts(): void {
    for (const item of this.customFonts) {
      this.registerCustomFont(item);
    }
  }

  registerCustomFont(item: ReaderCustomFontItem): string {
    if (!item.filePath) {
      return '';
    }
    const fontItem = new ReaderFontItem();
    fontItem.familyName = item.familyName;
    fontItem.filePath = item.filePath;
    fontItem.sourceName = item.sourceName;
    const result = ReaderFontHelper.registerFont(this.getUIContext(), fontItem);
    if (result.registered) {
      const oldPath = item.filePath;
      const oldFamilyName = item.familyName;
      item.filePath = result.filePath;
      item.familyName = this.familyNameForPath(result.filePath);
      if (this.readerFontFilePath === item.filePath || this.readerFontFilePath === oldPath ||
        this.readerFontFamily === item.familyName || this.readerFontFamily === oldFamilyName) {
        this.readerFontFilePath = item.filePath;
        this.readerFontFamily = item.familyName;
        this.readerActiveFontFamily = result.familyName;
        this.readerFontRegistered = true;
      }
      return result.familyName;
    }
    return '';
  }

  selectSystemFont(): void {
    const systemFontFamily = this.refreshSystemFontFamily();
    this.readerFontMode = 'system';
    this.readerFontFamily = '';
    this.readerFontFilePath = '';
    this.readerFontSourceName = '跟随主题';
    this.readerActiveFontFamily = '';
    this.readerFontRegistered = false;
    this.applyApplicationFont(ThemeRuntime.fontFamily() || systemFontFamily);
    this.saveFontSettings();
    promptAction.showToast({ message: '已恢复主题默认字体' });
  }

  selectCustomFont(item: ReaderCustomFontItem): void {
    if (!item || !item.familyName || !item.filePath) {
      return;
    }
    if (!this.fontFileExists(item.filePath)) {
      this.reloadCustomFonts();
      promptAction.showToast({ message: '字体文件不存在' });
      return;
    }
    this.readerFontMode = 'custom';
    const registeredFamily = this.registerCustomFont(item);
    if (!registeredFamily) {
      promptAction.showToast({ message: '字体注册失败，请更换字体文件' });
      return;
    }
    this.readerFontFamily = item.familyName;
    this.readerFontFilePath = item.filePath;
    this.readerFontSourceName = ReaderFontHelper.resolveDisplayName(item.sourceName, item.filePath);
    this.applyApplicationFont(registeredFamily);
    this.saveFontSettings();
    promptAction.showToast({ message: `已选择字体：${this.readerFontSourceName}` });
  }

  saveFontSettings(): void {
    ReaderSettingsStore.saveFontSettings(
      getContext(this),
      this.readerFontFamily,
      this.readerFontFilePath,
      this.readerFontSourceName,
      this.readerFontMode,
      this.readerSystemFontFamily,
      this.readerCustomFontsRaw
    ).catch((e: Error) => {
      console.warn('保存阅读字体设置失败:', e);
    });
  }

  applyApplicationFont(familyName: string): void {
    try {
      getContext(this).getApplicationContext().setFont(familyName || '');
    } catch (e) {
      console.warn('应用阅读字体失败:', e);
    }
  }

  syncSelectedCustomFont(): void {
    if (!this.readerFontFilePath) {
      return;
    }
    const index = this.findCustomFontIndexByFilePath(this.customFonts, this.readerFontFilePath);
    if (index < 0) {
      return;
    }
    const item = this.customFonts[index];
    this.readerFontFamily = item.familyName;
    this.readerFontSourceName = ReaderFontHelper.resolveDisplayName(item.sourceName, item.filePath);
    this.readerFontMode = 'custom';
  }

  readerFontOptions(): SelectOption[] {
    const options: SelectOption[] = [{ value: '跟随主题' }];
    for (const item of this.customFonts) {
      options.push({ value: item.sourceName || item.familyName });
    }
    return options;
  }

  readerFontSelectedIndex(): number {
    if (this.readerFontFilePath) {
      for (let i = 0; i < this.customFonts.length; i++) {
        const item = this.customFonts[i];
        if (item.filePath === this.readerFontFilePath || item.familyName === this.readerFontFamily) {
          return i + 1;
        }
      }
    }
    return 0;
  }

  readerFontValue(): string {
    const index = this.readerFontSelectedIndex();
    if (index <= 0) {
      return '跟随主题';
    }
    const customIndex = index - 1;
    if (customIndex >= 0 && customIndex < this.customFonts.length) {
      const item = this.customFonts[customIndex];
      return item.sourceName || item.familyName || '自定义字体';
    }
    return '跟随主题';
  }

  selectReaderFontByIndex(index: number): void {
    if (index <= 0) {
      this.selectSystemFont();
      return;
    }
    const customIndex = index - 1;
    if (customIndex >= 0 && customIndex < this.customFonts.length) {
      this.selectCustomFont(this.customFonts[customIndex]);
    }
  }

  isFontFile(name: string): boolean {
    const lower = (name || '').toLowerCase();
    return lower.endsWith('.ttf') || lower.endsWith('.otf') || lower.endsWith('.ttc');
  }

  fontExt(value: string): string {
    const lower = (value || '').toLowerCase();
    if (lower.includes('.otf')) return '.otf';
    if (lower.includes('.ttc')) return '.ttc';
    return '.ttf';
  }

  fontFileExists(path: string): boolean {
    try {
      return fs.accessSync(path);
    } catch (e) {
      return false;
    }
  }

  familyNameForPath(filePath: string): string {
    return ReaderFontHelper.normalizeFontFamily(filePath);
  }

  normalizedFontFamily(filePath: string): string {
    return ReaderFontHelper.normalizeFontFamily(filePath);
  }

  ensureAsciiStoredFontName(dir: string, name: string): string {
    if (this.isAsciiSafeFileName(name)) {
      return name;
    }
    const targetName = this.uniqueAsciiStoredFontName(dir, name);
    try {
      fs.renameSync(`${dir}/${name}`, `${dir}/${targetName}`);
      return targetName;
    } catch (e) {
      console.warn('迁移字体文件名失败:', e);
      return name;
    }
  }

  uniqueAsciiStoredFontName(dir: string, sourceName: string): string {
    const ext = this.fontExt(sourceName);
    const base = this.asciiStoredFontName(sourceName, 0).replace(ext, '');
    let candidate = `${base}${ext}`;
    let index = 1;
    while (this.fontFileExists(`${dir}/${candidate}`)) {
      candidate = `${base}_${index}${ext}`;
      index++;
    }
    return candidate;
  }

  asciiStoredFontName(sourceName: string, salt: number): string {
    const ext = this.fontExt(sourceName);
    let hash = salt & 0x7fffffff;
    for (let i = 0; i < sourceName.length; i++) {
      hash = ((hash * 31) + sourceName.charCodeAt(i)) & 0x7fffffff;
    }
    return `reader_font_${hash}${ext}`;
  }

  isAsciiSafeFileName(name: string): boolean {
    if (!name || name.includes('/') || name.includes('\\')) {
      return false;
    }
    for (let i = 0; i < name.length; i++) {
      const code = name.charCodeAt(i);
      if (code < 33 || code > 126) {
        return false;
      }
    }
    return true;
  }

  fileNameFromUri(uri: string): string {
    const decoded = decodeURIComponent(uri || '');
    const index = Math.max(decoded.lastIndexOf('/'), decoded.lastIndexOf('\\'));
    return index >= 0 ? decoded.substring(index + 1) : decoded || '自定义字体';
  }

  hasCustomFont(fonts: ReaderCustomFontItem[], familyName: string, filePath: string): boolean {
    for (const item of fonts) {
      if (item.familyName === familyName || item.filePath === filePath) {
        return true;
      }
    }
    return false;
  }

  findCustomFontIndexByFilePath(fonts: ReaderCustomFontItem[], filePath: string): number {
    for (let i = 0; i < fonts.length; i++) {
      if (fonts[i].filePath === filePath) {
        return i;
      }
    }
    return -1;
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

  primaryTextColor(): string {
    return ThemeRuntime.primaryTextColor(this.appDarkMode);
  }

  subTextColor(): string {
    return ThemeRuntime.subTextColor(this.appDarkMode);
  }

  accentColor(): string {
    return ThemeRuntime.accentColor(this.appDarkMode);
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

      Text('字体设置')
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
    .border({ width: { bottom: 0.5 }, color: this.appDarkMode ? '#24FFFFFF' : '#14000000' })
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
  fontSettingPanel() {
    Row() {
      Text('全局字体设置')
        .fontSize(16)
        .fontColor(this.primaryTextColor())
        .layoutWeight(1)

      Select(this.readerFontOptions())
        .selected(this.readerFontSelectedIndex())
        .value(this.readerFontValue())
        .font({ size: 14 })
        .fontColor(this.subTextColor())
        .backgroundColor(Color.Transparent)
        .arrowPosition(ArrowPosition.END)
        .padding({ left: 0, right: 0 })
        .borderRadius(16)
        .border({ width: 0 })
        .divider(null)
        .optionBgColor(Color.Transparent)
        .optionFontColor(this.primaryTextColor())
        .selectedOptionFontColor(this.accentColor())
        .selectedOptionBgColor(ThemeRuntime.accentSurfaceColor(this.appDarkMode))
        .menuBackgroundColor(ThemeRuntime.dropdownPanelColor(this.appDarkMode))
        .menuBackgroundBlurStyle(BlurStyle.NONE)
        .menuSystemMaterial(ImmersiveMaterialRuntime.selectMenuMaterial())
        .onSelect((index: number) => {
          this.selectReaderFontByIndex(index);
        })
    }
    .width('calc(100% - 32vp)')
    .constraintSize({ minHeight: 56 })
    .padding({ left: 0, right: 0, top: 12, bottom: 12 })
    .margin({ left: 16, right: 16 })
    .backgroundColor(Color.Transparent)
    .border({ width: { bottom: 0.5 }, color: this.appDarkMode ? '#24FFFFFF' : '#14000000' })
    .alignItems(VerticalAlign.Center)
  }

  // ===== 二开改造：在线字体下载与管理 =====

  initOnlineFontStates(): void {
    const states: OnlineFontStatus[] = [];
    for (const source of this.onlineFontSources) {
      const status = new OnlineFontStatus();
      status.state = 'idle';
      status.progress = 0;
      status.filePath = '';
      status.error = '';
      const filePath = `${this.onlineFontDir()}/${source.fileName}`;
      if (this.fontFileExists(filePath)) {
        status.state = 'done';
        status.progress = 100;
        status.filePath = filePath;
      }
      states.push(status);
    }
    this.onlineFontStates = states;
  }

  onlineFontDir(): string {
    return AppDataPaths.dir('reader_fonts');
  }

  isOnlineFontStateDownloading(index: number): boolean {
    const status = this.onlineFontStates[index];
    return !!status && status.state === 'downloading';
  }

  isOnlineFontStateError(index: number): boolean {
    const status = this.onlineFontStates[index];
    return !!status && status.state === 'error';
  }

  isOnlineFontDownloaded(index: number): boolean {
    const status = this.onlineFontStates[index];
    return !!status && status.state === 'done' && !!status.filePath && this.fontFileExists(status.filePath);
  }

  isOnlineFontApplied(index: number): boolean {
    const status = this.onlineFontStates[index];
    return !!status && status.state === 'done' && !!status.filePath &&
      this.readerFontFilePath === status.filePath;
  }

  async downloadOnlineFont(index: number): Promise<void> {
    if (this.downloadingOnlineFontIndex >= 0 || index < 0 || index >= this.onlineFontSources.length) {
      return;
    }
    const source = this.onlineFontSources[index];
    const status = this.onlineFontStates[index];
    if (!status || status.state === 'downloading') {
      return;
    }
    this.downloadingOnlineFontIndex = index;
    status.state = 'downloading';
    status.progress = 0;
    status.error = '';
    const httpRequest = http.createHttp();
    try {
      httpRequest.on('dataReceiveProgress', (info: http.DataReceiveProgressInfo) => {
        if (info.totalSize > 0) {
          status.progress = Math.min(99, Math.floor(info.receiveSize * 100 / info.totalSize));
        }
      });
      const response = await httpRequest.request(source.url, {
        method: http.RequestMethod.GET,
        connectTimeout: 20000,
        readTimeout: 180000,
        header: {
          'User-Agent': 'Mozilla/5.0 (Linux; Android 10; HarmonyOS) AppleWebKit/537.36 Chrome/120 Mobile Safari/537.36',
          'Accept': '*/*'
        },
        expectDataType: http.HttpDataType.ARRAY_BUFFER
      });
      if (response.responseCode !== 200) {
        status.state = 'error';
        status.error = `HTTP ${response.responseCode}`;
        promptAction.showToast({ message: '字体下载失败（网络或源不可用）' });
        return;
      }
      const buffer = response.result as ArrayBuffer;
      if (!buffer || buffer.byteLength < 100) {
        status.state = 'error';
        status.error = '响应内容异常';
        promptAction.showToast({ message: '字体下载失败（数据异常）' });
        return;
      }
      const filePath = `${this.onlineFontDir()}/${source.fileName}`;
      try {
        if (this.fontFileExists(filePath)) {
          fs.unlink(filePath);
        }
      } catch (e) {
        console.warn('清理旧字体文件失败:', JSON.stringify(e));
      }
      const file = fs.openSync(filePath, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      try {
        fs.writeSync(file.fd, buffer);
      } finally {
        fs.closeSync(file);
      }
      await this.reloadCustomFonts();
      status.state = 'done';
      status.progress = 100;
      status.filePath = filePath;
      status.error = '';
      promptAction.showToast({ message: `已下载「${source.title}」，可在上方选择应用` });
    } catch (e) {
      console.error('下载在线字体失败:', JSON.stringify(e));
      status.state = 'error';
      status.error = JSON.stringify(e);
      promptAction.showToast({ message: '字体下载失败，请检查网络后重试' });
    } finally {
      httpRequest.destroy();
      this.downloadingOnlineFontIndex = -1;
    }
  }

  async deleteOnlineFont(index: number): Promise<void> {
    if (index < 0 || index >= this.onlineFontSources.length || this.downloadingOnlineFontIndex >= 0) {
      return;
    }
    const source = this.onlineFontSources[index];
    const status = this.onlineFontStates[index];
    if (!status || status.state !== 'done' || !status.filePath) {
      return;
    }
    const filePath = status.filePath;
    try {
      if (this.fontFileExists(filePath)) {
        fs.unlink(filePath);
      }
    } catch (e) {
      console.warn('删除在线字体文件失败:', JSON.stringify(e));
      promptAction.showToast({ message: '删除字体失败' });
      return;
    }
    await this.reloadCustomFonts();
    status.state = 'idle';
    status.progress = 0;
    status.filePath = '';
    status.error = '';
    promptAction.showToast({ message: `已删除「${source.title}」` });
  }

  applyOnlineFont(index: number): void {
    const status = this.onlineFontStates[index];
    if (!status || status.state !== 'done' || !status.filePath) {
      return;
    }
    const item = this.findCustomFontByFilePath(status.filePath);
    if (item) {
      this.selectCustomFont(item);
    } else {
      this.reloadCustomFonts();
      promptAction.showToast({ message: '字体尚未注册，请重试' });
    }
  }

  findCustomFontByFilePath(filePath: string): ReaderCustomFontItem | null {
    for (const item of this.customFonts) {
      if (item.filePath === filePath) {
        return item;
      }
    }
    return null;
  }

  @Builder
  onlineFontItem(source: OnlineFontSource, index: number) {
    Column() {
      Row() {
        Column() {
          Text(source.title)
            .fontSize(16)
            .fontColor(this.primaryTextColor())
          Text(`${source.desc} · ${source.sizeHint}`)
            .fontSize(12)
            .fontColor(this.subTextColor())
            .margin({ top: 4 })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        if (this.isOnlineFontStateDownloading(index)) {
          Text(`下载中… ${this.onlineFontStates[index].progress}%`)
            .fontSize(13)
            .fontColor(this.accentColor())
        } else if (this.isOnlineFontDownloaded(index)) {
          Row({ space: 12 }) {
            if (this.isOnlineFontApplied(index)) {
              Text('已应用')
                .fontSize(13)
                .fontColor(this.subTextColor())
            } else {
              Button('应用')
                .fontSize(13)
                .height(30)
                .backgroundColor(this.accentColor())
                .onClick(() => this.applyOnlineFont(index))
            }
            Button('删除')
              .fontSize(13)
              .height(30)
              .backgroundColor(Color.Transparent)
              .fontColor(this.subTextColor())
              .border({ width: 1, color: this.appDarkMode ? '#40FFFFFF' : '#26000000' })
              .onClick(() => this.deleteOnlineFont(index))
          }
        } else if (this.isOnlineFontStateError(index)) {
          Column() {
            Text('下载失败')
              .fontSize(12)
              .fontColor('#E05555')
            Button('重试')
              .fontSize(13)
              .height(30)
              .backgroundColor(this.accentColor())
              .onClick(() => this.downloadOnlineFont(index))
          }
          .alignItems(HorizontalAlign.End)
        } else {
          Button('下载')
            .fontSize(13)
            .height(30)
            .backgroundColor(this.accentColor())
            .onClick(() => this.downloadOnlineFont(index))
        }
      }
      .width('calc(100% - 32vp)')
      .constraintSize({ minHeight: 64 })
      .padding({ left: 0, right: 0, top: 12, bottom: 12 })
      .margin({ left: 16, right: 16 })
      .backgroundColor(Color.Transparent)
      .border({ width: { bottom: index < this.onlineFontSources.length - 1 ? 0.5 : 0 },
        color: this.appDarkMode ? '#24FFFFFF' : '#14000000' })
      .alignItems(VerticalAlign.Center)
    }
  }

  @Builder
  customFontEntryItem() {
    Row() {
      Text('自定义字体')
        .fontColor(this.primaryTextColor())
        .fontSize(16)
        .layoutWeight(1)
      Text('上传 / 删除')
        .fontSize(13)
        .fontColor(this.subTextColor())
        .margin({ right: 8 })
      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(18)
        .fontColor([this.subTextColor()])
    }
    .width('calc(100% - 32vp)')
    .height(56)
    .padding({ left: 0, right: 0 })
    .margin({ left: 16, right: 16 })
    .backgroundColor(Color.Transparent)
    .border({ width: { bottom: 0.5 }, color: this.appDarkMode ? '#24FFFFFF' : '#14000000' })
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      router.pushUrl({ url: 'pages/CustomFontManager' });
    })
  }
}
