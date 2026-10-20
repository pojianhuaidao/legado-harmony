import { common } from '@kit.AbilityKit';
import { cloudSync, fileUri } from '@kit.CoreFileKit';
import fs from '@ohos.file.fs';
import util from '@ohos.util';
import auth, { AuthUser } from '@hw-agconnect/auth';
import {
  AppDataBackupImportResult,
  AppDataBackupImportSession,
  AppDataBackupSelection,
  AppDataBackupService
} from './AppDataBackupService';

/**
 * 华为账号登录（AGC Auth Service，hwid，仅作身份标识）+ 备份/恢复走华为云空间
 * （端云文件协同 / Device-Cloud File Sync），不再使用 AGC Cloud Storage 项目 Bucket。
 *
 * 依赖：
 *   1. AppScope/app.json5 中配置 cloudFileSyncEnabled = true；
 *   2. 用户在系统「设置 -> 云空间」中打开本应用的同步开关；
 *   3. 备份包写入应用沙箱 /data/storage/el2/cloud 目录后，由系统自动同步到
 *      用户自己的华为云空间（无需 AGC Cloud Storage 配额与 Bucket）。
 *
 * 云上目录结构：legado_backups/backup_<时间戳>_<uid前8位>.aiyuedubak
 * 备份文件使用现有 AppDataBackupService 的 AES-256-GCM 加密与清单格式。
 */
export class CloudBackupItem {
  cloudPath: string = '';
  name: string = '';
  size: number = 0;
  updatedTime: number = 0;
}

export class HuaweiCloudService {
  /** 云空间文件同步目录（应用沙箱 el2/cloud，写入后自动同步到用户华为云空间）。 */
  static readonly CLOUD_DIR: string = '/data/storage/el2/cloud/legado_backups';
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
  /** 占位/无效 agconnect 配置检测：client_secret / api_key 为空或含 YOUR/placeholder 等占位文本即视为无效；
   *  官方下载版 '[!...]' 加密凭据属有效配置，不得误判为占位（否则 bootstrap 会跳过 auth.init）。 */
  private static isPlaceholderAgconnectJson(json: string): boolean {
    try {
      const parsed = JSON.parse(json) as Record<string, Object>;
      const client = parsed['client'];
      if (!client || typeof client !== 'object') {
        return true;
      }
      const rec = client as Record<string, Object>;
      const placeholderText = (v: Object | undefined): boolean => {
        if (typeof v !== 'string' || v.length === 0) {
          return true;
        }
        // AGC 官方下载版凭据为 '[!...]' 加密格式，属正常配置，直接放行。
        if (v.indexOf('[!') === 0) {
          return false;
        }
        const lower = v.toLowerCase();
        return lower.indexOf('your_') >= 0 || lower.indexOf('your-') >= 0 ||
          lower.indexOf('placeholder') >= 0 || lower.indexOf('xxxx') >= 0 ||
          lower.indexOf('xxx') >= 0 || lower.indexOf('todo') >= 0;
      };
      if (placeholderText(rec['client_secret']) || placeholderText(rec['api_key'])) {
        return true;
      }
      // AGC Auth 依赖 oauth_client.client_id（应用级），缺失视为无效配置。
      const oauth = parsed['oauth_client'];
      if (!oauth || typeof oauth !== 'object') {
        return true;
      }
      const ocid = (oauth as Record<string, Object>)['client_id'];
      if (typeof ocid !== 'string' || ocid.length === 0) {
        return true;
      }
      return false;
    } catch (_) {
      return true;
    }
  }

  static async bootstrap(context: common.UIAbilityContext): Promise<void> {
    const trace = (msg: string): void => HuaweiCloudService.trace(context, '[bootstrap] ' + msg);
    trace('bootstrap begin');
    AppStorage.setOrCreate('huaweiCloudConfigured', false);
    AppStorage.setOrCreate('huaweiCloudUid', '');
    AppStorage.setOrCreate('huaweiCloudName', '');
    const json = await HuaweiCloudService.readRawFile(context, 'agconnect-services.json');
    if (!json) {
      trace('agconnect-services.json missing');
      return;
    }
    // 占位/无效配置直接跳过 AGC 原生初始化，避免 SDK 解析失败导致原生崩溃。
    if (HuaweiCloudService.isPlaceholderAgconnectJson(json)) {
      console.warn('[HuaweiCloud] agconnect-services.json 为占位/无效配置，跳过 AGC 初始化');
      trace('agconnect json is placeholder, skip');
      AppStorage.setOrCreate('huaweiCloudConfigured', false);
      AppStorage.setOrCreate('huaweiCloudBootstrapError', 'agconnect-services.json 配置无效或为占位文件');
      return;
    }
    trace('agconnect json valid');
    try {
      auth.init(context, json);
      // 标准集成（AGC 官方文档）：agconnect-services.json 为含密钥官方下载版，
      // SDK 自动读取 client_id 并解密 [!...] 加密凭据，无需手动 setClientId / setClientSecret
      // （该接口仅用于下载配置时勾选"不包含密钥"的场景，且应传项目级 Client ID）。
      // 手动 setClientId 传入与 SDK 解密凭据不一致的 clientId 会导致 client token auth failed。
      trace('auth.init ok');
      AppStorage.setOrCreate('huaweiCloudConfigured', true);
      AppStorage.setOrCreate('huaweiCloudBootstrapError', '');
      const user = await auth.getCurrentUser();
      if (user) {
        HuaweiCloudService.applyUser(user);
        trace('getCurrentUser ok, uid=' + user.getUid());
      } else {
        trace('getCurrentUser empty');
      }
    } catch (e) {
      console.warn('[HuaweiCloud] bootstrap failed', JSON.stringify(e));
      trace('bootstrap failed ' + JSON.stringify(e));
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
      HuaweiCloudService.ensureCloudDir();
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
   * 备份到华为云空间：本地生成加密备份包 → 写入云空间同步目录（自动同步到用户云空间）。
   * @param password 备份密码（可空，空则未加密）
   * @returns 云空间目录中的备份文件路径
   */
  static async backupToCloud(context: common.UIAbilityContext, password: string,
    onProgress?: (message: string, percent: number) => void): Promise<string> {
    const progress = (msg: string, percent: number): void => {
      HuaweiCloudService.trace(context, '[backupToCloud] ' + msg + ' p=' + percent);
      if (onProgress) {
        onProgress(msg, percent);
      }
    };
    progress('正在准备备份...', 1);
    const user = await auth.getCurrentUser();
    if (!user) {
      progress('未登录，备份中止', 0);
      throw new Error('请先登录华为账号');
    }
    progress('账号校验完成', 5);
    HuaweiCloudService.ensureCloudDir();
    progress('云空间同步目录就绪', 10);
    const selection = HuaweiCloudService.fullSelection();
    progress('开始生成备份包...', 15);
    const result = await AppDataBackupService.createBackup(context, selection, password, onProgress);
    const archivePath = result.archivePath;
    if (!archivePath) {
      progress('备份包生成失败', 0);
      throw new Error('备份文件生成失败');
    }
    progress('备份包生成完成', 40);
    const uid = user.getUid().substring(0, 8);
    const cloudPath = `${HuaweiCloudService.CLOUD_DIR}/${HuaweiCloudService.BACKUP_PREFIX}${Date.now()}_${uid}.aiyuedubak`;
    try {
      await AppDataBackupService.copyFile(archivePath, cloudPath);
    } catch (e) {
      progress('写入云空间目录失败', 0);
      throw new Error('写入云空间同步目录失败：' + HuaweiCloudService.errorMessage(e));
    }
    progress('备份包已写入云空间目录', 55);
    try {
      await AppDataBackupService.removeFile(archivePath);
    } catch (e) {
      HuaweiCloudService.trace(context, '[backupToCloud] remove temp archive failed ' + JSON.stringify(e));
    }
    progress('正在同步到华为云空间...', 65);
    await HuaweiCloudService.triggerSyncAndWait(context, cloudPath);
    progress('同步完成', 100);
    return cloudPath;
  }

  /** 列出云端备份文件（按最后修改时间倒序）。 */
  static async listBackups(): Promise<CloudBackupItem[]> {
    const items: CloudBackupItem[] = [];
    let names: string[] = [];
    try {
      names = fs.listFileSync(HuaweiCloudService.CLOUD_DIR);
    } catch (e) {
      return items;
    }
    for (const name of names) {
      if (!name.startsWith(HuaweiCloudService.BACKUP_PREFIX)) {
        continue;
      }
      const localPath = `${HuaweiCloudService.CLOUD_DIR}/${name}`;
      const item = new CloudBackupItem();
      item.cloudPath = localPath;
      item.name = name;
      try {
        const stat = fs.statSync(localPath);
        item.size = stat.size;
        item.updatedTime = stat.mtime;
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
   * 从云端恢复：云空间目录文件即本地实体，直接 prepareImport → importBackup（全量恢复）。
   * @param cloudPath 云空间目录中的备份文件路径
   * @param password 备份密码
   */
  static async restoreFromCloud(context: common.UIAbilityContext, cloudPath: string, password: string,
    onProgress?: (message: string, percent: number) => void): Promise<AppDataBackupImportResult> {
    const user = await auth.getCurrentUser();
    if (!user) {
      throw new Error('请先登录华为账号');
    }
    const stat = fs.statSync(cloudPath);
    if (stat.size <= 0) {
      throw new Error('云空间备份文件尚未同步到本机，请稍后重试');
    }
    let session: AppDataBackupImportSession | null = null;
    try {
      const uri = fileUri.getUriFromPath(cloudPath);
      session = await AppDataBackupService.prepareImport(context, uri, password, onProgress);
      const result = await AppDataBackupService.importBackup(context, session,
        HuaweiCloudService.fullSelection(), onProgress);
      return result;
    } finally {
      await AppDataBackupService.discardImport(session);
    }
  }

  /** 删除一个云空间备份文件（本地删除，系统同步后云端副本一并移除）。 */
  static async deleteBackup(cloudPath: string): Promise<void> {
    fs.unlinkSync(cloudPath);
  }

  private static applyUser(user: AuthUser): void {
    AppStorage.setOrCreate('huaweiCloudUid', user.getUid());
    const name = user.getDisplayName();
    AppStorage.setOrCreate('huaweiCloudName', name && name.length > 0 ? name : '');
  }

  private static ensureCloudDir(): void {
    try {
      // 目录已存在则直接复用（历史备份或系统云空间已创建过时不再重复创建，
      // 避免 mkdirSync 对已存在目录抛 File exists）
      let dirExists = false;
      try {
        dirExists = fs.accessSync(HuaweiCloudService.CLOUD_DIR);
      } catch (e) {
        dirExists = false;
      }
      if (dirExists) {
        HuaweiCloudService.cloudReady = true;
        return;
      }
      fs.mkdirSync(HuaweiCloudService.CLOUD_DIR, true);
      HuaweiCloudService.cloudReady = true;
    } catch (e) {
      console.warn('[HuaweiCloud] mkdir cloud dir failed', JSON.stringify(e));
      HuaweiCloudService.cloudReady = false;
      throw new Error('创建云空间同步目录失败：' + HuaweiCloudService.errorMessage(e));
    }
  }

  /**
   * 触发云空间端云同步并等待单文件上传完成。
   * 依赖用户在系统「设置 -> 云空间」中打开本应用的同步开关。
   */
  private static async triggerSyncAndWait(context: common.UIAbilityContext, cloudPath: string): Promise<void> {
    const uri = fileUri.getUriFromPath(cloudPath);
    const fileSync = new cloudSync.FileSync();
    const onProgress = (pg: cloudSync.SyncProgress): void => {
      HuaweiCloudService.trace(context, '[triggerSync] state=' + pg.state + ' err=' + pg.error);
    };
    fileSync.on('progress', onProgress);
    try {
      await fileSync.start();
    } catch (e) {
      fileSync.off('progress', onProgress);
      console.warn('[HuaweiCloud] FileSync start failed', JSON.stringify(e));
      throw new Error('云空间同步启动失败：请在系统「设置 -> 云空间」中打开本应用的同步开关');
    }
    const deadline = Date.now() + 120000;
    while (Date.now() < deadline) {
      try {
        const st = cloudSync.getCoreFileSyncState(uri);
        if (st === cloudSync.FileState.UPLOAD_SUCCESS) {
          fileSync.off('progress', onProgress);
          return;
        }
        if (st === cloudSync.FileState.UPLOAD_FAILURE) {
          fileSync.off('progress', onProgress);
          throw new Error('云空间同步失败，请检查网络与云空间容量');
        }
      } catch (e) {
        if (e instanceof Error && e.message === '云空间同步失败，请检查网络与云空间容量') {
          fileSync.off('progress', onProgress);
          throw e;
        }
        // 文件刚写入可能暂未建立索引，忽略错误继续轮询
      }
      await new Promise<void>((resolve: () => void) => setTimeout(resolve, 1000));
    }
    fileSync.off('progress', onProgress);
    throw new Error('云空间同步超时，文件已写入本机云空间目录，稍后将自动同步');
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

  private static async readRawFile(context: common.UIAbilityContext, name: string): Promise<string> {
    try {
      const data = await context.resourceManager.getRawFileContent(name);
      if (!data) {
        return '';
      }
      const decoder = new util.TextDecoder();
      return decoder.decodeToString(new Uint8Array(data));
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

  /** 诊断埋点：追加写 trace 文件（release 包 console 不输出，只能落盘）。 */
  private static trace(context: common.UIAbilityContext, msg: string): void {
    try {
      const d = new Date();
      const pad = (n: number): string => (n < 10 ? '0' : '') + n;
      const ts = `${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}.${String(d.getMilliseconds()).padStart(3, '0')}`;
      const file = fs.openSync(`${context.filesDir}/backup_trace.log`,
        fs.OpenMode.READ_WRITE | fs.OpenMode.APPEND);
      fs.writeSync(file.fd, `[${ts}] ${msg}\n`);
      fs.closeSync(file);
    } catch (e) {
      // 静默：trace 失败不影响主流程
    }
  }

  /** 诊断展示：读取 backup_trace.log 全文（无文件或读取失败返回空串）。 */
  static readTrace(context: common.UIAbilityContext): string {
    const tracePath = `${context.filesDir}/backup_trace.log`;
    // 文件不存在属正常状态（尚无诊断记录），与真正的读取异常区分开，避免误报「读取 trace 失败」
    let traceExists = false;
    try {
      traceExists = fs.accessSync(tracePath);
    } catch (e) {
      traceExists = false;
    }
    if (!traceExists) {
      return '（trace 为空）';
    }
    try {
      const file = fs.openSync(tracePath, fs.OpenMode.READ_ONLY);
      const stat = fs.statSync(file.fd);
      if (stat.size <= 0) {
        fs.closeSync(file);
        return '（trace 为空）';
      }
      const buf = new ArrayBuffer(stat.size);
      fs.readSync(file.fd, buf);
      fs.closeSync(file);
      const decoder = new util.TextDecoder();
      return decoder.decodeToString(new Uint8Array(buf));
    } catch (e) {
      return '（读取 trace 失败）';
    }
  }
}
