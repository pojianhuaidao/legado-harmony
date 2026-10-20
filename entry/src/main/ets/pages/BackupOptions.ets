import { common } from '@kit.AbilityKit';
import { router, promptAction } from '@kit.ArkUI';
import { syncSystemBars } from '../utils/SystemBars';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { ImmersiveBackButton } from '../components/ImmersiveBackButton';
import { ImmersiveMaterialRuntime } from '../utils/ImmersiveMaterialRuntime';
import { CloudBackupItem, HuaweiCloudService } from '../utils/HuaweiCloudService';

@Entry
@Component
struct BackupOptionsPage {
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageLink('themeRevision') themeRevision: number = 0;
  @StorageLink('huaweiCloudConfigured') huaweiCloudConfigured: boolean = false;
  @StorageLink('huaweiCloudUid') huaweiCloudUid: string = '';
  @StorageLink('huaweiCloudName') huaweiCloudName: string = '';
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navBarHeight') navBarHeight: number = 0;
  @State backupPasswordDraft: string = '';
  @State restorePasswordDraft: string = '';
  @State backups: CloudBackupItem[] = [];
  @State backupsLoaded: boolean = false;
  @State busy: boolean = false;
  @State busyText: string = '';
  @State traceText: string = '';

  aboutToAppear(): void {
    if (this.huaweiCloudConfigured && this.huaweiCloudUid) {
      this.refreshBackups();
    }
  }

  onPageShow(): void {
    this.syncBars();
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Scroll() {
        Column() {
          if (!this.huaweiCloudConfigured) {
            this.notConfiguredCard()
          }

          this.sectionTitle('华为账号')
          Column() {
            if (this.huaweiCloudUid) {
              this.accountRow()
            } else {
              this.loginRow()
            }
          }
          .width('calc(100% - 24vp)')
          .margin({ left: 12, right: 12 })
          .borderRadius(16)
          .clip(true)
          .backgroundColor(this.cardColor())

          if (this.huaweiCloudConfigured && this.huaweiCloudUid) {
            this.sectionTitle('华为远端备份')
            Column() {
              TextInput({ text: this.backupPasswordDraft, placeholder: '备份密码（留空则不加密，敏感字段将被排除）' })
                .type(InputType.Password)
                .width('calc(100% - 32vp)')
                .margin({ left: 16, right: 16, top: 14 })
                .fontColor(this.primaryTextColor())
                .placeholderColor(this.subTextColor())
                .onChange((value: string) => this.backupPasswordDraft = value)
              Button(this.busy ? (this.busyText === '备份' || this.busyText === '' ? '正在备份...' : this.busyText) : '备份到华为云端')
                .width('calc(100% - 32vp)')
                .margin({ left: 16, right: 16, top: 12, bottom: 14 })
                .fontSize(15)
                .fontColor(Color.White)
                .backgroundColor(this.buttonColor())
                .enabled(!this.busy)
                .onClick(() => this.startBackup())
              TextInput({ text: this.restorePasswordDraft, placeholder: '恢复密码（云端备份加密时必填）' })
                .type(InputType.Password)
                .width('calc(100% - 32vp)')
                .margin({ left: 16, right: 16, bottom: 4 })
                .fontColor(this.primaryTextColor())
                .placeholderColor(this.subTextColor())
                .onChange((value: string) => this.restorePasswordDraft = value)
              Button(this.busy && this.busyText === '恢复' ? '正在恢复...' : '从云端恢复')
                .width('calc(100% - 32vp)')
                .margin({ left: 16, right: 16, top: 8, bottom: 14 })
                .fontSize(15)
                .fontColor(this.buttonColor())
                .backgroundColor(Color.Transparent)
                .border({ width: 1, color: this.buttonColor() })
                .enabled(!this.busy)
                .onClick(() => this.startRestore())
              if (this.backupsLoaded) {
                Text(this.backups.length > 0 ? `云端已有 ${this.backups.length} 份备份` : '云端还没有备份')
                  .fontSize(12)
                  .fontColor(this.subTextColor())
                  .width('calc(100% - 32vp)')
                  .margin({ left: 16, right: 16, bottom: 8 })
              }
              Text('查看备份诊断日志')
                .fontSize(12)
                .fontColor(this.accentColor())
                .width('calc(100% - 32vp)')
                .margin({ left: 16, right: 16, bottom: 8 })
                .onClick(() => {
                  this.traceText = HuaweiCloudService.readTrace(getContext(this) as common.UIAbilityContext);
                })
              if (this.traceText.length > 0) {
                Text(this.traceText)
                  .fontSize(11)
                  .fontFamily('monospace')
                  .fontColor(this.subTextColor())
                  .width('calc(100% - 32vp)')
                  .margin({ left: 16, right: 16, bottom: 12 })
                  .maxLines(200)
              }
            }
            .width('calc(100% - 24vp)')
            .margin({ left: 12, right: 12 })
            .borderRadius(16)
            .clip(true)
            .backgroundColor(this.cardColor())

            if (this.backups.length > 0) {
              this.sectionTitle('云端备份列表')
              Column() {
                ForEach(this.backups, (item: CloudBackupItem) => {
                  this.backupRow(item)
                }, (item: CloudBackupItem) => item.cloudPath)
              }
              .width('calc(100% - 24vp)')
              .margin({ left: 12, right: 12 })
              .borderRadius(16)
              .clip(true)
              .backgroundColor(this.cardColor())
            }
          }

          this.sectionTitle('本地备份与 WebDAV')
          Column() {
            this.menuItem('WebDAV', '浏览远程 TXT / EPUB，并管理加密备份', true, () => {
              router.pushUrl({ url: 'pages/WebDav' });
            })
            this.menuItem('数据导入', '从备份文件导入书源、书架、进度、本地图书和设置', true, () => {
              router.pushUrl({ url: 'pages/DataBackup', params: { mode: 'import' } });
            })
            this.menuItem('数据导出', '将书源、书架、进度、本地图书和设置导出为备份', false, () => {
              router.pushUrl({ url: 'pages/DataBackup', params: { mode: 'export' } });
            })
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

  @Builder
  notConfiguredCard() {
    Column() {
      Text('尚未接入华为账号服务')
        .fontSize(16)
        .fontColor(this.primaryTextColor())
        .width('100%')
      Text('请在 AGC 控制台开通 Auth Service 与 Cloud Storage，下载 agconnect-services.json 放入 entry/src/main/resources/rawfile/ 后重启应用。')
        .fontSize(12)
        .fontColor(this.subTextColor())
        .margin({ top: 6 })
        .width('100%')
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .maxLines(4)
    }
    .width('calc(100% - 32vp)')
    .margin({ left: 16, right: 16, top: 8 })
    .padding(14)
    .borderRadius(12)
    .backgroundColor(this.cardColor())
  }

  @Builder
  loginRow() {
    Row() {
      Column() {
        Text('登录华为账号')
          .fontSize(16)
          .fontColor(this.primaryTextColor())
        Text('登录后可把书架、书源、进度、设置等备份到华为云端')
          .fontSize(12)
          .fontColor(this.subTextColor())
          .margin({ top: 4 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Button(this.busy ? '登录中...' : '登录')
        .fontSize(14)
        .fontColor(Color.White)
        .backgroundColor(this.buttonColor())
        .enabled(!this.busy)
        .onClick(() => this.signIn())
    }
    .width('calc(100% - 32vp)')
    .constraintSize({ minHeight: 72 })
    .padding({ left: 0, right: 0 })
    .margin({ left: 16, right: 16 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  accountRow() {
    Row() {
      Column() {
        Text(this.huaweiCloudName || '华为账号')
          .fontSize(16)
          .fontColor(this.primaryTextColor())
        Text(`已登录：${this.huaweiCloudUid}`)
          .fontSize(12)
          .fontColor(this.subTextColor())
          .margin({ top: 4 })
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .maxLines(1)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Button('退出登录')
        .fontSize(14)
        .fontColor(this.primaryTextColor())
        .backgroundColor(Color.Transparent)
        .border({ width: 1, color: this.subTextColor() })
        .enabled(!this.busy)
        .onClick(() => this.signOut())
    }
    .width('calc(100% - 32vp)')
    .constraintSize({ minHeight: 72 })
    .padding({ left: 0, right: 0 })
    .margin({ left: 16, right: 16 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  backupRow(item: CloudBackupItem) {
    Row() {
      Column() {
        Text(item.name)
          .fontSize(14)
          .fontColor(this.primaryTextColor())
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .maxLines(1)
          .width('100%')
        Text(this.backupMeta(item))
          .fontSize(12)
          .fontColor(this.subTextColor())
          .margin({ top: 3 })
          .width('100%')
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Button('恢复')
        .fontSize(13)
        .fontColor(Color.White)
        .backgroundColor(this.buttonColor())
        .enabled(!this.busy)
        .margin({ right: 8 })
        .onClick(() => this.restoreBackup(item))

      Button('删除')
        .fontSize(13)
        .fontColor(this.dangerColor())
        .backgroundColor(Color.Transparent)
        .enabled(!this.busy)
        .onClick(() => this.deleteBackup(item))
    }
    .width('calc(100% - 32vp)')
    .constraintSize({ minHeight: 64 })
    .padding({ left: 0, right: 0 })
    .margin({ left: 16, right: 16 })
    .backgroundColor(Color.Transparent)
    .border({ width: { bottom: 0.5 }, color: this.appDarkMode ? '#24FFFFFF' : '#14000000' })
    .alignItems(VerticalAlign.Center)
  }

  backupMeta(item: CloudBackupItem): string {
    let text = '';
    if (item.updatedTime > 0) {
      const date = new Date(item.updatedTime);
      text = `${date.getFullYear()}-${this.two(date.getMonth() + 1)}-${this.two(date.getDate())} ` +
        `${this.two(date.getHours())}:${this.two(date.getMinutes())}`;
    }
    if (item.size > 0) {
      text = text ? `${text} · ${(item.size / 1024 / 1024).toFixed(1)} MB` : `${(item.size / 1024 / 1024).toFixed(1)} MB`;
    }
    return text || '未知时间';
  }

  two(value: number): string {
    return value < 10 ? `0${value}` : `${value}`;
  }

  async signIn(): Promise<void> {
    this.busy = true;
    this.busyText = '登录';
    try {
      const ok = await HuaweiCloudService.signIn();
      if (ok) {
        promptAction.showToast({ message: '华为账号登录成功' });
        this.refreshBackups();
      } else {
        promptAction.showToast({ message: '未获取到账号信息' });
      }
    } catch (e) {
      promptAction.showToast({ message: (e as Error).message || '登录失败' });
    } finally {
      this.busy = false;
      this.busyText = '';
    }
  }

  async signOut(): Promise<void> {
    this.busy = true;
    this.busyText = '退出';
    try {
      await HuaweiCloudService.signOut();
      this.backups = [];
      this.backupsLoaded = false;
      promptAction.showToast({ message: '已退出华为账号' });
    } finally {
      this.busy = false;
      this.busyText = '';
    }
  }

  async startBackup(): Promise<void> {
    this.busy = true;
    this.busyText = '备份';
    try {
      const cloudPath = await HuaweiCloudService.backupToCloud(getContext(this) as common.UIAbilityContext, this.backupPasswordDraft.trim(),
        (message: string, percent: number) => {
          this.busyText = message.length > 0 ? message : '备份';
          this.busy = true;
        });
      promptAction.showToast({ message: `备份成功：${cloudPath}` });
      this.refreshBackups();
    } catch (e) {
      promptAction.showToast({ message: (e as Error).message || '备份失败' });
    } finally {
      this.busy = false;
      this.busyText = '';
    }
  }

  /** 从云端恢复：与「备份到华为云端」对称的主入口。列出云端备份并恢复最新一份（更精细的按条恢复见备份列表行内「恢复」按钮）。 */
  async startRestore(): Promise<void> {
    // 备份列表未加载时先刷新
    if (!this.backupsLoaded && !this.busy) {
      this.backupsLoaded = false;
      try {
        this.backups = await HuaweiCloudService.listBackups();
        this.backupsLoaded = true;
      } catch (e) {
        this.backupsLoaded = true;
        promptAction.showToast({ message: '读取云端备份失败，请稍后重试' });
        return;
      }
    }
    if (this.backups.length === 0) {
      promptAction.showToast({ message: '云端还没有备份，无法恢复' });
      return;
    }
    // 列表按修改时间倒序，最新一份排最前
    const target = this.backups[0];
    // 恢复会覆盖本地数据，先确认
    try {
      const confirm = await promptAction.showDialog({
        title: '从云端恢复',
        message: `将使用最新备份 ${target.name} 恢复书架、书源、进度、设置等数据，当前本地数据会被覆盖。是否继续？`,
        buttons: [
          { text: '取消', color: this.subTextColor() },
          { text: '恢复', color: this.dangerColor() }
        ]
      });
      if (confirm.index !== 1) {
        return;
      }
    } catch (e) {
      return;
    }
    this.busy = true;
    this.busyText = '恢复';
    try {
      const result = await HuaweiCloudService.restoreFromCloud(getContext(this) as common.UIAbilityContext, target.cloudPath,
        this.restorePasswordDraft.trim());
      promptAction.showToast({ message: `恢复完成：${result.summary()}` });
    } catch (e) {
      promptAction.showToast({ message: (e as Error).message || '恢复失败' });
    } finally {
      this.busy = false;
      this.busyText = '';
    }
  }

  async restoreBackup(item: CloudBackupItem): Promise<void> {
    this.busy = true;
    this.busyText = '恢复';
    try {
      const result = await HuaweiCloudService.restoreFromCloud(getContext(this) as common.UIAbilityContext, item.cloudPath,
        this.restorePasswordDraft.trim());
      promptAction.showToast({ message: `恢复完成：${result.summary()}` });
    } catch (e) {
      promptAction.showToast({ message: (e as Error).message || '恢复失败' });
    } finally {
      this.busy = false;
      this.busyText = '';
    }
  }

  async deleteBackup(item: CloudBackupItem): Promise<void> {
    try {
      const confirm = await promptAction.showDialog({
        title: '删除云端备份',
        message: `确定删除 ${item.name} 吗？此操作不可恢复。`,
        buttons: [
          { text: '取消', color: this.subTextColor() },
          { text: '删除', color: this.dangerColor() }
        ]
      });
      if (confirm.index !== 1) {
        return;
      }
    } catch (e) {
      return;
    }
    this.busy = true;
    this.busyText = '删除';
    try {
      await HuaweiCloudService.deleteBackup(item.cloudPath);
      promptAction.showToast({ message: '已删除' });
      this.refreshBackups();
    } catch (e) {
      promptAction.showToast({ message: (e as Error).message || '删除失败' });
    } finally {
      this.busy = false;
      this.busyText = '';
    }
  }

  async refreshBackups(): Promise<void> {
    if (!this.huaweiCloudConfigured || !this.huaweiCloudUid || this.busy) {
      return;
    }
    this.backupsLoaded = false;
    try {
      this.backups = await HuaweiCloudService.listBackups();
      this.backupsLoaded = true;
    } catch (e) {
      this.backupsLoaded = true;
      console.warn('[BackupOptions] list backups failed', JSON.stringify(e));
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

  subTextColor(): string {
    return ThemeRuntime.subTextColor(this.appDarkMode);
  }

  buttonColor(): string {
    return ThemeRuntime.buttonColor(this.appDarkMode);
  }

  dangerColor(): string {
    return ThemeRuntime.dangerColor(this.appDarkMode);
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
      Text('备份选项')
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
  menuItem(title: string, desc: string, showDivider: boolean, onClick: () => void) {
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
    .border({ width: { bottom: showDivider ? 0.5 : 0 },
      color: this.appDarkMode ? '#24FFFFFF' : '#14000000' })
    .alignItems(VerticalAlign.Center)
    .onClick(onClick)
  }

  @Builder
  sectionTitle(title: string) {
    Text(title)
      .fontSize(13)
      .fontColor(this.subTextColor())
      .width('100%')
      .padding({ left: 16, right: 16, top: 20, bottom: 8 })
  }
}
