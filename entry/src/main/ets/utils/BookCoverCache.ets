import { Context } from '@kit.AbilityKit';
import fs from '@ohos.file.fs';
import fileUri from '@ohos.file.fileuri';
import http from '@ohos.net.http';
import { CoverUrlNormalizer } from './CoverUrlNormalizer';
import { AppDataPaths } from './AppDataPaths';

export class BookCoverCache {
  private static resolvedCoverUris: Map<string, string> = new Map();
  private static inFlightResolutions: Map<string, Promise<string>> = new Map();
  private static activeNetworkTasks: number = 0;
  private static readonly MAX_NETWORK_TASKS: number = 4;
  private static networkWaiters: Array<() => void> = [];

  static resolveCachedCover(context: Context, raw: string): string {
    if (!raw || (!raw.startsWith('http://') && !raw.startsWith('https://'))) {
      return '';
    }
    const remembered = BookCoverCache.resolvedCoverUris.get(raw);
    if (remembered) return remembered;
    const cachedPath = BookCoverCache.cachedCoverPath(context, raw);
    if (!BookCoverCache.exists(cachedPath)) return '';
    const resolved = fileUri.getUriFromPath(cachedPath);
    BookCoverCache.resolvedCoverUris.set(raw, resolved);
    return resolved;
  }

  static async resolveCachedCoverAsync(context: Context, raw: string): Promise<string> {
    if (!raw || (!raw.startsWith('http://') && !raw.startsWith('https://'))) return '';
    const remembered = BookCoverCache.resolvedCoverUris.get(raw);
    if (remembered) return remembered;
    const cachedPath = BookCoverCache.cachedCoverPath(context, raw);
    if (!(await BookCoverCache.existsAsync(cachedPath))) return '';
    const resolved = fileUri.getUriFromPath(cachedPath);
    BookCoverCache.resolvedCoverUris.set(raw, resolved);
    return resolved;
  }

  static async resolveCover(context: Context, raw: string): Promise<string> {
    const active = BookCoverCache.inFlightResolutions.get(raw);
    if (active) return await active;
    const task = BookCoverCache.resolveCoverInternal(context, raw);
    BookCoverCache.inFlightResolutions.set(raw, task);
    try {
      return await task;
    } finally {
      if (BookCoverCache.inFlightResolutions.get(raw) === task) {
        BookCoverCache.inFlightResolutions.delete(raw);
      }
    }
  }

  private static async resolveCoverInternal(context: Context, raw: string): Promise<string> {
    if (!raw) {
      return '';
    }
    if (raw.startsWith('http://') || raw.startsWith('https://')) {
      const cachedPath = BookCoverCache.cachedCoverPath(context, raw);
      if (await BookCoverCache.existsAsync(cachedPath)) {
        const resolved = fileUri.getUriFromPath(cachedPath);
        BookCoverCache.resolvedCoverUris.set(raw, resolved);
        return resolved;
      }
      const path = await BookCoverCache.downloadCover(context, raw);
      if (!path) return raw;
      const resolved = fileUri.getUriFromPath(path);
      BookCoverCache.resolvedCoverUris.set(raw, resolved);
      return resolved;
    }
    const localPath = BookCoverCache.localPathFromUri(raw);
    if (localPath && await BookCoverCache.existsAsync(localPath)) {
      return raw.startsWith('file://') ? raw : fileUri.getUriFromPath(localPath);
    }
    const copiedPath = await BookCoverCache.copyCoverUriToCache(context, raw);
    if (copiedPath) {
      return fileUri.getUriFromPath(copiedPath);
    }
    return raw;
  }

  static async prepareCoverFile(context: Context, raw: string): Promise<string> {
    if (!raw) {
      return '';
    }
    if (raw.startsWith('http://') || raw.startsWith('https://')) {
      const cachedPath = BookCoverCache.cachedCoverPath(context, raw);
      if (await BookCoverCache.existsAsync(cachedPath)) {
        return cachedPath;
      }
      return await BookCoverCache.downloadCover(context, raw);
    }
    const localPath = BookCoverCache.localPathFromUri(raw);
    if (localPath && await BookCoverCache.existsAsync(localPath)) {
      return localPath;
    }
    return await BookCoverCache.copyCoverUriToCache(context, raw);
  }

  static deleteCachedCover(context: Context, raw: string): void {
    if (!raw) {
      return;
    }
    BookCoverCache.resolvedCoverUris.delete(raw);
    BookCoverCache.inFlightResolutions.delete(raw);
    if (raw.startsWith('http://') || raw.startsWith('https://')) {
      BookCoverCache.deletePath(BookCoverCache.cachedCoverPath(context, raw));
      return;
    }
    BookCoverCache.deletePath(BookCoverCache.cachedCoverPath(context, raw));
    const localPath = BookCoverCache.localPathFromUri(raw);
    if (!localPath || !BookCoverCache.isAppOwnedPath(context, localPath)) {
      return;
    }
    BookCoverCache.deletePath(localPath);
  }

  private static async downloadCover(context: Context, url: string): Promise<string> {
    const dir = `${context.cacheDir}/book_covers`;
    await BookCoverCache.ensureDirAsync(dir);
    const path = BookCoverCache.cachedCoverPath(context, url);
    if (await BookCoverCache.existsAsync(path)) {
      return path;
    }
    await BookCoverCache.acquireNetworkSlot();
    try {
      // Another request may have completed while this one waited for a slot.
      if (await BookCoverCache.existsAsync(path)) return path;
      const candidates = CoverUrlNormalizer.downloadCandidates(url);
      for (const requestUrl of candidates) {
        const request = http.createHttp();
        try {
          const response = await request.request(requestUrl, {
            method: http.RequestMethod.GET,
            connectTimeout: 10000,
            readTimeout: 10000,
            expectDataType: http.HttpDataType.ARRAY_BUFFER,
            header: {
              'User-Agent': 'Mozilla/5.0 (Linux; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
              'Accept': 'image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8',
              'Referer': BookCoverCache.refererFromUrl(requestUrl),
              'Origin': BookCoverCache.originFromUrl(requestUrl)
            }
          });
          if (response.responseCode < 200 || response.responseCode >= 300 || !(response.result instanceof ArrayBuffer)) {
            continue;
          }
          const file = await fs.open(path, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
          try {
            await fs.write(file.fd, response.result);
          } finally {
            await fs.close(file);
          }
          return path;
        } catch (e) {
          console.warn('下载书籍封面失败:', e);
        } finally {
          request.destroy();
        }
      }
      return '';
    } finally {
      BookCoverCache.releaseNetworkSlot();
    }
  }

  private static async acquireNetworkSlot(): Promise<void> {
    if (BookCoverCache.activeNetworkTasks < BookCoverCache.MAX_NETWORK_TASKS) {
      BookCoverCache.activeNetworkTasks++;
      return;
    }
    await new Promise<void>((resolve) => {
      BookCoverCache.networkWaiters.push(resolve);
    });
  }

  private static releaseNetworkSlot(): void {
    const next = BookCoverCache.networkWaiters.shift();
    if (next) {
      next();
      return;
    }
    BookCoverCache.activeNetworkTasks = Math.max(0, BookCoverCache.activeNetworkTasks - 1);
  }

  private static async copyCoverUriToCache(context: Context, raw: string): Promise<string> {
    if (!raw || raw.startsWith('http://') || raw.startsWith('https://')) {
      return '';
    }
    const dir = `${context.cacheDir}/book_covers`;
    await BookCoverCache.ensureDirAsync(dir);
    const path = BookCoverCache.cachedCoverPath(context, raw);
    if (await BookCoverCache.existsAsync(path)) {
      return path;
    }
    try {
      const source = raw.startsWith('/') ? fileUri.getUriFromPath(raw) : raw;
      await fs.copy(source, fileUri.getUriFromPath(path));
      return await BookCoverCache.existsAsync(path) ? path : '';
    } catch (e) {
      console.warn('复制书籍封面到缓存失败:', e);
      BookCoverCache.deletePath(path);
      return '';
    }
  }

  private static localPathFromUri(raw: string): string {
    if (raw.startsWith('file://')) {
      return decodeURIComponent(raw.substring('file://'.length));
    }
    return raw.startsWith('/') ? raw : '';
  }

  private static exists(path: string): boolean {
    try {
      return fs.accessSync(path);
    } catch (e) {
      return false;
    }
  }

  private static async existsAsync(path: string): Promise<boolean> {
    try {
      await fs.stat(path);
      return true;
    } catch (e) {
      return false;
    }
  }

  private static async ensureDirAsync(path: string): Promise<void> {
    try {
      await fs.mkdir(path, true);
    } catch (e) {
    }
  }

  private static cachedCoverPath(context: Context, url: string): string {
    return `${context.cacheDir}/book_covers/${BookCoverCache.hashText(url)}${BookCoverCache.coverExt(url)}`;
  }

  private static isAppOwnedPath(context: Context, path: string): boolean {
    return path.startsWith(`${AppDataPaths.dir('covers')}/`) || path.startsWith(`${context.cacheDir}/book_covers/`);
  }

  private static deletePath(path: string): void {
    try {
      if (path && BookCoverCache.exists(path)) {
        fs.unlinkSync(path);
      }
    } catch (e) {
      console.warn('删除书籍封面缓存失败:', e);
    }
  }

  private static coverExt(value: string): string {
    const lower = value.toLowerCase();
    if (lower.includes('.png')) return '.png';
    if (lower.includes('.webp')) return '.webp';
    if (lower.includes('.bmp')) return '.bmp';
    if (lower.includes('.gif')) return '.gif';
    return '.jpg';
  }

  private static originFromUrl(url: string): string {
    const match = url.match(/^(https?:\/\/[^\/]+)/);
    return match ? match[1] : '';
  }

  private static refererFromUrl(url: string): string {
    const origin = BookCoverCache.originFromUrl(url);
    return origin ? `${origin}/` : '';
  }

  private static hashText(value: string): string {
    let hash = 0;
    for (let i = 0; i < value.length; i++) {
      hash = value.charCodeAt(i) + ((hash << 5) - hash);
    }
    return Math.abs(hash).toString(16);
  }
}
