import relationalStore from '@ohos.data.relationalStore';
import { Book, BookChapter, BookSource, BookGroup, Bookmark, SearchKeyword, ExploreRule, TocRule, ContentRule } from './Book';
import { rssSources, RssSourceGroup, rssSourcesHistory, rssSourceDb, ToRssSources, ToRssSourcesDb, rssSourcesTypeParams } from './RssSource';
import { Context } from '@kit.AbilityKit';
import { BookIdentity } from '../../utils/BookIdentity';

interface ColumnMigration {
  table: string;
  column: string;
  definition: string;
}

export class ReaderPaginationCacheRecord {
  starts: number[] = [];
  ends: number[] = [];
}

class ReaderPaginationCacheWrite {
  bookUrl: string = '';
  chapterIndex: number = 0;
  layoutKey: string = '';
  starts: number[] = [];
  ends: number[] = [];

  constructor(bookUrl: string, chapterIndex: number, layoutKey: string, starts: number[], ends: number[]) {
    this.bookUrl = bookUrl;
    this.chapterIndex = chapterIndex;
    this.layoutKey = layoutKey;
    this.starts = [...starts];
    this.ends = [...ends];
  }
}

class BookLifecycleMigrationRecord {
  bookUrl: string = '';
  identityKey: string = '';
  variable: string = '{}';
  pendingAddToShelf: boolean = false;
  shelfModifiedTime: number = 0;
}

export class AppDatabase {
  private static readonly BATCH_INSERT_CHUNK_SIZE: number = 400;
  private static instance: AppDatabase | null = null;
  private store: relationalStore.RdbStore | null = null;
  private initialized: boolean = false;
  private initPromise: Promise<void> | null = null;
  private readerPaginationPendingWrites: Map<string, ReaderPaginationCacheWrite> =
    new Map<string, ReaderPaginationCacheWrite>();
  private readerPaginationWriteTasks: Map<string, Promise<void>> = new Map<string, Promise<void>>();
  private bookProgressWriteTasks: Map<string, Promise<void>> = new Map<string, Promise<void>>();
  private latestBookProgressWriteTimes: Map<string, number> = new Map<string, number>();
  private readonly DATABASE_NAME = 'legado.db';
  private readonly SCHEMA_VERSION = 19;

  private constructor() {}

  static getInstance(): AppDatabase {
    if (!AppDatabase.instance) {
      AppDatabase.instance = new AppDatabase();
    }
    return AppDatabase.instance;
  }

  async init(context: Context): Promise<void> {
    if (this.initialized && this.store) {
      return;
    }
    if (this.initPromise) {
      await this.initPromise;
      return;
    }

    this.initPromise = this.initInternal(context);
    try {
      await this.initPromise;
    } finally {
      this.initPromise = null;
    }
  }

  private async initInternal(context: Context): Promise<void> {
    const config: relationalStore.StoreConfig = {
      name: this.DATABASE_NAME,
      securityLevel: relationalStore.SecurityLevel.S1
    };

    this.store = await relationalStore.getRdbStore(context, config);
    await this.createTables();
    await this.initDefaultRssSourceGroups();
    await this.initDefaultData();
    this.initialized = true;
  }

  async initWithContext(context: Context): Promise<void> {
    await this.init(context);
  }

  private async createTables(): Promise<void> {
    if (!this.store) return;

    await this.store.executeSql(`
      CREATE TABLE IF NOT EXISTS books (
        bookUrl TEXT PRIMARY KEY,
        tocUrl TEXT DEFAULT '',
        origin TEXT DEFAULT 'local',
        originName TEXT DEFAULT '',
        name TEXT DEFAULT '',
        author TEXT DEFAULT '',
        kind TEXT,
        status TEXT DEFAULT '',
        customTag TEXT,
        coverUrl TEXT,
        customCoverUrl TEXT,
        intro TEXT,
        customIntro TEXT,
        charset TEXT,
        type INTEGER DEFAULT 0,
        groupId INTEGER DEFAULT 0,
        isPinned INTEGER DEFAULT 0,
        latestChapterTitle TEXT,
        updateTime TEXT DEFAULT '',
        latestChapterTime INTEGER DEFAULT 0,
        lastCheckTime INTEGER DEFAULT 0,
        lastCheckCount INTEGER DEFAULT 0,
        totalChapterNum INTEGER DEFAULT 0,
        durChapterTitle TEXT,
        durChapterIndex INTEGER DEFAULT 0,
        durChapterPos INTEGER DEFAULT 0,
        durChapterTime INTEGER DEFAULT 0,
        wordCount TEXT,
        canUpdate INTEGER DEFAULT 1,
        bookOrder INTEGER DEFAULT 0,
        originOrder INTEGER DEFAULT 0,
        variable TEXT,
        readConfig TEXT,
        syncTime INTEGER DEFAULT 0,
        identityKey TEXT DEFAULT '',
        pendingAddToShelf INTEGER DEFAULT 0,
        shelfModifiedTime INTEGER DEFAULT 0
      )
    `);

    await this.store.executeSql(`
      CREATE TABLE IF NOT EXISTS book_sources (
        bookSourceUrl TEXT PRIMARY KEY,
        bookSourceName TEXT DEFAULT '',
        bookSourceType INTEGER DEFAULT 0,
        bookSourceGroup TEXT DEFAULT '',
        bookSourceComment TEXT DEFAULT '',
        loginUrl TEXT DEFAULT '',
        loginUi TEXT,
        loginCheckJs TEXT DEFAULT '',
        loginHeader TEXT DEFAULT '',
        loginInfo TEXT DEFAULT '',
        rawSourceJson TEXT DEFAULT '',
        bookUrlPattern TEXT DEFAULT '',
        searchUrl TEXT DEFAULT '',
        exploreUrl TEXT DEFAULT '',
        jsLib TEXT DEFAULT '',
        header TEXT DEFAULT '',
        bookListRule TEXT DEFAULT '{}',
        searchRule TEXT DEFAULT '{}',
        exploreRule TEXT DEFAULT '{}',
        bookInfoRule TEXT DEFAULT '{}',
        tocRule TEXT DEFAULT '{}',
        contentRule TEXT DEFAULT '{}',
        variableComment TEXT DEFAULT '',
        variable TEXT DEFAULT '',
        lastUpdateTime INTEGER DEFAULT 0,
        respondTime INTEGER DEFAULT 180000,
        customOrder INTEGER DEFAULT 0,
        customButton INTEGER DEFAULT 0,
        eventListener INTEGER DEFAULT 0,
        isPinned INTEGER DEFAULT 0,
        enabled INTEGER DEFAULT 1,
        enabledExplore INTEGER DEFAULT 1,
        isLocked INTEGER DEFAULT 0,
        validationStatus INTEGER DEFAULT 0,
        weight INTEGER DEFAULT 0,
        concurrentRate TEXT DEFAULT '',
        enabledCookieJar INTEGER DEFAULT 1
      )
    `);

    await this.store.executeSql(`
      CREATE TABLE IF NOT EXISTS book_chapters (
        url TEXT PRIMARY KEY,
        title TEXT DEFAULT '',
        bookUrl TEXT DEFAULT '',
        chapterIndex INTEGER DEFAULT 0,
        isVip INTEGER DEFAULT 0,
        isPay INTEGER DEFAULT 0,
        resourceUrl TEXT DEFAULT '',
        tag TEXT DEFAULT '',
        startOffset INTEGER DEFAULT 0,
        endOffset INTEGER DEFAULT 0,
        variable TEXT DEFAULT ''
      )
    `);

    await this.store.executeSql(`
      CREATE TABLE IF NOT EXISTS book_contents (
        bookUrl TEXT DEFAULT '',
        chapterIndex INTEGER DEFAULT 0,
        chapterUrl TEXT DEFAULT '',
        chapterName TEXT DEFAULT '',
        content TEXT DEFAULT '',
        cacheDate INTEGER DEFAULT 0,
        PRIMARY KEY (bookUrl, chapterIndex)
      )
    `);

    await this.store.executeSql(`
      CREATE TABLE IF NOT EXISTS book_groups (
        groupId INTEGER PRIMARY KEY,
        groupName TEXT DEFAULT '',
        groupOrder INTEGER DEFAULT 0,
        show INTEGER DEFAULT 1,
        enableRefresh INTEGER DEFAULT 1
      )
    `);

    await this.store.executeSql(`
      CREATE TABLE IF NOT EXISTS search_keywords (
        keyword TEXT PRIMARY KEY,
        usage INTEGER DEFAULT 0,
        lastUseTime INTEGER DEFAULT 0
      )
    `);

    await this.store.executeSql(`
      CREATE TABLE IF NOT EXISTS reader_pagination_cache (
        bookUrl TEXT DEFAULT '',
        chapterIndex INTEGER DEFAULT 0,
        layoutKey TEXT DEFAULT '',
        starts TEXT DEFAULT '[]',
        ends TEXT DEFAULT '[]',
        updateTime INTEGER DEFAULT 0,
        PRIMARY KEY (bookUrl, chapterIndex, layoutKey)
      )
    `);

    await this.store.executeSql(`
      CREATE TABLE IF NOT EXISTS bookmarks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        bookUrl TEXT DEFAULT '',
        bookName TEXT DEFAULT '',
        bookAuthor TEXT DEFAULT '',
        chapterIndex INTEGER DEFAULT 0,
        chapterName TEXT DEFAULT '',
        pageIndex INTEGER DEFAULT 0,
        startPos INTEGER DEFAULT 0,
        endPos INTEGER DEFAULT 0,
        content TEXT DEFAULT '',
        createTime INTEGER DEFAULT 0,
        UNIQUE(bookUrl, chapterIndex, pageIndex)
      )
    `);

    await this.store.executeSql(`
      CREATE TABLE IF NOT EXISTS schema_meta (
        key TEXT PRIMARY KEY,
        value INTEGER DEFAULT 0
      )
    `);

    await this.store.executeSql(`
      CREATE TABLE IF NOT EXISTS book_mutation_journal (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        operation TEXT DEFAULT '',
        reason TEXT DEFAULT '',
        bookUrl TEXT DEFAULT '',
        identityKey TEXT DEFAULT '',
        pendingAddToShelf INTEGER DEFAULT 0,
        eventTime INTEGER DEFAULT 0,
        details TEXT DEFAULT ''
      )
    `);

    // ===== 订阅源(RSS)表：从 legado-Harmony 移植，SCHEMA_VERSION 19 =====
    await this.store.executeSql(`
      CREATE TABLE IF NOT EXISTS rssSources (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sourceType INTEGER DEFAULT 0,
        sourceName TEXT DEFAULT '',
        sourceUrl TEXT DEFAULT '',
        sourceIcon TEXT DEFAULT '',
        sourceIconIsUrl INTEGER DEFAULT 0,
        sourceGroup TEXT DEFAULT '',
        sourceComment TEXT DEFAULT '',
        enabled INTEGER DEFAULT 1,
        variableComment TEXT DEFAULT '',
        jsLib TEXT DEFAULT '',
        enabledCookieJar INTEGER DEFAULT 0,
        concurrentRate TEXT DEFAULT '',
        header TEXT DEFAULT '',
        loginUrl TEXT DEFAULT '',
        loginUi TEXT DEFAULT '',
        loginCheckJs TEXT DEFAULT '',
        coverDecodeJs TEXT DEFAULT '',
        sortUrl TEXT DEFAULT '',
        singleUrl INTEGER DEFAULT 1,
        articleStyle TEXT DEFAULT '',
        lastUpdateTime INTEGER DEFAULT 0,
        customOrder INTEGER DEFAULT 0,
        variable TEXT DEFAULT '',
        showRecentIcon INTEGER DEFAULT 1,
        autoComplete INTEGER DEFAULT 1,
        customizeTitle TEXT DEFAULT '',
        rssListRule TEXT DEFAULT '',
        rssWebViewRule TEXT DEFAULT ''
      )
    `);

    await this.store.executeSql(`
      CREATE TABLE IF NOT EXISTS rss_source_group (
        rssGroupId INTEGER PRIMARY KEY AUTOINCREMENT,
        rssGroupName TEXT DEFAULT '',
        groupSort INTEGER DEFAULT 0,
        isTop INTEGER DEFAULT 0,
        isDelete INTEGER DEFAULT 1
      )
    `);

    await this.store.executeSql(`
      CREATE TABLE IF NOT EXISTS rss_sources_history (
        sourceType INTEGER DEFAULT 0,
        sourceName TEXT DEFAULT '',
        sourceUrl TEXT PRIMARY KEY,
        sourceIcon TEXT DEFAULT '',
        sourceIconIsUrl INTEGER DEFAULT 0,
        sourceGroup TEXT DEFAULT '',
        lastUpdateTime INTEGER DEFAULT 0,
        showRecentIcon INTEGER DEFAULT 1,
        customizeTitle TEXT DEFAULT ''
      )
    `);
    await this.store.executeSql(`
      CREATE INDEX IF NOT EXISTS index_rssSources_sourceUrl ON rssSources(sourceUrl)
    `);
    // ===== 订阅源(RSS)表结束 =====

    const schemaVersion = await this.getSchemaVersion();
    if (schemaVersion < this.SCHEMA_VERSION) {
      await this.migrateTables();
      if (schemaVersion < 9) {
        await this.resetLegacyBookSourceValidationFailures();
      }
      if (schemaVersion < 14) {
        await this.repairOversizedImportedBookData();
      }
      if (schemaVersion < 15) {
        await this.migrateBookLifecycleMetadata();
      }
      await this.setSchemaVersion(this.SCHEMA_VERSION);
    }
    await this.createIndexes();
  }

  private async createIndexes(): Promise<void> {
    if (!this.store) return;
    await this.store.executeSql(
      'CREATE INDEX IF NOT EXISTS idx_book_chapters_book_order ON book_chapters(bookUrl, chapterIndex)');
    await this.store.executeSql(
      'CREATE INDEX IF NOT EXISTS idx_bookmarks_book_time ON bookmarks(bookUrl, createTime DESC)');
    await this.store.executeSql(
      'CREATE INDEX IF NOT EXISTS idx_books_read_time ON books(durChapterTime DESC)');
    await this.store.executeSql(
      'CREATE INDEX IF NOT EXISTS idx_books_identity_key ON books(identityKey)');
    await this.store.executeSql(
      'CREATE INDEX IF NOT EXISTS idx_book_mutation_time ON book_mutation_journal(eventTime DESC)');
    await this.store.executeSql(
      'CREATE INDEX IF NOT EXISTS idx_book_sources_enabled_order ON book_sources(enabled, isPinned DESC, customOrder)');
    await this.store.executeSql(
      'CREATE INDEX IF NOT EXISTS idx_book_sources_explore_order ON book_sources(enabled, enabledExplore, isPinned DESC, customOrder)');
    await this.store.executeSql(
      'CREATE INDEX IF NOT EXISTS index_rssSources_sourceUrl ON rssSources(sourceUrl)');
    await this.store.executeSql(
      'CREATE INDEX IF NOT EXISTS index_rssSources_group_order ON rssSources(sourceGroup, customOrder)');
  }

  private async getSchemaVersion(): Promise<number> {
    if (!this.store) return 0;

    try {
      const resultSet = await this.store.querySql(`SELECT value FROM schema_meta WHERE key = 'schema_version'`);
      try {
        if (resultSet.goToFirstRow()) {
          return resultSet.getLong(resultSet.getColumnIndex('value'));
        }
      } finally {
        resultSet.close();
      }
    } catch (e) {
    }
    return 0;
  }

  private async setSchemaVersion(version: number): Promise<void> {
    if (!this.store) return;

    try {
      await this.store.executeSql(`DELETE FROM schema_meta WHERE key = 'schema_version'`);
      await this.store.executeSql(`INSERT INTO schema_meta (key, value) VALUES ('schema_version', ${version})`);
    } catch (e) {
      console.error(`保存数据库版本 ${version} 失败`, e);
      throw e;
    }
  }

  private async migrateTables(): Promise<void> {
    if (!this.store) return;

    const migrations: ColumnMigration[] = [
      { table: 'books', column: 'tocUrl', definition: "tocUrl TEXT DEFAULT ''" },
      { table: 'books', column: 'origin', definition: "origin TEXT DEFAULT 'local'" },
      { table: 'books', column: 'originName', definition: "originName TEXT DEFAULT ''" },
      { table: 'books', column: 'kind', definition: "kind TEXT DEFAULT ''" },
      { table: 'books', column: 'status', definition: "status TEXT DEFAULT ''" },
      { table: 'books', column: 'customTag', definition: "customTag TEXT DEFAULT ''" },
      { table: 'books', column: 'coverUrl', definition: "coverUrl TEXT DEFAULT ''" },
      { table: 'books', column: 'customCoverUrl', definition: "customCoverUrl TEXT DEFAULT ''" },
      { table: 'books', column: 'intro', definition: "intro TEXT DEFAULT ''" },
      { table: 'books', column: 'customIntro', definition: "customIntro TEXT DEFAULT ''" },
      { table: 'books', column: 'charset', definition: "charset TEXT DEFAULT ''" },
      { table: 'books', column: 'type', definition: 'type INTEGER DEFAULT 0' },
      { table: 'books', column: 'groupId', definition: 'groupId INTEGER DEFAULT 0' },
      { table: 'books', column: 'isPinned', definition: 'isPinned INTEGER DEFAULT 0' },
      { table: 'books', column: 'latestChapterTitle', definition: "latestChapterTitle TEXT DEFAULT ''" },
      { table: 'books', column: 'updateTime', definition: "updateTime TEXT DEFAULT ''" },
      { table: 'books', column: 'latestChapterTime', definition: 'latestChapterTime INTEGER DEFAULT 0' },
      { table: 'books', column: 'lastCheckTime', definition: 'lastCheckTime INTEGER DEFAULT 0' },
      { table: 'books', column: 'lastCheckCount', definition: 'lastCheckCount INTEGER DEFAULT 0' },
      { table: 'books', column: 'totalChapterNum', definition: 'totalChapterNum INTEGER DEFAULT 0' },
      { table: 'books', column: 'durChapterTitle', definition: "durChapterTitle TEXT DEFAULT ''" },
      { table: 'books', column: 'durChapterIndex', definition: 'durChapterIndex INTEGER DEFAULT 0' },
      { table: 'books', column: 'durChapterPos', definition: 'durChapterPos INTEGER DEFAULT 0' },
      { table: 'books', column: 'durChapterTime', definition: 'durChapterTime INTEGER DEFAULT 0' },
      { table: 'books', column: 'wordCount', definition: "wordCount TEXT DEFAULT ''" },
      { table: 'books', column: 'canUpdate', definition: 'canUpdate INTEGER DEFAULT 1' },
      { table: 'books', column: 'bookOrder', definition: 'bookOrder INTEGER DEFAULT 0' },
      { table: 'books', column: 'originOrder', definition: 'originOrder INTEGER DEFAULT 0' },
      { table: 'books', column: 'variable', definition: 'variable TEXT' },
      { table: 'books', column: 'readConfig', definition: 'readConfig TEXT' },
      { table: 'books', column: 'syncTime', definition: 'syncTime INTEGER DEFAULT 0' },
      { table: 'books', column: 'identityKey', definition: "identityKey TEXT DEFAULT ''" },
      { table: 'books', column: 'pendingAddToShelf', definition: 'pendingAddToShelf INTEGER DEFAULT 0' },
      { table: 'books', column: 'shelfModifiedTime', definition: 'shelfModifiedTime INTEGER DEFAULT 0' },
      { table: 'book_sources', column: 'searchUrl', definition: "searchUrl TEXT DEFAULT ''" },
      { table: 'book_sources', column: 'exploreUrl', definition: "exploreUrl TEXT DEFAULT ''" },
      { table: 'book_sources', column: 'jsLib', definition: "jsLib TEXT DEFAULT ''" },
      { table: 'book_sources', column: 'bookSourceType', definition: 'bookSourceType INTEGER DEFAULT 0' },
      { table: 'book_sources', column: 'variable', definition: "variable TEXT DEFAULT ''" },
      { table: 'book_sources', column: 'enabledCookieJar', definition: 'enabledCookieJar INTEGER DEFAULT 1' },
      { table: 'book_sources', column: 'loginHeader', definition: "loginHeader TEXT DEFAULT ''" },
      { table: 'book_sources', column: 'loginInfo', definition: "loginInfo TEXT DEFAULT ''" },
      { table: 'book_sources', column: 'rawSourceJson', definition: "rawSourceJson TEXT DEFAULT ''" },
      { table: 'book_sources', column: 'respondTime', definition: 'respondTime INTEGER DEFAULT 180000' },
      { table: 'book_sources', column: 'customButton', definition: 'customButton INTEGER DEFAULT 0' },
      { table: 'book_sources', column: 'eventListener', definition: 'eventListener INTEGER DEFAULT 0' },
      { table: 'book_sources', column: 'isLocked', definition: 'isLocked INTEGER DEFAULT 0' },
      { table: 'book_sources', column: 'isPinned', definition: 'isPinned INTEGER DEFAULT 0' },
      { table: 'book_sources', column: 'validationStatus', definition: 'validationStatus INTEGER DEFAULT 0' },
      { table: 'book_chapters', column: 'variable', definition: "variable TEXT DEFAULT ''" }
    ];

    for (const migration of migrations) {
      await this.addColumnIfMissing(migration);
    }
  }

  private async addColumnIfMissing(migration: ColumnMigration): Promise<void> {
    if (!this.store) return;

    try {
      const resultSet = await this.store.querySql(`PRAGMA table_info(${migration.table})`);
      try {
        const nameIndex = resultSet.getColumnIndex('name');
        while (resultSet.goToNextRow()) {
          if (resultSet.getString(nameIndex) === migration.column) {
            return;
          }
        }
      } finally {
        resultSet.close();
      }
      await this.store.executeSql(`ALTER TABLE ${migration.table} ADD COLUMN ${migration.definition}`);
    } catch (e) {
      console.error(`数据库迁移失败: ${migration.table}.${migration.column}`, e);
      throw e;
    }
  }

  private async resetLegacyBookSourceValidationFailures(): Promise<void> {
    if (!this.store) return;
    try {
      await this.store.executeSql(
        `UPDATE book_sources SET validationStatus = ${BookSource.VALIDATION_UNCHECKED} ` +
        `WHERE validationStatus = ${BookSource.VALIDATION_FAILED}`
      );
    } catch (e) {
      console.warn('重置旧版书源校验失败状态失败:', e);
    }
  }

  private async repairOversizedImportedBookData(): Promise<void> {
    if (!this.store) return;
    try {
      // Android 阅读的 variable 可能包含正文/目录等运行时缓存。旧版导入器曾将其整段写入，
      // 书架启动时读取所有图书会因此长时间占用主线程。章节和页码进度已有独立列，清掉
      // 超大扩展字段不会丢失主要阅读位置；只处理网络书，避免影响本地图书路径元数据。
      await this.store.executeSql(
        `UPDATE books SET variable = '{}' ` +
        `WHERE origin NOT IN ('local', 'loc_book') AND LENGTH(COALESCE(variable, '')) > 65536`
      );
      await this.store.executeSql(
        `UPDATE books SET readConfig = NULL WHERE LENGTH(COALESCE(readConfig, '')) > 65536`
      );
      await this.store.executeSql(
        `UPDATE books SET intro = SUBSTR(intro, 1, 65536) WHERE LENGTH(COALESCE(intro, '')) > 65536`
      );
      await this.store.executeSql(
        `UPDATE books SET customIntro = SUBSTR(customIntro, 1, 65536) ` +
        `WHERE LENGTH(COALESCE(customIntro, '')) > 65536`
      );
    } catch (e) {
      console.warn('修复历史导入的超大书籍数据失败:', e);
    }
  }

  private async migrateBookLifecycleMetadata(): Promise<void> {
    if (!this.store) return;
    const legacyKey = 'searchExplorePendingAddToShelf';
    const records: BookLifecycleMigrationRecord[] = [];
    const resultSet = await this.store.querySql(
      'SELECT bookUrl, origin, variable, durChapterTime, lastCheckTime, latestChapterTime FROM books');
    try {
      while (resultSet.goToNextRow()) {
        const bookUrl = this.getStringColumn(resultSet, 'bookUrl');
        if (!bookUrl) continue;
        const book = new Book();
        book.bookUrl = bookUrl;
        book.origin = this.getStringColumn(resultSet, 'origin', 'local');
        const rawVariable = this.getStringColumn(resultSet, 'variable', '{}');
        let cleanedVariable = rawVariable;
        let pending = false;
        if (rawVariable.indexOf(legacyKey) >= 0) {
          try {
            const legacy = JSON.parse(rawVariable) as Record<string, string>;
            pending = String(legacy[legacyKey] || '') === 'true';
            const cleaned: Record<string, string> = {};
            for (const key of Object.keys(legacy)) {
              if (key !== legacyKey) cleaned[key] = legacy[key];
            }
            cleanedVariable = JSON.stringify(cleaned);
          } catch (_) {
          }
        }
        const modified = pending ? 0 : Math.max(
          this.getLongColumn(resultSet, 'durChapterTime'),
          this.getLongColumn(resultSet, 'lastCheckTime'),
          this.getLongColumn(resultSet, 'latestChapterTime'));
        const record = new BookLifecycleMigrationRecord();
        record.bookUrl = bookUrl;
        record.identityKey = BookIdentity.keyOfBook(book);
        record.variable = cleanedVariable;
        record.pendingAddToShelf = pending;
        record.shelfModifiedTime = modified;
        records.push(record);
      }
    } finally {
      resultSet.close();
    }
    for (const record of records) {
      const predicates = new relationalStore.RdbPredicates('books');
      predicates.equalTo('bookUrl', record.bookUrl);
      await this.store.update({
        identityKey: record.identityKey,
        pendingAddToShelf: record.pendingAddToShelf ? 1 : 0,
        shelfModifiedTime: record.shelfModifiedTime,
        variable: record.variable
      }, predicates);
    }
  }

  private async initDefaultData(): Promise<void> {
    if (!this.store) return;

    const resultSet = await this.store.querySql(`SELECT COUNT(*) as count FROM book_groups`);
    let shouldInsertDefaults = true;
    try {
      if (resultSet.goToFirstRow()) {
        shouldInsertDefaults = resultSet.getLong(resultSet.getColumnIndex('count')) === 0;
      }
    } finally {
      resultSet.close();
    }
    if (shouldInsertDefaults) {
      await this.store.executeSql(`
        INSERT INTO book_groups (groupId, groupName, groupOrder, show) 
        VALUES (${BookGroup.ID_ALL}, '全部', -10, 1)
      `);
      await this.store.executeSql(`
        INSERT INTO book_groups (groupId, groupName, groupOrder, enableRefresh, show) 
        VALUES (${BookGroup.ID_LOCAL}, '本地', -9, 0, 1)
      `);
      await this.store.executeSql(`
        INSERT INTO book_groups (groupId, groupName, groupOrder, show) 
        VALUES (${BookGroup.ID_AUDIO}, '音频', -8, 1)
      `);
      await this.store.executeSql(`
        INSERT INTO book_groups (groupId, groupName, groupOrder, show) 
        VALUES (${BookGroup.ID_NET_NONE}, '网络未分组', -7, 1)
      `);
      await this.store.executeSql(`
        INSERT INTO book_groups (groupId, groupName, groupOrder, show) 
        VALUES (${BookGroup.ID_LOCAL_NONE}, '本地未分组', -6, 0)
      `);
      await this.store.executeSql(`
        INSERT INTO book_groups (groupId, groupName, groupOrder, show) 
        VALUES (${BookGroup.ID_ERROR}, '更新失败', -1, 1)
      `);
    }
  }

  async insertBook(book: Book, reason: string = 'insert_book'): Promise<void> {
    if (!this.store) return;
    book.identityKey = BookIdentity.keyOfBook(book);
    if (!book.pendingAddToShelf && book.shelfModifiedTime <= 0) {
      book.shelfModifiedTime = Date.now();
    }
    const bucket: relationalStore.ValuesBucket = {
      bookUrl: book.bookUrl,
      tocUrl: book.tocUrl,
      origin: book.origin,
      originName: book.originName,
      name: book.name,
      author: book.author,
      kind: book.kind,
      status: book.status,
      customTag: book.customTag,
      coverUrl: book.coverUrl,
      customCoverUrl: book.customCoverUrl,
      intro: book.intro,
      customIntro: book.customIntro,
      charset: book.charset,
      type: book.type,
      groupId: book.group,
      isPinned: book.isPinned ? 1 : 0,
      latestChapterTitle: book.latestChapterTitle,
      updateTime: book.updateTime,
      latestChapterTime: book.latestChapterTime,
      lastCheckTime: book.lastCheckTime,
      lastCheckCount: book.lastCheckCount,
      totalChapterNum: book.totalChapterNum,
      durChapterTitle: book.durChapterTitle,
      durChapterIndex: book.durChapterIndex,
      durChapterPos: book.durChapterPos,
      durChapterTime: book.durChapterTime,
      wordCount: book.wordCount,
      canUpdate: book.canUpdate ? 1 : 0,
      bookOrder: book.order,
      originOrder: book.originOrder,
      variable: book.variable,
      readConfig: JSON.stringify(book.readConfig),
      syncTime: book.syncTime,
      identityKey: book.identityKey,
      pendingAddToShelf: book.pendingAddToShelf ? 1 : 0,
      shelfModifiedTime: book.shelfModifiedTime
    };

    await this.store.insert('books', bucket);
    await this.recordBookMutation('insert', reason, book);
    if (book.origin && book.origin !== 'local') {
    }
  }

  async updateBook(book: Book, syncRelevant: boolean = true, reason: string = 'update_book'): Promise<void> {
    if (!this.store) return;
    book.identityKey = BookIdentity.keyOfBook(book);
    const bucket: relationalStore.ValuesBucket = {
      tocUrl: book.tocUrl,
      origin: book.origin,
      originName: book.originName,
      name: book.name,
      author: book.author,
      kind: book.kind,
      status: book.status,
      customTag: book.customTag,
      coverUrl: book.coverUrl,
      customCoverUrl: book.customCoverUrl,
      intro: book.intro,
      customIntro: book.customIntro,
      charset: book.charset,
      type: book.type,
      groupId: book.group,
      isPinned: book.isPinned ? 1 : 0,
      latestChapterTitle: book.latestChapterTitle,
      updateTime: book.updateTime,
      latestChapterTime: book.latestChapterTime,
      lastCheckTime: book.lastCheckTime,
      lastCheckCount: book.lastCheckCount,
      totalChapterNum: book.totalChapterNum,
      durChapterTitle: book.durChapterTitle,
      durChapterIndex: book.durChapterIndex,
      durChapterPos: book.durChapterPos,
      durChapterTime: book.durChapterTime,
      wordCount: book.wordCount,
      canUpdate: book.canUpdate ? 1 : 0,
      bookOrder: book.order,
      originOrder: book.originOrder,
      variable: book.variable,
      readConfig: JSON.stringify(book.readConfig),
      syncTime: book.syncTime,
      identityKey: book.identityKey,
      pendingAddToShelf: book.pendingAddToShelf ? 1 : 0,
      shelfModifiedTime: book.shelfModifiedTime
    };

    const predicates = new relationalStore.RdbPredicates('books');
    predicates.equalTo('bookUrl', book.bookUrl);
    const affected = await this.store.update(bucket, predicates);
    if (affected <= 0) {
      await this.recordBookMutation('update_missed', reason, book, 'bookUrl 精确匹配未命中');
      console.warn(`更新书籍未命中数据库记录: ${book.bookUrl}`);
      return;
    }
    await this.recordBookMutation('update', reason, book);
    if (syncRelevant && book.origin && book.origin !== 'local') {
    }
  }

  async commitBookSourceSwitch(oldBookUrl: string, book: Book, chapters: BookChapter[]): Promise<void> {
    if (!this.store || !oldBookUrl || !book.bookUrl) return;
    book.identityKey = BookIdentity.keyOfBook(book);
    const bookBucket: relationalStore.ValuesBucket = {
      bookUrl: book.bookUrl,
      tocUrl: book.tocUrl,
      origin: book.origin,
      originName: book.originName,
      name: book.name,
      author: book.author,
      kind: book.kind,
      status: book.status,
      customTag: book.customTag,
      coverUrl: book.coverUrl,
      customCoverUrl: book.customCoverUrl,
      intro: book.intro,
      customIntro: book.customIntro,
      charset: book.charset,
      type: book.type,
      groupId: book.group,
      isPinned: book.isPinned ? 1 : 0,
      latestChapterTitle: book.latestChapterTitle,
      updateTime: book.updateTime,
      latestChapterTime: book.latestChapterTime,
      lastCheckTime: book.lastCheckTime,
      lastCheckCount: book.lastCheckCount,
      totalChapterNum: book.totalChapterNum,
      durChapterTitle: book.durChapterTitle,
      durChapterIndex: book.durChapterIndex,
      durChapterPos: book.durChapterPos,
      durChapterTime: book.durChapterTime,
      wordCount: book.wordCount,
      canUpdate: book.canUpdate ? 1 : 0,
      bookOrder: book.order,
      originOrder: book.originOrder,
      variable: book.variable,
      readConfig: JSON.stringify(book.readConfig),
      syncTime: book.syncTime,
      identityKey: book.identityKey,
      pendingAddToShelf: book.pendingAddToShelf ? 1 : 0,
      shelfModifiedTime: book.shelfModifiedTime
    };
    const chapterBuckets: relationalStore.ValuesBucket[] = [];
    for (const chapter of chapters) {
      chapterBuckets.push({
        url: chapter.url,
        title: chapter.title,
        bookUrl: book.bookUrl,
        chapterIndex: chapter.index,
        isVip: chapter.isVip ? 1 : 0,
        isPay: chapter.isPay ? 1 : 0,
        resourceUrl: chapter.resourceUrl,
        tag: chapter.tag,
        startOffset: chapter.start,
        endOffset: chapter.end,
        variable: chapter.variable
      });
    }

    const transaction = await this.store.createTransaction();
    try {
      if (oldBookUrl !== book.bookUrl) {
        const destinationBookmarks = new relationalStore.RdbPredicates('bookmarks');
        destinationBookmarks.equalTo('bookUrl', book.bookUrl);
        await transaction.delete(destinationBookmarks);

        const sourceBookmarks = new relationalStore.RdbPredicates('bookmarks');
        sourceBookmarks.equalTo('bookUrl', oldBookUrl);
        await transaction.update({
          bookUrl: book.bookUrl,
          bookName: book.name,
          bookAuthor: book.author
        }, sourceBookmarks);

        for (const table of ['book_chapters', 'book_contents', 'books']) {
          const oldPredicates = new relationalStore.RdbPredicates(table);
          oldPredicates.equalTo('bookUrl', oldBookUrl);
          await transaction.delete(oldPredicates);
          const destinationPredicates = new relationalStore.RdbPredicates(table);
          destinationPredicates.equalTo('bookUrl', book.bookUrl);
          await transaction.delete(destinationPredicates);
        }
        await transaction.insert('books', bookBucket);
      } else {
        const bookPredicates = new relationalStore.RdbPredicates('books');
        bookPredicates.equalTo('bookUrl', book.bookUrl);
        const updateBucket: relationalStore.ValuesBucket = { ...bookBucket };
        delete updateBucket.bookUrl;
        await transaction.update(updateBucket, bookPredicates);
        for (const table of ['book_chapters', 'book_contents']) {
          const predicates = new relationalStore.RdbPredicates(table);
          predicates.equalTo('bookUrl', book.bookUrl);
          await transaction.delete(predicates);
        }
      }
      for (let offset = 0; offset < chapterBuckets.length; offset += AppDatabase.BATCH_INSERT_CHUNK_SIZE) {
        await transaction.batchInsert('book_chapters',
          chapterBuckets.slice(offset, offset + AppDatabase.BATCH_INSERT_CHUNK_SIZE));
      }
      await transaction.commit();
    } catch (error) {
      await transaction.rollback();
      throw error;
    }
  }

  async updateBookReadingProgress(bookUrl: string, chapterTitle: string, chapterIndex: number,
    chapterPos: number, chapterTime: number, variable: string,
    syncRelevant: boolean = true): Promise<void> {
    if (!this.store || !bookUrl) return;
    const previousLatestTime = this.latestBookProgressWriteTimes.get(bookUrl) || 0;
    if (chapterTime < previousLatestTime) {
      console.info(`[ReaderProgress] skip stale snapshot before queue: ${bookUrl},` +
        `time=${chapterTime}<${previousLatestTime}`);
      return;
    }
    this.latestBookProgressWriteTimes.set(bookUrl, chapterTime);
    const previous = this.bookProgressWriteTasks.get(bookUrl) || Promise.resolve();
    const task = previous.catch((error: Error) => {
      console.warn(`[ReaderProgress] previous queued write failed: ${bookUrl}`, error);
    }).then(async (): Promise<void> => {
      const latestTime = this.latestBookProgressWriteTimes.get(bookUrl) || chapterTime;
      if (chapterTime < latestTime) {
        console.info(`[ReaderProgress] skip stale queued snapshot: ${bookUrl},` +
          `time=${chapterTime}<${latestTime}`);
        return;
      }
      await this.performBookReadingProgressUpdate(bookUrl, chapterTitle, chapterIndex,
        chapterPos, chapterTime, variable, syncRelevant);
    });
    this.bookProgressWriteTasks.set(bookUrl, task);
    try {
      await task;
    } finally {
      if (this.bookProgressWriteTasks.get(bookUrl) === task) {
        this.bookProgressWriteTasks.delete(bookUrl);
      }
    }
  }

  private async performBookReadingProgressUpdate(bookUrl: string, chapterTitle: string, chapterIndex: number,
    chapterPos: number, chapterTime: number, variable: string, syncRelevant: boolean): Promise<void> {
    if (!this.store || !bookUrl) return;
    const bucket: relationalStore.ValuesBucket = {
      durChapterTitle: chapterTitle,
      durChapterIndex: chapterIndex,
      durChapterPos: chapterPos,
      durChapterTime: chapterTime,
      variable: variable
    };
    const predicates = new relationalStore.RdbPredicates('books');
    predicates.equalTo('bookUrl', bookUrl);
    const affected = await this.store.update(bucket, predicates);
    if (affected <= 0) {
      const missing = new Book();
      missing.bookUrl = bookUrl;
      await this.recordBookMutation(
        'progress_update_missed', 'save_reading_progress', missing, 'bookUrl 精确匹配未命中');
      console.warn(`保存阅读进度未命中数据库记录: ${bookUrl}`);
      return;
    }
    if (syncRelevant) {
    }
  }

  async deleteBook(bookUrl: string, reason: string = 'delete_book'): Promise<void> {
    if (!this.store) return;
    const existing = await this.getBook(bookUrl);
    const predicates = new relationalStore.RdbPredicates('books');
    predicates.equalTo('bookUrl', bookUrl);
    const affected = await this.store.delete(predicates);
    if (affected > 0) {
      await this.recordBookMutation('delete', reason, existing, '', bookUrl);
    } else {
      await this.recordBookMutation('delete_missed', reason, existing, 'bookUrl 精确匹配未命中', bookUrl);
    }
    await this.deleteBookChapters(bookUrl);
    await this.deleteBookCachedContent(bookUrl);
    await this.deleteBookBookmarks(bookUrl);
    if (existing?.origin && existing.origin !== 'local') {
    }
  }

  private async recordBookMutation(operation: string, reason: string, book: Book | null,
    details: string = '', fallbackBookUrl: string = ''): Promise<void> {
    if (!this.store) return;
    try {
      const bookUrl = book?.bookUrl || fallbackBookUrl;
      const identityKey = book ? (book.identityKey || BookIdentity.keyOfBook(book)) : '';
      await this.store.insert('book_mutation_journal', {
        operation: operation,
        reason: reason,
        bookUrl: bookUrl,
        identityKey: identityKey,
        pendingAddToShelf: book?.pendingAddToShelf ? 1 : 0,
        eventTime: Date.now(),
        details: details
      });
      await this.store.executeSql(
        'DELETE FROM book_mutation_journal WHERE id NOT IN ' +
        '(SELECT id FROM book_mutation_journal ORDER BY id DESC LIMIT 500)');
    } catch (error) {
      console.warn('记录书架变更审计失败:', error);
    }
  }

  async insertBookmark(bookmark: Bookmark): Promise<number> {
    if (!this.store) return 0;
    const bucket: relationalStore.ValuesBucket = {
      bookUrl: bookmark.bookUrl,
      bookName: bookmark.bookName,
      bookAuthor: bookmark.bookAuthor,
      chapterIndex: bookmark.chapterIndex,
      chapterName: bookmark.chapterName,
      pageIndex: bookmark.pageIndex,
      startPos: bookmark.startPos,
      endPos: bookmark.endPos,
      content: bookmark.content,
      createTime: bookmark.createTime
    };
    const id = await this.store.insert('bookmarks', bucket);
    return id;
  }

  async getBookmarks(bookUrl: string): Promise<Bookmark[]> {
    const bookmarks: Bookmark[] = [];
    if (!this.store || !bookUrl) return bookmarks;
    const predicates = new relationalStore.RdbPredicates('bookmarks');
    predicates.equalTo('bookUrl', bookUrl);
    predicates.orderByDesc('createTime');
    const resultSet = await this.store.query(predicates, []);
    try {
      while (resultSet.goToNextRow()) {
        bookmarks.push(this.resultSetToBookmark(resultSet));
      }
    } finally {
      resultSet.close();
    }
    return bookmarks;
  }

  async getAllBookmarks(): Promise<Bookmark[]> {
    const bookmarks: Bookmark[] = [];
    if (!this.store) return bookmarks;
    const predicates = new relationalStore.RdbPredicates('bookmarks');
    predicates.orderByDesc('createTime');
    const resultSet = await this.store.query(predicates, []);
    try {
      while (resultSet.goToNextRow()) {
        bookmarks.push(this.resultSetToBookmark(resultSet));
      }
    } finally {
      resultSet.close();
    }
    return bookmarks;
  }

  async restoreBookmark(bookmark: Bookmark): Promise<void> {
    if (!this.store || !bookmark.bookUrl) return;
    const predicates = new relationalStore.RdbPredicates('bookmarks');
    predicates.equalTo('bookUrl', bookmark.bookUrl);
    predicates.equalTo('chapterIndex', bookmark.chapterIndex);
    predicates.equalTo('pageIndex', bookmark.pageIndex);
    await this.store.delete(predicates);
    await this.store.insert('bookmarks', {
      bookUrl: bookmark.bookUrl,
      bookName: bookmark.bookName,
      bookAuthor: bookmark.bookAuthor,
      chapterIndex: bookmark.chapterIndex,
      chapterName: bookmark.chapterName,
      pageIndex: bookmark.pageIndex,
      startPos: bookmark.startPos,
      endPos: bookmark.endPos,
      content: bookmark.content,
      createTime: bookmark.createTime
    });
  }

  async getBookmarkAt(bookUrl: string, chapterIndex: number, pageIndex: number): Promise<Bookmark | null> {
    if (!this.store || !bookUrl) return null;
    const predicates = new relationalStore.RdbPredicates('bookmarks');
    predicates.equalTo('bookUrl', bookUrl);
    predicates.equalTo('chapterIndex', chapterIndex);
    predicates.equalTo('pageIndex', pageIndex);
    const resultSet = await this.store.query(predicates, []);
    try {
      if (!resultSet.goToFirstRow()) return null;
      return this.resultSetToBookmark(resultSet);
    } finally {
      resultSet.close();
    }
  }

  async deleteBookmark(id: number): Promise<void> {
    if (!this.store || id <= 0) return;
    const predicates = new relationalStore.RdbPredicates('bookmarks');
    predicates.equalTo('id', id);
    await this.store.delete(predicates);
  }

  async deleteBookmarks(ids: number[]): Promise<void> {
    if (!this.store || ids.length === 0) return;
    const validIds = ids.filter((id: number) => id > 0);
    if (validIds.length === 0) return;
    const predicates = new relationalStore.RdbPredicates('bookmarks');
    predicates.in('id', validIds);
    await this.store.delete(predicates);
  }

  async deleteBookBookmarks(bookUrl: string): Promise<void> {
    if (!this.store || !bookUrl) return;
    const predicates = new relationalStore.RdbPredicates('bookmarks');
    predicates.equalTo('bookUrl', bookUrl);
    await this.store.delete(predicates);
  }

  async moveBookBookmarks(fromBookUrl: string, toBookUrl: string, bookName: string, bookAuthor: string): Promise<void> {
    if (!this.store || !fromBookUrl || !toBookUrl || fromBookUrl === toBookUrl) return;
    const predicates = new relationalStore.RdbPredicates('bookmarks');
    predicates.equalTo('bookUrl', fromBookUrl);
    await this.store.update({
      bookUrl: toBookUrl,
      bookName: bookName,
      bookAuthor: bookAuthor
    }, predicates);
  }

  async updateBookBookmarkMetadata(bookUrl: string, bookName: string, bookAuthor: string): Promise<void> {
    if (!this.store || !bookUrl) return;
    const predicates = new relationalStore.RdbPredicates('bookmarks');
    predicates.equalTo('bookUrl', bookUrl);
    await this.store.update({
      bookName: bookName,
      bookAuthor: bookAuthor
    }, predicates);
  }

  private resultSetToBookmark(resultSet: relationalStore.ResultSet): Bookmark {
    const bookmark = new Bookmark();
    bookmark.id = resultSet.getLong(resultSet.getColumnIndex('id'));
    bookmark.bookUrl = resultSet.getString(resultSet.getColumnIndex('bookUrl'));
    bookmark.bookName = resultSet.getString(resultSet.getColumnIndex('bookName'));
    bookmark.bookAuthor = resultSet.getString(resultSet.getColumnIndex('bookAuthor'));
    bookmark.chapterIndex = resultSet.getLong(resultSet.getColumnIndex('chapterIndex'));
    bookmark.chapterName = resultSet.getString(resultSet.getColumnIndex('chapterName'));
    bookmark.pageIndex = resultSet.getLong(resultSet.getColumnIndex('pageIndex'));
    bookmark.startPos = resultSet.getLong(resultSet.getColumnIndex('startPos'));
    bookmark.endPos = resultSet.getLong(resultSet.getColumnIndex('endPos'));
    bookmark.content = resultSet.getString(resultSet.getColumnIndex('content'));
    bookmark.createTime = resultSet.getLong(resultSet.getColumnIndex('createTime'));
    return bookmark;
  }

  async getBook(bookUrl: string): Promise<Book | null> {
    if (!this.store) return null;
    const predicates = new relationalStore.RdbPredicates('books');
    predicates.equalTo('bookUrl', bookUrl);
    const resultSet = await this.store.query(predicates, []);
    try {
      if (!resultSet.goToFirstRow()) return null;
      return this.resultSetToBook(resultSet);
    } finally {
      resultSet.close();
    }
  }

  async getAllBooks(): Promise<Book[]> {
    if (!this.store) return [];
    const predicates = new relationalStore.RdbPredicates('books');
    predicates.orderByDesc('durChapterTime');
    const resultSet = await this.store.query(predicates, []);
    const books: Book[] = [];
    try {
      while (resultSet.goToNextRow()) {
        books.push(this.resultSetToBook(resultSet));
      }
    } finally {
      resultSet.close();
    }
    return books;
  }

  async setBookPinned(bookUrl: string, pinned: boolean, modifiedTime: number = Date.now()): Promise<void> {
    if (!this.store || !bookUrl) return;
    const predicates = new relationalStore.RdbPredicates('books');
    predicates.equalTo('bookUrl', bookUrl);
    const affected = await this.store.update({
      isPinned: pinned ? 1 : 0,
      shelfModifiedTime: modifiedTime
    }, predicates);
    if (affected <= 0) {
      throw new Error(`置顶书籍未命中数据库记录: ${bookUrl}`);
    }
  }

  async getBookByIdentityKey(identityKey: string): Promise<Book | null> {
    if (!this.store || !identityKey) return null;
    const predicates = new relationalStore.RdbPredicates('books');
    predicates.equalTo('identityKey', identityKey);
    const resultSet = await this.store.query(predicates, []);
    try {
      if (!resultSet.goToFirstRow()) return null;
      return this.resultSetToBook(resultSet);
    } finally {
      resultSet.close();
    }
  }

  /**
   * Local books use a content fingerprint for cross-device progress sync. The
   * fingerprint lives in the variable JSON rather than in the source-facing
   * schema, so older databases remain compatible.
   */
  async getBookByLocalContentHash(contentHash: string): Promise<Book | null> {
    const normalized = (contentHash || '').trim();
    if (!this.store || !normalized) return null;
    const books = await this.getAllBooks();
    for (const book of books) {
      if (book.origin === 'local' && book.getVariable('localContentHash') === normalized) {
        return book;
      }
    }
    return null;
  }

  async restoreBook(book: Book): Promise<void> {
    if (!this.store || !book.bookUrl) return;
    book.identityKey = BookIdentity.keyOfBook(book);
    const existing = await this.getBook(book.bookUrl) || await this.getBookByIdentityKey(book.identityKey);
    if (existing) {
      if (existing.bookUrl !== book.bookUrl) {
        book.bookUrl = existing.bookUrl;
      }
      await this.updateBook(book, true, 'cloud_restore_update');
    } else {
      await this.insertBook(book, 'cloud_restore_insert');
    }
  }

  async getCustomBookGroups(): Promise<BookGroup[]> {
    const groups: BookGroup[] = [];
    if (!this.store) return groups;
    const resultSet = await this.store.querySql(
      'SELECT groupId, groupName, groupOrder, show, enableRefresh FROM book_groups WHERE groupId > 0 ORDER BY groupOrder, groupId'
    );
    try {
      while (resultSet.goToNextRow()) {
        const group = new BookGroup();
        group.groupId = resultSet.getLong(resultSet.getColumnIndex('groupId'));
        group.groupName = resultSet.getString(resultSet.getColumnIndex('groupName'));
        group.order = resultSet.getLong(resultSet.getColumnIndex('groupOrder'));
        group.show = resultSet.getLong(resultSet.getColumnIndex('show')) === 1;
        group.enableRefresh = resultSet.getLong(resultSet.getColumnIndex('enableRefresh')) === 1;
        groups.push(group);
      }
    } finally {
      resultSet.close();
    }
    return groups;
  }

  async restoreBookGroup(group: BookGroup): Promise<void> {
    if (!this.store || group.groupId <= 0 || !group.groupName.trim()) return;
    const predicates = new relationalStore.RdbPredicates('book_groups');
    predicates.equalTo('groupId', group.groupId);
    const resultSet = await this.store.query(predicates, []);
    const bucket: relationalStore.ValuesBucket = {
      groupId: group.groupId,
      groupName: group.groupName,
      groupOrder: group.order,
      show: group.show ? 1 : 0,
      enableRefresh: group.enableRefresh ? 1 : 0
    };
    const exists = resultSet.rowCount > 0;
    resultSet.close();
    if (exists) {
      await this.store.update(bucket, predicates);
    } else {
      await this.store.insert('book_groups', bucket);
    }
  }

  async addBookGroup(groupName: string): Promise<BookGroup | null> {
    if (!this.store || !groupName.trim()) return null;
    const name = groupName.trim();
    const duplicate = await this.store.querySql('SELECT groupId FROM book_groups WHERE groupName = ?', [name]);
    const duplicateExists = duplicate.rowCount > 0;
    duplicate.close();
    if (duplicateExists) return null;
    const maxResult = await this.store.querySql('SELECT MAX(groupId) AS maxId FROM book_groups WHERE groupId > 0');
    let maxId = 0;
    try {
      if (maxResult.goToFirstRow()) {
        maxId = maxResult.getLong(maxResult.getColumnIndex('maxId'));
      }
    } finally {
      maxResult.close();
    }
    const group = new BookGroup();
    group.groupId = Math.max(0, maxId) + 1;
    group.groupName = name;
    group.order = group.groupId;
    await this.store.insert('book_groups', {
      groupId: group.groupId, groupName: group.groupName, groupOrder: group.order, show: 1, enableRefresh: 1
    });
    return group;
  }

  async renameBookGroup(groupId: number, groupName: string): Promise<boolean> {
    if (!this.store || groupId <= 0 || !groupName.trim()) return false;
    const name = groupName.trim();
    const duplicate = await this.store.querySql(
      'SELECT groupId FROM book_groups WHERE groupName = ? AND groupId != ?', [name, groupId]
    );
    const duplicateExists = duplicate.rowCount > 0;
    duplicate.close();
    if (duplicateExists) return false;
    const predicates = new relationalStore.RdbPredicates('book_groups');
    predicates.equalTo('groupId', groupId);
    await this.store.update({ groupName: name }, predicates);
    return true;
  }

  async updateBooksGroup(bookUrls: string[], groupId: number): Promise<void> {
    if (!this.store || bookUrls.length === 0) return;
    const predicates = new relationalStore.RdbPredicates('books');
    predicates.in('bookUrl', bookUrls);
    await this.store.update({ groupId: groupId }, predicates);
  }

  async deleteBookGroup(groupId: number): Promise<void> {
    if (!this.store || groupId <= 0) return;
    const bookPredicates = new relationalStore.RdbPredicates('books');
    bookPredicates.equalTo('groupId', groupId);
    await this.store.update({ groupId: 0 }, bookPredicates);
    const groupPredicates = new relationalStore.RdbPredicates('book_groups');
    groupPredicates.equalTo('groupId', groupId);
    await this.store.delete(groupPredicates);
  }

  private resultSetToBook(resultSet: relationalStore.ResultSet): Book {
    const book = new Book();
    book.bookUrl = this.getStringColumn(resultSet, 'bookUrl');
    book.tocUrl = this.getStringColumn(resultSet, 'tocUrl');
    book.origin = this.getStringColumn(resultSet, 'origin', 'local');
    book.originName = this.getStringColumn(resultSet, 'originName');
    book.name = this.getStringColumn(resultSet, 'name');
    book.author = this.getStringColumn(resultSet, 'author');
    book.kind = this.getStringColumn(resultSet, 'kind');
    book.status = this.getStringColumn(resultSet, 'status');
    book.customTag = this.getStringColumn(resultSet, 'customTag');
    book.coverUrl = this.getStringColumn(resultSet, 'coverUrl');
    book.customCoverUrl = this.getStringColumn(resultSet, 'customCoverUrl');
    book.intro = this.getStringColumn(resultSet, 'intro');
    book.customIntro = this.getStringColumn(resultSet, 'customIntro');
    book.charset = this.getStringColumn(resultSet, 'charset');
    book.type = this.getLongColumn(resultSet, 'type');
    book.group = this.getLongColumn(resultSet, 'groupId');
    book.isPinned = this.getLongColumn(resultSet, 'isPinned') === 1;
    book.latestChapterTitle = this.getStringColumn(resultSet, 'latestChapterTitle');
    book.updateTime = this.getStringColumn(resultSet, 'updateTime');
    book.latestChapterTime = this.getLongColumn(resultSet, 'latestChapterTime');
    book.lastCheckTime = this.getLongColumn(resultSet, 'lastCheckTime');
    book.lastCheckCount = this.getLongColumn(resultSet, 'lastCheckCount');
    book.totalChapterNum = this.getLongColumn(resultSet, 'totalChapterNum');
    book.durChapterTitle = this.getStringColumn(resultSet, 'durChapterTitle');
    book.durChapterIndex = this.getLongColumn(resultSet, 'durChapterIndex');
    book.durChapterPos = this.getLongColumn(resultSet, 'durChapterPos');
    book.durChapterTime = this.getLongColumn(resultSet, 'durChapterTime');
    book.wordCount = this.getStringColumn(resultSet, 'wordCount');
    book.canUpdate = this.getLongColumn(resultSet, 'canUpdate', 1) === 1;
    book.order = this.getLongColumn(resultSet, 'bookOrder');
    book.originOrder = this.getLongColumn(resultSet, 'originOrder');
    book.variable = this.getStringColumn(resultSet, 'variable');
    const readConfigStr = this.getStringColumn(resultSet, 'readConfig');
    if (readConfigStr) {
      try {
        book.readConfig = JSON.parse(readConfigStr);
      } catch (e) {
        book.readConfig = null;
      }
    }
    book.syncTime = this.getLongColumn(resultSet, 'syncTime');
    book.identityKey = this.getStringColumn(resultSet, 'identityKey') || BookIdentity.keyOfBook(book);
    book.pendingAddToShelf = this.getLongColumn(resultSet, 'pendingAddToShelf') === 1;
    book.shelfModifiedTime = this.getLongColumn(resultSet, 'shelfModifiedTime');
    return book;
  }

  private getStringColumn(resultSet: relationalStore.ResultSet, column: string, fallback: string = ''): string {
    const index = resultSet.getColumnIndex(column);
    if (index < 0) {
      return fallback;
    }
    return resultSet.getString(index) || fallback;
  }

  private getLongColumn(resultSet: relationalStore.ResultSet, column: string, fallback: number = 0): number {
    const index = resultSet.getColumnIndex(column);
    if (index < 0) {
      return fallback;
    }
    return resultSet.getLong(index);
  }

  async insertBookSource(source: BookSource): Promise<boolean> {
    if (!this.store) return false;
    const bucket: relationalStore.ValuesBucket = {
      bookSourceUrl: source.bookSourceUrl,
      bookSourceName: source.bookSourceName,
      bookSourceType: source.bookSourceType,
      bookSourceGroup: source.bookSourceGroup,
      bookSourceComment: source.bookSourceComment,
      loginUrl: source.loginUrl,
      loginUi: source.loginUi,
      loginCheckJs: source.loginCheckJs,
      loginHeader: source.loginHeader,
      loginInfo: source.loginInfo,
      rawSourceJson: source.rawSourceJson,
      bookUrlPattern: source.bookUrlPattern,
      searchUrl: source.searchUrl,
      exploreUrl: source.exploreUrl,
      jsLib: source.jsLib,
      header: source.header,
      bookListRule: JSON.stringify(source.bookListRule),
      searchRule: JSON.stringify(source.searchRule),
      exploreRule: JSON.stringify(source.exploreRule),
      bookInfoRule: JSON.stringify(source.bookInfoRule),
      tocRule: JSON.stringify(source.tocRule),
      contentRule: JSON.stringify(source.contentRule),
      variableComment: source.variableComment,
      variable: source.variable,
      lastUpdateTime: source.lastUpdateTime,
      respondTime: source.respondTime,
      customOrder: source.customOrder,
      customButton: source.customButton ? 1 : 0,
      eventListener: source.eventListener ? 1 : 0,
      isPinned: source.isPinned ? 1 : 0,
      enabled: source.enabled ? 1 : 0,
      enabledExplore: source.enabledExplore ? 1 : 0,
      isLocked: source.isLocked ? 1 : 0,
      validationStatus: this.normalizeBookSourceValidationStatus(source.validationStatus),
      weight: source.weight,
      concurrentRate: source.concurrentRate,
      enabledCookieJar: source.enabledCookieJar ? 1 : 0
    };

    const predicates = new relationalStore.RdbPredicates('book_sources');
    predicates.equalTo('bookSourceUrl', source.bookSourceUrl);
    const resultSet = await this.store.query(predicates, []);
    const exists = resultSet.goToFirstRow();
    if (exists) {
      let locked = false;
      try {
        locked = this.getLongColumn(resultSet, 'isLocked') === 1;
        if (!locked) {
          // 导入更新已有书源时保留用户在管理页设置的顺序。
          bucket['customOrder'] = this.getLongColumn(resultSet, 'customOrder');
          source.customOrder = bucket['customOrder'] as number;
          bucket['isPinned'] = this.getLongColumn(resultSet, 'isPinned');
          source.isPinned = bucket['isPinned'] === 1;
          // 登录信息、脚本设置和运行时缓存属于用户状态，更新书源定义时不能被覆盖。
          bucket['variable'] = this.getStringColumn(resultSet, 'variable');
          source.variable = bucket['variable'] as string;
          bucket['loginHeader'] = this.getStringColumn(resultSet, 'loginHeader');
          source.loginHeader = bucket['loginHeader'] as string;
          bucket['loginInfo'] = this.getStringColumn(resultSet, 'loginInfo');
          source.loginInfo = bucket['loginInfo'] as string;
        }
      } finally {
        resultSet.close();
      }
      if (locked) return false;
      await this.store.update(bucket, predicates);
    } else {
      resultSet.close();
      // 新书源追加到现有顺序末尾，避免默认值 0 把它插到列表顶部。
      const maxOrderResult = await this.store.querySql('SELECT MAX(customOrder) AS maxOrder FROM book_sources');
      let maxOrder = -1;
      try {
        if (maxOrderResult.goToFirstRow()) {
          maxOrder = this.getLongColumn(maxOrderResult, 'maxOrder', -1);
        }
      } finally {
        maxOrderResult.close();
      }
      source.customOrder = Math.max(0, maxOrder + 1);
      bucket['customOrder'] = source.customOrder;
      await this.store.insert('book_sources', bucket);
    }
    return true;
  }

  async updateBookSource(source: BookSource, originalBookSourceUrl: string = ''): Promise<void> {
    if (!this.store) return;
    const lookupUrl = originalBookSourceUrl || source.bookSourceUrl;
    if (await this.isBookSourceLocked(lookupUrl)) return;
    const bucket: relationalStore.ValuesBucket = {
      bookSourceUrl: source.bookSourceUrl,
      bookSourceName: source.bookSourceName,
      bookSourceType: source.bookSourceType,
      bookSourceGroup: source.bookSourceGroup,
      bookSourceComment: source.bookSourceComment,
      loginUrl: source.loginUrl,
      loginUi: source.loginUi,
      loginCheckJs: source.loginCheckJs,
      loginHeader: source.loginHeader,
      loginInfo: source.loginInfo,
      rawSourceJson: source.rawSourceJson,
      bookUrlPattern: source.bookUrlPattern,
      searchUrl: source.searchUrl,
      exploreUrl: source.exploreUrl,
      jsLib: source.jsLib,
      header: source.header,
      bookListRule: JSON.stringify(source.bookListRule),
      searchRule: JSON.stringify(source.searchRule),
      exploreRule: JSON.stringify(source.exploreRule),
      bookInfoRule: JSON.stringify(source.bookInfoRule),
      tocRule: JSON.stringify(source.tocRule),
      contentRule: JSON.stringify(source.contentRule),
      variableComment: source.variableComment,
      variable: source.variable,
      lastUpdateTime: source.lastUpdateTime,
      respondTime: source.respondTime,
      customOrder: source.customOrder,
      customButton: source.customButton ? 1 : 0,
      eventListener: source.eventListener ? 1 : 0,
      isPinned: source.isPinned ? 1 : 0,
      enabled: source.enabled ? 1 : 0,
      enabledExplore: source.enabledExplore ? 1 : 0,
      isLocked: source.isLocked ? 1 : 0,
      validationStatus: this.normalizeBookSourceValidationStatus(source.validationStatus),
      weight: source.weight,
      concurrentRate: source.concurrentRate,
      enabledCookieJar: source.enabledCookieJar ? 1 : 0
    };

    const predicates = new relationalStore.RdbPredicates('book_sources');
    predicates.equalTo('bookSourceUrl', lookupUrl);
    await this.store.update(bucket, predicates);
  }

  async deleteBookSource(bookSourceUrl: string): Promise<void> {
    if (!this.store) return;
    if (await this.isBookSourceLocked(bookSourceUrl)) return;
    const predicates = new relationalStore.RdbPredicates('book_sources');
    predicates.equalTo('bookSourceUrl', bookSourceUrl);
    await this.store.delete(predicates);
  }

  async deleteBookSourceForSync(bookSourceUrl: string): Promise<void> {
    if (!this.store || !bookSourceUrl) return;
    const predicates = new relationalStore.RdbPredicates('book_sources');
    predicates.equalTo('bookSourceUrl', bookSourceUrl);
    await this.store.delete(predicates);
  }

  async getBookSource(bookSourceUrl: string): Promise<BookSource | null> {
    if (!this.store) return null;
    const predicates = new relationalStore.RdbPredicates('book_sources');
    predicates.equalTo('bookSourceUrl', bookSourceUrl);
    const resultSet = await this.store.query(predicates, []);
    try {
      if (!resultSet.goToFirstRow()) return null;
      return this.resultSetToBookSource(resultSet);
    } finally {
      resultSet.close();
    }
  }

  async getAllBookSources(): Promise<BookSource[]> {
    if (!this.store) return [];
    const predicates = new relationalStore.RdbPredicates('book_sources');
    predicates.orderByDesc('isPinned');
    predicates.orderByAsc('customOrder');
    const resultSet = await this.store.query(predicates, []);
    const sources: BookSource[] = [];
    try {
      while (resultSet.goToNextRow()) {
        sources.push(this.resultSetToBookSource(resultSet));
      }
    } finally {
      resultSet.close();
    }
    return sources;
  }

  async restoreBookSource(source: BookSource): Promise<void> {
    if (!this.store || !source.bookSourceUrl) return;
    const bucket: relationalStore.ValuesBucket = {
      bookSourceUrl: source.bookSourceUrl,
      bookSourceName: source.bookSourceName,
      bookSourceType: source.bookSourceType,
      bookSourceGroup: source.bookSourceGroup,
      bookSourceComment: source.bookSourceComment,
      loginUrl: source.loginUrl,
      loginUi: source.loginUi,
      loginCheckJs: source.loginCheckJs,
      loginHeader: source.loginHeader,
      loginInfo: source.loginInfo,
      rawSourceJson: source.rawSourceJson,
      bookUrlPattern: source.bookUrlPattern,
      searchUrl: source.searchUrl,
      exploreUrl: source.exploreUrl,
      jsLib: source.jsLib,
      header: source.header,
      bookListRule: JSON.stringify(source.bookListRule),
      searchRule: JSON.stringify(source.searchRule),
      exploreRule: JSON.stringify(source.exploreRule),
      bookInfoRule: JSON.stringify(source.bookInfoRule),
      tocRule: JSON.stringify(source.tocRule),
      contentRule: JSON.stringify(source.contentRule),
      variableComment: source.variableComment,
      variable: source.variable,
      lastUpdateTime: source.lastUpdateTime,
      respondTime: source.respondTime,
      customOrder: source.customOrder,
      customButton: source.customButton ? 1 : 0,
      eventListener: source.eventListener ? 1 : 0,
      isPinned: source.isPinned ? 1 : 0,
      enabled: source.enabled ? 1 : 0,
      enabledExplore: source.enabledExplore ? 1 : 0,
      isLocked: source.isLocked ? 1 : 0,
      validationStatus: this.normalizeBookSourceValidationStatus(source.validationStatus),
      weight: source.weight,
      concurrentRate: source.concurrentRate,
      enabledCookieJar: source.enabledCookieJar ? 1 : 0
    };
    const predicates = new relationalStore.RdbPredicates('book_sources');
    predicates.equalTo('bookSourceUrl', source.bookSourceUrl);
    const resultSet = await this.store.query(predicates, []);
    const exists = resultSet.rowCount > 0;
    resultSet.close();
    if (exists) {
      await this.store.update(bucket, predicates);
    } else {
      await this.store.insert('book_sources', bucket);
    }
  }

  /** 列表只读取轻量字段；规则详情在实际使用时再按主键加载。 */
  async getBookSourceSummaries(): Promise<BookSource[]> {
    if (!this.store) return [];
    const predicates = new relationalStore.RdbPredicates('book_sources');
    predicates.orderByDesc('isPinned');
    predicates.orderByAsc('customOrder');
    const columns = [
      'bookSourceUrl', 'bookSourceName', 'bookSourceGroup', 'loginUrl', 'loginUi',
      'loginCheckJs', 'loginHeader', 'exploreUrl', 'lastUpdateTime', 'customOrder', 'isPinned', 'enabled', 'enabledExplore', 'isLocked',
      'validationStatus'
    ];
    const resultSet = await this.store.query(predicates, columns);
    const sources: BookSource[] = [];
    try {
      while (resultSet.goToNextRow()) {
        const source = new BookSource();
        source.bookSourceUrl = resultSet.getString(resultSet.getColumnIndex('bookSourceUrl'));
        source.bookSourceName = resultSet.getString(resultSet.getColumnIndex('bookSourceName'));
        source.bookSourceGroup = resultSet.getString(resultSet.getColumnIndex('bookSourceGroup'));
        source.loginUrl = resultSet.getString(resultSet.getColumnIndex('loginUrl'));
        source.loginUi = resultSet.getString(resultSet.getColumnIndex('loginUi'));
        source.loginCheckJs = resultSet.getString(resultSet.getColumnIndex('loginCheckJs'));
        source.loginHeader = resultSet.getString(resultSet.getColumnIndex('loginHeader'));
        source.exploreUrl = resultSet.getString(resultSet.getColumnIndex('exploreUrl'));
        source.lastUpdateTime = resultSet.getLong(resultSet.getColumnIndex('lastUpdateTime'));
        source.customOrder = resultSet.getLong(resultSet.getColumnIndex('customOrder'));
        source.isPinned = this.getLongColumn(resultSet, 'isPinned') === 1;
        source.enabled = resultSet.getLong(resultSet.getColumnIndex('enabled')) === 1;
        source.enabledExplore = resultSet.getLong(resultSet.getColumnIndex('enabledExplore')) === 1;
        source.isLocked = this.getLongColumn(resultSet, 'isLocked') === 1;
        source.validationStatus = this.normalizeBookSourceValidationStatus(
          this.getLongColumn(resultSet, 'validationStatus'));
        sources.push(source);
      }
    } finally {
      resultSet.close();
    }
    return sources;
  }

  async updateBookSourceListFields(bookSourceUrl: string, fields: Record<string, string | number>): Promise<void> {
    if (!this.store) return;
    if (await this.isBookSourceLocked(bookSourceUrl)) return;
    const bucket: relationalStore.ValuesBucket = {};
    if (fields['bookSourceGroup'] !== undefined) bucket['bookSourceGroup'] = fields['bookSourceGroup'];
    if (fields['enabled'] !== undefined) bucket['enabled'] = fields['enabled'];
    if (fields['enabledExplore'] !== undefined) bucket['enabledExplore'] = fields['enabledExplore'];
    if (fields['customOrder'] !== undefined) bucket['customOrder'] = fields['customOrder'];
    if (fields['validationStatus'] !== undefined) {
      bucket['validationStatus'] = this.normalizeBookSourceValidationStatus(Number(fields['validationStatus']));
    }
    bucket['lastUpdateTime'] = Date.now();
    const predicates = new relationalStore.RdbPredicates('book_sources');
    predicates.equalTo('bookSourceUrl', bookSourceUrl);
    await this.store.update(bucket, predicates);
    if (fields['bookSourceGroup'] !== undefined ||
      fields['enabled'] !== undefined ||
      fields['enabledExplore'] !== undefined ||
      fields['customOrder'] !== undefined) {
    }
  }

  /** 书源排序属于列表管理信息，不受书源内容锁定状态影响。 */
  async updateBookSourceOrders(bookSourceUrls: string[]): Promise<void> {
    if (!this.store || bookSourceUrls.length === 0) return;
    const transaction = await this.store.createTransaction();
    try {
      for (let index = 0; index < bookSourceUrls.length; index++) {
        const bookSourceUrl = bookSourceUrls[index];
        if (!bookSourceUrl) continue;
        const predicates = new relationalStore.RdbPredicates('book_sources');
        predicates.equalTo('bookSourceUrl', bookSourceUrl);
        await transaction.update({ customOrder: index }, predicates);
      }
      await transaction.commit();
    } catch (e) {
      await transaction.rollback();
      throw e;
    }
  }

  /** 置顶属于列表管理信息，不受书源规则锁定状态影响。 */
  async setBookSourcePinned(bookSourceUrl: string, pinned: boolean): Promise<void> {
    if (!this.store || !bookSourceUrl) return;
    const predicates = new relationalStore.RdbPredicates('book_sources');
    predicates.equalTo('bookSourceUrl', bookSourceUrl);
    await this.store.update({ isPinned: pinned ? 1 : 0 }, predicates);
  }

  /** 分组重命名或删除时更新归属；这类列表管理操作不改动书源规则内容。 */
  async updateBookSourceGroupMembership(bookSourceUrl: string, groupName: string): Promise<void> {
    if (!this.store || !bookSourceUrl) return;
    const predicates = new relationalStore.RdbPredicates('book_sources');
    predicates.equalTo('bookSourceUrl', bookSourceUrl);
    await this.store.update({ bookSourceGroup: groupName, lastUpdateTime: Date.now() }, predicates);
  }

  async setBookSourceLocked(bookSourceUrl: string, locked: boolean): Promise<void> {
    if (!this.store) return;
    const predicates = new relationalStore.RdbPredicates('book_sources');
    predicates.equalTo('bookSourceUrl', bookSourceUrl);
    await this.store.update({ isLocked: locked ? 1 : 0 }, predicates);
  }

  /** 校验结果是运行状态，锁定书源也需要正常记录。 */
  async updateBookSourceValidationStatus(bookSourceUrl: string, validationStatus: number): Promise<void> {
    if (!this.store || !bookSourceUrl) return;
    const predicates = new relationalStore.RdbPredicates('book_sources');
    predicates.equalTo('bookSourceUrl', bookSourceUrl);
    await this.store.update({
      validationStatus: this.normalizeBookSourceValidationStatus(validationStatus)
    }, predicates);
  }

  /** Runtime source variables (for mirror selection/login actions) remain writable for locked rule definitions. */
  async updateBookSourceVariable(bookSourceUrl: string, variable: string): Promise<void> {
    if (!this.store || !bookSourceUrl) return;
    const predicates = new relationalStore.RdbPredicates('book_sources');
    predicates.equalTo('bookSourceUrl', bookSourceUrl);
    await this.store.update({ variable: variable || '' }, predicates);
  }

  async updateBookSourceLoginRuntime(bookSourceUrl: string, variable: string, loginHeader: string,
    loginInfo: string): Promise<void> {
    if (!this.store || !bookSourceUrl) return;
    const predicates = new relationalStore.RdbPredicates('book_sources');
    predicates.equalTo('bookSourceUrl', bookSourceUrl);
    await this.store.update({
      variable: variable || '',
      loginHeader: loginHeader || '',
      loginInfo: loginInfo || ''
    }, predicates);
  }

  private normalizeBookSourceValidationStatus(value: number): number {
    if (value === BookSource.VALIDATION_PASSED || value === BookSource.VALIDATION_FAILED ||
      value === BookSource.VALIDATION_NO_RESULTS || value === BookSource.VALIDATION_NEEDS_VERIFICATION ||
      value === BookSource.VALIDATION_TEMPORARY_ERROR) {
      return value;
    }
    return BookSource.VALIDATION_UNCHECKED;
  }

  private async isBookSourceLocked(bookSourceUrl: string): Promise<boolean> {
    if (!this.store || !bookSourceUrl) return false;
    const predicates = new relationalStore.RdbPredicates('book_sources');
    predicates.equalTo('bookSourceUrl', bookSourceUrl);
    const resultSet = await this.store.query(predicates, ['isLocked']);
    try {
      if (!resultSet.goToFirstRow()) return false;
      return this.getLongColumn(resultSet, 'isLocked') === 1;
    } finally {
      resultSet.close();
    }
  }

  async getEnabledBookSources(): Promise<BookSource[]> {
    return this.getEnabledBookSourcesForRuleScope('all');
  }

  async getEnabledBookSourcesForSearch(): Promise<BookSource[]> {
    return this.getEnabledBookSourcesForRuleScope('search');
  }

  async getEnabledBookSourcesForExplore(): Promise<BookSource[]> {
    return this.getEnabledBookSourcesForRuleScope('explore');
  }

  private async getEnabledBookSourcesForRuleScope(ruleScope: string): Promise<BookSource[]> {
    if (!this.store) return [];
    const predicates = new relationalStore.RdbPredicates('book_sources');
    predicates.equalTo('enabled', 1);
    if (ruleScope === 'explore') predicates.equalTo('enabledExplore', 1);
    predicates.orderByDesc('isPinned');
    predicates.orderByAsc('customOrder');
    const columns = ruleScope === 'search' ? this.searchBookSourceColumns() :
      (ruleScope === 'explore' ? this.exploreBookSourceColumns() : []);
    const resultSet = await this.store.query(predicates, columns);
    const sources: BookSource[] = [];
    try {
      while (resultSet.goToNextRow()) {
        sources.push(this.resultSetToBookSource(resultSet, ruleScope));
      }
    } finally {
      resultSet.close();
    }
    return sources;
  }

  async searchBookSources(keyword: string): Promise<BookSource[]> {
    if (!this.store) return [];
    const predicates = new relationalStore.RdbPredicates('book_sources');
    predicates.like('bookSourceName', `%${keyword}%`);
    predicates.orderByDesc('isPinned');
    predicates.orderByAsc('customOrder');
    const resultSet = await this.store.query(predicates, []);
    const sources: BookSource[] = [];
    try {
      while (resultSet.goToNextRow()) {
        sources.push(this.resultSetToBookSource(resultSet));
      }
    } finally {
      resultSet.close();
    }
    return sources;
  }

  private resultSetToBookSource(resultSet: relationalStore.ResultSet, ruleScope: string = 'all'): BookSource {
    const source = new BookSource();
    source.bookSourceUrl = this.getStringColumn(resultSet, 'bookSourceUrl');
    source.bookSourceName = this.getStringColumn(resultSet, 'bookSourceName');
    source.bookSourceType = this.getLongColumn(resultSet, 'bookSourceType');
    source.bookSourceGroup = this.getStringColumn(resultSet, 'bookSourceGroup');
    source.bookSourceComment = this.getStringColumn(resultSet, 'bookSourceComment');
    source.loginUrl = this.getStringColumn(resultSet, 'loginUrl');
    source.loginUi = this.getStringColumn(resultSet, 'loginUi');
    source.loginCheckJs = this.getStringColumn(resultSet, 'loginCheckJs');
    source.loginHeader = this.getStringColumn(resultSet, 'loginHeader');
    source.loginInfo = this.getStringColumn(resultSet, 'loginInfo');
    source.rawSourceJson = this.getStringColumn(resultSet, 'rawSourceJson');
    source.bookUrlPattern = this.getStringColumn(resultSet, 'bookUrlPattern');
    source.searchUrl = this.getStringColumn(resultSet, 'searchUrl');
    source.exploreUrl = this.getStringColumn(resultSet, 'exploreUrl');
    source.jsLib = this.getStringColumn(resultSet, 'jsLib');
    source.header = this.getStringColumn(resultSet, 'header');
    if (ruleScope === 'all') {
      try {
        source.bookListRule = JSON.parse(this.getStringColumn(resultSet, 'bookListRule'));
      } catch (e) {}
    }
    if (ruleScope === 'all' || ruleScope === 'search' || ruleScope === 'explore') {
      try {
        source.searchRule = JSON.parse(this.getStringColumn(resultSet, 'searchRule'));
      } catch (e) {}
    }
    if (ruleScope === 'all' || ruleScope === 'explore') {
      try {
        const parsed = JSON.parse(this.getStringColumn(resultSet, 'exploreRule')) as Object;
        if (parsed && !Array.isArray(parsed)) source.exploreRule = parsed as ExploreRule;
      } catch (e) {}
    }
    if (ruleScope === 'all') {
      try {
        source.bookInfoRule = JSON.parse(this.getStringColumn(resultSet, 'bookInfoRule'));
      } catch (e) {}
      try {
        const parsed = JSON.parse(this.getStringColumn(resultSet, 'tocRule')) as Object;
        if (parsed && !Array.isArray(parsed)) source.tocRule = parsed as TocRule;
        source.tocRule.nextTocUrl = source.tocRule.nextTocUrl || '';
      } catch (e) {}
      try {
        const parsed = JSON.parse(this.getStringColumn(resultSet, 'contentRule')) as Object;
        if (parsed && !Array.isArray(parsed)) source.contentRule = parsed as ContentRule;
        source.contentRule.sourceRegex = source.contentRule.sourceRegex || '';
        source.contentRule.nextContentUrl = source.contentRule.nextContentUrl || '';
        source.contentRule.imageDecode = source.contentRule.imageDecode || '';
      } catch (e) {}
    }
    source.variableComment = this.getStringColumn(resultSet, 'variableComment');
    source.variable = this.getStringColumn(resultSet, 'variable');
    source.lastUpdateTime = this.getLongColumn(resultSet, 'lastUpdateTime');
    source.respondTime = this.getLongColumn(resultSet, 'respondTime', 180000);
    source.customOrder = this.getLongColumn(resultSet, 'customOrder');
    source.customButton = this.getLongColumn(resultSet, 'customButton') === 1;
    source.eventListener = this.getLongColumn(resultSet, 'eventListener') === 1;
    source.isPinned = this.getLongColumn(resultSet, 'isPinned') === 1;
    source.enabled = this.getLongColumn(resultSet, 'enabled') === 1;
    source.isLocked = this.getLongColumn(resultSet, 'isLocked') === 1;
    source.enabledExplore = this.getLongColumn(resultSet, 'enabledExplore') === 1;
    source.validationStatus = this.normalizeBookSourceValidationStatus(
      this.getLongColumn(resultSet, 'validationStatus'));
    source.weight = this.getLongColumn(resultSet, 'weight');
    source.concurrentRate = this.getStringColumn(resultSet, 'concurrentRate');
    source.enabledCookieJar = this.getLongColumn(resultSet, 'enabledCookieJar', 1) === 1;
    return source;
  }

  private searchBookSourceColumns(): string[] {
    return [
      'bookSourceUrl', 'bookSourceName', 'bookSourceType', 'bookSourceGroup', 'bookSourceComment',
      'loginUrl', 'loginHeader', 'loginInfo', 'searchUrl', 'jsLib', 'header', 'searchRule',
      'variable', 'lastUpdateTime', 'respondTime', 'customOrder', 'customButton', 'eventListener',
      'isPinned', 'enabled', 'isLocked', 'validationStatus', 'weight', 'concurrentRate', 'enabledCookieJar'
    ];
  }

  private exploreBookSourceColumns(): string[] {
    return [
      'bookSourceUrl', 'bookSourceName', 'bookSourceType', 'bookSourceGroup', 'bookSourceComment',
      'loginUrl', 'loginHeader', 'loginInfo', 'searchUrl', 'exploreUrl', 'jsLib', 'header',
      'searchRule', 'exploreRule', 'variable', 'lastUpdateTime', 'respondTime', 'customOrder',
      'customButton', 'eventListener', 'isPinned', 'enabled', 'isLocked', 'enabledExplore',
      'validationStatus', 'weight', 'concurrentRate', 'enabledCookieJar'
    ];
  }

  async insertBookChapter(chapter: BookChapter): Promise<void> {
    if (!this.store) return;
    const bucket: relationalStore.ValuesBucket = {
      url: chapter.url,
      title: chapter.title,
      bookUrl: chapter.bookUrl,
      chapterIndex: chapter.index,
      isVip: chapter.isVip ? 1 : 0,
      isPay: chapter.isPay ? 1 : 0,
      resourceUrl: chapter.resourceUrl,
      tag: chapter.tag,
      startOffset: chapter.start,
      endOffset: chapter.end,
      variable: chapter.variable
    };

    await this.store.insert('book_chapters', bucket);
  }

  async insertBookChapters(chapters: BookChapter[]): Promise<void> {
    if (!this.store || chapters.length === 0) return;
    const buckets: relationalStore.ValuesBucket[] = [];
    for (const chapter of chapters) {
      buckets.push({
        url: chapter.url,
        title: chapter.title,
        bookUrl: chapter.bookUrl,
        chapterIndex: chapter.index,
        isVip: chapter.isVip ? 1 : 0,
        isPay: chapter.isPay ? 1 : 0,
        resourceUrl: chapter.resourceUrl,
        tag: chapter.tag,
        startOffset: chapter.start,
        endOffset: chapter.end,
        variable: chapter.variable
      });
    }
    for (let offset = 0; offset < buckets.length; offset += AppDatabase.BATCH_INSERT_CHUNK_SIZE) {
      await this.store.batchInsert('book_chapters',
        buckets.slice(offset, offset + AppDatabase.BATCH_INSERT_CHUNK_SIZE));
    }
  }

  async insertBookChaptersWithContents(bookUrl: string, chapters: BookChapter[], contents: string[]): Promise<void> {
    if (!this.store || !bookUrl || chapters.length === 0 || chapters.length !== contents.length) return;
    const cacheDate = Date.now();
    const chapterBuckets: relationalStore.ValuesBucket[] = [];
    const contentBuckets: relationalStore.ValuesBucket[] = [];
    for (let i = 0; i < chapters.length; i++) {
      const chapter = chapters[i];
      chapterBuckets.push({
        url: chapter.url,
        title: chapter.title,
        bookUrl: chapter.bookUrl,
        chapterIndex: chapter.index,
        isVip: chapter.isVip ? 1 : 0,
        isPay: chapter.isPay ? 1 : 0,
        resourceUrl: chapter.resourceUrl,
        tag: chapter.tag,
        startOffset: chapter.start,
        endOffset: chapter.end,
        variable: chapter.variable
      });
      contentBuckets.push({
        bookUrl: bookUrl,
        chapterIndex: chapter.index,
        chapterUrl: chapter.url,
        chapterName: chapter.title,
        content: contents[i] || ' ',
        cacheDate: cacheDate
      });
      chapter.cacheDate = cacheDate;
    }
    const transaction = await this.store.createTransaction();
    try {
      for (let offset = 0; offset < chapterBuckets.length; offset += AppDatabase.BATCH_INSERT_CHUNK_SIZE) {
        await transaction.batchInsert('book_chapters',
          chapterBuckets.slice(offset, offset + AppDatabase.BATCH_INSERT_CHUNK_SIZE));
        await transaction.batchInsert('book_contents',
          contentBuckets.slice(offset, offset + AppDatabase.BATCH_INSERT_CHUNK_SIZE));
      }
      await transaction.commit();
    } catch (e) {
      await transaction.rollback();
      throw e;
    }
  }

  async deleteBookChapters(bookUrl: string): Promise<void> {
    if (!this.store) return;
    const predicates = new relationalStore.RdbPredicates('book_chapters');
    predicates.equalTo('bookUrl', bookUrl);
    await this.store.delete(predicates);
    await this.deleteReaderPaginationCache(bookUrl);
  }

  async getBookChapters(bookUrl: string): Promise<BookChapter[]> {
    if (!this.store) return [];
    const predicates = new relationalStore.RdbPredicates('book_chapters');
    predicates.equalTo('bookUrl', bookUrl);
    predicates.orderByAsc('chapterIndex');
    const resultSet = await this.store.query(predicates, []);
    const chapters: BookChapter[] = [];
    try {
      while (resultSet.goToNextRow()) {
        chapters.push(this.resultSetToBookChapter(resultSet));
      }
    } finally {
      resultSet.close();
    }
    const cacheDates = await this.getBookChapterCacheDateMap(bookUrl);
    for (const chapter of chapters) {
      chapter.cacheDate = cacheDates.get(chapter.index) || 0;
    }
    return chapters;
  }

  async searchBookChapters(bookUrl: string, keyword: string): Promise<BookChapter[]> {
    if (!this.store || !bookUrl || !keyword.trim()) return [];
    const predicates = new relationalStore.RdbPredicates('book_chapters');
    predicates.equalTo('bookUrl', bookUrl);
    predicates.like('title', `%${keyword.trim()}%`);
    predicates.orderByAsc('chapterIndex');
    const resultSet = await this.store.query(predicates, []);
    const chapters: BookChapter[] = [];
    try {
      while (resultSet.goToNextRow()) {
        chapters.push(this.resultSetToBookChapter(resultSet));
      }
    } finally {
      resultSet.close();
    }
    const cacheDates = await this.getBookChapterCacheDateMap(bookUrl);
    for (const chapter of chapters) {
      chapter.cacheDate = cacheDates.get(chapter.index) || 0;
    }
    return chapters;
  }

  async getBookChapterCount(bookUrl: string): Promise<number> {
    if (!this.store) return 0;
    const predicates = new relationalStore.RdbPredicates('book_chapters');
    predicates.equalTo('bookUrl', bookUrl);
    const resultSet = await this.store.query(predicates, []);
    try {
      return resultSet.rowCount;
    } finally {
      resultSet.close();
    }
  }

  async getCachedChapterContent(bookUrl: string, chapterIndex: number): Promise<string> {
    if (!this.store) return '';
    const predicates = new relationalStore.RdbPredicates('book_contents');
    predicates.equalTo('bookUrl', bookUrl);
    predicates.equalTo('chapterIndex', chapterIndex);
    const resultSet = await this.store.query(predicates, ['content']);
    try {
      if (!resultSet.goToFirstRow()) return '';
      return resultSet.getString(resultSet.getColumnIndex('content')) || '';
    } finally {
      resultSet.close();
    }
  }

  async saveCachedChapterContent(bookUrl: string, chapter: BookChapter, content: string): Promise<void> {
    if (!this.store || !bookUrl || !content) return;
    const cacheDate = Date.now();
    const bucket: relationalStore.ValuesBucket = {
      bookUrl: bookUrl,
      chapterIndex: chapter.index,
      chapterUrl: chapter.url,
      chapterName: chapter.title,
      content: content,
      cacheDate: cacheDate
    };
    const predicates = new relationalStore.RdbPredicates('book_contents');
    predicates.equalTo('bookUrl', bookUrl);
    predicates.equalTo('chapterIndex', chapter.index);
    const resultSet = await this.store.query(predicates, []);
    const exists = resultSet.rowCount > 0;
    resultSet.close();
    if (exists) {
      await this.store.update(bucket, predicates);
    } else {
      await this.store.insert('book_contents', bucket);
    }
    chapter.cacheDate = cacheDate;
  }

  async deleteBookCachedContent(bookUrl: string): Promise<void> {
    if (!this.store) return;
    const predicates = new relationalStore.RdbPredicates('book_contents');
    predicates.equalTo('bookUrl', bookUrl);
    await this.store.delete(predicates);
    await this.deleteReaderPaginationCache(bookUrl);
  }

  async deleteCachedChapterContent(bookUrl: string, chapterIndex: number): Promise<void> {
    if (!this.store) return;
    const predicates = new relationalStore.RdbPredicates('book_contents');
    predicates.equalTo('bookUrl', bookUrl);
    predicates.equalTo('chapterIndex', chapterIndex);
    await this.store.delete(predicates);
    await this.deleteReaderPaginationCache(bookUrl, chapterIndex);
  }

  async getReaderPaginationCache(bookUrl: string, chapterIndex: number,
    layoutKey: string): Promise<ReaderPaginationCacheRecord | null> {
    if (!this.store || !bookUrl || !layoutKey) return null;
    const predicates = new relationalStore.RdbPredicates('reader_pagination_cache');
    predicates.equalTo('bookUrl', bookUrl);
    predicates.equalTo('chapterIndex', chapterIndex);
    predicates.equalTo('layoutKey', layoutKey);
    const resultSet = await this.store.query(predicates, ['starts', 'ends']);
    try {
      if (!resultSet.goToFirstRow()) return null;
      const starts = JSON.parse(resultSet.getString(resultSet.getColumnIndex('starts'))) as number[];
      const ends = JSON.parse(resultSet.getString(resultSet.getColumnIndex('ends'))) as number[];
      if (!Array.isArray(starts) || !Array.isArray(ends) || starts.length === 0 || starts.length !== ends.length) {
        return null;
      }
      const record = new ReaderPaginationCacheRecord();
      record.starts = starts;
      record.ends = ends;
      return record;
    } catch (_) {
      return null;
    } finally {
      resultSet.close();
    }
  }

  async saveReaderPaginationCache(bookUrl: string, chapterIndex: number, layoutKey: string,
    starts: number[], ends: number[]): Promise<void> {
    if (!this.store || !bookUrl || !layoutKey || starts.length === 0 || starts.length !== ends.length) return;
    const queueKey = `${bookUrl}\n${chapterIndex}`;
    this.readerPaginationPendingWrites.set(queueKey,
      new ReaderPaginationCacheWrite(bookUrl, chapterIndex, layoutKey, starts, ends));
    let task = this.readerPaginationWriteTasks.get(queueKey);
    if (!task) {
      task = this.flushReaderPaginationCacheWrites(queueKey);
      this.readerPaginationWriteTasks.set(queueKey, task);
    }
    await task;
  }

  private async flushReaderPaginationCacheWrites(queueKey: string): Promise<void> {
    try {
      while (this.readerPaginationPendingWrites.has(queueKey)) {
        const write = this.readerPaginationPendingWrites.get(queueKey);
        this.readerPaginationPendingWrites.delete(queueKey);
        if (!write || !this.store) continue;
        await this.deleteReaderPaginationCache(write.bookUrl, write.chapterIndex);
        const bucket: relationalStore.ValuesBucket = {
          bookUrl: write.bookUrl,
          chapterIndex: write.chapterIndex,
          layoutKey: write.layoutKey,
          starts: JSON.stringify(write.starts),
          ends: JSON.stringify(write.ends),
          updateTime: Date.now()
        };
        await this.store.insert('reader_pagination_cache', bucket,
          relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);
      }
    } finally {
      this.readerPaginationWriteTasks.delete(queueKey);
    }
  }

  async deleteReaderPaginationCache(bookUrl: string, chapterIndex: number = -1): Promise<void> {
    if (!this.store || !bookUrl) return;
    const predicates = new relationalStore.RdbPredicates('reader_pagination_cache');
    predicates.equalTo('bookUrl', bookUrl);
    if (chapterIndex >= 0) predicates.equalTo('chapterIndex', chapterIndex);
    await this.store.delete(predicates);
  }

  async getBookChapterCacheDateMap(bookUrl: string): Promise<Map<number, number>> {
    const cacheDates: Map<number, number> = new Map();
    if (!this.store) return cacheDates;
    const predicates = new relationalStore.RdbPredicates('book_contents');
    predicates.equalTo('bookUrl', bookUrl);
    const resultSet = await this.store.query(predicates, ['chapterIndex', 'cacheDate']);
    try {
      while (resultSet.goToNextRow()) {
        cacheDates.set(
          resultSet.getLong(resultSet.getColumnIndex('chapterIndex')),
          resultSet.getLong(resultSet.getColumnIndex('cacheDate'))
        );
      }
    } finally {
      resultSet.close();
    }
    return cacheDates;
  }

  async getBookCachedChapterIndices(bookUrl: string): Promise<number[]> {
    const indices: number[] = [];
    const cacheDates = await this.getBookChapterCacheDateMap(bookUrl);
    cacheDates.forEach((_cacheDate: number, index: number) => {
      indices.push(index);
    });
    return indices;
  }

  private resultSetToBookChapter(resultSet: relationalStore.ResultSet): BookChapter {
    const chapter = new BookChapter();
    chapter.url = resultSet.getString(resultSet.getColumnIndex('url'));
    chapter.title = resultSet.getString(resultSet.getColumnIndex('title'));
    chapter.bookUrl = resultSet.getString(resultSet.getColumnIndex('bookUrl'));
    chapter.index = resultSet.getLong(resultSet.getColumnIndex('chapterIndex'));
    chapter.isVip = resultSet.getLong(resultSet.getColumnIndex('isVip')) === 1;
    chapter.isPay = resultSet.getLong(resultSet.getColumnIndex('isPay')) === 1;
    chapter.resourceUrl = resultSet.getString(resultSet.getColumnIndex('resourceUrl'));
    chapter.tag = resultSet.getString(resultSet.getColumnIndex('tag'));
    chapter.start = resultSet.getLong(resultSet.getColumnIndex('startOffset'));
    chapter.end = resultSet.getLong(resultSet.getColumnIndex('endOffset'));
    chapter.variable = resultSet.getString(resultSet.getColumnIndex('variable'));
    return chapter;
  }

  async getSearchKeywords(): Promise<SearchKeyword[]> {
    if (!this.store) return [];
    const predicates = new relationalStore.RdbPredicates('search_keywords');
    predicates.orderByDesc('lastUseTime');
    const resultSet = await this.store.query(predicates, []);
    const keywords: SearchKeyword[] = [];
    try {
      while (resultSet.goToNextRow()) {
        const keyword = new SearchKeyword();
        keyword.keyword = resultSet.getString(resultSet.getColumnIndex('keyword'));
        keyword.usage = resultSet.getLong(resultSet.getColumnIndex('usage'));
        keyword.lastUseTime = resultSet.getLong(resultSet.getColumnIndex('lastUseTime'));
        keywords.push(keyword);
      }
    } finally {
      resultSet.close();
    }
    return keywords;
  }

  async saveSearchKeyword(keyword: string): Promise<void> {
    if (!this.store) return;

    const predicates = new relationalStore.RdbPredicates('search_keywords');
    predicates.equalTo('keyword', keyword);
    const resultSet = await this.store.query(predicates, []);
    let usage = 0;
    try {
      if (resultSet.goToFirstRow()) {
        usage = resultSet.getLong(resultSet.getColumnIndex('usage')) + 1;
      }
    } finally {
      resultSet.close();
    }
    if (usage > 0) {
      const bucket: relationalStore.ValuesBucket = {
        usage: usage,
        lastUseTime: Date.now()
      };
      await this.store.update(bucket, predicates);
    } else {
      const bucket: relationalStore.ValuesBucket = {
        keyword: keyword,
        usage: 1,
        lastUseTime: Date.now()
      };
      await this.store.insert('search_keywords', bucket);
    }
  }

  async clearSearchKeywords(): Promise<void> {
    if (!this.store) return;
    await this.store.executeSql('DELETE FROM search_keywords');
  }

  async restoreSearchKeyword(keyword: SearchKeyword): Promise<void> {
    if (!this.store || !keyword.keyword) return;
    const predicates = new relationalStore.RdbPredicates('search_keywords');
    predicates.equalTo('keyword', keyword.keyword);
    const resultSet = await this.store.query(predicates, []);
    const bucket: relationalStore.ValuesBucket = {
      keyword: keyword.keyword,
      usage: keyword.usage,
      lastUseTime: keyword.lastUseTime
    };
    const exists = resultSet.rowCount > 0;
    resultSet.close();
    if (exists) {
      await this.store.update(bucket, predicates);
    } else {
      await this.store.insert('search_keywords', bucket);
    }
  }

  async deleteSearchKeyword(keyword: string): Promise<void> {
    if (!this.store) return;
    const predicates = new relationalStore.RdbPredicates('search_keywords');
    predicates.equalTo('keyword', keyword);
    await this.store.delete(predicates);
  }

  // ==================== 订阅源(RSS) DAO：从 legado-Harmony 移植 ====================

  private toRssSourcesBucket(dbRow: rssSourceDb): relationalStore.ValuesBucket {
    const bucket: relationalStore.ValuesBucket = {
      sourceType: dbRow.sourceType,
      sourceName: dbRow.sourceName || '',
      sourceUrl: dbRow.sourceUrl,
      sourceIcon: dbRow.sourceIcon || '',
      sourceIconIsUrl: dbRow.sourceIconIsUrl ? 1 : 0,
      sourceGroup: dbRow.sourceGroup || '',
      sourceComment: dbRow.sourceComment || '',
      enabled: dbRow.enabled ? 1 : 0,
      variableComment: dbRow.variableComment || '',
      jsLib: dbRow.jsLib || '',
      enabledCookieJar: dbRow.enabledCookieJar ? 1 : 0,
      concurrentRate: dbRow.concurrentRate || '',
      header: dbRow.header || '',
      loginUrl: dbRow.loginUrl || '',
      loginUi: dbRow.loginUi || '',
      loginCheckJs: dbRow.loginCheckJs || '',
      coverDecodeJs: dbRow.coverDecodeJs || '',
      sortUrl: dbRow.sortUrl || '',
      singleUrl: dbRow.singleUrl ? 1 : 0,
      articleStyle: dbRow.articleStyle || '',
      lastUpdateTime: dbRow.lastUpdateTime,
      customOrder: dbRow.customOrder,
      variable: dbRow.variable || '',
      showRecentIcon: dbRow.showRecentIcon ? 1 : 0,
      autoComplete: dbRow.autoComplete ? 1 : 0,
      customizeTitle: dbRow.customizeTitle || '',
      rssListRule: dbRow.rssListRule || '',
      rssWebViewRule: dbRow.rssWebViewRule || ''
    };
    if (dbRow.id !== undefined && dbRow.id !== 0) {
      bucket['id'] = dbRow.id;
    }
    return bucket;
  }

  private toRssSourcesHistoryBucket(history: rssSourcesHistory): relationalStore.ValuesBucket {
    const bucket: relationalStore.ValuesBucket = {
      sourceType: history.sourceType,
      sourceName: history.sourceName || '',
      sourceUrl: history.sourceUrl,
      sourceIcon: history.sourceIcon || '',
      sourceIconIsUrl: history.sourceIconIsUrl ? 1 : 0,
      sourceGroup: history.sourceGroup || '',
      lastUpdateTime: history.lastUpdateTime,
      showRecentIcon: history.showRecentIcon ? 1 : 0,
      customizeTitle: history.customizeTitle || ''
    };
    return bucket;
  }

  private resultSetToRssSources(resultSet: relationalStore.ResultSet): rssSources {
    const dbRow: rssSourceDb = {
      id: this.getLongColumn(resultSet, 'id'),
      sourceType: this.getLongColumn(resultSet, 'sourceType'),
      sourceName: this.getStringColumn(resultSet, 'sourceName'),
      sourceUrl: this.getStringColumn(resultSet, 'sourceUrl'),
      sourceIcon: this.getStringColumn(resultSet, 'sourceIcon'),
      sourceIconIsUrl: this.getLongColumn(resultSet, 'sourceIconIsUrl') === 1,
      sourceGroup: this.getStringColumn(resultSet, 'sourceGroup'),
      sourceComment: this.getStringColumn(resultSet, 'sourceComment'),
      enabled: this.getLongColumn(resultSet, 'enabled', 1) === 1,
      variableComment: this.getStringColumn(resultSet, 'variableComment'),
      jsLib: this.getStringColumn(resultSet, 'jsLib'),
      enabledCookieJar: this.getLongColumn(resultSet, 'enabledCookieJar') === 1,
      concurrentRate: this.getStringColumn(resultSet, 'concurrentRate'),
      header: this.getStringColumn(resultSet, 'header'),
      loginUrl: this.getStringColumn(resultSet, 'loginUrl'),
      loginUi: this.getStringColumn(resultSet, 'loginUi'),
      loginCheckJs: this.getStringColumn(resultSet, 'loginCheckJs'),
      coverDecodeJs: this.getStringColumn(resultSet, 'coverDecodeJs'),
      sortUrl: this.getStringColumn(resultSet, 'sortUrl'),
      singleUrl: this.getLongColumn(resultSet, 'singleUrl', 1) === 1,
      articleStyle: this.getStringColumn(resultSet, 'articleStyle'),
      lastUpdateTime: this.getLongColumn(resultSet, 'lastUpdateTime'),
      customOrder: this.getLongColumn(resultSet, 'customOrder'),
      variable: this.getStringColumn(resultSet, 'variable'),
      showRecentIcon: this.getLongColumn(resultSet, 'showRecentIcon', 1) === 1,
      autoComplete: this.getLongColumn(resultSet, 'autoComplete', 1) === 1,
      customizeTitle: this.getStringColumn(resultSet, 'customizeTitle'),
      rssListRule: this.getStringColumn(resultSet, 'rssListRule'),
      rssWebViewRule: this.getStringColumn(resultSet, 'rssWebViewRule')
    };
    return ToRssSources(dbRow);
  }

  private resultSetToRssSourceGroup(resultSet: relationalStore.ResultSet): RssSourceGroup {
    const group = new RssSourceGroup();
    group.rssGroupId = this.getLongColumn(resultSet, 'rssGroupId');
    group.rssGroupName = this.getStringColumn(resultSet, 'rssGroupName');
    group.groupSort = this.getLongColumn(resultSet, 'groupSort');
    group.isTop = this.getLongColumn(resultSet, 'isTop') === 1;
    group.isDelete = this.getLongColumn(resultSet, 'isDelete', 1) === 1;
    return group;
  }

  private resultSetToRssSourcesHistory(resultSet: relationalStore.ResultSet): rssSourcesHistory {
    const history = new rssSourcesHistory();
    history.sourceType = this.getLongColumn(resultSet, 'sourceType');
    history.sourceName = this.getStringColumn(resultSet, 'sourceName');
    history.sourceUrl = this.getStringColumn(resultSet, 'sourceUrl');
    history.sourceIcon = this.getStringColumn(resultSet, 'sourceIcon');
    history.sourceIconIsUrl = this.getLongColumn(resultSet, 'sourceIconIsUrl') === 1;
    history.sourceGroup = this.getStringColumn(resultSet, 'sourceGroup');
    history.lastUpdateTime = this.getLongColumn(resultSet, 'lastUpdateTime');
    history.showRecentIcon = this.getLongColumn(resultSet, 'showRecentIcon', 1) === 1;
    history.customizeTitle = this.getStringColumn(resultSet, 'customizeTitle');
    return history;
  }

  // 系统初始订阅源分组数据（对应源 rssSourceGroupDao.initGroupData）
  async initDefaultRssSourceGroups(): Promise<void> {
    if (!this.store) return;
    try {
      const groupList = await this.getRssSourceGroups();
      if (groupList.length > 0) {
        return;
      }
      const initGroup = ['小说', '漫画', '影视', '资讯', '收藏夹'];
      for (let index = 0; index < initGroup.length; index++) {
        const group = new RssSourceGroup();
        group.rssGroupName = initGroup[index];
        group.groupSort = index;
        group.isTop = false;
        group.isDelete = false;
        const bucket: relationalStore.ValuesBucket = {
          rssGroupName: group.rssGroupName,
          groupSort: group.groupSort || 0,
          isTop: group.isTop ? 1 : 0,
          isDelete: group.isDelete ? 1 : 0
        };
        await this.store.insert('rss_source_group', bucket);
      }
    } catch (e) {
      console.error('初始化订阅源分组失败', e);
    }
  }

  // 查询订阅源分组（对应源 rssSourceGroupDao.search）
  async getRssSourceGroups(): Promise<RssSourceGroup[]> {
    if (!this.store) return [];
    const groups: RssSourceGroup[] = [];
    try {
      const resultSet = await this.store.querySql('SELECT * FROM rss_source_group ORDER BY isTop DESC, groupSort ASC');
      try {
        while (resultSet.goToNextRow()) {
          groups.push(this.resultSetToRssSourceGroup(resultSet));
        }
      } finally {
        resultSet.close();
      }
    } catch (e) {
      console.error('查询订阅源分组失败', e);
    }
    return groups;
  }

  // 新增订阅源分组（供 rssSourcesUtil.insertRssSourceGroup 使用）
  async insertRssSourceGroup(rssGroupName: string): Promise<boolean> {
    if (!this.store || !rssGroupName) return false;
    const group = new RssSourceGroup();
    group.rssGroupName = rssGroupName;
    group.groupSort = 0;
    group.isTop = false;
    group.isDelete = true;
    const bucket: relationalStore.ValuesBucket = {
      rssGroupName: group.rssGroupName,
      groupSort: group.groupSort,
      isTop: group.isTop ? 1 : 0,
      isDelete: group.isDelete ? 1 : 0
    };
    await this.store.insert('rss_source_group', bucket);
    return true;
  }

  // 搜索订阅源（对应源 subscriptionDao.search）
  async getRssSources(searchParams?: rssSourcesTypeParams): Promise<rssSources[]> {
    if (!this.store) return [];
    const searchKey = searchParams?.searchKey ?? '';
    const enabled = searchParams?.enabled;
    const whereClause: string[] = [];
    if (enabled !== undefined) {
      whereClause.push(`enabled = ${enabled ? 1 : 0}`);
    }
    if (searchKey && searchKey.length > 0) {
      whereClause.push(`(sourceName LIKE '%${searchKey}%' OR sourceGroup LIKE '%${searchKey}%')`);
    }
    let sql = 'SELECT * FROM rssSources';
    if (whereClause.length > 0) {
      sql += ` WHERE ${whereClause.join(' AND ')}`;
    }
    sql += ' ORDER BY lastUpdateTime DESC, customOrder ASC';
    const rssList: rssSources[] = [];
    try {
      const resultSet = await this.store.querySql(sql);
      try {
        while (resultSet.goToNextRow()) {
          rssList.push(this.resultSetToRssSources(resultSet));
        }
      } finally {
        resultSet.close();
      }
    } catch (e) {
      console.error('查询订阅源失败', e);
    }
    return rssList;
  }

  // 按 sourceUrl 精确查询单个订阅源（对应源 subscriptionDao.getRssSources）
  async getRssSourcesByUrl(key: string): Promise<rssSources | null> {
    if (!this.store) return null;
    try {
      const predicates = new relationalStore.RdbPredicates('rssSources');
      predicates.equalTo('sourceUrl', key);
      const resultSet = await this.store.query(predicates, []);
      try {
        if (resultSet.goToFirstRow()) {
          return this.resultSetToRssSources(resultSet);
        }
      } finally {
        resultSet.close();
      }
    } catch (e) {
      console.error('查询订阅源失败', e);
    }
    return null;
  }

  // 校验 sourceUrl 是否已收藏（对应源 subscriptionDao.queryByUrl，LIKE 匹配）
  async queryRssSourcesByUrl(url: string): Promise<boolean> {
    if (!this.store) return false;
    try {
      const predicates = new relationalStore.RdbPredicates('rssSources');
      predicates.like('sourceUrl', url);
      const resultSet = await this.store.query(predicates, []);
      try {
        return resultSet.rowCount > 0;
      } finally {
        resultSet.close();
      }
    } catch (e) {
      console.error('校验订阅源收藏失败', e);
      return false;
    }
  }

  // 新增或更新订阅源（对应源 subscriptionDao.insert，upsert 语义）
  async insertRssSource(rssSource: rssSources): Promise<boolean> {
    if (!this.store) return false;
    try {
      const predicates = new relationalStore.RdbPredicates('rssSources');
      if (rssSource.id !== undefined && rssSource.id !== 0) {
        predicates.equalTo('id', rssSource.id);
      } else {
        predicates.equalTo('sourceUrl', rssSource.sourceUrl);
      }
      const resultSet = await this.store.query(predicates, []);
      let exists = false;
      try {
        exists = resultSet.goToFirstRow();
      } finally {
        resultSet.close();
      }
      if (exists) {
        return await this.updateRssSource(rssSource);
      }
      const dbRow = ToRssSourcesDb(rssSource);
      dbRow.lastUpdateTime = Date.now();
      const bucket = this.toRssSourcesBucket(dbRow);
      delete bucket['id'];
      await this.store.insert('rssSources', bucket);
      return true;
    } catch (e) {
      console.error('新增订阅源失败', e);
      return false;
    }
  }

  // 更新订阅源（对应源 subscriptionDao.update，含历史联动）
  async updateRssSource(rssSource: rssSources): Promise<boolean> {
    if (!this.store) return false;
    try {
      const predicates = new relationalStore.RdbPredicates('rssSources');
      if (rssSource.id !== undefined && rssSource.id !== 0) {
        predicates.equalTo('id', rssSource.id);
      } else {
        predicates.equalTo('sourceUrl', rssSource.sourceUrl);
      }
      const resultSet = await this.store.query(predicates, []);
      let exists = false;
      try {
        exists = resultSet.goToFirstRow();
      } finally {
        resultSet.close();
      }
      if (!exists) {
        return await this.insertRssSource(rssSource);
      }
      const dbRow = ToRssSourcesDb(rssSource);
      dbRow.lastUpdateTime = Date.now();
      dbRow.showRecentIcon = true;
      const bucket = this.toRssSourcesBucket(dbRow);
      await this.store.update(bucket, predicates);
      // 存在历史记录时联动刷新（对应源 update 中的 rssSourcesHistoryDao 联动）
      const historyList = await this.getRssSourcesHistory(rssSource.sourceUrl);
      if (historyList.length > 0) {
        const history: rssSourcesHistory = new rssSourcesHistory();
        history.sourceType = rssSource.sourceType;
        history.sourceName = rssSource.sourceName;
        history.sourceUrl = rssSource.sourceUrl;
        history.sourceIcon = rssSource.sourceIcon;
        history.sourceIconIsUrl = rssSource.sourceIconIsUrl;
        history.sourceGroup = rssSource.sourceGroup;
        history.lastUpdateTime = Date.now();
        history.showRecentIcon = true;
        history.customizeTitle = rssSource.customizeTitle;
        await this.insertRssSourcesHistory(history);
      }
      return true;
    } catch (e) {
      console.error('更新订阅源失败', e);
      return false;
    }
  }

  // 更新订阅源最近图标标记（对应源 subscriptionDao.updateRecentIcon）
  async updateRssSourceRecentIcon(rssSource: rssSources): Promise<boolean> {
    if (!this.store) return false;
    try {
      const predicates = new relationalStore.RdbPredicates('rssSources');
      if (rssSource.id !== undefined && rssSource.id !== 0) {
        predicates.equalTo('id', rssSource.id);
      } else {
        predicates.equalTo('sourceUrl', rssSource.sourceUrl);
      }
      const dbRow = ToRssSourcesDb(rssSource);
      dbRow.showRecentIcon = false;
      const bucket = this.toRssSourcesBucket(dbRow);
      await this.store.update(bucket, predicates);
      return true;
    } catch (e) {
      console.error('更新订阅源最近图标失败', e);
      return false;
    }
  }

  // 置顶订阅源（对应源 subscriptionDao.isTopRssSources）
  async isTopRssSources(rssSource: rssSources): Promise<boolean> {
    if (!this.store) return false;
    try {
      const predicates = new relationalStore.RdbPredicates('rssSources');
      if (rssSource.id !== undefined && rssSource.id !== 0) {
        predicates.equalTo('id', rssSource.id);
      } else {
        predicates.equalTo('sourceUrl', rssSource.sourceUrl);
      }
      const dbRow = ToRssSourcesDb(rssSource);
      dbRow.lastUpdateTime = Date.now();
      dbRow.customOrder = 0;
      const bucket = this.toRssSourcesBucket(dbRow);
      await this.store.update(bucket, predicates);
      return true;
    } catch (e) {
      console.error('置顶订阅源失败', e);
      return false;
    }
  }

  // 批量新增订阅源（对应源 subscriptionDao.batchInsert）
  async batchInsertRssSources(list: rssSources[]): Promise<boolean> {
    if (!this.store) return false;
    try {
      for (let index = 0; index < list.length; index++) {
        await this.insertRssSource(list[index]);
      }
      return true;
    } catch (e) {
      console.error('批量导入订阅源失败', e);
      return false;
    }
  }

  // 删除订阅源（对应源 subscriptionDao.deleteRssSources）
  async deleteRssSources(rssSource: rssSources): Promise<boolean> {
    if (!this.store) return false;
    try {
      const predicates = new relationalStore.RdbPredicates('rssSources');
      if (rssSource.id !== undefined && rssSource.id !== 0) {
        predicates.equalTo('id', rssSource.id);
      } else {
        predicates.equalTo('sourceUrl', rssSource.sourceUrl);
      }
      await this.store.delete(predicates);
      await this.deleteRssSourcesHistory(rssSource.sourceUrl);
      return true;
    } catch (e) {
      console.error('删除订阅源失败', e);
      return false;
    }
  }

  // 批量删除订阅源（对应源 subscriptionDao.deleteRssSourcesList）
  async deleteRssSourcesList(list: rssSources[]): Promise<boolean> {
    if (!this.store) return false;
    try {
      for (let index = 0; index < list.length; index++) {
        await this.deleteRssSources(list[index]);
      }
      return true;
    } catch (e) {
      console.error('批量删除订阅源失败', e);
      return false;
    }
  }

  // 查询订阅源历史记录（对应源 rssSourcesHistoryDao.search）
  async getRssSourcesHistory(sourceUrl?: string): Promise<rssSourcesHistory[]> {
    if (!this.store) return [];
    let sql = 'SELECT * FROM rss_sources_history';
    if (sourceUrl && sourceUrl.length > 0) {
      sql += ` WHERE sourceUrl LIKE '%${sourceUrl}%'`;
    }
    sql += ' ORDER BY lastUpdateTime DESC';
    const historyList: rssSourcesHistory[] = [];
    try {
      const resultSet = await this.store.querySql(sql);
      try {
        while (resultSet.goToNextRow()) {
          historyList.push(this.resultSetToRssSourcesHistory(resultSet));
        }
      } finally {
        resultSet.close();
      }
    } catch (e) {
      console.error('查询订阅源历史失败', e);
    }
    return historyList;
  }

  // 新增或更新订阅源历史（对应源 rssSourcesHistoryDao.insert/update，upsert 语义）
  async insertRssSourcesHistory(history: rssSourcesHistory): Promise<boolean> {
    if (!this.store) return false;
    try {
      const predicates = new relationalStore.RdbPredicates('rss_sources_history');
      predicates.equalTo('sourceUrl', history.sourceUrl);
      const resultSet = await this.store.query(predicates, []);
      let exists = false;
      try {
        exists = resultSet.goToFirstRow();
      } finally {
        resultSet.close();
      }
      if (exists) {
        history.lastUpdateTime = Date.now();
        history.showRecentIcon = true;
        const bucket = this.toRssSourcesHistoryBucket(history);
        await this.store.update(bucket, predicates);
        return true;
      }
      history.lastUpdateTime = Date.now();
      const insertBucket = this.toRssSourcesHistoryBucket(history);
      await this.store.insert('rss_sources_history', insertBucket);
      return true;
    } catch (e) {
      console.error('新增订阅源历史失败', e);
      return false;
    }
  }

  // 删除订阅源历史（对应源 rssSourcesHistoryDao.deleteRssSourcesHistory）
  async deleteRssSourcesHistory(rssHistoryUrl: string): Promise<boolean> {
    if (!this.store) return false;
    try {
      const predicates = new relationalStore.RdbPredicates('rss_sources_history');
      predicates.equalTo('sourceUrl', rssHistoryUrl);
      await this.store.delete(predicates);
      return true;
    } catch (e) {
      console.error('删除订阅源历史失败', e);
      return false;
    }
  }

  // 清空全部订阅源访问记录
  async clearRssSourcesHistory(): Promise<boolean> {
    if (!this.store) return false;
    try {
      const predicates = new relationalStore.RdbPredicates('rss_sources_history');
      await this.store.delete(predicates);
      return true;
    } catch (e) {
      console.error('清空订阅源访问记录失败', e);
      return false;
    }
  }
}

export const appDb = AppDatabase.getInstance();
