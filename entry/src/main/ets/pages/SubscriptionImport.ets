/**
 * 订阅导入页 —— 从 legado-Harmony SubscriptionImport.ets 精简移植
 * 支持：1) 粘贴订阅源 JSON 文本；2) 输入 URL 网络获取后解析；3) 选择本地文件导入。
 * 复用 RssSourcesUtils.parseRssSourcesFromJson / applyImport 与 AppDatabase 订阅 DAO。
 */
import { router, promptAction } from '@kit.ArkUI';
import http from '@ohos.net.http';
import { picker, fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { rssSources } from '../model/data/RssSource';
import rssSourcesUtil from '../utils/RssSourcesUtils';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { ImmersiveBackButton } from '../components/ImmersiveBackButton';
import { syncSystemBars } from '../utils/SystemBars';

@Entry
@Component
struct SubscriptionImportPage {
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageLink('themeRevision') themeRevision: number = 0;
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navBarHeight') navBarHeight: number = 0;
  @State inputText: string = '';
  @State parseResult: rssSources[] = [];
  @State parseInfo: string = '';
  @State parsing: boolean = false;
  @State errorInfo: string = '';

  onPageShow(): void {
    syncSystemBars(getContext(this), this.appDarkMode);
  }

  onBackPress(): boolean {
    router.back();
    return true;
  }

  async pickSubscriptionFile(): Promise<void> {
    try {
      const documentPicker = new picker.DocumentViewPicker();
      const result = await documentPicker.select({ maxSelectNumber: 1 });
      if (!result || result.length === 0) {
        return;
      }
      const uri = result[0];
      const file = fs.openSync(uri, fs.OpenMode.READ_ONLY);
      const stat = fs.statSync(file.fd);
      const buf = new ArrayBuffer(stat.size);
      fs.readSync(file.fd, buf);
      fs.closeSync(file);
      const text = util.TextDecoder.create('utf-8').decodeToString(new Uint8Array(buf));
      this.inputText = text;
      this.applyParseResult(rssSourcesUtil.parseRssSourcesFromJson(text));
    } catch (e) {
      this.errorInfo = '读取文件失败，请确认文件为 UTF-8 编码的 JSON 订阅源';
    }
  }

  async parseInput(): Promise<void> {
    const text = this.inputText.trim();
    if (text.length === 0) {
      promptAction.showToast({ message: '请输入订阅源 JSON 或 URL' });
      return;
    }
    if (text.startsWith('http://') || text.startsWith('https://')) {
      this.parsing = true;
      this.errorInfo = '';
      try {
        const resp = await this.fetchText(text);
        this.applyParseResult(rssSourcesUtil.parseRssSourcesFromJson(resp));
      } catch (e) {
        this.errorInfo = '网络获取失败，请检查 URL 后重试';
      }
      this.parsing = false;
      return;
    }
    this.applyParseResult(rssSourcesUtil.parseRssSourcesFromJson(text));
  }

  applyParseResult(list: rssSources[]): void {
    if (list.length === 0) {
      this.parseResult = [];
      this.parseInfo = '';
      promptAction.showToast({ message: '未解析到有效订阅源，请检查输入内容' });
      return;
    }
    this.parseResult = list;
    this.parseInfo = `解析到 ${list.length} 个订阅源`;
    promptAction.showToast({ message: this.parseInfo });
  }

  fetchText(url: string): Promise<string> {
    return new Promise<string>((resolve, reject) => {
      const httpRequest = http.createHttp();
      httpRequest.request(url, {
        method: http.RequestMethod.GET,
        connectTimeout: 15000,
        readTimeout: 30000
      }).then((response) => {
        if (response.responseCode === 200) {
          resolve(response.result as string);
        } else {
          reject(new Error('HTTP ' + response.responseCode));
        }
        httpRequest.destroy();
      }).catch((err: Error) => {
        httpRequest.destroy();
        reject(err);
      });
    });
  }

  async confirmImport(): Promise<void> {
    if (this.parseResult.length === 0) {
      promptAction.showToast({ message: '请先解析订阅源' });
      return;
    }
    const ok = await rssSourcesUtil.applyImport(this.parseResult, '订阅');
    if (ok) {
      promptAction.showToast({ message: `已导入 ${this.parseResult.length} 个订阅源` });
      this.parseResult = [];
      this.parseInfo = '';
      this.inputText = '';
    } else {
      promptAction.showToast({ message: '导入失败' });
    }
  }

  build() {
    Column() {
      Row() {
        ImmersiveBackButton({
          iconColor: ThemeRuntime.primaryTextColor(this.appDarkMode),
          darkMode: this.appDarkMode,
          buttonSize: 40,
          containerWidth: 56,
          materialScale: 0.83,
          onBack: () => router.back()
        })
        Text('订阅导入')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(ThemeRuntime.primaryTextColor(this.appDarkMode))
        Blank()
      }
      .width('100%')
      .height(56 + this.statusBarHeight)
      .padding({ left: 4, right: 16, top: this.statusBarHeight })
      .alignItems(VerticalAlign.Center)

      Scroll() {
        Column({ space: 12 }) {
          Text('粘贴订阅源 JSON、输入订阅源 URL 后自动获取，或从本地文件导入')
            .fontSize(13)
            .fontColor(ThemeRuntime.subTextColor(this.appDarkMode))
            .width('100%')

          TextArea({
            placeholder: '例如：[{"sourceName":"某某订阅","sourceUrl":"https://...","rssListRule":{...}}]',
            text: this.inputText
          })
            .onChange((value: string) => {
              this.inputText = value;
            })
            .width('100%')
            .height(220)
            .fontSize(14)
            .backgroundColor(ThemeRuntime.glassPanelColor(this.appDarkMode, '', 'panel'))
            .borderRadius(14)
            .padding(12)

          if (this.parsing) {
            Row() {
              LoadingProgress()
                .width(22)
                .height(22)
              Text('正在获取...')
                .fontSize(14)
                .fontColor(ThemeRuntime.subTextColor(this.appDarkMode))
                .margin({ left: 10 })
            }
            .width('100%')
            .justifyContent(FlexAlign.Center)
          }

          if (this.errorInfo.length > 0) {
            Text(this.errorInfo)
              .fontSize(13)
              .fontColor('#E53935')
              .width('100%')
          }

          if (this.parseInfo.length > 0) {
            Text(this.parseInfo)
              .fontSize(14)
              .fontColor(ThemeRuntime.primaryTextColor(this.appDarkMode))
              .width('100%')
          }

          Row({ space: 12 }) {
            Button('选择文件')
              .width(120)
              .height(40)
              .fontSize(15)
              .backgroundColor(ThemeRuntime.inputColor(this.appDarkMode))
              .fontColor(ThemeRuntime.primaryTextColor(this.appDarkMode))
              .onClick(() => {
                this.pickSubscriptionFile();
              })
            Button('解析')
              .width(100)
              .height(40)
              .fontSize(15)
              .onClick(() => {
                this.parseInput();
              })
            Button('确认导入')
              .width(120)
              .height(40)
              .fontSize(15)
              .backgroundColor('#007DFF')
              .enabled(this.parseResult.length > 0)
              .onClick(() => {
                this.confirmImport();
              })
          }
          .width('100%')
          .justifyContent(FlexAlign.Center)
          .margin({ top: 8 })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 8 })
      }
      .width('100%')
      .layoutWeight(1)
      .align(Alignment.Top)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(ThemeRuntime.pageColor(this.appDarkMode))
  }
}
