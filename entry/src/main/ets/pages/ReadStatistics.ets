import { router, promptAction } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { syncSystemBars } from '../utils/SystemBars';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { ImmersiveBackButton } from '../components/ImmersiveBackButton';
import { appDb } from '../model/data/AppDatabase';
import { Book, Bookmark } from '../model/data/Book';

interface ReadStatItem {
  bookName: string;
  bookUrl: string;
  author: string;
  coverUrl: string;
  subTitle: string;
  bookmarkId: number;
}

@Entry
@Component
struct ReadStatisticsPage {
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageLink('themeRevision') themeRevision: number = 0;
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navBarHeight') navBarHeight: number = 0;
  @State type: number = 0;
  @State titleList: number[] = [0, 0, 0];
  @State typeList: number[] = [0, 0, 0];
  @State bookList: ReadStatItem[] = [];
  @State loaded: boolean = false;
  private readBooks: ReadStatItem[] = [];
  private finishedBooks: ReadStatItem[] = [];
  private bookmarkBooks: ReadStatItem[] = [];
  @State manageMode: boolean = false;
  @State selectedBookUrls: string[] = [];
  @State selectedBookmarkIds: number[] = [];
  @State showDeleteDialog: boolean = false;

  aboutToAppear(): void {
    this.syncBars();
    this.loadData();
  }

  onPageShow(): void {
    this.syncBars();
  }

  async loadData(): Promise<void> {
    this.loaded = false;
    try {
      const books = await appDb.getAllBooks();
      const bookmarks = await appDb.getAllBookmarks();

      const readBooks: ReadStatItem[] = [];
      const finishedBooks: ReadStatItem[] = [];
      const bookmarkBooks: ReadStatItem[] = [];

      books.forEach((b: Book) => {
        const total = Math.max(0, b.totalChapterNum);
        const current = Math.max(0, b.durChapterIndex);
        const dur = Math.max(0, b.durChapterTime);
        const cover = b.getDisplayCover();
        const sub = this.formatSubtitle(total, current, dur);
        readBooks.push(this.toItem(b, sub));
        if (total > 0 && current >= total - 1) {
          finishedBooks.push(this.toItem(b, '已读完 · 共 ' + total + ' 章'));
        }
      });

      const seen = new Set<string>();
      bookmarks.forEach((bm: Bookmark) => {
        const key = bm.bookName || bm.bookUrl;
        if (seen.has(key)) {
          return;
        }
        seen.add(key);
        const date = new Date(Math.max(0, bm.createTime));
        const dateText = date.getFullYear() + '-' +
          String(date.getMonth() + 1).padStart(2, '0') + '-' +
          String(date.getDate()).padStart(2, '0');
        bookmarkBooks.push({
          bookName: bm.bookName || '未知书籍',
          bookUrl: bm.bookUrl,
          author: bm.bookAuthor || '',
          coverUrl: '',
          subTitle: '书签时间 ' + dateText + (bm.chapterName ? ' · ' + bm.chapterName : ''),
          bookmarkId: bm.id
        });
      });

      this.titleList = [readBooks.length, finishedBooks.length, bookmarkBooks.length];

      const typeCounts = [0, 0, 0];
      books.forEach((b: Book) => {
        const t = b.type;
        if (t === 1) {
          typeCounts[1]++;
        } else if (t === 2) {
          typeCounts[2]++;
        } else {
          typeCounts[0]++;
        }
      });
      this.typeList = typeCounts;

      this.readBooks = readBooks;
      this.finishedBooks = finishedBooks;
      this.bookmarkBooks = bookmarkBooks;
      this.rebuildList();
    } catch (e) {
      hilog.warn(0x0000, 'readStat', 'load failed %{public}s', JSON.stringify(e));
      this.bookList = [];
    }
    this.loaded = true;
  }

  rebuildList(): void {
    const books = this.currentSourceBooks();
    this.bookList = books;
  }

  currentSourceBooks(): ReadStatItem[] {
    if (this.type === 1) {
      return this.finishedBooks;
    }
    if (this.type === 2) {
      return this.bookmarkBooks;
    }
    return this.readBooks;
  }

  toItem(b: Book, sub: string): ReadStatItem {
    return {
      bookName: b.name || '未知书籍',
      bookUrl: b.bookUrl,
      author: b.author || '',
      coverUrl: b.getDisplayCover(),
      subTitle: sub,
      bookmarkId: 0
    };
  }

  formatSubtitle(total: number, current: number, dur: number): string {
    const minutes = Math.floor(dur / 60000);
    const hour = Math.floor(minutes / 60);
    const min = minutes % 60;
    const durText = hour > 0 ? (hour + ' 小时 ' + min + ' 分') : (min + ' 分钟');
    const progress = total > 0 ? Math.min(100, Math.round((current / total) * 100)) + '%' : '';
    return (progress ? progress + ' · ' : '') + '阅读 ' + durText;
  }

  @Builder
  titleBar() {
    Row() {
      ImmersiveBackButton()
      Text('阅读统计')
        .fontSize(17)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.primaryTextColor())
        .layoutWeight(1)
        .margin({ left: 4 })
      Text(this.manageMode ? '完成' : '管理')
        .fontSize(14)
        .fontColor(ThemeRuntime.accentColor(this.appDarkMode))
        .padding({ left: 12, right: 12, top: 8, bottom: 8 })
        .onClick(() => {
          this.manageMode = !this.manageMode;
          this.selectedBookUrls = [];
          this.selectedBookmarkIds = [];
        })
    }
    .width('100%')
    .height(56)
    .padding({ left: 4, right: 12 })
    .backgroundColor(this.pageColor())
  }

  @Builder
  statCards() {
    Row() {
      this.statCard(0, '读过', this.titleList[0])
      this.statCard(1, '读完', this.titleList[1])
      this.statCard(2, '书签', this.titleList[2])
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 4, bottom: 4 })
  }

  @Builder
  statCard(index: number, title: string, count: number) {
    Column({ space: 4 }) {
      Text(String(count))
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.type === index ? ThemeRuntime.accentColor(this.appDarkMode) : this.primaryTextColor())
      Text(title)
        .fontSize(12)
        .fontColor(this.type === index ? ThemeRuntime.accentColor(this.appDarkMode) : this.subTextColor())
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Center)
    .padding({ top: 12, bottom: 12 })
    .margin({ left: 4, right: 4 })
    .borderRadius(12)
    .backgroundColor(this.cardColor())
    .border({
      width: 1,
      color: this.type === index ? ThemeRuntime.accentColor(this.appDarkMode) : ThemeRuntime.dividerColor(this.appDarkMode)
    })
    .onClick(() => {
      this.type = index;
      this.rebuildList();
    })
  }

  @Builder
  typeRow() {
    Row({ space: 4 }) {
      ForEach(['小说', '漫画', '有声书'], (name: string, index: number) => {
        Text(`${name} ${this.typeList[index]}`)
          .fontSize(12)
          .fontColor(this.subTextColor())
          .padding({ left: 10, right: 10, top: 4, bottom: 4 })
          .borderRadius(8)
          .backgroundColor(this.cardColor())
      }, (name: string) => name)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 8, bottom: 4 })
  }

  @Builder
  listSection() {
    Column({ space: 8 }) {
      if (!this.loaded) {
        Row() {
          Text('加载中…')
            .fontSize(12)
            .fontColor(this.subTextColor())
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .padding({ top: 32, bottom: 32 })
      } else if (this.bookList.length === 0) {
        Column({ space: 8 }) {
          Text('暂无记录')
            .fontSize(14)
            .fontColor(this.subTextColor())
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
        .padding({ top: 48, bottom: 48 })
      } else {
        ForEach(this.bookList, (item: ReadStatItem) => {
          this.bookRow(item)
        }, (item: ReadStatItem) => this.type + '_' + item.bookUrl + '_' + item.bookmarkId)
      }
    }
    .width('100%')
    .padding({ left: 12, right: 12 })
  }

  @Builder
  bookRow(item: ReadStatItem) {
    Row() {
      if (this.manageMode) {
        this.checkBox(item)
      }
      Stack({ alignContent: Alignment.Center }) {
        if (item.coverUrl && item.coverUrl.length > 0) {
          Image(item.coverUrl)
            .width(48)
            .height(64)
            .objectFit(ImageFit.Cover)
            .borderRadius(6)
            .backgroundColor(this.cardColor())
        } else {
          Column() {
            Text('书')
              .fontSize(14)
              .fontColor(this.subTextColor())
          }
          .width(48)
          .height(64)
          .borderRadius(6)
          .backgroundColor(this.cardColor())
        }
      }
      Column({ space: 3 }) {
        Text(item.bookName)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.primaryTextColor())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Text(item.author)
          .fontSize(12)
          .fontColor(this.subTextColor())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Text(item.subTitle)
          .fontSize(11)
          .fontColor(this.subTextColor())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 10 })
    }
    .width('100%')
    .padding({ left: 8, right: 8, top: 10, bottom: 10 })
    .borderRadius(12)
    .backgroundColor(this.cardColor())
    .onClick(() => {
      if (this.manageMode) {
        this.toggleSelect(item);
        return;
      }
      if (item.bookUrl) {
        router.pushUrl({ url: 'pages/ReadBook', params: { bookUrl: item.bookUrl } }).catch(() => {
          this.showToastSafely('打开失败');
        });
      } else {
        this.showToastSafely('缺少书籍信息');
      }
    })
  }

  @Builder
  checkBox(item: ReadStatItem) {
    const selected = this.type === 2
      ? this.selectedBookmarkIds.indexOf(item.bookmarkId) >= 0
      : this.selectedBookUrls.indexOf(item.bookUrl) >= 0;
    SymbolGlyph(selected ? $r('sys.symbol.checkmark_circle') : $r('sys.symbol.circle'))
      .fontSize(22)
      .fontColor([selected ? ThemeRuntime.accentColor(this.appDarkMode) : this.subTextColor()])
      .margin({ right: 6 })
  }

  toggleSelect(item: ReadStatItem): void {
    if (this.type === 2) {
      const idx = this.selectedBookmarkIds.indexOf(item.bookmarkId);
      if (idx >= 0) {
        this.selectedBookmarkIds.splice(idx, 1);
      } else {
        this.selectedBookmarkIds.push(item.bookmarkId);
      }
      this.selectedBookmarkIds = this.selectedBookmarkIds.slice();
    } else {
      const idx = this.selectedBookUrls.indexOf(item.bookUrl);
      if (idx >= 0) {
        this.selectedBookUrls.splice(idx, 1);
      } else {
        this.selectedBookUrls.push(item.bookUrl);
      }
      this.selectedBookUrls = this.selectedBookUrls.slice();
    }
  }

  async deleteSelected(): Promise<void> {
    try {
      if (this.type === 2) {
        if (this.selectedBookmarkIds.length > 0) {
          await appDb.deleteBookmarks(this.selectedBookmarkIds);
        }
      } else {
        for (const url of this.selectedBookUrls) {
          await appDb.deleteBook(url);
        }
      }
      this.showToastSafely('已删除 ' + Math.max(this.selectedBookUrls.length, this.selectedBookmarkIds.length) + ' 项');
      this.manageMode = false;
      this.selectedBookUrls = [];
      this.selectedBookmarkIds = [];
      await this.loadData();
    } catch (e) {
      hilog.warn(0x0000, 'readStat', 'delete failed %{public}s', JSON.stringify(e));
      this.showToastSafely('删除失败');
    }
  }

  showToastSafely(msg: string): void {
    try {
      promptAction.showToast({ message: msg, duration: 1500 });
    } catch (e) {
      // ignore
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

  syncBars(): void {
    syncSystemBars(getContext(this), this.appDarkMode, this.pageColor());
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Scroll() {
        Column() {
          this.statCards()
          this.typeRow()
          this.listSection()
          if (this.manageMode && (this.selectedBookUrls.length > 0 || this.selectedBookmarkIds.length > 0)) {
            Button('删除所选')
              .width('100%')
              .height(44)
              .fontSize(15)
              .fontColor(Color.White)
              .backgroundColor('#E64545')
              .borderRadius(12)
              .margin({ left: 16, right: 16, top: 12, bottom: 24 })
              .onClick(() => {
                this.showDeleteDialog = true;
              })
          }
        }
        .width('100%')
        .padding({ top: 56 + this.statusBarHeight, bottom: 32 + this.navBarHeight })
      }
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .width('100%')
      .height('100%')
      .align(Alignment.TopStart)

      this.titleBar()

      if (this.showDeleteDialog) {
        AlertDialog.show({
          title: '删除所选记录',
          message: '删除后不可恢复，是否继续？',
          primaryButton: {
            value: '取消',
            action: () => {
              this.showDeleteDialog = false;
            }
          },
          secondaryButton: {
            value: '删除',
            fontColor: '#E64545',
            action: () => {
              this.showDeleteDialog = false;
              this.deleteSelected();
            }
          }
        });
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.pageColor())
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
