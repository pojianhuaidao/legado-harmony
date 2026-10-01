import { common } from '@kit.AbilityKit';
import { router } from '@kit.ArkUI';
import { util } from '@kit.ArkTS';
import { ImmersiveBackButton } from '../components/ImmersiveBackButton';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { syncSystemBars } from '../utils/SystemBars';

@Entry
@Component
struct OpenSourceLicensesPage {
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageLink('themeRevision') themeRevision: number = 0;
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navBarHeight') navBarHeight: number = 0;
  @State licenseText: string = '正在加载开源许可…';

  aboutToAppear(): void {
    this.syncBars();
    this.loadLicenseText();
  }

  onPageShow(): void {
    this.syncBars();
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Scroll() {
        Column() {
          Column() {
            Text('爱·阅读采用 GPL-3.0 许可证，并包含 ohos_quickjs、QuickJS 和部分 OpenHarmony/Huawei N-API 封装代码。以下源码信息、版权声明与完整许可文本随 HAP 一同分发。')
              .fontSize(14)
              .fontColor(this.secondaryTextColor())
              .lineHeight(22)
              .width('100%')
          }
          .width('100%')
          .padding(16)
          .backgroundColor(this.cardColor())
          .borderRadius(10)
          .margin({ left: 16, right: 16, bottom: 12 })
          .alignItems(HorizontalAlign.Start)

          Column() {
            Text(this.licenseText)
              .fontSize(12)
              .fontColor(this.primaryTextColor())
              .lineHeight(19)
              .width('100%')
              .copyOption(CopyOptions.LocalDevice)
          }
          .width('100%')
          .padding(16)
          .backgroundColor(this.cardColor())
          .borderRadius(10)
          .margin({ left: 16, right: 16, bottom: 24 + this.navBarHeight })
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .padding({ top: 56 + this.statusBarHeight })
        .alignItems(HorizontalAlign.Center)
      }
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .width('100%')
      .height('100%')

      Row() {
        ImmersiveBackButton({ iconColor: this.primaryTextColor(), darkMode: this.appDarkMode,
          buttonSize: 40, containerWidth: 56, materialScale: 0.83, compactLayout: true,
          onBack: () => router.back() })

        Text('开源软件许可')
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
    .width('100%')
    .height('100%')
    .backgroundColor(this.pageColor())
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  async loadLicenseText(): Promise<void> {
    const context = getContext(this) as common.UIAbilityContext;
    try {
      const gplBytes = await context.resourceManager.getRawFileContent('licenses/GPL-3.0.txt');
      const thirdPartyBytes = await context.resourceManager
        .getRawFileContent('licenses/THIRD_PARTY_LICENSES.txt');
      const projectNotice = 'OPEN SOURCE PROJECT INFORMATION\n' +
        '开源项目信息\n\n' +
        'Project / 项目：爱·阅读 / legado-harmony\n' +
        'Copyright (c) 2026 李其健\n' +
        'Source / 源码：https://github.com/wip3l/legado-harmony\n' +
        'License / 许可证：GNU General Public License version 3 (GPL-3.0)\n\n';
      const gplText = util.TextDecoder.create('utf-8').decodeWithStream(gplBytes, { stream: false });
      const thirdPartyText = util.TextDecoder.create('utf-8')
        .decodeWithStream(thirdPartyBytes, { stream: false });
      this.licenseText = projectNotice + gplText + '\n\n' + thirdPartyText;
    } catch (error) {
      console.error('加载开源许可失败:', error);
      this.licenseText = '开源许可文本加载失败，请查看项目根目录 LICENSE、NOTICE 和 THIRD_PARTY_NOTICES.md。';
    }
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

  secondaryTextColor(): string {
    return ThemeRuntime.subTextColor(this.appDarkMode);
  }

  syncBars(): void {
    syncSystemBars(getContext(this), this.appDarkMode, this.pageColor());
  }
}
