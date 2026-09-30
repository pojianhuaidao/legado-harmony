export class AccountCommerceConfig {
  /**
   * Must be an HTTPS origin that hosts the companion service in /server.
   * Keep client secrets on that service only.
   */
  static readonly API_BASE_URL: string = '';
  static readonly THEME_PRICE_POINTS: number = 60;
  static readonly THEME_VALID_DAYS: number = 365;

  static isServerConfigured(): boolean {
    const value = AccountCommerceConfig.API_BASE_URL.trim();
    return value.startsWith('https://') && !value.includes('example.com');
  }
}
