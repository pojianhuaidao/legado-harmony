import { common } from '@kit.AbilityKit';
import { abilityAccessCtrl, Permissions, PermissionRequestResult } from '@kit.AbilityKit';
import { Environment } from '@kit.CoreFileKit';
import { preferences } from '@kit.ArkData';
import fs from '@ohos.file.fs';

/**
 * 应用数据根目录统一管理。
 *
 * 沙箱迁移目标（用户选定方案）：
 *   手机端将用户内容数据（本地图书/字体/封面/启动图/背景图/相册）从
 *   filesDir 迁移到公共 Download 目录下的 reading.hm.o 子目录
 *   （Download/reading.hm.o/{local_books,reader_fonts,reader_backgrounds,
 *   theme_startups,cover_albums,covers}）。
 *
 * 说明：
 *   - 数据库（relationalStore）与 Preferences 仍在应用沙箱内，系统不允许迁出。
 *   - 自动迁移仅在系统支持直接读写 Download 时执行；不支持时由
 *     「备份选项」页提供手动迁移入口（通过 Download 能力建立授权后再迁移）。
 *   - 所有模块通过 AppDataPaths.dir(name) 读取目录，避免硬编码 filesDir。
 */
export class AppDataPaths {
  static readonly DOWNLOAD_SUB_DIR: string = 'reading.hm.o';
  static readonly MIGRATED_KEY: string = 'appDataRootMigratedV1';
  static readonly MIGRATED_ROOT_KEY: string = 'appDataRootPathV1';
  static readonly MIGRATE_FAILED_KEY: string = 'appDataDownloadMigrateFailed';
  static readonly MIGRATE_FAILED_REASON_KEY: string = 'appDataDownloadMigrateFailedReason';
  /** 公共 Download 目录读写权限：user_grant + restricted（需 AGC 控制台 ACL 申请后才能在设置中授权）。 */
  static readonly DOWNLOAD_PERMISSION: Permissions = 'ohos.permission.READ_WRITE_DOWNLOAD_DIRECTORY' as Permissions;
  static readonly USER_CONTENT_DIRS: string[] = [
    'local_books',
    'reader_fonts',
    'reader_backgrounds',
    'theme_startups',
    'cover_albums',
    'covers'
  ];

  static initStorage(filesDir: string): void {
    const existing = AppStorage.get<string>('appContentRoot');
    if (existing === undefined || existing === null || existing === '') {
      AppStorage.setOrCreate('appContentRoot', filesDir);
    }
  }

  static contentRoot(): string {
    const root = AppStorage.get<string>('appContentRoot');
    return root && root.length > 0 ? root : '';
  }

  static dir(name: string): string {
    const root = AppDataPaths.contentRoot();
    return root ? `${root}/${name}` : name;
  }

  static async downloadBaseDir(): Promise<string> {
    try {
      if (canIUse('SystemCapability.FileManagement.File.Environment.FolderObtain')) {
        return Environment.getUserDownloadDir();
      }
    } catch (e) {
      console.warn('[AppDataPaths] getUserDownloadDir unavailable', JSON.stringify(e));
    }
    return '';
  }

  /**
   * 尝试将用户内容目录从 filesDir 迁移到 Download/reading.hm.o。
   * 成功返回 true 并写入 AppStorage 根目录；失败返回 false（回退沙箱）。
   */
  static async migrateToDownload(context: common.UIAbilityContext): Promise<boolean> {
    const filesDir = AppStorage.get<string>('appFilesDir') || '';
    if (!filesDir) {
      return false;
    }
    if (AppStorage.get<boolean>(AppDataPaths.MIGRATED_KEY) === true) {
      return true;
    }
    const downloadDir = await AppDataPaths.downloadBaseDir();
    if (!downloadDir) {
      AppStorage.setOrCreate(AppDataPaths.MIGRATE_FAILED_KEY, true);
      AppStorage.setOrCreate(AppDataPaths.MIGRATE_FAILED_REASON_KEY, '系统不支持获取公共下载目录');
      return false;
    }
    // 二开改造：迁移前必须先申请公共 Download 目录读写权限（user_grant）。
    // 该权限同时为 restricted 权限，若 AGC 控制台未加入 ACL 白名单，
    // 系统会在授权时直接拒绝（返回错误而非弹授权框），此时必须提示用户去 AGC 侧申请。
    if (!await AppDataPaths.ensureDownloadPermission(context)) {
      AppStorage.setOrCreate(AppDataPaths.MIGRATE_FAILED_KEY, true);
      AppStorage.setOrCreate(AppDataPaths.MIGRATE_FAILED_REASON_KEY,
        '未获得公共下载目录读写权限（ohos.permission.READ_WRITE_DOWNLOAD_DIRECTORY）。' +
        '该权限为受限权限，需要开发者在 AGC 控制台完成 ACL 申请并发布新版本后，系统设置中才会出现授权项');
      return false;
    }
    const targetRoot = `${downloadDir}/${AppDataPaths.DOWNLOAD_SUB_DIR}`;
    try {
      if (!AppDataPaths.exists(targetRoot)) {
        fs.mkdirSync(targetRoot);
      }
      let movedAny: boolean = false;
      for (const name of AppDataPaths.USER_CONTENT_DIRS) {
        const src = `${filesDir}/${name}`;
        if (!AppDataPaths.exists(src)) {
          continue;
        }
        const dst = `${targetRoot}/${name}`;
        if (AppDataPaths.exists(dst)) {
          // 目标已存在同名目录，先移除旧占位，保留最新数据。
          try {
            fs.rmdirSync(dst);
          } catch (e) {
            console.warn(`[AppDataPaths] clear existing dst failed ${name}`, JSON.stringify(e));
          }
        }
        try {
          fs.moveDirSync(src, dst, 1);
          movedAny = true;
        } catch (e) {
          console.warn(`[AppDataPaths] move ${name} failed`, JSON.stringify(e));
        }
      }
      if (movedAny || AppDataPaths.exists(targetRoot)) {
        AppStorage.setOrCreate('appContentRoot', targetRoot);
        AppStorage.setOrCreate(AppDataPaths.MIGRATED_KEY, true);
        await AppDataPaths.markMigrated(context, targetRoot);
        return true;
      }
      return false;
    } catch (e) {
      console.warn('[AppDataPaths] migrateToDownload failed', JSON.stringify(e));
      AppStorage.setOrCreate(AppDataPaths.MIGRATE_FAILED_KEY, true);
      return false;
    }
  }

  /** 由备份选项页调用：先建立 Download 目录访问能力后执行迁移。 */
  static async manualMigrate(context: common.UIAbilityContext): Promise<boolean> {
    return AppDataPaths.migrateToDownload(context);
  }

  /**
   * 申请公共 Download 目录读写权限。
   * 返回 true 表示已授权；false 表示用户拒绝或 restricted 权限未过 ACL 白名单。
   * 失败原因写入 AppStorage（MIGRATE_FAILED_REASON_KEY），供页面展示。
   */
  static async ensureDownloadPermission(context: common.UIAbilityContext): Promise<boolean> {
    try {
      const manager = abilityAccessCtrl.createAtManager();
      const result: PermissionRequestResult = await manager.requestPermissionsFromUser(
        context, [AppDataPaths.DOWNLOAD_PERMISSION]);
      const granted = result.authResults.length > 0 && result.authResults[0] === 0;
      if (!granted) {
        console.warn(`[AppDataPaths] download permission denied code=${result.authResults.length > 0 ? result.authResults[0] : -1}`);
      }
      return granted;
    } catch (e) {
      // restricted 权限未过 ACL 白名单时系统会直接抛错（如 12100001 权限未在ACL白名单内）
      console.warn('[AppDataPaths] request download permission failed', JSON.stringify(e));
      return false;
    }
  }

  /** 应用启动时恢复持久化的迁移状态（重启后 AppStorage 会丢失）。 */
  static async loadPersistedRoot(context: common.UIAbilityContext): Promise<string> {
    if (AppStorage.get<boolean>(AppDataPaths.MIGRATED_KEY) === true) {
      return AppStorage.get<string>('appContentRoot') || '';
    }
    try {
      const pref = await preferences.getPreferences(context, 'app_data_paths');
      const migrated = pref.getSync(AppDataPaths.MIGRATED_KEY, false);
      const root = pref.getSync(AppDataPaths.MIGRATED_ROOT_KEY, '') as string;
      if (migrated === true && root && root.length > 0) {
        AppStorage.setOrCreate(AppDataPaths.MIGRATED_KEY, true);
        AppStorage.setOrCreate('appContentRoot', root);
        return root;
      }
    } catch (e) {
      console.warn('[AppDataPaths] load persisted root failed', JSON.stringify(e));
    }
    return '';
  }

  static async wasMigrated(context: common.UIAbilityContext): Promise<boolean> {
    if (AppStorage.get<boolean>(AppDataPaths.MIGRATED_KEY) === true) {
      return true;
    }
    try {
      const pref = await preferences.getPreferences(context, 'app_data_paths');
      const value = pref.getSync(AppDataPaths.MIGRATED_KEY, false);
      return value === true;
    } catch (e) {
      return false;
    }
  }

  private static async markMigrated(context: common.UIAbilityContext, root: string): Promise<void> {
    try {
      const pref = await preferences.getPreferences(context, 'app_data_paths');
      await pref.put(AppDataPaths.MIGRATED_KEY, true);
      await pref.put(AppDataPaths.MIGRATED_ROOT_KEY, root);
      await pref.flush();
    } catch (e) {
      console.warn('[AppDataPaths] persist migrated flag failed', JSON.stringify(e));
    }
  }

  private static exists(path: string): boolean {
    try {
      return fs.accessSync(path);
    } catch (e) {
      return false;
    }
  }
}
