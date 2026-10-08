import { router, promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { syncSystemBars } from '../utils/SystemBars';
import { SystemTtsReader, TtsVoiceOption } from '../utils/SystemTtsReader';
import { ImmersiveBackButton } from '../components/ImmersiveBackButton';
import { AdaptiveIconButton } from '../components/AdaptiveIconButton';
import { TtsSettings, TtsSettingsStore } from '../utils/TtsSettingsStore';
import { ImmersiveMaterialRuntime } from '../utils/ImmersiveMaterialRuntime';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { RoleTagger } from '../utils/RoleTagger';
import { CloudTtsVoiceProvider, CloudTtsVoiceData } from '../utils/CloudTtsVoiceProvider';
import { CloudTtsDriver } from '../utils/CloudTtsDriver';

/** 角色音色映射条目（与 ReadBook.ets 内定义一致）：p 为 TTS 音色 person id，n 为音色显示名。 */
interface RoleTtsVoiceEntry {
  p: number;
  n: string;
}

/** 云端音色连接条目（由 ttsCloudVoices JSON 解析而来，key = provider:voice）。 */
interface CloudVoiceEntry {
  key: string;
  provider: string;
  label: string;
  baseUrl: string;
  model: string;
  voice: string;
  name: string;
  gender: string;
  language: string;
}

@Entry
@Component
struct TtsSettingsPage {
  @StorageLink('ttsPerson') ttsPerson: number = 0;
  @StorageLink('ttsOnline') ttsOnline: number = 1;
  @StorageLink('ttsStyle') ttsStyle: string = '';
  @StorageLink('ttsLanguage') ttsLanguage: string = 'zh-CN';
  @StorageLink('ttsSpeed') ttsSpeed: number = 1;
  @StorageLink('ttsInstalledVoiceKeys') ttsInstalledVoiceKeys: string = '';
  @StorageLink('ttsRoleEnabled') ttsRoleEnabled: boolean = false;
  @StorageLink('ttsRoleProvider') ttsRoleProvider: string = 'zhipu';
  @StorageLink('ttsRoleBaseUrl') ttsRoleBaseUrl: string = '';
  @StorageLink('ttsRoleModel') ttsRoleModel: string = '';
  @StorageLink('ttsRoleApiKey') ttsRoleApiKey: string = '';
  @StorageLink('ttsRoleVoiceMap') ttsRoleVoiceMap: string = '{}';
  @StorageLink('ttsCloudProvider') ttsCloudProvider: string = '';
  @StorageLink('ttsCloudBaseUrl') ttsCloudBaseUrl: string = '';
  @StorageLink('ttsCloudModel') ttsCloudModel: string = '';
  @StorageLink('ttsCloudApiKey') ttsCloudApiKey: string = '';
  @StorageLink('ttsCloudVoices') ttsCloudVoices: string = '[]';
  @StorageLink('ttsCloudActiveVoice') ttsCloudActiveVoice: string = '';
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
  @State showRoleMapSheet: boolean = false;
  @State rolePickTarget: string = '';
  @State roleMapDraftJson: string = '{}';
  @State newRoleName: string = '';
  private speedSaveTimerId: number = -1;
  private roleFieldSaveTimerId: number = -1;
  private context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
  private cloudDriver: CloudTtsDriver = new CloudTtsDriver(getContext(this) as common.UIAbilityContext);
  @State cloudImporting: boolean = false;
  @State cloudImportMessage: string = '';
  @State cloudImportError: string = '';

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
    this.flushRoleFieldSettings();
    this.previewReader.shutdown();
    this.isPreviewing = false;
    this.cloudDriver.shutdown();
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
        Scroll() {
          Column() {
            this.sectionTitle('朗读音色')
            this.voiceDropdownSelector()

          this.sectionTitle('云端音色（API Key 一键导入）')
          Column({ space: 12 }) {
            Row({ space: 8 }) {
              this.cloudProviderChip('xiaomi')
              this.cloudProviderChip('aliyun')
            }
            .width('100%')

            Row() {
              Text('接口地址')
                .fontSize(15)
                .fontColor(this.primaryTextColor())
                .width(84)
              TextInput({ text: this.ttsCloudBaseUrl, placeholder: '留空使用厂商默认' })
                .layoutWeight(1)
                .fontSize(14)
                .onChange((value: string) => {
                  this.ttsCloudBaseUrl = value.trim();
                  this.saveSettings();
                })
            }
            .width('100%')

            Row() {
              Text('模型')
                .fontSize(15)
                .fontColor(this.primaryTextColor())
                .width(84)
              TextInput({ text: this.ttsCloudModel, placeholder: '留空使用厂商默认' })
                .layoutWeight(1)
                .fontSize(14)
                .onChange((value: string) => {
                  this.ttsCloudModel = value.trim();
                  this.saveSettings();
                })
            }
            .width('100%')

            Row() {
              Text('API Key')
                .fontSize(15)
                .fontColor(this.primaryTextColor())
                .width(84)
              TextInput({ text: this.ttsCloudApiKey, placeholder: '请输入厂商账号获取的 API Key' })
                .type(InputType.Password)
                .layoutWeight(1)
                .fontSize(14)
                .onChange((value: string) => {
                  this.ttsCloudApiKey = value.trim();
                  this.saveSettings();
                })
            }
            .width('100%')

            Button(this.cloudImporting ? '校验中…' : '校验并一键导入')
              .width('100%')
              .height(42)
              .enabled(!this.cloudImporting && (this.ttsCloudApiKey || '').trim().length > 0)
              .backgroundColor(this.buttonColor())
              .fontColor('#FFFFFF')
              .onClick(() => {
                this.importCloudVoices();
              })

            if (this.cloudImportMessage) {
              Text(this.cloudImportMessage)
                .fontSize(13)
                .fontColor(this.accentColor())
                .width('100%')
            }
            if (this.cloudImportError) {
              Text(this.cloudImportError)
                .fontSize(13)
                .fontColor('#E53935')
                .width('100%')
            }

            if (this.parsedCloudVoices().length > 0) {
              Text(`已导入 ${this.parsedCloudVoices().length} 个云端音色`)
                .fontSize(13)
                .fontColor(this.subTextColor())
                .width('100%')
              ForEach(this.parsedCloudVoices(), (entry: CloudVoiceEntry) => {
                this.cloudVoiceRow(entry)
              }, (entry: CloudVoiceEntry) => entry.key)
            }

            Text('说明：云端音色由厂商免费 TTS 接口提供（小米 OpenAI 兼容限免 / 阿里 CosyVoice 新用户 1 万字符 90 天）。输入 API Key 校验通过后一键导入，导入的音色可直接用于朗读，缓存音频保存在应用沙箱内，删除音色时一并清理。')
              .fontSize(12)
              .fontColor(this.subTextColor())
              .lineHeight(18)
              .width('100%')
          }
          .width('calc(100% - 24vp)')
          .padding(16)
          .margin({ left: 12, right: 12 })
          .borderRadius(16)
          .clip(true)
          .backgroundColor(this.cardColor())

          this.sectionTitle('系统离线音色')
          Column({ space: 10 }) {
            Text('系统离线语音包由系统 TTS 服务托管，应用无法直接卸载。可在此清除本应用记录的“已下载”标记；如需释放存储，请前往系统设置中卸载对应语音包。')
              .fontSize(13)
              .fontColor(this.subTextColor())
              .lineHeight(20)
              .width('100%')

            if (this.installedVoiceCount() > 0) {
              Text(`已标记 ${this.installedVoiceCount()} 个已下载音色`)
                .fontSize(13)
                .fontColor(this.primaryTextColor())
                .width('100%')
            }

            ForEach(this.locallyInstalledVoices(), (voice: TtsVoiceOption) => {
              Row() {
                Text(this.voiceTitle(voice))
                  .fontSize(14)
                  .fontColor(this.primaryTextColor())
                  .layoutWeight(1)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                Button('移除标记')
                  .height(32)
                  .fontSize(12)
                  .backgroundColor(this.cardColor())
                  .fontColor(this.accentColor())
                  .onClick(() => {
                    this.clearInstalledVoiceMark(voice);
                  })
              }
              .width('100%')
              .padding({ top: 4, bottom: 4 })
            }, (voice: TtsVoiceOption) => this.installedVoiceKey(voice))

            Button('清除全部已下载标记')
              .width('100%')
              .height(40)
              .enabled(this.installedVoiceCount() > 0)
              .backgroundColor(this.buttonColor())
              .fontColor('#FFFFFF')
              .onClick(() => {
                this.clearAllInstalledMarks();
              })
          }
          .width('calc(100% - 24vp)')
          .padding(16)
          .margin({ left: 12, right: 12 })
          .borderRadius(16)
          .clip(true)
          .backgroundColor(this.cardColor())

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

          this.sectionTitle('分角色朗读')
          Column({ space: 12 }) {
            Row() {
              Text('启用分角色朗读')
                .fontSize(16)
                .fontColor(this.primaryTextColor())
                .layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: this.ttsRoleEnabled })
                .selectedColor(this.accentColor())
                .onChange((on: boolean) => {
                  this.ttsRoleEnabled = on;
                  this.saveSettings();
                })
            }
            .width('100%')

            if (this.ttsRoleEnabled) {
              Row() {
                Text('服务厂商')
                  .fontSize(15)
                  .fontColor(this.primaryTextColor())
                  .layoutWeight(1)
                Text(this.roleProviderLabel())
                  .fontSize(14)
                  .fontColor(this.subTextColor())
                SymbolGlyph($r('sys.symbol.chevron_right'))
                  .fontSize(14)
                  .fontColor([this.subTextColor()])
                  .width(14)
              }
              .width('100%')
              .onClick(() => {
                this.showRoleProviderPicker();
              })

              Row() {
                Text('接口地址')
                  .fontSize(15)
                  .fontColor(this.primaryTextColor())
                  .width(72)
                TextInput({ placeholder: '留空使用厂商默认', text: this.ttsRoleBaseUrl })
                  .layoutWeight(1)
                  .height(38)
                  .fontSize(14)
                  .fontColor(this.primaryTextColor())
                  .backgroundColor(this.inputColor())
                  .borderRadius(8)
                  .onChange((value: string) => {
                    this.ttsRoleBaseUrl = value.trim();
                    this.scheduleRoleFieldSave();
                  })
              }
              .width('100%')

              Row() {
                Text('模型')
                  .fontSize(15)
                  .fontColor(this.primaryTextColor())
                  .width(72)
                TextInput({ placeholder: '留空使用厂商默认', text: this.ttsRoleModel })
                  .layoutWeight(1)
                  .height(38)
                  .fontSize(14)
                  .fontColor(this.primaryTextColor())
                  .backgroundColor(this.inputColor())
                  .borderRadius(8)
                  .onChange((value: string) => {
                    this.ttsRoleModel = value.trim();
                    this.scheduleRoleFieldSave();
                  })
              }
              .width('100%')

              Row() {
                Text('API Key')
                  .fontSize(15)
                  .fontColor(this.primaryTextColor())
                  .width(72)
                TextInput({ placeholder: '必填，用于调用标注接口', text: this.ttsRoleApiKey })
                  .layoutWeight(1)
                  .height(38)
                  .fontSize(14)
                  .fontColor(this.primaryTextColor())
                  .backgroundColor(this.inputColor())
                  .borderRadius(8)
                  .type(InputType.Password)
                  .onChange((value: string) => {
                    this.ttsRoleApiKey = value.trim();
                    this.scheduleRoleFieldSave();
                  })
              }
              .width('100%')

              Button('角色音色映射')
                .width('100%')
                .height(40)
                .backgroundColor(this.buttonColor())
                .fontColor('#FFFFFF')
                .onClick(() => {
                  this.openRoleMapSheet();
                })
              Text('旁白沿用当前音色；其余角色自动按性别分配，可在此手动调整。')
                .fontSize(12)
                .fontColor(this.subTextColor())
                .width('100%')
            }
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

      if (this.showRoleMapSheet) {
        this.roleMapSheetBuilder()
        if (this.rolePickTarget.length > 0) {
          this.roleMapVoicePicker()
        }
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

  dividerColor(): string {
    return ThemeRuntime.dividerColor(this.appDarkMode);
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

  @Builder
  cloudProviderChip(provider: string) {
    Column() {
      Text(this.cloudProviderLabel(provider))
        .fontSize(14)
        .fontColor(this.ttsCloudProvider === provider ? '#FFFFFF' : this.primaryTextColor())
    }
    .height(38)
    .justifyContent(FlexAlign.Center)
    .padding({ left: 18, right: 18 })
    .borderRadius(19)
    .backgroundColor(this.ttsCloudProvider === provider ? this.accentColor() : this.cardColor())
    .border({ width: this.ttsCloudProvider === provider ? 0 : 1, color: this.dividerColor() })
    .onClick(() => {
      this.selectCloudProvider(provider);
    })
  }

  @Builder
  cloudVoiceRow(entry: CloudVoiceEntry) {
    Column({ space: 6 }) {
      Row() {
        Column({ space: 2 }) {
          Text(entry.name)
            .fontSize(15)
            .fontColor(this.primaryTextColor())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(`${entry.label} · ${entry.voice}`)
            .fontSize(12)
            .fontColor(this.subTextColor())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        if (this.isCloudVoiceActive(entry)) {
          Text('朗读中')
            .fontSize(11)
            .fontColor(this.accentColor())
        }
      }
      .width('100%')

      Row({ space: 8 }) {
        Button(this.isCloudVoiceActive(entry) ? '已设为当前音色' : '设为当前音色')
          .layoutWeight(1)
          .height(34)
          .fontSize(13)
          .backgroundColor(this.isCloudVoiceActive(entry) ? this.cardColor() : this.buttonColor())
          .fontColor(this.isCloudVoiceActive(entry) ? this.accentColor() : '#FFFFFF')
          .enabled(!this.isCloudVoiceActive(entry))
          .onClick(() => {
            this.selectCloudVoice(entry);
          })
        Button('试听')
          .layoutWeight(1)
          .height(34)
          .fontSize(13)
          .backgroundColor(this.cardColor())
          .fontColor(this.accentColor())
          .onClick(() => {
            this.previewCloudVoice(entry);
          })
        Button('删除')
          .layoutWeight(1)
          .height(34)
          .fontSize(13)
          .backgroundColor(this.cardColor())
          .fontColor('#E53935')
          .onClick(() => {
            this.deleteCloudVoice(entry);
          })
      }
      .width('100%')
    }
    .width('100%')
    .padding(10)
    .borderRadius(10)
    .backgroundColor(this.inputColor())
  }

  parsedCloudVoices(): CloudVoiceEntry[] {
    try {
      const raw = JSON.parse(this.ttsCloudVoices || '[]') as CloudTtsVoiceData[];
      return raw.map((item: CloudTtsVoiceData) => {
        const entry: CloudVoiceEntry = {
          key: `${item.provider}:${item.voice}`,
          provider: item.provider,
          label: item.label,
          baseUrl: item.baseUrl,
          model: item.model,
          voice: item.voice,
          name: item.name,
          gender: item.gender,
          language: item.language
        };
        return entry;
      });
    } catch (_) {
      return [];
    }
  }

  cloudProviderLabel(provider: string): string {
    return CloudTtsVoiceProvider.providerLabel(provider);
  }

  isCloudVoiceActive(entry: CloudVoiceEntry): boolean {
    return (this.ttsCloudActiveVoice || '') === entry.key;
  }

  selectCloudProvider(provider: string): void {
    if (this.ttsCloudProvider === provider) {
      return;
    }
    this.ttsCloudProvider = provider;
    if (!(this.ttsCloudBaseUrl || '').trim()) {
      this.ttsCloudBaseUrl = CloudTtsVoiceProvider.providerInfo(provider).baseUrl;
    }
    if (!(this.ttsCloudModel || '').trim()) {
      this.ttsCloudModel = CloudTtsVoiceProvider.providerInfo(provider).ttsModel;
    }
    this.saveSettings();
  }

  async importCloudVoices(): Promise<void> {
    const apiKey = (this.ttsCloudApiKey || '').trim();
    if (!apiKey) {
      this.cloudImportError = '请先输入 API Key';
      return;
    }
    const provider = this.ttsCloudProvider || 'aliyun';
    this.cloudImporting = true;
    this.cloudImportMessage = '';
    this.cloudImportError = '';
    try {
      const voices = await CloudTtsVoiceProvider.fetchVoices(provider, apiKey, this.ttsCloudBaseUrl);
      if (voices.length === 0) {
        this.cloudImportError = '未获取到可用音色，请检查接口地址/模型后重试';
        return;
      }
      const map: Record<string, CloudVoiceEntry> = {};
      for (const existing of this.parsedCloudVoices()) {
        map[existing.key] = existing;
      }
      for (const voice of voices) {
        const entry: CloudVoiceEntry = {
          key: `${voice.provider}:${voice.voice}`,
          provider: voice.provider,
          label: voice.label,
          baseUrl: voice.baseUrl,
          model: voice.model,
          voice: voice.voice,
          name: voice.name,
          gender: voice.gender,
          language: voice.language
        };
        map[entry.key] = entry;
      }
      this.ttsCloudVoices = JSON.stringify(Object.values(map));
      this.saveSettings();
      this.cloudImportMessage = `校验通过，已导入 ${voices.length} 个音色连接`;
    } catch (error) {
      this.cloudImportError = CloudTtsDriver.errorMessage(error as Object);
    } finally {
      this.cloudImporting = false;
    }
  }

  selectCloudVoice(entry: CloudVoiceEntry): void {
    if (this.isPreviewing) {
      this.previewReader.stop();
      this.isPreviewing = false;
    }
    this.cloudDriver.stop();
    this.ttsCloudActiveVoice = entry.key;
    this.saveSettings();
    promptAction.showToast({ message: `已选择云端音色 ${entry.name}` });
  }

  async previewCloudVoice(entry: CloudVoiceEntry): Promise<void> {
    if (this.isPreviewing) {
      this.previewReader.stop();
    }
    this.cloudDriver.stop();
    const apiKey = (this.ttsCloudApiKey || '').trim();
    if (!apiKey) {
      this.isPreviewing = false;
      this.cloudImportError = '请先输入 API Key 再试听';
      return;
    }
    this.isPreviewing = true;
    this.cloudImportError = '';
    await this.cloudDriver.speak({
      text: this.previewText,
      provider: entry.provider,
      baseUrl: entry.baseUrl || this.ttsCloudBaseUrl,
      model: entry.model || this.ttsCloudModel,
      apiKey: apiKey,
      voice: entry.voice,
      speed: this.ttsSpeed,
      onFinished: () => {
        this.isPreviewing = false;
      },
      onError: (message: string) => {
        this.isPreviewing = false;
        promptAction.showToast({ message: `试听失败：${message}` });
      }
    });
  }

  async deleteCloudVoice(entry: CloudVoiceEntry): Promise<void> {
    this.cloudDriver.stop();
    if (this.isPreviewing) {
      this.isPreviewing = false;
    }
    const voices = this.parsedCloudVoices().filter((item: CloudVoiceEntry) => item.key !== entry.key);
    this.ttsCloudVoices = JSON.stringify(voices);
    if (this.isCloudVoiceActive(entry)) {
      this.ttsCloudActiveVoice = '';
    }
    const removed: number = await this.cloudDriver.clearVoiceCache(entry.voice);
    this.saveSettings();
    promptAction.showToast({ message: `已删除音色连接，并清理 ${removed} 个缓存文件` });
  }

  installedVoiceCount(): number {
    return (this.ttsInstalledVoiceKeys || '').split('\n').filter((key: string) => key.length > 0).length;
  }

  locallyInstalledVoices(): TtsVoiceOption[] {
    return this.voices.filter((voice: TtsVoiceOption) => this.isLocallyInstalledVoice(voice));
  }

  clearInstalledVoiceMark(voice: TtsVoiceOption): void {
    const key = this.installedVoiceKey(voice);
    const keys = (this.ttsInstalledVoiceKeys || '').split('\n')
      .filter((item: string) => item.length > 0 && item !== key);
    this.ttsInstalledVoiceKeys = keys.join('\n');
    this.voices = this.applyInstalledOverrides(this.voices);
    this.saveSettings();
    promptAction.showToast({ message: `已移除「${voice.name}」的已下载标记；如需释放存储，请前往系统设置卸载语音包` });
  }

  clearAllInstalledMarks(): void {
    this.ttsInstalledVoiceKeys = '';
    this.voices = this.applyInstalledOverrides(this.voices);
    this.saveSettings();
    promptAction.showToast({ message: '已清除全部已下载标记；如需释放存储，请前往系统设置卸载语音包' });
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
    this.ttsRoleEnabled = settings.roleTtsEnabled;
    this.ttsRoleProvider = settings.roleTtsProvider || 'zhipu';
    this.ttsRoleBaseUrl = settings.roleTtsBaseUrl || '';
    this.ttsRoleModel = settings.roleTtsModel || '';
    this.ttsRoleApiKey = settings.roleTtsApiKey || '';
    this.ttsRoleVoiceMap = settings.roleVoiceMap || '{}';
    this.ttsCloudProvider = settings.cloudTtsProvider || '';
    this.ttsCloudBaseUrl = settings.cloudTtsBaseUrl || '';
    this.ttsCloudModel = settings.cloudTtsModel || '';
    this.ttsCloudApiKey = settings.cloudTtsApiKey || '';
    this.ttsCloudVoices = settings.cloudTtsVoices || '[]';
    this.ttsCloudActiveVoice = settings.cloudTtsActiveVoice || '';
  }

  currentSettings(): TtsSettings {
    const settings = new TtsSettings();
    settings.person = this.ttsPerson;
    settings.online = this.ttsOnline;
    settings.style = this.ttsStyle;
    settings.language = this.ttsLanguage;
    settings.speed = this.ttsSpeed;
    settings.installedVoiceKeys = this.ttsInstalledVoiceKeys;
    settings.roleTtsEnabled = this.ttsRoleEnabled;
    settings.roleTtsProvider = this.ttsRoleProvider || 'zhipu';
    settings.roleTtsBaseUrl = this.ttsRoleBaseUrl || '';
    settings.roleTtsModel = this.ttsRoleModel || '';
    settings.roleTtsApiKey = this.ttsRoleApiKey || '';
    settings.roleVoiceMap = this.ttsRoleVoiceMap || '{}';
    settings.cloudTtsProvider = this.ttsCloudProvider || '';
    settings.cloudTtsBaseUrl = this.ttsCloudBaseUrl || '';
    settings.cloudTtsModel = this.ttsCloudModel || '';
    settings.cloudTtsApiKey = this.ttsCloudApiKey || '';
    settings.cloudTtsVoices = this.ttsCloudVoices || '[]';
    settings.cloudTtsActiveVoice = this.ttsCloudActiveVoice || '';
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

  roleProviderLabel(): string {
    const p = RoleTagger.PROVIDERS[this.ttsRoleProvider];
    return p ? p.label : (this.ttsRoleProvider || 'zhipu');
  }

  showRoleProviderPicker(): void {
    ActionSheet.show({
      title: '选择服务厂商',
      message: '均为 OpenAI 兼容接口，阿里/小米等端口已预留',
      confirm: { value: '取消', action: () => { } },
      sheets: [
        { title: '智谱', action: () => { this.setRoleProvider('zhipu'); } },
        { title: '阿里百炼', action: () => { this.setRoleProvider('aliyun'); } },
        { title: '小米', action: () => { this.setRoleProvider('xiaomi'); } },
        { title: 'DeepSeek', action: () => { this.setRoleProvider('deepseek'); } },
        { title: '硅基流动', action: () => { this.setRoleProvider('siliconflow'); } }
      ]
    });
  }

  setRoleProvider(provider: string): void {
    this.ttsRoleProvider = provider;
    this.saveSettings();
    const p = RoleTagger.PROVIDERS[provider];
    promptAction.showToast({ message: '已切换到' + (p ? p.label : provider) });
  }

  openRoleMapSheet(): void {
    this.roleMapDraftJson = this.ttsRoleVoiceMap || '{}';
    this.rolePickTarget = '';
    this.showRoleMapSheet = true;
  }

  closeRoleMapSheet(): void {
    this.showRoleMapSheet = false;
    this.rolePickTarget = '';
  }

  parseRoleVoiceMap(): Record<string, RoleTtsVoiceEntry> {
    try {
      const raw = (this.roleMapDraftJson || '{}').trim();
      if (!raw) {
        return {};
      }
      return JSON.parse(raw) as Record<string, RoleTtsVoiceEntry>;
    } catch (_) {
      return {};
    }
  }

  addRoleToMap(): void {
    const name = this.newRoleName.trim();
    if (!name) {
      promptAction.showToast({ message: '请输入角色名' });
      return;
    }
    const map = this.parseRoleVoiceMap();
    if (map[name]) {
      promptAction.showToast({ message: '该角色已存在，可直接点击选择音色' });
      return;
    }
    const current = this.findCurrentVoice() || TtsSettingsPage.defaultVoice();
    map[name] = { p: current.id, n: this.voiceTitle(current) };
    this.roleMapDraftJson = JSON.stringify(map);
    this.newRoleName = '';
    this.persistRoleMap(map);
    promptAction.showToast({ message: `已添加角色「${name}」，点击可为它指定音色` });
  }

  removeRoleFromMap(name: string): void {
    promptAction.showDialog({
      title: '删除角色',
      message: `确定删除角色「${name}」的音色映射吗？删除后朗读时该角色将按性别自动分配音色。`,
      buttons: [
        { text: '取消', color: this.subTextColor() },
        { text: '删除', color: '#E53935' }
      ]
    }).then((result: promptAction.ShowDialogSuccessResponse) => {
      if (result.index === 1) {
        const map = this.parseRoleVoiceMap();
        const next: Record<string, RoleTtsVoiceEntry> = {};
        const keys = Object.keys(map);
        for (const k of keys) {
          if (k !== name) {
            next[k] = map[k];
          }
        }
        this.roleMapDraftJson = JSON.stringify(next);
        this.persistRoleMap(next);
        promptAction.showToast({ message: `已删除角色「${name}」的音色映射` });
      }
    }).catch(() => {
    });
  }

  scheduleRoleFieldSave(): void {
    if (this.roleFieldSaveTimerId >= 0) {
      clearTimeout(this.roleFieldSaveTimerId);
    }
    this.roleFieldSaveTimerId = setTimeout(() => {
      this.roleFieldSaveTimerId = -1;
      this.saveSettings();
    }, 300);
  }

  flushRoleFieldSettings(): void {
    if (this.roleFieldSaveTimerId >= 0) {
      clearTimeout(this.roleFieldSaveTimerId);
      this.roleFieldSaveTimerId = -1;
      this.saveSettings();
    }
  }

  roleMapRoleNames(): string[] {
    return Object.keys(this.parseRoleVoiceMap());
  }

  roleVoiceTitle(entry: RoleTtsVoiceEntry | undefined): string {
    if (!entry || !entry.n) {
      return '默认音色';
    }
    return entry.n;
  }

  // 分角色朗读要求音色已下载到本地（available 且非 downloadable），
  // 在线音质角色若未下载，实机播放会被系统引擎回退默认音色。
  roleVoiceUsable(entry: RoleTtsVoiceEntry | undefined): boolean {
    if (!entry) {
      return true;
    }
    return this.voices.some((v: TtsVoiceOption) => v.available && !v.downloadable && v.id === entry.p);
  }

  roleVoicePickerVoices(): TtsVoiceOption[] {
    return this.voices.filter((v: TtsVoiceOption) => v.available && !v.downloadable);
  }

  selectRoleVoice(name: string, voice: TtsVoiceOption): void {
    if (!voice.available || voice.downloadable) {
      promptAction.showToast({ message: '该音色未下载到本地，请先下载后再指定给角色' });
      return;
    }
    const map = this.parseRoleVoiceMap();
    map[name] = { p: voice.id, n: this.voiceTitle(voice) };
    this.roleMapDraftJson = JSON.stringify(map);
    this.rolePickTarget = '';
    this.persistRoleMap(map);
  }

  persistRoleMap(map?: Record<string, RoleTtsVoiceEntry>): void {
    try {
      const json = JSON.stringify(map ? map : this.parseRoleVoiceMap());
      AppStorage.setOrCreate('ttsRoleVoiceMap', json);
      this.ttsRoleVoiceMap = json;
      this.saveSettings();
    } catch (_) {
    }
  }

  @Builder
  roleMapSheetBuilder() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column()
        .width('100%')
        .height('100%')
        .onClick(() => {
          this.closeRoleMapSheet();
        })

      Column() {
        Row() {
          Text('角色音色映射')
            .fontSize(16)
            .fontColor(this.primaryTextColor())
            .layoutWeight(1)
          Text('完成')
            .fontSize(14)
            .fontColor(this.accentColor())
            .onClick(() => {
              this.closeRoleMapSheet();
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 14, bottom: 8 })

        Row({ space: 8 }) {
          TextInput({ placeholder: '新增角色名，如：旁白、小明', text: this.newRoleName })
            .layoutWeight(1)
            .height(36)
            .fontSize(14)
            .fontColor(this.primaryTextColor())
            .backgroundColor(this.inputColor())
            .borderRadius(8)
            .onChange((value: string) => {
              this.newRoleName = value;
            })
          Button('添加')
            .height(36)
            .fontSize(14)
            .backgroundColor(this.accentColor())
            .fontColor('#FFFFFF')
            .onClick(() => {
              this.addRoleToMap();
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 2, bottom: 6 })

        if (this.roleMapRoleNames().length === 0) {
          Text('暂无角色。可先朗读一次自动生成，或在上方输入角色名添加（含旁白）并指定音色')
            .fontSize(13)
            .fontColor(this.subTextColor())
            .padding({ left: 16, right: 16, bottom: 16 })
        } else {
          ForEach(this.roleMapRoleNames(), (name: string) => {
            Row() {
              Text(name)
                .fontSize(15)
                .fontColor(this.primaryTextColor())
                .layoutWeight(1)
              Text(this.roleVoiceTitle(this.parseRoleVoiceMap()[name]) +
                (this.roleVoiceUsable(this.parseRoleVoiceMap()[name]) ? '' : '（需重新选择）'))
                .fontSize(13)
                .fontColor(this.subTextColor())
              Text('删除')
                .fontSize(12)
                .fontColor('#E53935')
                .margin({ left: 10, right: 2 })
                .onClick(() => {
                  this.removeRoleFromMap(name);
                })
              SymbolGlyph($r('sys.symbol.chevron_right'))
                .fontSize(13)
                .fontColor([this.subTextColor()])
                .width(13)
            }
            .width('100%')
            .height(44)
            .padding({ left: 16, right: 16 })
            .onClick(() => {
              this.rolePickTarget = name;
            })
          }, (name: string) => name)
        }
      }
      .width('calc(100% - 24vp)')
      .constraintSize({ maxWidth: 560 })
      .padding({ top: 6, bottom: 12 })
      .backgroundColor(this.cardColor())
      .borderRadius(16)
      .border({ width: 1, color: this.appDarkMode ? '#3A3A3C' : '#E5E5EA' })
      .position({ x: 12, y: this.statusBarHeight + 120 })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  roleMapVoicePicker() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column()
        .width('100%')
        .height('100%')
        .onClick(() => {
          this.rolePickTarget = '';
        })

      Column() {
        Text(`${this.rolePickTarget} 音色`)
          .fontSize(15)
          .fontColor(this.primaryTextColor())
          .padding({ left: 16, right: 16, top: 14, bottom: 2 })
        Text('仅列出已下载到本地的音色；在线音质音色需先在「系统音色」中下载')
          .fontSize(11)
          .fontColor(this.subTextColor())
          .padding({ left: 16, right: 16, bottom: 8 })
        Scroll() {
          Column() {
            ForEach(this.roleVoicePickerVoices(), (voice: TtsVoiceOption) => {
              Row() {
                Text(this.voiceTitle(voice))
                  .fontSize(15)
                  .fontColor(this.primaryTextColor())
                  .layoutWeight(1)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                if (this.roleVoiceTitle(this.parseRoleVoiceMap()[this.rolePickTarget]) === this.voiceTitle(voice)) {
                  Text('当前')
                    .fontSize(12)
                    .fontColor(this.accentColor())
                }
              }
              .width('100%')
              .height(44)
              .padding({ left: 16, right: 16 })
              .onClick(() => {
                this.selectRoleVoice(this.rolePickTarget, voice);
              })
            }, (voice: TtsVoiceOption) => this.voiceKey(voice))
          }
          .width('100%')
        }
        .constraintSize({ maxHeight: 380 })
        .width('100%')
      }
      .width('calc(100% - 24vp)')
      .constraintSize({ maxWidth: 560 })
      .padding({ bottom: 8 })
      .backgroundColor(this.cardColor())
      .borderRadius(16)
      .border({ width: 1, color: this.appDarkMode ? '#3A3A3C' : '#E5E5EA' })
      .position({ x: 12, y: this.statusBarHeight + 120 })
    }
    .width('100%')
    .height('100%')
  }

}
