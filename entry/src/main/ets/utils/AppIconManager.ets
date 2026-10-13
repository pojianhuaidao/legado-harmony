import { AppIconSettings, AppIconSettingsStore } from './AppIconSettingsStore';
import { bundleManager } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Context } from '@kit.AbilityKit';

export class AppIconOption {
  id: string = '';
  title: string = '';
  desc: string = '';
  preview: Resource = $r('app.media.icon');
}

// 运行时动态图标方案：每个选项对应 app.json5 alternateIcons 中声明的备用图标
// （AppScope/resources/base/media 下的 ic_app_* 资源），通过 bundleManager.setAlternateIcon 即时切换，
// 无需重新构建侧载包。
export class AppIconManager {
  static readonly OPTIONS: AppIconOption[] = [
    AppIconManager.option(
      AppIconSettingsStore.DEFAULT_ICON_ID,
      '默认图标',
      '当前桌面图标',
      $r('app.media.icon')
    ),
    AppIconManager.option(
      'warm_book',
      '纸书暖光',
      '温润纸页与书签',
      $r('app.media.ic_app_warm_book')
    ),
    AppIconManager.option(
      'night_neon',
      '夜读霓虹',
      '深色发光书页',
      $r('app.media.ic_app_night_neon')
    ),
    AppIconManager.option(
      'minimal_line',
      '极简线性',
      '清爽几何线条',
      $r('app.media.ic_app_minimal_line')
    ),
    AppIconManager.option(
      'ink_wash',
      '水墨书山',
      '东方水墨意象',
      $r('app.media.ic_app_ink_wash')
    ),
    AppIconManager.option(
      'pixel_retro',
      '像素复古',
      '轻快像素书本',
      $r('app.media.ic_app_pixel_retro')
    ),
    AppIconManager.option(
      'theme_classic_blue',
      '经典蓝·书页',
      '经典蓝主题专属图标',
      $r('app.media.ic_app_theme_classic_blue')
    ),
    AppIconManager.option(
      'theme_warm_paper',
      '暖纸·书笺',
      '暖纸主题专属图标',
      $r('app.media.ic_app_theme_warm_paper')
    ),
    AppIconManager.option(
      'theme_forest_mist',
      '林雾·叶语',
      '林雾主题专属图标',
      $r('app.media.ic_app_theme_forest_mist')
    ),
    AppIconManager.option(
      'theme_ink_wash',
      '水墨·书山',
      '水墨主题专属图标',
      $r('app.media.ic_app_theme_ink_wash')
    ),
    AppIconManager.option(
      'theme_neon_night',
      '霓虹·夜读',
      '霓虹主题专属图标',
      $r('app.media.ic_app_theme_neon_night')
    )
  ];

  // 返回 app.json5 alternateIcons 中对应的备用图标 name；默认图标返回空串表示恢复系统默认图标
  static alternateIconName(iconId: string): string {
    const normalized = AppIconSettingsStore.normalizeIconId(iconId);
    if (normalized === AppIconSettingsStore.DEFAULT_ICON_ID) {
      return '';
    }
    return `ic_app_${normalized}`;
  }

  static optionById(iconId: string): AppIconOption {
    const normalized = AppIconSettingsStore.normalizeIconId(iconId);
    const matched = AppIconManager.OPTIONS.find((option: AppIconOption) => option.id === normalized);
    return matched || AppIconManager.OPTIONS[0];
  }

  // 二开改造：主题 id → 同名图标 id（如 classic-blue → theme_classic_blue）；
  // 主题没有同名图标（含默认主题与自定义主题）时返回默认图标。
  static themeIconId(themeId: string): string {
    const normalized = (themeId || '').replace(/-/g, '_').trim();
    if (!normalized || normalized === 'plain_default' || normalized === AppIconSettingsStore.DEFAULT_ICON_ID ||
      normalized === 'custom') {
      return AppIconSettingsStore.DEFAULT_ICON_ID;
    }
    const candidate = `theme_${normalized}`;
    for (const option of AppIconManager.OPTIONS) {
      if (option.id === candidate) {
        return candidate;
      }
    }
    return AppIconSettingsStore.DEFAULT_ICON_ID;
  }

  // 二开改造：按图标 id 切换桌面图标并持久化（保留 followTheme 开关原值，避免覆盖主题页设置）。
  static async applyIcon(context: Context, iconId: string): Promise<boolean> {
    const normalized = AppIconManager.optionById(iconId).id;
    const alternateName = AppIconManager.alternateIconName(normalized);
    try {
      await bundleManager.setAlternateIcon(alternateName);
      const current = await AppIconSettingsStore.load(context);
      const settings = new AppIconSettings();
      settings.iconId = normalized;
      settings.followTheme = current.followTheme;
      AppIconSettingsStore.applyToStorage(settings);
      AppIconSettingsStore.save(context, settings).catch((e: Error) => {
        hilog.warn(0x0000, 'appIcon', 'Save app icon selection failed err=%{public}s', JSON.stringify(e));
      });
      return true;
    } catch (e) {
      hilog.warn(0x0000, 'appIcon', 'setAlternateIcon failed err=%{public}s', JSON.stringify(e));
      return false;
    }
  }

  // 二开改造：主题切换联动入口。是否跟随以该主题项内部的小开关为准（themeFollowMap），
  // 顶部全局开关已移除；未记录的主题默认跟随。
  static async applyThemeIcon(context: Context, themeId: string): Promise<boolean> {
    const settings = await AppIconSettingsStore.load(context);
    if (!AppIconSettingsStore.themeFollow(settings, themeId)) {
      return false;
    }
    return AppIconManager.applyIcon(context, AppIconManager.themeIconId(themeId));
  }

  // 二开改造：按主题项内部小开关的明确决策切换图标。
  // follow=true → 切换同名主题图标；follow=false → 切回默认图标。
  static async applyThemeIconDecision(context: Context, themeId: string, follow: boolean): Promise<boolean> {
    if (follow) {
      return AppIconManager.applyIcon(context, AppIconManager.themeIconId(themeId));
    }
    return AppIconManager.applyIcon(context, AppIconSettingsStore.DEFAULT_ICON_ID);
  }

  private static option(
    id: string,
    title: string,
    desc: string,
    preview: Resource
  ): AppIconOption {
    const option = new AppIconOption();
    option.id = id;
    option.title = title;
    option.desc = desc;
    option.preview = preview;
    return option;
  }
}
