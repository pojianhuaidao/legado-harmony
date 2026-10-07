/**
 * 分角色朗读链式调度器。
 *
 * 职责：按角色标注结果逐段推进朗读，每段调用外部注入的 playSegment（内部走
 * SystemTtsReader.start 并携带该角色音色 person），上一段 onFinished 后自动
 * 播下一段，全部播完触发 onAllFinished（供上层续播下一章）。
 *
 * SystemTtsReader.start() 内部会先 stop 上一次朗读（stop 不触发 onFinished），
 * 因此链式逐段 start 是安全的，不会出现回调串扰。
 */
export interface RoleTtsPlayItem {
  role: string;
  text: string;
  /** 相对整章朗读文本起点的源偏移（用于将来高亮/进度定位） */
  sourceStart: number;
  /** 该角色使用的 TTS 音色 person id */
  person: number;
}

export interface RoleTtsDriverOptions {
  onSegmentStart?: (item: RoleTtsPlayItem, index: number, total: number) => void;
  onAllFinished?: () => void;
  onError?: (message: string) => void;
}

export class RoleTtsDriver {
  private items: RoleTtsPlayItem[] = [];
  private index: number = 0;
  private stopped: boolean = false;

  start(items: RoleTtsPlayItem[], options: RoleTtsDriverOptions,
    playSegment: (item: RoleTtsPlayItem, done: () => void, fail: (message: string) => void) => void): void {
    this.items = items.slice();
    this.index = 0;
    this.stopped = false;
    if (this.items.length === 0) {
      if (options.onAllFinished) {
        options.onAllFinished();
      }
      return;
    }
    this.playNext(options, playSegment);
  }

  stop(): void {
    this.stopped = true;
    this.items = [];
  }

  isStopped(): boolean {
    return this.stopped;
  }

  private playNext(options: RoleTtsDriverOptions,
    playSegment: (item: RoleTtsPlayItem, done: () => void, fail: (message: string) => void) => void): void {
    if (this.stopped) {
      return;
    }
    if (this.index >= this.items.length) {
      if (options.onAllFinished) {
        options.onAllFinished();
      }
      return;
    }
    const item = this.items[this.index];
    if (options.onSegmentStart) {
      options.onSegmentStart(item, this.index, this.items.length);
    }
    playSegment(item, () => {
      if (this.stopped) {
        return;
      }
      this.index++;
      this.playNext(options, playSegment);
    }, (message: string) => {
      if (this.stopped) {
        return;
      }
      if (options.onError) {
        options.onError(message);
      }
    });
  }
}
