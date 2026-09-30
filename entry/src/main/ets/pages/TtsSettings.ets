import { router, promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { syncSystemBars } from '../utils/SystemBars';
import { SystemTtsReader, TtsVoiceOption } from '../utils/SystemTtsReader';
import { ImmersiveBackButton } from '../components/ImmersiveBackButton';
import { AdaptiveIconButton } from '../components/AdaptiveIconButton';
import { TtsSettings, TtsSettingsStore } from '../utils/TtsSettingsStore';
import { ImmersiveMaterialRuntime } from '../utils/ImmersiveMaterialRuntime';
import { ThemeRuntime } from '../theme/ThemeRuntime';

@Entry
@Component
struct TtsSettingsPage {
  @StorageLink('ttsPerson') ttsPerson: number = 0;
  @StorageLink('ttsOnline') ttsOnline: number = 1;
  @StorageLink('ttsStyle') ttsStyle: string = '';
  @StorageLink('ttsLanguage') ttsLanguage: string = 'zh-CN';
  @StorageLink('ttsSpeed') ttsSpeed: number = 1;
  @StorageLink('ttsInstalledVoiceKeys') ttsInstalledVoiceKeys: string = '';
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageLink('themeRevision') themeRevision: number = 0;
  @StorageLink('appLightAccentColor') appLightAccentColor: string = '#007DFF';
  @StorageLink('appDarkAccentColor') appDarkAccentColor: string = '#4E9BFF';
  @StorageLink('appLightButtonColor') appLightButtonColor: string = '#007DFF';
  @StorageLink('appDarkButtonColor') appDarkButtonColor: string = '#3F8CFF';
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navBarHeight') navBarHeight: number = 0;

  @State voices: TtsVoiceOption[] = [TtsSettingsPage.defaultVoice()];
  @State selectedVoiceKey: string = '';
  private previewText: string = '这是一段朗读试听文字。点击试听后，会按照当前音色和倍速播放。';
  private previewReader: SystemTtsReader = new SystemTtsReader();
  @State isPreviewing: boolean = false;
  @State isLoadingVoices: boolean = false;
  @State downloadingVoiceKey: string = '';
  @State downloadProgressText: string = '';
  @State showVoiceDropdown: boolean = false;
  private speedSaveTimerId: number = -1;
  private context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;

  aboutToAppear(): void {
    this.syncBars();
    this.loadSettingsAndVoices();
  }

  onPageShow(): void {
    this.syncBars();
    this.loadSettingsAndVoices();
  }

  aboutToDisappear(): void {
    this.flushPendingSpeedSettings();
    this.previewReader.shutdown();
    this.isPreviewing = false;
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
        Scroll() {
          Column() {
            this.sectionTitle('朗读音色')
            this.voiceDropdownSelector()

          this.sectionTitle('朗读倍速')
          Column() {
            Row() {
              Text('倍速')
                .fontSize(16)
                .fontColor(this.primaryTextColor())
                .layoutWeight(1)
              Text(`${this.ttsSpeed.toFixed(1)}x`)
                .fontSize(14)
                .fontColor(this.subTextColor())
            }
            .width('100%')

            Row({ space: 10 }) {
              this.speedStepButton($r('sys.symbol.minus'), '降低朗读倍速', this.ttsSpeed > 0.5, () => {
                this.applySpeed(this.ttsSpeed - 0.1);
              })
              Slider({ value: this.ttsSpeed, min: 0.5, max: 2, step: 0.1 })
                .layoutWeight(1)
                .showTips(true)
                .selectedColor(this.accentColor())
                .sliderInteractionMode(ImmersiveMaterialRuntime.supportsHds() ? SliderInteraction.SLIDE_AND_CLICK_UP : SliderInteraction.SLIDE_ONLY)
                .onChange((value: number) => {
                  this.applySpeed(value);
                })
              this.speedStepButton($r('sys.symbol.plus'), '提高朗读倍速', this.ttsSpeed !== 2, () => {
                this.applySpeed(this.ttsSpeed + 0.1);
              })
            }
            .width('100%')
            .margin({ top: 10 })

            Row({ space: 8 }) {
              this.speedChip(0.8)
              this.speedChip(1.0)
              this.speedChip(1.2)
              this.speedChip(1.5)
              this.speedChip(2.0)
            }
            .width('100%')
            .margin({ top: 10 })
          }
          .width('calc(100% - 24vp)')
          .padding({ left: 16, right: 16, top: 14, bottom: 14 })
          .margin({ left: 12, right: 12 })
          .borderRadius(16)
          .clip(true)
          .backgroundColor(this.cardColor())

          this.sectionTitle('预览')
          Column({ space: 12 }) {
            Text(this.previewText)
              .fontSize(14)
              .lineHeight(22)
              .fontColor(this.subTextColor())
              .width('100%')

            Button(this.isPreviewing ? '停止试听' : '试听')
              .width('100%')
              .height(42)
              .backgroundColor(this.isPreviewing ? '#E53935' : this.buttonColor())
              .fontColor('#FFFFFF')
              .onClick(() => {
                this.togglePreview();
              })
          }
          .width('calc(100% - 24vp)')
          .padding(16)
          .margin({ left: 12, right: 12 })
          .borderRadius(16)
          .clip(true)
          .backgroundColor(this.cardColor())

          }
          .width('100%')
          .padding({ top: 56 + this.statusBarHeight, bottom: this.navBarHeight + 32 })
        }
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
        .width('100%')
        .height('100%')
        .align(Alignment.TopStart)

      this.titleBar()

      if (this.showVoiceDropdown) {
        this.voiceDropdownMenu()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.pageColor())
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
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

  inputColor(): string {
    return ThemeRuntime.inputColor(this.appDarkMode);
  }

  accentColor(): string {
    return ThemeRuntime.accentColor(this.appDarkMode);
  }

  buttonColor(): string {
    return ThemeRuntime.buttonColor(this.appDarkMode);
  }

  syncBars(): void {
    syncSystemBars(getContext(this), this.appDarkMode, this.pageColor());
  }

  selectedVoiceTitle(): string {
    const systemVoice = this.findCurrentVoice();
    if (systemVoice) {
      return this.voiceTitle(systemVoice);
    }
    return this.isLoadingVoices ? '正在加载音色...' : '默认音色';
  }

  @Builder
  voiceDropdownSelector() {
    Row() {
      Text(this.selectedVoiceTitle())
        .fontSize(16)
        .fontColor(this.primaryTextColor())
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      SymbolGlyph(this.showVoiceDropdown ? $r('sys.symbol.chevron_up') : $r('sys.symbol.chevron_down'))
        .fontSize(18)
        .fontColor([this.subTextColor()])
        .width(18)
    }
    .width('calc(100% - 24vp)')
    .height(54)
    .padding({ left: 16, right: 16 })
    .margin({ left: 12, right: 12 })
    .borderRadius(14)
    .backgroundColor(this.cardColor())
    .onClick(() => {
      this.showVoiceDropdown = !this.showVoiceDropdown;
    })
  }

  @Builder
  voiceDropdownMenu() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column()
        .width('100%')
        .height('100%')
        .onClick(() => {
          this.showVoiceDropdown = false;
        })

      Column() {
        Scroll() {
          Column() {
            this.voiceDropdownSectionTitle('系统音色')
            ForEach(this.voices, (voice: TtsVoiceOption) => {
              this.systemVoiceDropdownOption(voice)
            }, (voice: TtsVoiceOption) => this.voiceKey(voice))
          }
          .width('100%')
        }
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
        .width('100%')
        .constraintSize({ maxHeight: 420 })
      }
      .width('calc(100% - 24vp)')
      .constraintSize({ maxWidth: 560 })
      .padding({ top: 6, bottom: 6 })
      // API 6 changed how backdropBlur composites for custom overlays, so the
      // translucent glass tint let page content bleed through the voice list.
      // Use the opaque card surface instead, matching the other settings
      // dropdown menus, so every option stays readable.
      .backgroundColor(this.cardColor())
      .borderRadius(ThemeRuntime.glassCornerRadius(16, 'overlay'))
      .border({ width: ThemeRuntime.glassBorderWidth('overlay'), color: ThemeRuntime.glassBorderColor(this.appDarkMode, 'overlay') })
      .shadow({ radius: ThemeRuntime.glassShadowRadius('overlay'), color: ThemeRuntime.glassShadowColor(this.appDarkMode, 'overlay'), offsetX: ThemeRuntime.glassShadowOffsetX('overlay'), offsetY: ThemeRuntime.glassShadowOffsetY('overlay') })
      .position({ x: 12, y: this.statusBarHeight + 108 })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  voiceDropdownSectionTitle(title: string) {
    Text(title)
      .fontSize(12)
      .fontColor(this.subTextColor())
      .width('100%')
      .padding({ left: 14, right: 14, top: 8, bottom: 5 })
  }

  @Builder
  systemVoiceDropdownOption(voice: TtsVoiceOption) {
    Row() {
      Text(this.voiceTitle(voice))
        .fontSize(15)
        .fontColor((voice.available || voice.downloadable) ? this.primaryTextColor() : this.subTextColor())
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      if (this.isVoiceDownloading(voice)) {
        Text(this.downloadProgressText || '下载中')
          .fontSize(11)
          .fontColor(this.accentColor())
      } else if (this.isVoiceSelected(voice)) {
        SymbolGlyph($r('sys.symbol.checkmark'))
          .fontSize(18)
          .fontColor([this.accentColor()])
      } else if (!voice.available && voice.downloadable) {
        Text('下载')
          .fontSize(12)
          .fontColor(this.accentColor())
      }
    }
    .width('100%')
    .height(46)
    .padding({ left: 14, right: 14 })
    .opacity((voice.available || voice.downloadable) ? 1 : 0.5)
    .onClick(() => {
      if (!voice.available && !voice.downloadable) {
        return;
      }
      this.showVoiceDropdown = false;
      this.selectVoice(voice);
    })
  }

  normalizeDefaultOnlineVoice(): void {
    if (this.ttsOnline === 0 && this.ttsPerson === 0 && !this.ttsStyle &&
      this.sameLanguage(this.ttsLanguage || 'zh-CN', 'zh-CN')) {
      this.ttsOnline = 1;
      this.saveSettings();
    }
  }

  async loadSettingsAndVoices(): Promise<void> {
    try {
      const settings = await TtsSettingsStore.load(getContext(this));
      this.applySettings(settings);
    } catch (e) {
      console.warn('加载朗读设置失败:', e);
    }
    this.normalizeDefaultOnlineVoice();
    this.selectedVoiceKey = this.currentVoiceKey();
    this.loadVoices();
  }

  applySettings(settings: TtsSettings): void {
    this.ttsPerson = settings.person;
    this.ttsOnline = settings.online;
    this.ttsStyle = settings.style;
    this.ttsLanguage = settings.language;
    this.ttsSpeed = settings.speed;
    this.ttsInstalledVoiceKeys = settings.installedVoiceKeys;
  }

  currentSettings(): TtsSettings {
    const settings = new TtsSettings();
    settings.person = this.ttsPerson;
    settings.online = this.ttsOnline;
    settings.style = this.ttsStyle;
    settings.language = this.ttsLanguage;
    settings.speed = this.ttsSpeed;
    settings.installedVoiceKeys = this.ttsInstalledVoiceKeys;
    return settings;
  }

  saveSettings(): void {
    const settings = this.currentSettings();
    TtsSettingsStore.applyToStorage(settings);
    TtsSettingsStore.save(getContext(this), settings).catch((e: Error) => {
      console.warn('保存朗读设置失败:', e);
    });
  }

  static defaultVoice(): TtsVoiceOption {
    const option = new TtsVoiceOption();
    option.id = 0;
    option.name = '默认音色';
    option.online = 1;
    option.status = 'default';
    option.language = 'zh-CN';
    return option;
  }

  async loadVoices(): Promise<void> {
    if (this.isLoadingVoices) {
      return;
    }
    this.isLoadingVoices = true;
    try {
      const voices = await SystemTtsReader.listAvailableVoices();
      this.voices = this.applyInstalledOverrides(this.mergeWithDefaultVoice(voices));
      const currentVoice = this.findCurrentVoice();
      if (!currentVoice || !currentVoice.available) {
        const defaultVoice = this.firstAvailableVoice();
        this.applyVoice(defaultVoice, false);
      } else {
        this.selectedVoiceKey = this.voiceKey(currentVoice);
      }
    } catch (_) {
      this.voices = [TtsSettingsPage.defaultVoice()];
      this.ttsPerson = 0;
      this.ttsOnline = 1;
      this.ttsStyle = '';
      this.ttsLanguage = 'zh-CN';
      this.saveSettings();
      this.selectedVoiceKey = this.currentVoiceKey();
    } finally {
      this.isLoadingVoices = false;
    }
  }

  mergeWithDefaultVoice(voices: TtsVoiceOption[]): TtsVoiceOption[] {
    const options: TtsVoiceOption[] = [TtsSettingsPage.defaultVoice()];
    for (const voice of voices) {
      const existingIndex = options.findIndex((item: TtsVoiceOption) =>
        this.isSameVoiceOption(item, voice) || this.isSameDisplayVoice(item, voice));
      if (existingIndex < 0) {
        options.push(voice);
      } else if (this.shouldPreferVoiceOption(voice, options[existingIndex])) {
        options[existingIndex] = voice;
      }
    }
    return options;
  }

  isSameVoiceOption(left: TtsVoiceOption, right: TtsVoiceOption): boolean {
    if (left.id !== right.id || left.online !== right.online ||
      !this.sameLanguage(left.language || 'zh-CN', right.language || 'zh-CN')) {
      return false;
    }
    if (this.isKnownVoiceId(left.id)) {
      return true;
    }
    return (left.style || '') === (right.style || '');
  }

  isSameDisplayVoice(left: TtsVoiceOption, right: TtsVoiceOption): boolean {
    if (this.voiceTitle(left) === this.voiceTitle(right)) {
      return true;
    }
    return (left.name || '') === (right.name || '') && left.online === right.online &&
      this.sameLanguage(left.language || 'zh-CN', right.language || 'zh-CN');
  }

  shouldPreferVoiceOption(candidate: TtsVoiceOption, current: TtsVoiceOption): boolean {
    if (candidate.available !== current.available) {
      return candidate.available;
    }
    if (this.isKnownVoiceId(candidate.id) !== this.isKnownVoiceId(current.id)) {
      return this.isKnownVoiceId(candidate.id);
    }
    if (candidate.downloadable !== current.downloadable) {
      return candidate.downloadable;
    }
    return !current.style && !!candidate.style;
  }

  isKnownVoiceId(id: number): boolean {
    return id === 0 || id === 8 || id === 13 || id === 21;
  }

  firstAvailableVoice(): TtsVoiceOption {
    return this.voices.find((voice: TtsVoiceOption) => voice.available) || this.voices[0] ||
      TtsSettingsPage.defaultVoice();
  }

  async selectVoice(voice: TtsVoiceOption): Promise<void> {
    if (!voice.available) {
      if (voice.downloadable) {
        await this.downloadAndSelectVoice(voice);
      } else {
        promptAction.showToast({ message: '该系统音色当前不可用' });
      }
      return;
    }
    this.applyVoice(voice, true);
  }

  applyVoice(voice: TtsVoiceOption, stopPreview: boolean): void {
    if (stopPreview && this.isPreviewing) {
      this.previewReader.stop();
      this.isPreviewing = false;
    }
    this.ttsPerson = voice.id;
    this.ttsOnline = voice.online;
    this.ttsStyle = voice.style;
    this.ttsLanguage = voice.language;
    this.selectedVoiceKey = this.voiceKey(voice);
    this.saveSettings();
  }

  async downloadAndSelectVoice(voice: TtsVoiceOption): Promise<void> {
    if (!SystemTtsReader.supportsVoiceDownload()) {
      promptAction.showToast({ message: '当前系统版本不支持下载系统音色，请升级系统后重试' });
      return;
    }
    if (this.downloadingVoiceKey) {
      promptAction.showToast({ message: '正在下载音色，请稍候' });
      return;
    }
    const key = this.voiceKey(voice);
    this.downloadingVoiceKey = key;
    this.downloadProgressText = '';
    try {
      promptAction.showToast({ message: `开始下载 ${voice.name}` });
      await SystemTtsReader.downloadVoice(voice, {
        onStart: (_message: string) => {
          this.downloadProgressText = '准备中';
        },
        onProgress: (progress: string) => {
          this.downloadProgressText = this.formatDownloadProgress(progress);
        }
      });
      this.markVoiceInstalled(voice);
      await this.loadVoices();
      let downloaded = this.findMatchingVoice(voice, true);
      if (!downloaded) {
        downloaded = this.markVoiceOptionInstalled(voice);
        this.voices = this.applyInstalledOverrides(this.mergeWithDefaultVoice(this.voices.concat([downloaded])));
      }
      this.applyVoice(downloaded, true);
      promptAction.showToast({ message: `已启用 ${downloaded.name}` });
    } catch (error) {
      promptAction.showToast({ message: `音色下载失败：${this.shortErrorMessage(error as Object)}` });
    } finally {
      this.downloadingVoiceKey = '';
      this.downloadProgressText = '';
    }
  }

  isVoiceSelected(voice: TtsVoiceOption): boolean {
    return this.isCurrentVoice(voice);
  }

  applyInstalledOverrides(voices: TtsVoiceOption[]): TtsVoiceOption[] {
    const options: TtsVoiceOption[] = [];
    for (const voice of voices) {
      options.push(this.isLocallyInstalledVoice(voice) ? this.markVoiceOptionInstalled(voice) : voice);
    }
    return options;
  }

  markVoiceInstalled(voice: TtsVoiceOption): void {
    const key = this.installedVoiceKey(voice);
    if (!key || this.installedVoiceKeyExists(key)) {
      return;
    }
    this.ttsInstalledVoiceKeys = this.ttsInstalledVoiceKeys ?
      `${this.ttsInstalledVoiceKeys}\n${key}` : key;
    this.saveSettings();
  }

  isLocallyInstalledVoice(voice: TtsVoiceOption): boolean {
    return this.installedVoiceKeyExists(this.installedVoiceKey(voice));
  }

  installedVoiceKeyExists(key: string): boolean {
    if (!key) {
      return false;
    }
    const keys = this.ttsInstalledVoiceKeys.split('\n');
    return keys.includes(key);
  }

  installedVoiceKey(voice: TtsVoiceOption): string {
    const style = this.isKnownVoiceId(voice.id) ? '' : (voice.style || '');
    return `${voice.id}_${voice.online}_${this.normalizeLanguage(voice.language || 'zh-CN')}_${style}`;
  }

  markVoiceOptionInstalled(voice: TtsVoiceOption): TtsVoiceOption {
    const option = this.copyVoiceOption(voice);
    option.available = true;
    option.downloadable = false;
    option.status = 'INSTALLED';
    option.systemStatus = 'INSTALLED';
    return option;
  }

  copyVoiceOption(voice: TtsVoiceOption): TtsVoiceOption {
    const option = new TtsVoiceOption();
    option.id = voice.id;
    option.name = voice.name;
    option.online = voice.online;
    option.status = voice.status;
    option.systemStatus = voice.systemStatus;
    option.style = voice.style;
    option.language = voice.language;
    option.downloadLanguage = voice.downloadLanguage;
    option.gender = voice.gender;
    option.available = voice.available;
    option.downloadable = voice.downloadable;
    return option;
  }

  voiceTitle(voice: TtsVoiceOption): string {
    if (voice.status === 'default') {
      return `${voice.name} · 系统默认`;
    }
    if (this.isVoiceDownloading(voice)) {
      const progress = this.downloadProgressText ? ` · ${this.downloadProgressText}` : '';
      return `${voice.name} · 下载中${progress}`;
    }
    const suffix = voice.online === 0 ? '在线' : '离线';
    const gender = this.voiceGenderText(voice);
    const state = voice.available ? '' : (voice.downloadable ? ' · 需下载' : ' · 不可用');
    return `${voice.name} · ${suffix}${gender}${state}`;
  }

  voiceGenderText(voice: TtsVoiceOption): string {
    const value = (voice.gender || '').toLowerCase();
    if (value === 'male' || value === '男' || value === '男声') {
      return ' · 男声';
    }
    if (value === 'female' || value === '女' || value === '女声') {
      return ' · 女声';
    }
    return '';
  }

  voiceKey(voice: TtsVoiceOption): string {
    return `${voice.id}_${voice.online}_${voice.language || 'zh-CN'}_${voice.style || ''}_${voice.name || ''}`;
  }

  currentVoiceKey(): string {
    const matched = this.findCurrentVoice();
    return matched ? this.voiceKey(matched) :
      `${this.ttsPerson}_${this.ttsOnline}_${this.ttsLanguage || 'zh-CN'}_${this.ttsStyle || ''}_`;
  }

  findCurrentVoice(): TtsVoiceOption | undefined {
    return this.voices.find((voice: TtsVoiceOption) => this.isCurrentVoice(voice));
  }

  isCurrentVoice(voice: TtsVoiceOption): boolean {
    return voice.id === this.ttsPerson && voice.online === this.ttsOnline &&
      (voice.style || '') === (this.ttsStyle || '') &&
      this.sameLanguage(voice.language || 'zh-CN', this.ttsLanguage || 'zh-CN');
  }

  findMatchingVoice(target: TtsVoiceOption, availableOnly: boolean): TtsVoiceOption | undefined {
    const exact = this.voices.find((voice: TtsVoiceOption) => voice.id === target.id && voice.online === target.online &&
      (voice.style || '') === (target.style || '') &&
      this.sameLanguage(voice.language || 'zh-CN', target.language || 'zh-CN') &&
      (!availableOnly || voice.available));
    if (exact) {
      return exact;
    }
    const sameModule = this.voices.find((voice: TtsVoiceOption) => voice.id === target.id &&
      voice.online === target.online && this.sameLanguage(voice.language || 'zh-CN', target.language || 'zh-CN') &&
      (!availableOnly || voice.available));
    if (sameModule) {
      return sameModule;
    }
    return this.voices.find((voice: TtsVoiceOption) => voice.id === target.id &&
      (!availableOnly || voice.available));
  }

  sameLanguage(left: string, right: string): boolean {
    return this.normalizeLanguage(left) === this.normalizeLanguage(right);
  }

  normalizeLanguage(language: string): string {
    const value = (language || 'zh-CN').trim().replace(/_/g, '-').toLowerCase();
    if (value === 'zh' || value === 'zh-cn' || value.startsWith('zh-hans')) {
      return 'zh-CN';
    }
    if (value === 'en' || value === 'en-us') {
      return 'en-US';
    }
    return value || 'zh-CN';
  }

  isVoiceDownloading(voice: TtsVoiceOption): boolean {
    return this.downloadingVoiceKey === this.voiceKey(voice);
  }

  formatDownloadProgress(progress: string): string {
    const value = (progress || '').trim();
    if (!value) {
      return '下载中';
    }
    return value;
  }

  shortErrorMessage(error: Object | undefined): string {
    if (!error) {
      return '未知错误';
    }
    const anyError = error as Record<string, Object>;
    const message = anyError['message'];
    if (message !== undefined) {
      return String(message);
    }
    return String(error);
  }

  @Builder
  titleBar() {
    Row() {
      ImmersiveBackButton({ iconColor: this.primaryTextColor(), darkMode: this.appDarkMode,
        buttonSize: 40, containerWidth: 56, materialScale: 0.83, compactLayout: true,
        onBack: () => router.back() })

      Text('朗读设置')
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

  async togglePreview(): Promise<void> {
    if (this.isPreviewing) {
      this.previewReader.stop();
      this.isPreviewing = false;
      return;
    }
    try {
      this.isPreviewing = true;
      await this.previewReader.start(this.getPreviewText(), {
        person: this.ttsPerson,
        online: this.ttsOnline,
        style: this.ttsStyle,
        language: this.ttsLanguage,
        speed: this.ttsSpeed,
        onFinished: () => {
          this.isPreviewing = false;
        },
        onError: (message: string) => {
          this.isPreviewing = false;
          promptAction.showToast({ message });
        }
      });
    } catch (e) {
      this.isPreviewing = false;
      promptAction.showToast({ message: '试听失败' });
    }
  }

  getPreviewText(): string {
    const language = (this.ttsLanguage || '').toLowerCase();
    if (language.startsWith('en')) {
      return 'This is a short text for voice preview. The current voice and speed will be used for playback.';
    }
    return this.previewText;
  }

  @Builder
  speedChip(value: number) {
    Stack({ alignContent: Alignment.Center }) {
      Text(`${value.toFixed(1)}x`)
        .fontSize(13)
        .fontColor(Math.abs(this.ttsSpeed - value) < 0.01 ? '#FFFFFF' : this.primaryTextColor())
    }
        .layoutWeight(1)
      .height(32)
      .borderRadius(16)
      .backgroundColor(Math.abs(this.ttsSpeed - value) < 0.01 ? this.accentColor() : this.inputColor())
      .onClick(() => {
        this.applySpeed(value);
      })
  }

  @Builder
  speedStepButton(icon: Resource, accessibilityText: string, enabled: boolean, action: () => void) {
    Stack({ alignContent: Alignment.Center }) {
      AdaptiveIconButton({
        icon: icon,
        accessibilityLabel: accessibilityText,
        buttonEnabled: enabled,
        buttonSize: 34,
        iconSize: 16,
        fillColor: this.inputColor(),
        iconColor: this.primaryTextColor(),
        disabledIconColor: this.subTextColor(),
        action: action
      })
    }
    .width(34)
    .height(34)
    .borderRadius(17)
    .backgroundColor(this.inputColor())
  }

  applySpeed(value: number): void {
    const nextSpeed = Math.max(0.5, Math.min(2, Math.round(value * 10) / 10));
    if (Math.abs(this.ttsSpeed - nextSpeed) < 0.01) {
      return;
    }
    this.ttsSpeed = nextSpeed;
    this.scheduleSpeedSettingsSave();
  }

  scheduleSpeedSettingsSave(): void {
    if (this.speedSaveTimerId >= 0) {
      clearTimeout(this.speedSaveTimerId);
    }
    this.speedSaveTimerId = setTimeout(() => {
      this.speedSaveTimerId = -1;
      this.saveSettings();
    }, 300);
  }

  flushPendingSpeedSettings(): void {
    if (this.speedSaveTimerId >= 0) {
      clearTimeout(this.speedSaveTimerId);
      this.speedSaveTimerId = -1;
      this.saveSettings();
    }
  }

}
