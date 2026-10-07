import { font } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import fs from '@ohos.file.fs';

/**
 * 二开改造：内置开源字体。
 *
 * 项目在 resources/rawfile/fonts/ 内置了以下 SIL OFL 1.1 许可字体（附许可文本）：
 *  - SourceHanSansCN-Regular.otf  思源黑体（Adobe 思源黑体，OFL）
 *  - SourceHanSerifCN-Regular.otf 思源宋体（Adobe 思源宋体，OFL）
 *  - LXGWWenKaiLite-Regular.ttf   霞鹜文楷 Lite（OFL）
 *
 * 首次启动时把 rawfile 中的字体复制到 filesDir/reader_fonts 并注册到字体系统，
 * 同时把内置字体合并进 readerCustomFontsRaw，使阅读字体设置（含阅读页内字体弹窗）
 * 可以直接选用。复制是幂等的：目标文件已存在则跳过。
 */
export class BuiltinFontSpec {
  fileName: string = '';
  familyName: string = '';
  displayName: string = '';
}

export class BuiltinFontManager {
  private static readonly TAG: string = 'BuiltinFonts';
  private static readonly FONTS: BuiltinFontSpec[] = [
    {
      fileName: 'SourceHanSansCN-Regular.otf',
      familyName: 'SourceHanSansCN',
      displayName: '思源黑体'
    },
    {
      fileName: 'SourceHanSerifCN-Regular.otf',
      familyName: 'SourceHanSerifCN',
      displayName: '思源宋体'
    },
    {
      fileName: 'LXGWWenKaiLite-Regular.ttf',
      familyName: 'LXGWWenKaiLite',
      displayName: '霞鹜文楷'
    }
  ];

  static async ensure(context: common.Context): Promise<void> {
    const fontDir = `${context.filesDir}/reader_fonts`;
    try {
      fs.mkdirSync(fontDir);
    } catch (e) {
      // 目录已存在时忽略
    }
    for (const spec of BuiltinFontManager.FONTS) {
      const targetPath = `${fontDir}/${spec.fileName}`;
      if (!BuiltinFontManager.fileExists(targetPath)) {
        try {
          const content = await context.resourceManager.getRawFileContent(`fonts/${spec.fileName}`);
          const buffer = BuiltinFontManager.toArrayBuffer(content);
          const file = fs.openSync(targetPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE);
          try {
            fs.writeSync(file.fd, buffer);
          } finally {
            fs.closeSync(file);
          }
          hilog.info(0x0000, BuiltinFontManager.TAG, 'Copied builtin font %{public}s', spec.fileName);
        } catch (e) {
          hilog.warn(0x0000, BuiltinFontManager.TAG,
            'Copy builtin font %{public}s failed: %{public}s', spec.fileName, JSON.stringify(e));
          continue;
        }
      }
      BuiltinFontManager.mergeIntoRaw(targetPath, spec);
      try {
        font.registerFont({
          familyName: spec.familyName,
          familySrc: `file://${targetPath}`
        });
      } catch (e) {
        hilog.warn(0x0000, BuiltinFontManager.TAG,
          'Register builtin font %{public}s failed: %{public}s', spec.familyName, JSON.stringify(e));
      }
    }
  }

  private static fileExists(path: string): boolean {
    try {
      const stat = fs.statSync(path);
      return stat.size > 0;
    } catch (e) {
      return false;
    }
  }

  private static toArrayBuffer(data: Uint8Array): ArrayBuffer {
    if (data.byteOffset === 0 && data.byteLength === data.buffer.byteLength) {
      return data.buffer as ArrayBuffer;
    }
    const copy = new Uint8Array(data.byteLength);
    copy.set(data);
    return copy.buffer as ArrayBuffer;
  }

  private static mergeIntoRaw(targetPath: string, spec: BuiltinFontSpec): void {
    const raw = AppStorage.get<string>('readerCustomFontsRaw') || '';
    let list: Array<Record<string, string>> = [];
    try {
      const parsed = JSON.parse(raw) as Record<string, Object> | Array<Record<string, string>>;
      if (Array.isArray(parsed)) {
        list = (parsed as Array<Record<string, string>>).slice();
      } else if (parsed && Array.isArray(parsed.fonts)) {
        list = (parsed.fonts as Array<Record<string, string>>).slice();
      }
    } catch (e) {
      list = [];
    }
    const exists = list.some((f: Record<string, string>) => f && f.familyName === spec.familyName);
    if (!exists) {
      const entry: Record<string, string> = {
        familyName: spec.familyName,
        filePath: targetPath,
        sourceName: spec.displayName
      };
      list.push(entry);
      AppStorage.setOrCreate('readerCustomFontsRaw', JSON.stringify({ fonts: list }));
      hilog.info(0x0000, BuiltinFontManager.TAG, 'Merged builtin font %{public}s into reader fonts', spec.familyName);
    }
  }
}
