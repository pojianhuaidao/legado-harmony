import { common } from '@kit.AbilityKit';
import { BusinessError, request } from '@kit.BasicServicesKit';
import { fileUri } from '@kit.CoreFileKit';
import { cloudCommon, cloudStorage } from '@kit.CloudFoundationKit';
import util from '@ohos.util';
import auth, { AuthUser } from '@hw-agconnect/auth';
import {
  AppDataBackupImportResult,
  AppDataBackupImportSession,
  AppDataBackupSelection,
  AppDataBackupService
} from './AppDataBackupService';

/**
 * 华为账号登录（AGC Auth Service，hwid）+ 远端备份/恢复（AGC Cloud Storage）。
 *
 * 依赖用户到 AGC 控制台开通的项目（见交付清单）：
 *   1. Auth Service（认证服务）—— 启用华为账号登录；
 *   2. Cloud Storage（云存储）—— 创建 Bucket 并开通配额；
 *   3. 下载 agconnect-services.json 放入 resources/rawfile/ 替换占位文件。
 *
 * 云上目录结构：legado_backups/backup_<时间戳>_<uid前8位>.qingyebak
 * 备份文件使用现有 AppDataBackupService 的 AES-256-GCM 加密与清单格式。
 */
export class CloudBackupItem {
  cloudPath: string = '';
  name: string = '';
  size: number = 0;
  updatedTime: number = 0;
}

export class HuaweiCloudService {
  static readonly CLOUD_DIR: string = 'legado_backups';
  static readonly BACKUP_PREFIX: string = 'backup_';
  private static cloudReady: boolean = false;

  static isConfigured(): boolean {
    return AppStorage.get<boolean>('huaweiCloudConfigured') === true;
  }

  static loginUid(): string {
    return AppStorage.get<string>('huaweiCloudUid') || '';
  }

  static loginDisplayName(): string {
    return AppStorage.get<string>('huaweiCloudName') || '';
  }

  static isLoggedIn(): boolean {
    const uid = AppStorage.get<string>('huaweiCloudUid');
    return uid !== undefined && uid !== null && uid.length > 0;
  }

  /**
   * 应用启动时调用：读取 agconnect-services.json，若存在则初始化 AGC Auth
   * 并恢复登录态。文件缺失仅标记未配置，不影响应用其余功能。
   */
  static async bootstrap(context: common.UIAbilityContext): Promise<void> {
    AppStorage.setOrCreate('huaweiCloudConfigured', false);
    AppStorage.setOrCreate('huaweiCloudUid', '');
    AppStorage.setOrCreate('huaweiCloudName', '');
    const json = await HuaweiCloudService.readRawFile(context, 'agconnect-services.json');
    if (!json) {
      return;
    }
    try {
      auth.init(context, json);
      // 二开改造：hwid 登录的 client_id 必须使用 oauth_client.client_id（应用级），
      // 顶层 client_id 是 AGC 网关/产品级标识，传入会导致鉴权 clientId 不匹配而登录失败。
      const parsed = JSON.parse(json) as Record<string, Object>;
      let clientId = '';
      const oauth = parsed['oauth_client'];
      if (oauth && typeof oauth === 'object') {
        const ocid = (oauth as Record<string, Object>)['client_id'];
        if (typeof ocid === 'string' && ocid.length > 0) {
          clientId = ocid;
        }
      }
      if (clientId.length === 0) {
        const cid = parsed['client_id'];
        if (typeof cid === 'string' && cid.length > 0) {
          clientId = cid;
        }
      }
      if (clientId.length > 0) {
        auth.setClientId(clientId);
      }
      AppStorage.setOrCreate('huaweiCloudConfigured', true);
      AppStorage.setOrCreate('huaweiCloudBootstrapError', '');
      const user = await auth.getCurrentUser();
      if (user) {
        HuaweiCloudService.applyUser(user);
      }
    } catch (e) {
      console.warn('[HuaweiCloud] bootstrap failed', JSON.stringify(e));
      AppStorage.setOrCreate('huaweiCloudConfigured', false);
      AppStorage.setOrCreate('huaweiCloudBootstrapError', HuaweiCloudService.errorMessage(e));
    }
  }

  /** 弹出华为账号授权登录；成功后写入 AppStorage 登录态。 */
  static async signIn(): Promise<boolean> {
    if (!HuaweiCloudService.isConfigured()) {
      throw new Error('AGC 配置未就绪：请在 AGC 控制台开通 Auth Service 并放置 agconnect-services.json');
    }
    try {
      const result = await auth.signIn({ credentialInfo: { kind: 'hwid' }, autoCreateUser: true });
      const user = result.getUser();
      if (!user) {
        return false;
      }
      HuaweiCloudService.applyUser(user);
      HuaweiCloudService.initCloud();
      return true;
    } catch (e) {
      console.warn('[HuaweiCloud] signIn failed', JSON.stringify(e));
      throw new Error(HuaweiCloudService.errorText(e, '华为账号登录失败'));
    }
  }

  static async signOut(): Promise<void> {
    try {
      await auth.signOut();
    } catch (e) {
      console.warn('[HuaweiCloud] signOut failed', JSON.stringify(e));
    }
    AppStorage.setOrCreate('huaweiCloudUid', '');
    AppStorage.setOrCreate('huaweiCloudName', '');
    HuaweiCloudService.cloudReady = false;
  }

  /**
   * 备份到华为云端：本地生成加密备份包 → 上传到 Cloud Storage。
   * @param password 备份密码（可空，空则未加密）
   * @returns 云路径
   */
  static async backupToCloud(context: common.UIAbilityContext, password: string,
    onProgress?: (message: string, percent: number) => void): Promise<string> {
    const user = await auth.getCurrentUser();
    if (!user) {
      throw new Error('请先登录华为账号');
    }
    await HuaweiCloudService.ensureCloud();
    const selection = HuaweiCloudService.fullSelection();
    const result = await AppDataBackupService.createBackup(context, selection, password, onProgress);
    const archivePath = result.archivePath;
    if (!archivePath) {
      throw new Error('备份文件生成失败');
    }
    // Cloud Storage 上传的 localPath 以 cache 目录为根
    const cacheName = `cloud_backup_${Date.now()}.qingyebak`;
    const cachePath = `${context.cacheDir}/${cacheName}`;
    await AppDataBackupService.copyFile(archivePath, cachePath);
    try {
      await AppDataBackupService.removeFile(archivePath);
    } catch (e) {
      console.warn('[HuaweiCloud] remove temp archive failed', JSON.stringify(e));
    }
    const uid = user.getUid().substring(0, 8);
    const cloudPath = `${HuaweiCloudService.CLOUD_DIR}/${HuaweiCloudService.BACKUP_PREFIX}${Date.now()}_${uid}.qingyebak`;
    const bucket = cloudStorage.bucket();
    const task = await bucket.uploadFile(context, {
      localPath: cacheName,
      cloudPath: cloudPath,
      metadata: { contentType: 'application/octet-stream' }
    });
    await HuaweiCloudService.awaitTask(task);
    try {
      await AppDataBackupService.removeFile(cachePath);
    } catch (e) {
      console.warn('[HuaweiCloud] remove uploaded cache failed', JSON.stringify(e));
    }
    return cloudPath;
  }

  /** 列出云端备份文件（按最后修改时间倒序）。 */
  static async listBackups(): Promise<CloudBackupItem[]> {
    await HuaweiCloudService.ensureCloud();
    const bucket = cloudStorage.bucket();
    const res = await bucket.list(`${HuaweiCloudService.CLOUD_DIR}/`);
    const items: CloudBackupItem[] = [];
    for (const cloudPath of res.files) {
      const item = new CloudBackupItem();
      item.cloudPath = cloudPath;
      const idx = cloudPath.lastIndexOf('/');
      item.name = idx >= 0 ? cloudPath.substring(idx + 1) : cloudPath;
      try {
        const meta = await bucket.getMetadata(cloudPath);
        item.size = meta.size;
        item.updatedTime = meta.modifyTime.getTime();
      } catch (e) {
        item.size = 0;
        item.updatedTime = 0;
      }
      items.push(item);
    }
    items.sort((a: CloudBackupItem, b: CloudBackupItem): number => b.updatedTime - a.updatedTime);
    return items;
  }

  /**
   * 从云端恢复：下载备份包 → prepareImport → importBackup（全量恢复）。
   * @param cloudPath 云端文件路径
   * @param password 备份密码
   */
  static async restoreFromCloud(context: common.UIAbilityContext, cloudPath: string, password: string,
    onProgress?: (message: string, percent: number) => void): Promise<AppDataBackupImportResult> {
    const user = await auth.getCurrentUser();
    if (!user) {
      throw new Error('请先登录华为账号');
    }
    await HuaweiCloudService.ensureCloud();
    const cacheName = `cloud_restore_${Date.now()}.qingyebak`;
    const bucket = cloudStorage.bucket();
    const task = await bucket.downloadFile(context, {
      localPath: cacheName,
      cloudPath: cloudPath
    });
    await HuaweiCloudService.awaitTask(task);
    const localPath = `${context.cacheDir}/${cacheName}`;
    let session: AppDataBackupImportSession | null = null;
    try {
      const uri = fileUri.getUriFromPath(localPath);
      session = await AppDataBackupService.prepareImport(context, uri, password, onProgress);
      const result = await AppDataBackupService.importBackup(context, session,
        HuaweiCloudService.fullSelection(), onProgress);
      return result;
    } finally {
      await AppDataBackupService.discardImport(session);
      try {
        await AppDataBackupService.removeFile(localPath);
      } catch (e) {
        console.warn('[HuaweiCloud] remove restored cache failed', JSON.stringify(e));
      }
    }
  }

  /** 删除一个云端备份文件。 */
  static async deleteBackup(cloudPath: string): Promise<void> {
    await HuaweiCloudService.ensureCloud();
    const bucket = cloudStorage.bucket();
    await bucket.deleteFile(cloudPath);
  }

  private static applyUser(user: AuthUser): void {
    AppStorage.setOrCreate('huaweiCloudUid', user.getUid());
    const name = user.getDisplayName();
    AppStorage.setOrCreate('huaweiCloudName', name && name.length > 0 ? name : '');
  }

  private static initCloud(): void {
    try {
      cloudCommon.init({
        authProvider: auth.getAuthProvider(),
        region: cloudCommon.CloudRegion.CHINA
      });
      HuaweiCloudService.cloudReady = true;
    } catch (e) {
      console.warn('[HuaweiCloud] cloudCommon init failed', JSON.stringify(e));
      HuaweiCloudService.cloudReady = false;
      throw new Error('云存储初始化失败：请在 AGC 控制台开通 Cloud Storage');
    }
  }

  private static async ensureCloud(): Promise<void> {
    if (HuaweiCloudService.cloudReady) {
      return;
    }
    const user = await auth.getCurrentUser();
    if (!user) {
      throw new Error('请先登录华为账号');
    }
    HuaweiCloudService.initCloud();
  }

  private static fullSelection(): AppDataBackupSelection {
    const selection = new AppDataBackupSelection();
    selection.sources = true;
    selection.rssSources = true;
    selection.bookshelf = true;
    selection.progress = true;
    selection.bookmarks = true;
    selection.localBooks = true;
    selection.settings = true;
    selection.searchHistory = true;
    return selection;
  }

  private static awaitTask(task: request.agent.Task): Promise<void> {
    return new Promise<void>((resolve: () => void, reject: (reason: Error) => void) => {
      const onCompleted = (): void => {
        task.off('completed', onCompleted);
        task.off('failed', onFailed);
        resolve();
      };
      const onFailed = (): void => {
        task.off('completed', onCompleted);
        task.off('failed', onFailed);
        reject(new Error('云传输失败'));
      };
      task.on('completed', onCompleted);
      task.on('failed', onFailed);
    });
  }

  private static async readRawFile(context: common.UIAbilityContext, name: string): Promise<string> {
    try {
      const data = await context.resourceManager.getRawFileContent(name);
      if (!data) {
        return '';
      }
      const decoder = new util.TextDecoder();
      return decoder.decodeToString(data);
    } catch (e) {
      return '';
    }
  }

  private static errorText(e: Object, fallback: string): string {
    const msg = HuaweiCloudService.errorMessage(e);
    return msg.length > 0 ? `${fallback}：${msg}` : fallback;
  }

  private static errorMessage(e: Object): string {
    if (typeof e === 'object' && e !== null) {
      const rec = e as Record<string, Object>;
      const msg = rec['message'];
      if (typeof msg === 'string' && msg.length > 0) {
        return msg;
      }
      if (typeof msg === 'number') {
        return String(msg);
      }
    }
    return '';
  }
}
