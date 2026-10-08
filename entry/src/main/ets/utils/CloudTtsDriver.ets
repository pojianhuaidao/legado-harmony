import { common } from '@kit.AbilityKit';
import fs from '@ohos.file.fs';
import { CloudTtsVoiceProvider } from './CloudTtsVoiceProvider';
import { TtsAvAudioPlayer } from './TtsAvAudioPlayer';

/**
 * 云端 TTS 播放驱动：合成云端音色音频 -> 写入沙箱缓存文件 -> AVPlayer 播放。
 *
 * 与 SystemTtsReader 保持同构接口（start / stop / pause / resume / isSpeaking /
 * isPaused / shutdown），方便朗读页统一路由。
 */

export interface CloudTtsPlayOptions {
  text: string;
  provider: string;
  baseUrl: string;
  model: string;
  apiKey: string;
  voice: string;
  speed: number;
  onStart?: () => void;
  onFinished?: () => void;
  onError?: (message: string) => void;
}

export class CloudTtsDriver {
  private context: common.UIAbilityContext;
  private player: TtsAvAudioPlayer = new TtsAvAudioPlayer();
  private activeRequestId: number = 0;
  private running: boolean = false;
  private paused: boolean = false;

  constructor(context: common.UIAbilityContext) {
    this.context = context;
  }

  isSpeaking(): boolean {
    return this.running;
  }

  isPaused(): boolean {
    return this.paused;
  }

  async speak(options: CloudTtsPlayOptions): Promise<void> {
    const requestId = ++this.activeRequestId;
    this.running = true;
    this.paused = false;
    try {
      const audio = await CloudTtsVoiceProvider.synthesize({
        text: options.text,
        baseUrl: options.baseUrl,
        model: options.model,
        apiKey: options.apiKey,
        voice: options.voice,
        speed: options.speed
      });
      if (requestId !== this.activeRequestId) {
        return;
      }
      const filePath = await this.writeCacheFile(requestId, options.voice, audio);
      if (requestId !== this.activeRequestId) {
        return;
      }
      if (options.onStart) {
        options.onStart();
      }
      await this.player.play(filePath, options.speed);
      if (requestId !== this.activeRequestId) {
        return;
      }
      this.running = false;
      if (options.onFinished) {
        options.onFinished();
      }
    } catch (error) {
      if (requestId !== this.activeRequestId) {
        return;
      }
      this.running = false;
      if (options.onError) {
        options.onError(CloudTtsDriver.errorMessage(error));
      }
    }
  }

  async pause(): Promise<void> {
    if (!this.running || this.paused) {
      return;
    }
    this.paused = true;
    await this.player.pause();
  }

  async resume(): Promise<void> {
    if (!this.running || !this.paused) {
      return;
    }
    this.paused = false;
    await this.player.resume();
  }

  stop(): void {
    this.activeRequestId++;
    this.running = false;
    this.paused = false;
    this.player.stop();
  }

  shutdown(): void {
    this.stop();
    this.player.release();
  }

  /** 删除沙箱缓存目录中指定音色（voice）相关的全部音频缓存文件。 */
  async clearVoiceCache(voice: string): Promise<number> {
    const dir = this.cacheDir();
    let removed: number = 0;
    try {
      if (!fs.accessSync(dir)) {
        return 0;
      }
      const entries = fs.listFileSync(dir);
      for (const name of entries) {
        if (name.indexOf('_' + voice + '_') >= 0) {
          const target = dir + '/' + name;
          try {
            fs.unlinkSync(target);
            removed++;
          } catch (_) {
          }
        }
      }
    } catch (_) {
    }
    return removed;
  }

  /** 清空沙箱缓存目录（删除全部云端音色缓存文件）。 */
  async clearAllCache(): Promise<number> {
    const dir = this.cacheDir();
    let removed: number = 0;
    try {
      if (!fs.accessSync(dir)) {
        return 0;
      }
      const entries = fs.listFileSync(dir);
      for (const name of entries) {
        try {
          fs.unlinkSync(dir + '/' + name);
          removed++;
        } catch (_) {
        }
      }
    } catch (_) {
    }
    return removed;
  }

  private cacheDir(): string {
    return this.context.filesDir + '/cloud_tts_cache';
  }

  private async writeCacheFile(requestId: number, voice: string, audio: ArrayBuffer): Promise<string> {
    const dir = this.cacheDir();
    if (!fs.accessSync(dir)) {
      fs.mkdirSync(dir, true);
    }
    const name = 'cloud_' + voice + '_' + Date.now() + '_' + requestId + '.wav';
    const filePath = dir + '/' + name;
    const file = fs.openSync(filePath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    try {
      fs.writeSync(file.fd, audio);
    } finally {
      fs.closeSync(file);
    }
    return filePath;
  }

  static errorMessage(error: Object | undefined): string {
    if (!error) {
      return '云端音色朗读失败';
    }
    const anyError = error as Record<string, Object>;
    const message = anyError['message'];
    if (message !== undefined) {
      return String(message);
    }
    return String(error);
  }
}
