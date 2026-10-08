import http from '@ohos.net.http';
import util from '@ohos.util';

/**
 * 云端 TTS 音色提供器（一期：小米 / 阿里百炼）。
 *
 * 两家厂商均采用 OpenAI 兼容接口 + Bearer Token 鉴权：
 *  - 阿里百炼：baseUrl https://dashscope.aliyuncs.com/compatible-mode/v1，
 *    TTS 模型 cosyvoice-v2，端点 /audio/speech（OpenAI 兼容语音合成）。
 *  - 小米：baseUrl https://api.xiaomimimo.com/v1，OpenAI 兼容端点 /audio/speech。
 *
 * 校验 API Key：GET {baseUrl}/models（OpenAI 兼容标准端点，两家均支持）。
 * 拉取音色列表：厂商暂未开放公开的“列出可用音色”REST 接口，因此在 Key 校验
 * 通过后返回厂商预设音色列表（阿里 CosyVoice 为官方真实音色 ID；小米以占位
 * 音色 ID 为准，用户可修改音色 ID / 接口地址后重新导入）。
 */

export interface CloudTtsPresetVoice {
  voice: string;
  name: string;
  gender: string;
  language: string;
}

export interface CloudTtsProviderInfo {
  provider: string;
  label: string;
  baseUrl: string;
  ttsModel: string;
  voices: CloudTtsPresetVoice[];
}

/** 持久化到 AppStorage / preferences 的云端音色连接数据（纯数据，可 JSON 序列化）。 */
export interface CloudTtsVoiceData {
  provider: string;
  label: string;
  baseUrl: string;
  model: string;
  voice: string;
  name: string;
  gender: string;
  language: string;
}

export interface CloudTtsSynthesizeOptions {
  text: string;
  baseUrl: string;
  model: string;
  apiKey: string;
  voice: string;
  speed: number;
}

export class CloudTtsVoiceProvider {
  static readonly PROVIDERS: Record<string, CloudTtsProviderInfo> = {
    'aliyun': {
      provider: 'aliyun',
      label: '阿里百炼',
      baseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
      ttsModel: 'cosyvoice-v2',
      voices: [
        { voice: 'longxiaochun', name: '龙小淳（女声）', gender: 'female', language: 'zh-CN' },
        { voice: 'longxiaoxia', name: '龙小夏（女声）', gender: 'female', language: 'zh-CN' },
        { voice: 'longshu', name: '龙书（男声）', gender: 'male', language: 'zh-CN' },
        { voice: 'longwan', name: '龙婉（女声）', gender: 'female', language: 'zh-CN' },
        { voice: 'longxiang', name: '龙翔（男声）', gender: 'male', language: 'zh-CN' },
        { voice: 'longchen', name: '龙辰（男声）', gender: 'male', language: 'zh-CN' },
        { voice: 'longchun', name: '龙春（男声）', gender: 'male', language: 'zh-CN' },
        { voice: 'longyan', name: '龙研（女声）', gender: 'female', language: 'zh-CN' }
      ]
    },
    'xiaomi': {
      provider: 'xiaomi',
      label: '小米',
      baseUrl: 'https://api.xiaomimimo.com/v1',
      ttsModel: 'tts',
      voices: [
        { voice: 'xiaomi-female', name: '小米女声', gender: 'female', language: 'zh-CN' },
        { voice: 'xiaomi-male', name: '小米男声', gender: 'male', language: 'zh-CN' }
      ]
    }
  };

  static providerList(): string[] {
    return Object.keys(CloudTtsVoiceProvider.PROVIDERS);
  }

  static providerInfo(provider: string): CloudTtsProviderInfo {
    const info = CloudTtsVoiceProvider.PROVIDERS[provider];
    if (!info) {
      return CloudTtsVoiceProvider.PROVIDERS['aliyun'];
    }
    return info;
  }

  static providerLabel(provider: string): string {
    return CloudTtsVoiceProvider.providerInfo(provider).label;
  }

  static defaultModel(provider: string): string {
    return CloudTtsVoiceProvider.providerInfo(provider).ttsModel;
  }

  /**
   * 校验 API Key：请求 OpenAI 兼容的 /models 端点。
   * 200 = Key 有效；401/403 = Key 无效；其他 = 网络或服务异常。
   */
  static async validateApiKey(provider: string, apiKey: string, baseUrl: string): Promise<void> {
    const url = CloudTtsVoiceProvider.normalizeBaseUrl(baseUrl) + '/models';
    const httpRequest = http.createHttp();
    try {
      const response = await CloudTtsVoiceProvider.withTimeout(
        httpRequest.request(url, {
          method: http.RequestMethod.GET,
          header: {
            'Authorization': 'Bearer ' + apiKey
          },
          connectTimeout: 15000,
          readTimeout: 30000
        }),
        40000,
        'API Key 校验超时',
        () => {
          httpRequest.destroy();
        }
      );
      if (response.responseCode === 200) {
        return;
      }
      if (response.responseCode === 401 || response.responseCode === 403) {
        throw new Error('API Key 无效，请检查是否输入正确');
      }
      const bodyText = typeof response.result === 'string' ? response.result : '';
      throw new Error('API Key 校验失败（HTTP ' + response.responseCode + '）' +
        (bodyText ? ': ' + bodyText.substring(0, 200) : ''));
    } finally {
      httpRequest.destroy();
    }
  }

  /**
   * 拉取可用音色列表：校验 Key 通过后返回厂商预设音色。
   * 厂商暂未开放公开的列表接口，预设列表即“可导入为音色连接”的音色集合。
   */
  static async fetchVoices(provider: string, apiKey: string, baseUrl: string): Promise<CloudTtsVoiceData[]> {
    const info = CloudTtsVoiceProvider.providerInfo(provider);
    const effectiveBaseUrl = CloudTtsVoiceProvider.normalizeBaseUrl(baseUrl);
    await CloudTtsVoiceProvider.validateApiKey(provider, apiKey, effectiveBaseUrl);
    const data: CloudTtsVoiceData[] = [];
    for (const preset of info.voices) {
      data.push({
        provider: provider,
        label: info.label,
        baseUrl: effectiveBaseUrl,
        model: info.ttsModel,
        voice: preset.voice,
        name: preset.name,
        gender: preset.gender,
        language: preset.language
      });
    }
    return data;
  }

  /**
   * 云端语音合成（OpenAI 兼容 /audio/speech），返回音频二进制数据（wav）。
   */
  static async synthesize(options: CloudTtsSynthesizeOptions): Promise<ArrayBuffer> {
    const url = CloudTtsVoiceProvider.normalizeBaseUrl(options.baseUrl) + '/audio/speech';
    const payload: Record<string, string | number> = {
      'model': options.model,
      'input': options.text,
      'voice': options.voice,
      'response_format': 'wav',
      'speed': options.speed
    };
    const httpRequest = http.createHttp();
    try {
      const response = await CloudTtsVoiceProvider.withTimeout(
        httpRequest.request(url, {
          method: http.RequestMethod.POST,
          header: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ' + options.apiKey
          },
          extraData: JSON.stringify(payload),
          connectTimeout: 20000,
          readTimeout: 120000
        }),
        130000,
        '云端语音合成超时（120s 无响应）',
        () => {
          httpRequest.destroy();
        }
      );
      if (response.responseCode !== 200) {
        const bodyText = typeof response.result === 'string' ? response.result : '';
        throw new Error('语音合成失败（HTTP ' + response.responseCode + '）' +
          (bodyText ? ': ' + bodyText.substring(0, 300) : ''));
      }
      const result = response.result;
      if (result instanceof ArrayBuffer) {
        return result;
      }
      if (typeof result === 'string') {
        // 某些实现以字符串返回二进制（可能被编码为 UTF-8 文本流）。
        // 直接按文本 UTF-8 转字节，仍可作为音频缓存写入（wav 头可被 AVPlayer 识别）。
        const encoder = new util.TextEncoder();
        return encoder.encodeInto(result).buffer;
      }
      throw new Error('语音合成返回数据格式异常');
    } finally {
      httpRequest.destroy();
    }
  }

  static normalizeBaseUrl(baseUrl: string): string {
    return (baseUrl || '').trim().replace(/\/+$/, '');
  }

  private static withTimeout<T>(promise: Promise<T>, ms: number, message: string,
    onTimeout: () => void): Promise<T> {
    return new Promise<T>((resolve: (value: T) => void, reject: (reason: Object) => void) => {
      const timer = setTimeout(() => {
        onTimeout();
        reject(new Error(message));
      }, ms);
      promise.then((value: T) => {
        clearTimeout(timer);
        resolve(value);
      }, (reason: Object) => {
        clearTimeout(timer);
        reject(reason);
      });
    });
  }
}
