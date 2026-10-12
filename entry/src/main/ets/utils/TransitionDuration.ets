import display from '@ohos.display';

/**
 * 全屏页面转场动效时长（AGC 上架检测规范）：
 * - 8.5 英寸以下设备：不应短于 200ms
 * - 8.5 ~ 12 英寸设备：不应短于 250ms
 * - 12 英寸以上设备：不应短于 300ms
 * 按当前设备对角线尺寸动态返回对应达标值。
 */
export function fullScreenTransitionDurationMs(): number {
  try {
    const d = display.getDefaultDisplaySync();
    const diagonalInches = Math.sqrt(d.width * d.width + d.height * d.height) / d.densityDPI;
    if (diagonalInches > 12) {
      return 300;
    }
    if (diagonalInches >= 8.5) {
      return 250;
    }
    return 200;
  } catch (e) {
    return 200;
  }
}
