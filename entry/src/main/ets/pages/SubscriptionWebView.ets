/**
 * 订阅源(RSS)Web 阅读页 —— 从 legado-Harmony rssWebView.ets 移植，按爱·阅读风格重写
 *
 * 从原版 rssWebView.ets 搬运的浏览器能力：
 *  1) 自定义 UA（Android / iPhone / 电脑 / 自定义），@StorageLink('systemUa') 持久化并实时生效；
 *  2) 浏览器菜单：刷新、复制链接、用系统浏览器打开、UA 设置；
 *  3) 收藏 / 取消收藏（复用 AppDatabase 订阅源 DAO，收藏进「收藏夹」分组）；
 *  4) sourceUrl 为空时兜底加载，避免空白页与打开失败；
 *  5) onErrorReceive 展示错误码与错误描述，便于定位失败原因；
 *  6) 返回 / 历史回退后触发 rssSourcesVersion 自增，订阅列表自动刷新。
 */
import { router, promptAction } from '@kit.ArkUI';
import { webview } from '@kit.ArkWeb';
import pasteboard from '@ohos.pasteboard';
import { common, Want } from '@kit.AbilityKit';
import { syncSystemBars } from '../utils/SystemBars';
import { ImmersiveBackButton } from '../components/ImmersiveBackButton';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { AppDatabase } from '../model/data/AppDatabase';
import { rssSources, WEB_USER_AGENT, SUBSCRIPTION_GROUP_TYPE } from '../model/data/RssSource';

const FALLBACK_URL = 'https://www.baidu.com';
const UA_LABELS: string[] = ['Android', 'iPhone', '电脑', '自定义'];

/**
 * 浏览器菜单弹窗（搬运自原版 WebSetup.ets，按爱·阅读风格重写）
 */
@CustomDialog
struct WebMenuDialog {
  controller?: CustomDialogController
  onRefresh: () => void = () => {}
  onCopyUrl: () => void = () => {}
  onOpenBrowser: () => void = () => {}
  onOpenUa: () => void = () => {}
  primaryTextColor: string = '#000000'
  cardColor: string = '#FFFFFF'

  build() {
    Column() {
      Column({ space: 0 }) {
        this.menuRow('刷新', () => {
          this.controller?.close()
          this.onRefresh()
        })
        Divider().color('#1A000000').margin({ left: 20, right: 20 })
        this.menuRow('复制链接', () => {
          this.controller?.close()
          this.onCopyUrl()
        })
        Divider().color('#1A000000').margin({ left: 20, right: 20 })
        this.menuRow('系统浏览器打开', () => {
          this.controller?.close()
          this.onOpenBrowser()
        })
        Divider().color('#1A000000').margin({ left: 20, right: 20 })
        this.menuRow('UA 设置', () => {
          this.onOpenUa()
        })
      }
      .width('100%')
      .backgroundColor(this.cardColor)
      .borderRadius({ topLeft: 16, topRight: 16 })

      Text('取消')
        .fontSize(16)
        .fontColor(this.primaryTextColor)
        .textAlign(TextAlign.Center)
        .width('100%')
        .height(52)
        .backgroundColor(this.cardColor)
        .borderRadius(16)
        .margin({ top: 8 })
        .onClick(() => {
          this.controller?.close()
        })
    }
    .width('100%')
    .padding({ left: 12, right: 12, bottom: 16 })
  }

  @Builder
  menuRow(title: string, action: () => void) {
    Row() {
      Text(title)
        .fontSize(16)
        .fontColor(this.primaryTextColor)
      Blank()
      Text('›')
        .fontSize(18)
        .fontColor(this.primaryTextColor)
        .opacity(0.4)
    }
    .width('100%')
    .height(52)
    .padding({ left: 20, right: 20 })
    .onClick(action)
  }
}

/**
 * UA 设置弹窗（搬运自原版 WebSetupUA.ets，按爱·阅读风格重写）
 */
@CustomDialog
struct UASetupDialog {
  controller?: CustomDialogController
  @StorageLink('systemUa') systemUa: number = 0
  @StorageLink('appDarkMode') appDarkMode: boolean = false
  primaryTextColor: string = '#000000'
  cardColor: string = '#FFFFFF'

  build() {
    Column() {
      Text('UA 设置')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.primaryTextColor)
        .textAlign(TextAlign.Center)
        .width('100%')
        .height(48)

      ForEach(UA_LABELS, (label: string, index: number) => {
        Row() {
          Text(label)
            .fontSize(16)
            .fontColor(this.primaryTextColor)
          Blank()
          if (this.systemUa === index) {
            Text('✓')
              .fontSize(16)
              .fontColor(ThemeRuntime.accentColor(this.appDarkMode))
          }
        }
        .width('100%')
        .height(48)
        .padding({ left: 20, right: 20 })
        .onClick(() => {
          this.systemUa = index
          this.controller?.close()
        })
      })

      Divider().color('#1A000000').margin({ left: 20, right: 20 })
      Text('取消')
        .fontSize(16)
        .fontColor(this.primaryTextColor)
        .textAlign(TextAlign.Center)
        .width('100%')
        .height(48)
        .onClick(() => {
          this.controller?.close()
        })
    }
    .width('100%')
    .backgroundColor(this.cardColor)
    .borderRadius({ topLeft: 16, topRight: 16 })
    .padding({ bottom: 16 })
  }
}

@Entry
@Component
struct SubscriptionWebViewPage {
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageLink('themeRevision') themeRevision: number = 0;
  @StorageLink('systemUa') @Watch('onSystemUaChanged') systemUa: number = 0;
  @StorageLink('searchExploreAdBlockEnabled') adBlockEnabled: boolean = true;
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navBarHeight') navBarHeight: number = 0;
  @State sourceUrl: string = '';
  @State sourceName: string = '';
  @State sourceIcon: string = '';
  @State sourceGroup: string = '';
  @State currentUrl: string = '';
  @State progress: number = 0;
  @State canGoBack: boolean = false;
  @State isCollected: boolean = false;
  private mainFrameLoaded: boolean = false;
  private pendingMainFrameError: string = '';
  private lastErrorNotifiedUrl: string = '';
  private controller: webview.WebviewController = new webview.WebviewController();

  webMenuDialog: CustomDialogController | null = new CustomDialogController({
    builder: WebMenuDialog({
      primaryTextColor: this.primaryTextColor(),
      cardColor: this.cardColor(),
      onRefresh: (): void => {
        this.controller.refresh();
      },
      onCopyUrl: (): void => {
        this.copyCurrentUrl();
      },
      onOpenBrowser: (): void => {
        this.openSystemBrowser();
      },
      onOpenUa: (): void => {
        this.uaSetupDialog?.open();
      }
    }),
    autoCancel: true,
    alignment: DialogAlignment.Bottom,
    customStyle: true,
    backgroundColor: Color.Transparent
  })

  uaSetupDialog: CustomDialogController | null = new CustomDialogController({
    builder: UASetupDialog({
      primaryTextColor: this.primaryTextColor(),
      cardColor: this.cardColor()
    }),
    autoCancel: true,
    alignment: DialogAlignment.Bottom,
    customStyle: true,
    backgroundColor: Color.Transparent
  })

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
    if (this.sourceUrl.length === 0) {
      this.sourceUrl = FALLBACK_URL;
    }
    this.currentUrl = this.sourceUrl;
    this.applyUserAgent();
    this.refreshCollectedState();
  }

  onPageShow(): void {
    syncSystemBars(getContext(this), this.appDarkMode);
  }

  onBackPress(): boolean {
    if (this.canGoBack) {
      this.controller.backward();
      return true;
    }
    this.notifyListRefresh();
    return false;
  }

  onSystemUaChanged(): void {
    this.applyUserAgent();
    this.controller.refresh();
  }

  applyUserAgent(): void {
    try {
      const index = this.systemUa >= 0 && this.systemUa < WEB_USER_AGENT.length ? this.systemUa : 0;
      this.controller.setCustomUserAgent(WEB_USER_AGENT[index]);
    } catch (e) {
      // controller 尚未绑定 Web 组件时忽略，onPageBegin 会再次设置
    }
  }

  copyCurrentUrl(): void {
    const url = this.currentUrl.length > 0 ? this.currentUrl : this.sourceUrl;
    const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, url);
    const systemPasteboard = pasteboard.getSystemPasteboard();
    systemPasteboard.setData(data).then(() => {
      promptAction.showToast({ message: '链接已复制' });
    }).catch(() => {
      promptAction.showToast({ message: '复制失败' });
    });
  }

  openSystemBrowser(): void {
    const ctx = getContext(this) as common.UIAbilityContext;
    const url = this.currentUrl.length > 0 ? this.currentUrl : this.sourceUrl;
    const want: Want = {
      action: 'ohos.want.action.viewData',
      entities: ['entity.system.browsable'],
      uri: url
    };
    ctx.startAbility(want).then(() => {
    }).catch(() => {
      promptAction.showToast({ message: '打开系统浏览器失败' });
    });
  }

  refreshCollectedState(): void {
    if (this.sourceUrl.length === 0 || this.sourceUrl === FALLBACK_URL) {
      this.isCollected = false;
      return;
    }
    AppDatabase.getInstance().getRssSourcesByUrl(this.sourceUrl).then((item: rssSources | null) => {
      this.isCollected = item !== null;
    }).catch(() => {
      this.isCollected = false;
    });
  }

  toggleCollect(): void {
    if (this.sourceUrl.length === 0 || this.sourceUrl === FALLBACK_URL) {
      promptAction.showToast({ message: '当前页面不可收藏' });
      return;
    }
    if (this.isCollected) {
      AppDatabase.getInstance().getRssSourcesByUrl(this.sourceUrl).then((item: rssSources | null) => {
        if (item) {
          return AppDatabase.getInstance().deleteRssSources(item);
        }
        return Promise.resolve(false);
      }).then((ok: boolean) => {
        this.isCollected = !ok;
        this.notifyListRefresh();
        promptAction.showToast({ message: '已取消收藏' });
      }).catch(() => {
        promptAction.showToast({ message: '操作失败' });
      });
    } else {
      const item = new rssSources();
      item.sourceType = 0;
      item.sourceName = this.sourceName.length > 0 ? this.sourceName : this.currentUrl;
      item.sourceUrl = this.sourceUrl;
      item.sourceIcon = this.sourceIcon;
      item.sourceIconIsUrl = false;
      item.sourceGroup = SUBSCRIPTION_GROUP_TYPE[4];
      item.lastUpdateTime = Date.now();
      item.customizeTitle = this.sourceName;
      AppDatabase.getInstance().insertRssSource(item).then((ok: boolean) => {
        this.isCollected = ok;
        this.notifyListRefresh();
        promptAction.showToast({ message: ok ? '已收藏到收藏夹' : '收藏失败' });
      }).catch(() => {
        promptAction.showToast({ message: '操作失败' });
      });
    }
  }

  notifyListRefresh(): void {
    const version = AppStorage.get<number>('rssSourcesVersion') ?? 0;
    AppStorage.setOrCreate('rssSourcesVersion', version + 1);
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

        Text(this.isCollected ? '★' : '☆')
          .fontSize(20)
          .fontColor(this.isCollected ? this.accentColor() : this.subTextColor())
          .width(40)
          .height(56)
          .textAlign(TextAlign.Center)
          .onClick(() => {
            this.toggleCollect();
          })

        Text('···')
          .fontSize(20)
          .fontColor(this.primaryTextColor())
          .width(44)
          .height(56)
          .textAlign(TextAlign.Center)
          .onClick(() => {
            this.webMenuDialog?.open();
          })

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
          this.mainFrameLoaded = false;
          this.pendingMainFrameError = '';
          this.lastErrorNotifiedUrl = '';
          this.applyUserAgent();
        })
        .onPageEnd((event?: OnPageEndEvent) => {
          if (event && event.url) {
            this.currentUrl = event.url;
          }
          this.mainFrameLoaded = true;
          this.pendingMainFrameError = '';
          this.updateNavState();
        })
        .onProgressChange((event?: OnProgressChangeEvent) => {
          this.progress = event ? event.newProgress : 0;
          if (this.progress === 100) {
            this.updateNavState();
          }
        })
        .onInterceptRequest((event?: OnInterceptRequestEvent): WebResourceResponse | null => {
          // 去广告开关开启时，拦截命中黑名单的广告请求（主框架请求放行，避免误伤整页）
          if (this.adBlockEnabled && event && event.request) {
            const requestUrl = event.request.getRequestUrl();
            if (requestUrl && !event.request.isMainFrame() && AdBlocker.shouldBlockRequest(requestUrl)) {
              const blocked = new webview.WebResourceResponse();
              blocked.setResponseMimeType('text/html');
              blocked.setResponseEncoding('UTF-8');
              blocked.setResponseData('');
              return blocked;
            }
          }
          return null;
        })
        .onAlert((event?: OnAlertEvent): boolean => {
          // 去广告开关开启时，广告弹窗取消；非广告弹窗（如书山源更新公告）放行走默认展示
          if (this.adBlockEnabled && event && AdBlocker.shouldBlockAlert(event.url, event.message)) {
            event.result.handleCancel();
            return true;
          }
          return false;
        })
        .onErrorReceive((event?: OnErrorReceiveEvent) => {
          const code = event ? event.error.getErrorCode() : -1;
          const info = event ? event.error.getErrorInfo() : '';
          if (this.mainFrameLoaded) {
            // 主页面已经加载成功，本次错误来自子资源（广告、iframe、图片等），
            // 页面仍可正常使用，不再弹错误提示。
            return;
          }
          this.pendingMainFrameError = `加载失败(${code}): ${info}`;
          setTimeout(() => {
            if (this.mainFrameLoaded || !this.pendingMainFrameError) return;
            if (this.progress >= 100) return;
            const message = this.pendingMainFrameError;
            this.pendingMainFrameError = '';
            const key = this.currentUrl || this.sourceUrl;
            if (!key || this.lastErrorNotifiedUrl === key) return;
            this.lastErrorNotifiedUrl = key;
            promptAction.showToast({ message: message });
          }, 900);
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
