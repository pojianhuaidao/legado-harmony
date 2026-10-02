import { AppIconSettingsStore } from './AppIconSettingsStore';

export class AppIconOption {
  id: string = '';
  title: string = '';
  desc: string = '';
  preview: Resource = $r('app.media.icon');
}

// 静态图标方案：每个选项对应一组编译期默认图标资源（layered_image_<id> 与 icon.png），
// 不再依赖运行时动态图标（AppGallery selectDynamicIcon）。
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

  static optionById(iconId: string): AppIconOption {
    const normalized = AppIconSettingsStore.normalizeIconId(iconId);
    const matched = AppIconManager.OPTIONS.find((option: AppIconOption) => option.id === normalized);
    return matched || AppIconManager.OPTIONS[0];
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
