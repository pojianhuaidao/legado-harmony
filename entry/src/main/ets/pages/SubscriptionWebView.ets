/**
 * 订阅源(RSS)Web 阅读页 —— 从 legado-Harmony rssWebView.ets 移植，按爱·阅读风格重写
 *
 * 通过 router 参数接收订阅源信息，加载其 sourceUrl；
 * 支持页面内前进/后退，返回键优先回退 Web 历史。
 */
import { router, promptAction } from '@kit.ArkUI';
import { webview } from '@kit.ArkWeb';
import { syncSystemBars } from '../utils/SystemBars';
import { ImmersiveBackButton } from '../components/ImmersiveBackButton';
import { ThemeRuntime } from '../theme/ThemeRuntime';

@Entry
@Component
struct SubscriptionWebViewPage {
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageLink('themeRevision') themeRevision: number = 0;
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navBarHeight') navBarHeight: number = 0;
  @State sourceUrl: string = '';
  @State sourceName: string = '';
  @State sourceIcon: string = '';
  @State sourceGroup: string = '';
  @State currentUrl: string = '';
  @State progress: number = 0;
  @State canGoBack: boolean = false;
  private controller: webview.WebviewController = new webview.WebviewController();

  aboutToAppear(): void {
    syncSystemBars(getContext(this), this.appDarkMode);
    const params = router.getParams() as Record<string, string>;
    if (params) {
      this.sourceUrl = params['sourceUrl'] || '';
      this.sourceName = params['sourceName'] || '';
      this.sourceIcon = params['sourceIcon'] || '';
      this.sourceGroup = params['sourceGroup'] || '';
      const customTitle = params['customizeTitle'] || '';
      if (customTitle.length > 0) {
        this.sourceName = customTitle;
      }
    }
    this.currentUrl = this.sourceUrl;
  }

  onPageShow(): void {
    syncSystemBars(getContext(this), this.appDarkMode);
  }

  onBackPress(): boolean {
    if (this.canGoBack) {
      this.controller.backward();
      return true;
    }
    return false;
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

  accentColor(): string {
    return ThemeRuntime.accentColor(this.appDarkMode);
  }

  build() {
    Column() {
      Row() {
        ImmersiveBackButton({
          iconColor: this.primaryTextColor(),
          darkMode: this.appDarkMode,
          onBack: () => router.back()
        })

        Column() {
          Text(this.sourceName.length > 0 ? this.sourceName : '订阅源')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.primaryTextColor())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.currentUrl)
            .fontSize(11)
            .fontColor(this.subTextColor())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        SymbolGlyph($r('sys.symbol.arrow_left'))
          .fontSize(21)
          .fontColor([this.canGoBack ? this.primaryTextColor() : this.subTextColor()])
          .width(44)
          .height(56)
          .onClick(() => {
            if (this.canGoBack) {
              this.controller.backward();
            }
          })

        SymbolGlyph($r('sys.symbol.arrow_clockwise'))
          .fontSize(20)
          .fontColor([this.primaryTextColor()])
          .width(44)
          .height(56)
          .onClick(() => {
            this.controller.refresh();
          })
      }
      .width('100%')
      .height(56)
      .padding({ left: 8, right: 8 })
      .backgroundColor(this.cardColor())
      .alignItems(VerticalAlign.Center)

      if (this.progress > 0 && this.progress < 100) {
        Progress({ value: this.progress, total: 100, type: ProgressType.Linear })
          .width('100%')
          .height(2)
          .color(this.accentColor())
      }

      Web({ src: this.sourceUrl, controller: this.controller })
        .width('100%')
        .layoutWeight(1)
        .javaScriptAccess(true)
        .domStorageAccess(true)
        .onlineImageAccess(true)
        .imageAccess(true)
        .mixedMode(MixedMode.All)
        .onPageBegin((event?: OnPageBeginEvent) => {
          if (event && event.url) {
            this.currentUrl = event.url;
          }
        })
        .onPageEnd((event?: OnPageEndEvent) => {
          if (event && event.url) {
            this.currentUrl = event.url;
          }
          this.updateNavState();
        })
        .onProgressChange((event?: OnProgressChangeEvent) => {
          this.progress = event ? event.newProgress : 0;
          if (this.progress === 100) {
            this.updateNavState();
          }
        })
        .onErrorReceive(() => {
          promptAction.showToast({ message: '页面加载失败' });
        })
    }
    .width('100%')
    .height('100%')
    .padding({ top: this.statusBarHeight, bottom: this.navBarHeight })
    .backgroundColor(this.pageColor())
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }

  updateNavState(): void {
    try {
      this.canGoBack = this.controller.accessBackward();
    } catch (e) {
      this.canGoBack = false;
    }
  }
}
