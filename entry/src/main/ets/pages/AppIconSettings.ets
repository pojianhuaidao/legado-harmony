import { router, promptAction } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { syncSystemBars } from '../utils/SystemBars';
import { AppIconManager, AppIconOption } from '../utils/AppIconManager';
import { AppIconSettings, AppIconSettingsStore } from '../utils/AppIconSettingsStore';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { ImmersiveBackButton } from '../components/ImmersiveBackButton';

@Entry
@Component
struct AppIconSettingsPage {
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageLink('themeRevision') themeRevision: number = 0;
  @StorageLink('appIconId') appIconId: string = AppIconSettingsStore.DEFAULT_ICON_ID;
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navBarHeight') navBarHeight: number = 0;
  aboutToAppear(): void {
    this.syncBars();
    AppIconSettingsStore.load(getContext(this)).then((settings: AppIconSettings) => {
      AppIconSettingsStore.applyToStorage(settings);
    }).catch(() => {
      AppStorage.setOrCreate(AppIconSettingsStore.KEY_ICON_ID, AppIconSettingsStore.DEFAULT_ICON_ID);
    });
  }

  onPageShow(): void {
    this.syncBars();
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Scroll() {
        Column() {
          Text('选择桌面图标')
            .fontSize(13)
            .fontColor(this.subTextColor())
            .width('100%')
            .padding({ left: 16, right: 16, top: 20, bottom: 8 })

          Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
            ForEach(AppIconManager.OPTIONS, (option: AppIconOption) => {
              this.iconCard(option)
            }, (option: AppIconOption) => option.id)
          }
          .width('100%')
          .padding({ left: 12, right: 12 })
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

  optionBorderColor(selected: boolean): string {
    if (selected) {
      return ThemeRuntime.accentColor(this.appDarkMode);
    }
    return ThemeRuntime.dividerColor(this.appDarkMode);
  }

  syncBars(): void {
    syncSystemBars(getContext(this), this.appDarkMode, this.pageColor());
  }

  selectIcon(option: AppIconOption): void {
    if (this.appIconId === option.id) {
      this.showToastSafely(`当前已是${option.title}`);
      return;
    }
    const settings = new AppIconSettings();
    settings.iconId = option.id;
    AppIconSettingsStore.applyToStorage(settings);
    AppIconSettingsStore.save(getContext(this), settings).catch((e: Error) => {
      hilog.warn(0x0000, 'appIcon', 'Save app icon selection failed err=%{public}s', JSON.stringify(e));
    });
    this.showToastSafely(`已选择${option.title}图标，需重新构建侧载包（scripts\\build_sidecar.ps1 -IconId ${option.id}）后安装生效`);
  }

  showToastSafely(message: string): void {
    try {
      promptAction.showToast({ message: message });
    } catch (e) {
      hilog.warn(0x0000, 'appIcon', 'Show app icon toast failed err=%{public}s', JSON.stringify(e));
    }
  }

  backSafely(): void {
    try {
      router.back();
    } catch (e) {
      hilog.warn(0x0000, 'appIcon', 'Back from app icon settings failed err=%{public}s', JSON.stringify(e));
    }
  }

  @Builder
  titleBar() {
    Row() {
      ImmersiveBackButton({ iconColor: this.primaryTextColor(), darkMode: this.appDarkMode,
        buttonSize: 40, containerWidth: 56, materialScale: 0.83, compactLayout: true,
        onBack: () => this.backSafely() })
      Text('图标设置')
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
  iconCard(option: AppIconOption) {
    Column() {
      Stack({ alignContent: Alignment.TopEnd }) {
        Image(option.preview)
          .width(72)
          .height(72)
          .borderRadius(18)
          .objectFit(ImageFit.Cover)
        if (this.appIconId === option.id) {
          Text('✓')
            .fontSize(14)
            .fontColor('#FFFFFF')
            .fontWeight(FontWeight.Bold)
            .width(22)
            .height(22)
            .textAlign(TextAlign.Center)
            .backgroundColor(ThemeRuntime.accentColor(this.appDarkMode))
            .borderRadius(11)
            .margin({ top: -4, right: -4 })
        }
      }
      .width(82)
      .height(82)
      .alignContent(Alignment.Center)

      Text(option.title)
        .fontSize(15)
        .fontColor(this.primaryTextColor())
        .fontWeight(FontWeight.Medium)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: 8 })

      Text(option.desc)
        .fontSize(11)
        .fontColor(this.subTextColor())
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: 3 })
    }
    .width('48%')
    .height(166)
    .padding({ top: 14, left: 10, right: 10, bottom: 12 })
    .margin({ bottom: 12 })
    .backgroundColor(this.cardColor())
    .borderRadius(8)
    .border({ width: 1, color: this.optionBorderColor(this.appIconId === option.id) })
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      this.selectIcon(option);
    })
  }
}
