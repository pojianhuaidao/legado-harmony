import { common } from '@kit.AbilityKit';
import fs from '@ohos.file.fs';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';
import { TtsAvAudioPlayer } from './TtsAvAudioPlayer';

/**
 * 离线 TTS 播放驱动（开源模型预生成音频直放）。
 *
 * 定位：替代被剔除的微软 Edge/Azure 在线合成音色。本驱动不做端侧模型推理，
 * 而是播放「开源 TTS 模型（Piper / Kokoro / sherpa-onnx VITS 等）在 PC 端
 * 预生成、按句存放」的 wav 音频文件，实现完全离线朗读。
 *
 * 目录约定（沙箱 filesDir 内）：
 *   filesDir/tts_offline/<engine>/<sentenceSha1>.wav
 * engine 取值：piper | kokoro | sherpa-vits
 *
 * 未命中缓存时通过 onFallback 回调通知调用方，调用方应回退到系统 TTS 继续朗读，
 * 保证任何情况下朗读链路不断。
 */

export interface OfflineTtsPlayOptions {
  text: string;
  engine: string;
  speed: number;
  onStart?: () => void;
  onFinished?: () => void;
  onFallback?: () => void;
  onError?: (message: string) => void;
}

export class OfflineTtsDriver {
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

  /**
   * 朗读一段文本。逐句查找离线预生成音频；全部命中则顺序播放并回调
   * onFinished，任一缺失则不做任何播放并回调 onFallback（由调用方回退）。
   */
  async speak(options: OfflineTtsPlayOptions): Promise<void> {
    const requestId = ++this.activeRequestId;
    this.running = true;
    this.paused = false;
    try {
      const sentences = OfflineTtsDriver.splitSentences(options.text);
      if (sentences.length === 0) {
        this.running = false;
        if (options.onFinished) {
          options.onFinished();
        }
        return;
      }
      const engine = OfflineTtsDriver.sanitizeEngine(options.engine);
      const paths: string[] = [];
      for (const sentence of sentences) {
        const candidate = this.cachePath(engine, sentence);
        if (!fs.accessSync(candidate)) {
          this.running = false;
          if (options.onFallback) {
            options.onFallback();
          }
          return;
        }
        paths.push(candidate);
      }
      if (requestId !== this.activeRequestId) {
        return;
      }
      if (options.onStart) {
        options.onStart();
      }
      for (const path of paths) {
        if (requestId !== this.activeRequestId) {
          return;
        }
        await this.player.play(path, options.speed);
      }
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
        options.onError(OfflineTtsDriver.errorMessage(error));
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

  /** 离线音频根目录。 */
  static rootDir(context: common.UIAbilityContext): string {
    return context.filesDir + '/tts_offline';
  }

  /** 指定引擎的音频目录（filesDir/tts_offline/<engine>）。 */
  static engineDir(context: common.UIAbilityContext, engine: string): string {
    return OfflineTtsDriver.rootDir(context) + '/' + OfflineTtsDriver.sanitizeEngine(engine);
  }

  /** 统计指定引擎目录下已预生成的句子音频数量。 */
  async cachedCount(engine: string): Promise<number> {
    const dir = OfflineTtsDriver.engineDir(this.context, engine);
    try {
      if (!fs.accessSync(dir)) {
        return 0;
      }
      return fs.listFileSync(dir).length;
    } catch (_) {
      return 0;
    }
  }

  /** 清空指定引擎的离线音频缓存。 */
  async clearEngineCache(engine: string): Promise<number> {
    const dir = OfflineTtsDriver.engineDir(this.context, engine);
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

  /**
   * 按中文标点将文本切分为句子（保持与 PC 端预生成工具一致的切分粒度）。
   * 连续长句（无标点）整体保留为一句。
   */
  static splitSentences(text: string): string[] {
    const trimmed = (text || '').replace(/\s+/g, ' ').trim();
    if (!trimmed) {
      return [];
    }
    const parts = trimmed.split(/(?<=[。！？；…!?;])/);
    const result: string[] = [];
    for (const part of parts) {
      const sentence = part.trim();
      if (sentence.length > 0) {
        result.push(sentence);
      }
    }
    return result.length > 0 ? result : [trimmed];
  }

  /** 句子音频文件名：<sha256 前 24 位>.wav（PC 端预生成工具按同规则命名）。 */
  static sentenceFileName(sentence: string): string {
    const digest = cryptoFramework.createMd('SHA256');
    digest.updateSync({ data: new Uint8Array(new util.TextEncoder().encode(sentence)) });
    const data = digest.digestSync().data;
    let result = '';
    for (let index = 0; index < data.length && index < 12; index++) {
      result += data[index].toString(16).padStart(2, '0');
    }
    return result + '.wav';
  }

  private cachePath(engine: string, sentence: string): string {
    return OfflineTtsDriver.engineDir(this.context, engine) + '/' + OfflineTtsDriver.sentenceFileName(sentence);
  }

  static sanitizeEngine(engine: string): string {
    const value = (engine || 'piper').trim().toLowerCase();
    if (value === 'kokoro') {
      return 'kokoro';
    }
    if (value === 'sherpa-vits') {
      return 'sherpa-vits';
    }
    return 'piper';
  }

  static errorMessage(error: Object | undefined): string {
    if (!error) {
      return '离线音色朗读失败';
    }
    const anyError = error as Record<string, Object>;
    const message = anyError['message'];
    if (message !== undefined) {
      return String(message);
    }
    return String(error);
  }
}
