import http from '@ohos.net.http';
import util from '@ohos.util';

/**
 * 云端 TTS 音色提供器（一期：小米 / 阿里百炼）。
 *
 * 两家厂商均采用 OpenAI 兼容接口 + Bearer Token 鉴权：
 *  - 阿里百炼：baseUrl https://dashscope.aliyuncs.com/compatible-mode/v1，
 *    TTS 模型 cosyvoice-v2，端点 /audio/speech（OpenAI 兼容语音合成）。
 *  - 小米：baseUrl https://api.xiaomimimo.com/v1，OpenAI 兼容 chat/completions（MiMo-V2.5-TTS）。
 *
 * 校验 API Key：GET {baseUrl}/models（OpenAI 兼容标准端点，两家均支持）。
 * 拉取音色列表：厂商暂未开放公开的“列出可用音色”REST 接口，因此在 Key 校验
 * 通过后返回厂商预设音色列表（阿里 CosyVoice 为官方真实音色 ID；小米为官方
 * 预置音色 mimo_default/茉莉/苏打/白桦/Mia/Chloe/Milo/Dean）。
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
  provider: string;
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
      ttsModel: 'mimo-v2.5-tts',
      voices: [
        { voice: 'mimo_default', name: '小米默认（冰糖）', gender: 'female', language: 'zh-CN' },
        { voice: '茉莉', name: '茉莉', gender: 'female', language: 'zh-CN' },
        { voice: '苏打', name: '苏打', gender: 'male', language: 'zh-CN' },
        { voice: '白桦', name: '白桦', gender: 'male', language: 'zh-CN' },
        { voice: 'Mia', name: 'Mia', gender: 'female', language: 'en-US' },
        { voice: 'Chloe', name: 'Chloe', gender: 'female', language: 'en-US' },
        { voice: 'Milo', name: 'Milo', gender: 'male', language: 'en-US' },
        { voice: 'Dean', name: 'Dean', gender: 'male', language: 'en-US' }
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
   * 云端语音合成，返回音频二进制数据（wav）。
   * - 小米 MiMo：OpenAI 兼容 chat/completions（文本放 assistant 消息，音色走 audio 参数），
   *   响应 JSON 的 choices[0].message.audio.data 为 base64 音频。
   * - 阿里百炼等：OpenAI 兼容 /audio/speech，直接返回音频流。
   */
  static async synthesize(options: CloudTtsSynthesizeOptions): Promise<ArrayBuffer> {
    const baseUrl = CloudTtsVoiceProvider.normalizeBaseUrl(options.baseUrl);
    const httpRequest = http.createHttp();
    try {
      if (options.provider === 'xiaomi') {
        return await CloudTtsVoiceProvider.synthesizeViaChat(options, baseUrl, httpRequest);
      }
      const url = baseUrl + '/audio/speech';
      const payload: Record<string, string | number> = {
        'model': options.model,
        'input': options.text,
        'voice': options.voice,
        'response_format': 'wav',
        'speed': options.speed
      };
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

  /**
   * 小米 MiMo TTS 合成：POST {baseUrl}/chat/completions，解析 JSON 内嵌 base64 音频。
   */
  private static async synthesizeViaChat(options: CloudTtsSynthesizeOptions, baseUrl: string,
    httpRequest: http.HttpRequest): Promise<ArrayBuffer> {
    const speedHint = options.speed <= 0.8 ? '语速稍慢' : (options.speed >= 1.2 ? '语速稍快' : '语速适中');
    const payload: Record<string, Object> = {
      'model': options.model,
      'messages': [
        { 'role': 'user', 'content': speedHint },
        { 'role': 'assistant', 'content': options.text }
      ],
      'audio': {
        'format': 'wav',
        'voice': options.voice
      }
    };
    const response = await CloudTtsVoiceProvider.withTimeout(
      httpRequest.request(baseUrl + '/chat/completions', {
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
    if (typeof response.result !== 'string') {
      throw new Error('语音合成返回数据格式异常');
    }
    const json = JSON.parse(response.result) as Record<string, Object>;
    const choices = json['choices'] as Array<Record<string, Object>>;
    const message = choices && choices.length > 0 ? choices[0]['message'] as Record<string, Object> : undefined;
    const audioData = message ? message['audio'] as Record<string, Object> : undefined;
    const data = audioData ? audioData['data'] as string : undefined;
    if (typeof data !== 'string' || data.length === 0) {
      throw new Error('语音合成返回中缺少音频数据');
    }
    const base64 = new util.Base64Helper();
    const bytes = base64.decodeSync(data);
    const out = new ArrayBuffer(bytes.byteLength);
    new Uint8Array(out).set(bytes);
    return out;
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
