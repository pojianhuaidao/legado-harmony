import http from '@ohos.net.http';
import util from '@ohos.util';
import { BusinessError } from '@ohos.base';

/**
 * 云端 TTS 音色提供器（小米 / 阿里百炼 / 火山豆包）。
 *
 *  - 阿里百炼：OpenAI 兼容接口 + Bearer Token，TTS 模型 cosyvoice-v2，端点 /audio/speech。
 *  - 小米：OpenAI 兼容 chat/completions（MiMo-V2.5-TTS）。
 *  - 火山豆包：HTTP POST 到 openspeech.bytedance.com/api/v1/tts，
 *    鉴权头 Authorization: Bearer; {AppID} 与 X-Apikey: Bearer; {AccessToken}，
 *    响应 JSON code==3000 时 data 为 base64 音频（mp3）。
 *
 * 校验 API Key：xiaomi/aliyun 走 GET {baseUrl}/models（OpenAI 兼容标准端点）；
 * volcano 用极短文本走 synthesize 校验。
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
  /** 火山引擎 App ID（仅 volcano 厂商使用，用于 Bearer 鉴权头）。 */
  appId?: string;
}

export interface CloudTtsSynthesizeOptions {
  provider: string;
  text: string;
  baseUrl: string;
  model: string;
  apiKey: string;
  voice: string;
  speed: number;
  /** 火山引擎 App ID（仅 volcano 厂商使用）。 */
  appId?: string;
}

/** 火山豆包 TTS 请求体结构（ArkTS 严格模式显式类型标注）。 */
interface VolcanoTtsAppPayload {
  appid: string;
  token: string;
  cluster: string;
}

interface VolcanoTtsUserPayload {
  uid: string;
}

interface VolcanoTtsAudioPayload {
  voice_type: string;
  encoding: string;
  speed_ratio: number;
  volume_ratio: number;
  pitch_ratio: number;
}

interface VolcanoTtsRequestPayloadBody {
  reqid: string;
  text: string;
  operation: string;
}

interface VolcanoTtsRequestPayload {
  app: VolcanoTtsAppPayload;
  user: VolcanoTtsUserPayload;
  audio: VolcanoTtsAudioPayload;
  request: VolcanoTtsRequestPayloadBody;
}

/** 小米 MiMo chat/completions 请求体结构。 */
interface ChatTtsAudioPayload {
  format: string;
  voice: string;
}

interface ChatTtsMessagePayload {
  role: string;
  content: string;
}

interface ChatTtsRequestPayload {
  model: string;
  messages: ChatTtsMessagePayload[];
  audio: ChatTtsAudioPayload;
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
    },
    'volcano': {
      provider: 'volcano',
      label: '火山豆包',
      baseUrl: 'https://openspeech.bytedance.com/api/v1/tts',
      ttsModel: 'volcano_tts',
      voices: [
        { voice: 'BV700_V2_streaming', name: '灿灿 2.0', gender: 'female', language: 'zh-CN' },
        { voice: 'BV705_streaming', name: '炀炀', gender: 'female', language: 'zh-CN' },
        { voice: 'BV701_V2_streaming', name: '擎苍 2.0', gender: 'male', language: 'zh-CN' },
        { voice: 'BV001_V2_streaming', name: '通用女声 2.0', gender: 'female', language: 'zh-CN' },
        { voice: 'BV700_streaming', name: '灿灿', gender: 'female', language: 'zh-CN' },
        { voice: 'BV406_V2_streaming', name: '超自然音色-梓梓 2.0', gender: 'female', language: 'zh-CN' },
        { voice: 'BV407_V2_streaming', name: '超自然音色-燃燃 2.0', gender: 'male', language: 'zh-CN' },
        { voice: 'BV001_streaming', name: '通用女声', gender: 'female', language: 'zh-CN' },
        { voice: 'BV002_streaming', name: '通用男声', gender: 'male', language: 'zh-CN' },
        { voice: 'BV701_streaming', name: '擎苍', gender: 'male', language: 'zh-CN' },
        { voice: 'BV123_streaming', name: '阳光青年', gender: 'male', language: 'zh-CN' },
        { voice: 'BV120_streaming', name: '反卷青年', gender: 'male', language: 'zh-CN' },
        { voice: 'BV119_streaming', name: '通用赘婿', gender: 'male', language: 'zh-CN' },
        { voice: 'BV115_streaming', name: '古风少御', gender: 'female', language: 'zh-CN' },
        { voice: 'BV107_streaming', name: '霸气青叔', gender: 'male', language: 'zh-CN' },
        { voice: 'BV100_streaming', name: '质朴青年', gender: 'male', language: 'zh-CN' },
        { voice: 'BV104_streaming', name: '温柔淑女', gender: 'female', language: 'zh-CN' },
        { voice: 'BV004_streaming', name: '开朗青年', gender: 'male', language: 'zh-CN' },
        { voice: 'BV113_streaming', name: '甜宠少御', gender: 'female', language: 'zh-CN' },
        { voice: 'BV102_streaming', name: '儒雅青年', gender: 'male', language: 'zh-CN' },
        { voice: 'BV405_streaming', name: '甜美小源', gender: 'female', language: 'zh-CN' },
        { voice: 'BV009_streaming', name: '知性女声', gender: 'female', language: 'zh-CN' },
        { voice: 'BV008_streaming', name: '亲切男声', gender: 'male', language: 'zh-CN' },
        { voice: 'BV419_streaming', name: '诚诚', gender: 'male', language: 'zh-CN' },
        { voice: 'BV415_streaming', name: '童童', gender: 'male', language: 'zh-CN' }
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
   * 校验 API Key。
   * - xiaomi / aliyun：请求 OpenAI 兼容的 /models 端点，200 = 有效。
   * - volcano：用极短文本走 synthesize 校验，code==3000 即成功。
   */
  static async validateApiKey(provider: string, apiKey: string, baseUrl: string, appId?: string): Promise<void> {
    if (provider === 'volcano') {
      await CloudTtsVoiceProvider.synthesize({
        provider: 'volcano',
        text: '测试',
        baseUrl: baseUrl,
        model: CloudTtsVoiceProvider.providerInfo('volcano').ttsModel,
        apiKey: apiKey,
        voice: 'BV700_streaming',
        speed: 1,
        appId: appId || ''
      });
      return;
    }
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
   * 拉取可用音色列表：校验通过后返回厂商预设音色。
   * - volcano：用 appId + accessToken 校验后返回预设音色。
   * - xiaomi / aliyun：校验 API Key 后返回预设音色。
   */
  static async fetchVoices(provider: string, apiKey: string, baseUrl: string, appId?: string): Promise<CloudTtsVoiceData[]> {
    const info = CloudTtsVoiceProvider.providerInfo(provider);
    const effectiveBaseUrl = CloudTtsVoiceProvider.normalizeBaseUrl(baseUrl);
    await CloudTtsVoiceProvider.validateApiKey(provider, apiKey, effectiveBaseUrl, appId);
    const data: CloudTtsVoiceData[] = [];
    for (const preset of info.voices) {
      const entry: CloudTtsVoiceData = {
        provider: provider,
        label: info.label,
        baseUrl: effectiveBaseUrl,
        model: info.ttsModel,
        voice: preset.voice,
        name: preset.name,
        gender: preset.gender,
        language: preset.language
      };
      if (provider === 'volcano') {
        entry.appId = appId || '';
      }
      data.push(entry);
    }
    return data;
  }

  /**
   * 云端语音合成，返回音频二进制数据（wav / mp3）。
   * - 小米 MiMo：OpenAI 兼容 chat/completions（文本放 assistant 消息，音色走 audio 参数），
   *   响应 JSON 的 choices[0].message.audio.data 为 base64 音频。
   * - 阿里百炼等：OpenAI 兼容 /audio/speech，直接返回音频流。
   * - 火山引擎豆包：POST {baseUrl}，Bearer; appId + X-Apikey: Bearer; token 双凭证，
   *   响应 JSON code==3000 时 data 为 base64 音频。
   */
  static async synthesize(options: CloudTtsSynthesizeOptions): Promise<ArrayBuffer> {
    if (options.provider === 'volcano') {
      return CloudTtsVoiceProvider.synthesizeViaVolcano(options);
    }
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
   * 火山引擎豆包 TTS 合成：POST https://openspeech.bytedance.com/api/v1/tts，
   * 鉴权头为 'Authorization: Bearer; {appId}' 与 'X-Apikey: Bearer; {accessToken}'，
   * 响应 JSON code==3000 时 data 为 base64 音频（mp3）。
   */
  private static async synthesizeViaVolcano(options: CloudTtsSynthesizeOptions): Promise<ArrayBuffer> {
    const baseUrl = CloudTtsVoiceProvider.normalizeBaseUrl(options.baseUrl);
    const appId = (options.appId || '').trim();
    const accessToken = (options.apiKey || '').trim();
    if (!appId || !accessToken) {
      throw new Error('火山豆包需要同时配置 App ID 与 Access Token');
    }
    const reqId = CloudTtsVoiceProvider.randomReqId();
    const cluster = (options.model || '').trim() || 'volcano_tts';
    const payload: VolcanoTtsRequestPayload = {
      'app': {
        'appid': appId,
        'token': accessToken,
        'cluster': cluster
      },
      'user': {
        'uid': 'legado_tts'
      },
      'audio': {
        'voice_type': options.voice,
        'encoding': 'mp3',
        'speed_ratio': options.speed,
        'volume_ratio': 1.0,
        'pitch_ratio': 1.0
      },
      'request': {
        'reqid': reqId,
        'text': options.text,
        'operation': 'query'
      }
    };
    const httpRequest = http.createHttp();
    try {
      const response = await CloudTtsVoiceProvider.withTimeout(
        httpRequest.request(baseUrl, {
          method: http.RequestMethod.POST,
          header: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer; ' + appId,
            'X-Apikey': 'Bearer; ' + accessToken
          },
          extraData: JSON.stringify(payload),
          connectTimeout: 20000,
          readTimeout: 120000
        }),
        130000,
        '火山语音合成超时（120s 无响应）',
        () => {
          httpRequest.destroy();
        }
      );
      if (response.responseCode !== 200) {
        const bodyText = typeof response.result === 'string' ? response.result : '';
        throw new Error('火山语音合成失败（HTTP ' + response.responseCode + '）' +
          (bodyText ? ': ' + bodyText.substring(0, 300) : ''));
      }
      if (typeof response.result !== 'string') {
        throw new Error('火山语音合成返回数据格式异常');
      }
      const json = JSON.parse(response.result) as Record<string, Object>;
      const code = json['code'] as number;
      const message = (json['message'] as string) || '未知错误';
      if (code !== 3000) {
        throw new Error('火山语音合成失败：' + message + '（code=' + String(code) + '）');
      }
      const data = json['data'] as string;
      if (typeof data !== 'string' || data.length === 0) {
        throw new Error('火山语音合成返回中缺少音频数据');
      }
      const base64 = new util.Base64Helper();
      const bytes = base64.decodeSync(data);
      const out = new ArrayBuffer(bytes.byteLength);
      new Uint8Array(out).set(bytes);
      return out;
    } finally {
      httpRequest.destroy();
    }
  }

  private static randomReqId(): string {
    return 'legado_' + Date.now().toString() + '_' + Math.floor(Math.random() * 1000000).toString();
  }

  private static randomUuid(): string {
    let hex = '';
    for (let i = 0; i < 32; i++) {
      hex += Math.floor(Math.random() * 16).toString(16);
    }
    return hex.substring(0, 8) + '-' + hex.substring(8, 12) + '-' + hex.substring(12, 16) + '-' +
      hex.substring(16, 20) + '-' + hex.substring(20);
  }

  private static withPromise<T>(promise: Promise<T>, ms: number, message: string,
    onTimeout: () => void): Promise<T> {
    return new Promise<T>((resolve: (value: T) => void, reject: (reason: Object) => void) => {
      let settled = false;
      const timer = setTimeout(() => {
        if (!settled) {
          settled = true;
          onTimeout();
          reject(new Error(message));
        }
      }, ms);
      promise.then((value: T) => {
        if (!settled) {
          settled = true;
          clearTimeout(timer);
          resolve(value);
        }
      }, (reason: Object) => {
        if (!settled) {
          settled = true;
          clearTimeout(timer);
          reject(reason);
        }
      });
    });
  }

  /**
   * 小米 MiMo TTS 合成：POST {baseUrl}/chat/completions，解析 JSON 内嵌 base64 音频。
   */
  private static async synthesizeViaChat(options: CloudTtsSynthesizeOptions, baseUrl: string,
    httpRequest: http.HttpRequest): Promise<ArrayBuffer> {
    const speedHint = options.speed <= 0.8 ? '语速稍慢' : (options.speed >= 1.2 ? '语速稍快' : '语速适中');
    const payload: ChatTtsRequestPayload = {
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
