/**
 * 订阅管理页（书源管理「订阅管理」入口路由目标）
 * 内嵌 SubscriptionTab（pageMode=true），顶部带返回按钮与「订阅管理」标题。
 */
import { router } from '@kit.ArkUI';
import { SubscriptionTab } from '../components/SubscriptionTab';
import { syncSystemBars } from '../utils/SystemBars';
import { ThemeRuntime } from '../theme/ThemeRuntime';

@Entry
@Component
struct SubscriptionIndexPage {
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageLink('themeRevision') themeRevision: number = 0;
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navBarHeight') navBarHeight: number = 0;

  onPageShow(): void {
    syncSystemBars();
  }

  onBackPress(): boolean {
    router.back();
    return true;
  }

  build() {
    Column() {
      SubscriptionTab({
        statusBarHeight: this.statusBarHeight,
        navBarHeight: this.navBarHeight,
        isActive: true,
        pageMode: true
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(ThemeRuntime.pageColor(this.appDarkMode))
  }
}
