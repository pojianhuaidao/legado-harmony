import { Context } from '@kit.AbilityKit';
import preferences from '@ohos.data.preferences';

export class AppIconSettings {
  iconId: string = AppIconSettingsStore.DEFAULT_ICON_ID;
  // 二开改造：主题与同名图标关联。开关开 = 切换主题时跟随切换同名图标；关 = 保持当前图标。
  followTheme: boolean = true;
  // 二开改造（第三版）：每个主题项独立的「图标跟随」开关，键为主题 id，值为是否跟随。
  // 未记录的主题默认跟随（true）。此字段替代顶部的全局开关。
  themeFollowMap: Record<string, boolean> = {};
}

export class AppIconSettingsStore {
  static readonly KEY_ICON_ID: string = 'appIconId';
  static readonly KEY_FOLLOW_THEME: string = 'appIconFollowTheme';
  static readonly KEY_THEME_FOLLOW_MAP: string = 'appIconThemeFollowMap';
  static readonly DEFAULT_ICON_ID: string = 'default';
  private static readonly STORE_NAME: string = 'app_icon_settings';
  private static cachedSettings: AppIconSettings | null = null;

  static async load(context: Context): Promise<AppIconSettings> {
    if (AppIconSettingsStore.cachedSettings) {
      return AppIconSettingsStore.clone(AppIconSettingsStore.cachedSettings);
    }
    const store = await preferences.getPreferences(context, AppIconSettingsStore.STORE_NAME);
    const settings = new AppIconSettings();
    settings.iconId = AppIconSettingsStore.normalizeIconId(await AppIconSettingsStore.getString(
      store, AppIconSettingsStore.KEY_ICON_ID, AppIconSettingsStore.DEFAULT_ICON_ID));
    settings.followTheme = await AppIconSettingsStore.getBoolean(
      store, AppIconSettingsStore.KEY_FOLLOW_THEME, true);
    settings.themeFollowMap = AppIconSettingsStore.parseThemeFollowMap(
      await AppIconSettingsStore.getString(store, AppIconSettingsStore.KEY_THEME_FOLLOW_MAP, '{}'));
    AppIconSettingsStore.cachedSettings = AppIconSettingsStore.clone(settings);
    return settings;
  }

  static async save(context: Context, settings: AppIconSettings): Promise<void> {
    const normalized = AppIconSettingsStore.clone(settings);
    AppIconSettingsStore.cachedSettings = AppIconSettingsStore.clone(normalized);
    const store = await preferences.getPreferences(context, AppIconSettingsStore.STORE_NAME);
    await store.put(AppIconSettingsStore.KEY_ICON_ID, normalized.iconId);
    await store.put(AppIconSettingsStore.KEY_FOLLOW_THEME, normalized.followTheme);
    await store.put(AppIconSettingsStore.KEY_THEME_FOLLOW_MAP, AppIconSettingsStore.serializeThemeFollowMap(normalized.themeFollowMap));
    await store.flush();
  }

  static applyToStorage(settings: AppIconSettings): void {
    const normalized = AppIconSettingsStore.clone(settings);
    AppIconSettingsStore.cachedSettings = AppIconSettingsStore.clone(normalized);
    AppStorage.setOrCreate(AppIconSettingsStore.KEY_ICON_ID, normalized.iconId);
    AppStorage.setOrCreate(AppIconSettingsStore.KEY_FOLLOW_THEME, normalized.followTheme);
    AppStorage.setOrCreate(AppIconSettingsStore.KEY_THEME_FOLLOW_MAP,
      AppIconSettingsStore.serializeThemeFollowMap(normalized.themeFollowMap));
  }

  /** 读取某个主题的「图标跟随」开关状态；未记录的主题默认跟随。 */
  static themeFollow(settings: AppIconSettings, themeId: string): boolean {
    const normalized = AppIconSettingsStore.normalizeIconId(themeId);
    const value = settings.themeFollowMap[normalized];
    return value === undefined ? true : value;
  }

  /** 持久化某个主题的「图标跟随」开关状态并同步到 AppStorage。 */
  static async setThemeFollow(context: Context, themeId: string, enabled: boolean): Promise<void> {
    const current = await AppIconSettingsStore.load(context);
    const normalized = AppIconSettingsStore.normalizeIconId(themeId);
    const map = AppIconSettingsStore.cloneMap(current.themeFollowMap);
    map[normalized] = enabled;
    const updated = new AppIconSettings();
    updated.iconId = current.iconId;
    updated.followTheme = current.followTheme;
    updated.themeFollowMap = map;
    AppIconSettingsStore.cachedSettings = AppIconSettingsStore.clone(updated);
    await AppIconSettingsStore.save(context, updated);
    AppIconSettingsStore.applyToStorage(updated);
  }

  private static parseThemeFollowMap(value: string): Record<string, boolean> {
    try {
      const parsed = JSON.parse(value) as Record<string, boolean>;
      if (parsed && typeof parsed === 'object') {
        return parsed;
      }
    } catch (e) {
      console.warn('[AppIconSettingsStore] parse themeFollowMap failed', JSON.stringify(e));
    }
    return {};
  }

  private static serializeThemeFollowMap(map: Record<string, boolean>): string {
    return JSON.stringify(map);
  }

  private static cloneMap(source: Record<string, boolean>): Record<string, boolean> {
    const result: Record<string, boolean> = {};
    for (const key of Object.keys(source)) {
      result[key] = source[key];
    }
    return result;
  }

  static normalizeIconId(value: string): string {
    const text = (value || '').trim();
    if (!text) {
      return AppIconSettingsStore.DEFAULT_ICON_ID;
    }
    return text;
  }

  private static async getString(
    store: preferences.Preferences,
    key: string,
    fallback: string
  ): Promise<string> {
    const value = await store.get(key, fallback);
    return typeof value === 'string' ? value : fallback;
  }

  private static async getBoolean(
    store: preferences.Preferences,
    key: string,
    fallback: boolean
  ): Promise<boolean> {
    const value = await store.get(key, fallback);
    return typeof value === 'boolean' ? value : fallback;
  }

  private static clone(source: AppIconSettings): AppIconSettings {
    const settings = new AppIconSettings();
    settings.iconId = AppIconSettingsStore.normalizeIconId(source.iconId);
    settings.followTheme = source.followTheme;
    settings.themeFollowMap = AppIconSettingsStore.cloneMap(source.themeFollowMap);
    return settings;
  }
}
