/**
 * 单源/单请求整体超时兜底工具。
 *
 * 搜索、探索、校验链路中存在多处"没有整体 deadline"的长任务：书源 JS 脚本执行
 * （StageWebRuntime 单步 20s、最多 20 步）、聚合源（如书山 70+ 子源）云端 API
 * 多步重试等，单源最坏可阻塞数分钟。UI 侧 isLoading 依赖这些 Promise resolve，
 * 一旦内部 await 永不结束，界面就会一直停留在"加载中/校验中"。
 *
 * withTimeout 用 Promise.race 施加整体期限：超时立即走失败分支（UI 解除等待、
 * 校验跳过当前源继续下一个），同时保留原任务在后台自然结束（内部均有超时），
 * 避免悬挂句柄泄漏。
 */
export class TimeoutHelper {
  /**
   * 在 ms 毫秒内未完成则按 onTimeout 返回失败值；完成则透传原结果。
   * onTimeout 返回 T，保证调用方拿到一致类型，不抛未处理异常。
   */
  static withTimeout<T>(
    task: Promise<T>,
    ms: number,
    onTimeout: () => T
  ): Promise<T> {
    const timeoutMs = Math.max(1, Math.round(ms));
    if (!Number.isFinite(timeoutMs)) {
      return task;
    }
    return new Promise<T>((resolve) => {
      const timer = setTimeout(() => {
        resolve(onTimeout());
      }, timeoutMs);
      task.then(
        (value: T) => {
          clearTimeout(timer);
          resolve(value);
        },
        (reason: Object) => {
          clearTimeout(timer);
          resolve(onTimeout());
        }
      );
    });
  }
}
