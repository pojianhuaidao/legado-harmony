export class ThemeEntitlement {
  themeId: string = '';
  expiresAt: number = 0;
}

export class ThemeCatalogItem {
  themeId: string = '';
  displayName: string = '';
  pricePoints: number = 60;
  validDays: number = 365;
}

export class ThemeCatalogResponse {
  themes: ThemeCatalogItem[] = [];
}

export class AccountSnapshot {
  userId: string = '';
  displayName: string = '华为用户';
  avatarUrl: string = '';
  points: number = 0;
  paidPoints: number = 0;
  promoPoints: number = 0;
  iapDebtPoints: number = 0;
  welcomeGranted: boolean = false;
  entitlements: ThemeEntitlement[] = [];
}

export class AccountApiError extends Error {
  statusCode: number = 0;
  errorCode: string = '';
  retryAfterSeconds: number = 0;

  constructor(message: string, statusCode: number = 0, errorCode: string = '',
    retryAfterSeconds: number = 0) {
    super(message);
    this.name = 'AccountApiError';
    this.statusCode = statusCode;
    this.errorCode = errorCode;
    this.retryAfterSeconds = Math.max(0, Math.floor(Number(retryAfterSeconds) || 0));
  }
}
