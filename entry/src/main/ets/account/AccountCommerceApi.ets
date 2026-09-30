import http from '@ohos.net.http';
import { util } from '@kit.ArkTS';
import { AccountCommerceConfig } from './AccountCommerceConfig';
import {
  AccountApiError,
  AccountSnapshot,
  ThemeCatalogResponse
} from './AccountCommerceModels';

class ApiErrorBody {
  code: string = '';
  message: string = '';
  retryAfter: number = 0;
}

export class AccountCommerceApi {
  static async fetchThemeCatalog(): Promise<ThemeCatalogResponse> {
    const value = await AccountCommerceApi.request('/v1/themes/catalog', 'GET', '', '');
    return JSON.parse(value) as ThemeCatalogResponse;
  }

  private static async request(path: string, method: string, body: string, sessionToken: string): Promise<string> {
    if (!AccountCommerceConfig.isServerConfigured()) {
      throw new AccountApiError('账号服务端尚未配置', 0, 'SERVER_NOT_CONFIGURED');
    }
    const client = http.createHttp();
    const headers: Record<string, string> = {
      'Accept': 'application/json',
      'Content-Type': 'application/json;charset=UTF-8',
      'Cache-Control': 'no-cache, no-store',
      'Pragma': 'no-cache'
    };
    if (sessionToken) {
      headers['Authorization'] = `Bearer ${sessionToken}`;
    }
    try {
      const response = await client.request(`${AccountCommerceConfig.API_BASE_URL}${path}`, {
        method: AccountCommerceApi.resolveMethod(method),
        header: headers,
        extraData: body || undefined,
        connectTimeout: 10000,
        readTimeout: 15000,
        expectDataType: http.HttpDataType.ARRAY_BUFFER
      });
      const statusCode = Number(response.responseCode);
      const value = AccountCommerceApi.responseText(response.result);
      if (statusCode < 200 || statusCode >= 300) {
        const error = AccountCommerceApi.parseError(value);
        throw new AccountApiError(
          error.message || `服务请求失败（${statusCode}）`,
          statusCode,
          error.code,
          error.retryAfter
        );
      }
      return value;
    } finally {
      client.destroy();
    }
  }

  private static resolveMethod(method: string): http.RequestMethod {
    if (method === 'GET') {
      return http.RequestMethod.GET;
    }
    return http.RequestMethod.POST;
  }

  private static responseText(result: string | Object | ArrayBuffer): string {
    if (typeof result === 'string') {
      return result;
    }
    if (result instanceof ArrayBuffer) {
      return util.TextDecoder.create('utf-8')
        .decodeWithStream(new Uint8Array(result), { stream: false });
    }
    if (result instanceof Uint8Array) {
      return util.TextDecoder.create('utf-8')
        .decodeWithStream(result, { stream: false });
    }
    return JSON.stringify(result);
  }

  private static parseError(value: string): ApiErrorBody {
    try {
      return JSON.parse(value) as ApiErrorBody;
    } catch (e) {
      const result = new ApiErrorBody();
      result.message = value;
      return result;
    }
  }
}
