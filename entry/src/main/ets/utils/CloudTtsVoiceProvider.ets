import http from '@ohos.net.http';
import webSocket from '@ohos.net.webSocket';
import util from '@ohos.util';
import { BusinessError } from '@ohos.base';

/**
 * 云端 TTS 音色提供器（二期：小米 / 阿里百炼 / 火山豆包 / 微软在线）。
 *
 *  - 阿里百炼：OpenAI 兼容接口 + Bearer Token，TTS 模型 cosyvoice-v2，端点 /audio/speech。
 *  - 小米：OpenAI 兼容 chat/completions（MiMo-V2.5-TTS）。
 *  - 火山豆包：HTTP POST 到 openspeech.bytedance.com/api/v1/tts，
 *    鉴权头 Authorization: Bearer; {AppID} 与 X-Apikey: Bearer; {AccessToken}，
 *    响应 JSON code==3000 时 data 为 base64 音频（mp3）。
 *  - 微软在线（轻悦同款）：免 Key，WebSocket 连接微软 bing speech 接口，
 *    先发二进制 speech.config，再发 SSML 文本请求，累积音频帧直至 turn.end。
 *
 * 校验 API Key：xiaomi/aliyun 走 GET {baseUrl}/models（OpenAI 兼容标准端点）；
 * volcano 用极短文本走 synthesize 校验；edge 免 Key 直接成功。
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

/** 微软 Edge speech.config 二进制消息中的 JSON 配置结构。 */
interface EdgeSpeechConfigAppPayload {
  name: string;
}

interface EdgeSpeechMetadataOptionsPayload {
  sentenceBoundaryEnabled: string;
  wordBoundaryEnabled: string;
}

interface EdgeSpeechAudioPayload {
  metadataoptions: EdgeSpeechMetadataOptionsPayload;
  outputFormat: string;
}

interface EdgeSpeechSynthesisPayload {
  audio: EdgeSpeechAudioPayload;
}

interface EdgeSpeechTtsPayload {
  stream: string;
}

interface EdgeSpeechContextPayload {
  synthesis: EdgeSpeechSynthesisPayload;
  tts: EdgeSpeechTtsPayload;
}

interface EdgeSpeechConfigPayload {
  contexts: EdgeSpeechContextPayload[];
  os: string;
  app: EdgeSpeechConfigAppPayload;
  secmsgecv: string;
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
    },
    'edge': {
      provider: 'edge',
      label: '微软在线（轻悦同款）',
      baseUrl: 'wss://speech.platform.bing.com/consumer/speech/synthesize/readaloud/edge/v1?TrustedClientToken=6A5AA1D4EAFF4E9FB37E23D68491D6F4',
      ttsModel: '',
      voices: [
        { voice: 'zh-CN-XiaoxiaoNeural', name: '晓晓', gender: 'female', language: 'zh-CN' },
        { voice: 'zh-CN-XiaoyiNeural', name: '晓伊', gender: 'female', language: 'zh-CN' },
        { voice: 'zh-CN-YunxiNeural', name: '云希', gender: 'male', language: 'zh-CN' },
        { voice: 'zh-CN-YunjianNeural', name: '云健', gender: 'male', language: 'zh-CN' },
        { voice: 'zh-CN-YunyangNeural', name: '云扬', gender: 'male', language: 'zh-CN' },
        { voice: 'zh-CN-YunxiaNeural', name: '云夏', gender: 'male', language: 'zh-CN' },
        { voice: 'zh-CN-liaoning-XiaobeiNeural', name: '小蓓', gender: 'female', language: 'zh-CN' },
        { voice: 'zh-CN-shaanxi-XiaoniNeural', name: '小妮', gender: 'female', language: 'zh-CN' }
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
   * - edge：免 Key，直接成功。
   */
  static async validateApiKey(provider: string, apiKey: string, baseUrl: string, appId?: string): Promise<void> {
    if (provider === 'edge') {
      return;
    }
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
   * - edge：免 Key，无需校验直接返回预设音色。
   * - volcano：用 appId + accessToken 校验后返回预设音色。
   * - xiaomi / aliyun：校验 API Key 后返回预设音色。
   */
  static async fetchVoices(provider: string, apiKey: string, baseUrl: string, appId?: string): Promise<CloudTtsVoiceData[]> {
    const info = CloudTtsVoiceProvider.providerInfo(provider);
    const effectiveBaseUrl = provider === 'edge'
      ? info.baseUrl
      : CloudTtsVoiceProvider.normalizeBaseUrl(baseUrl);
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
   * - 微软 Edge 在线：WebSocket wss 连接，speech.config + SSML 文本，按 audio+ 二进制帧累积音频。
   */
  static async synthesize(options: CloudTtsSynthesizeOptions): Promise<ArrayBuffer> {
    if (options.provider === 'edge') {
      return CloudTtsVoiceProvider.synthesizeViaEdge(options);
    }
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

  /**
   * 微软 Edge 在线 TTS 合成（免 Key）：WebSocket 连接 bing speech 端点，
   * 先发二进制 speech.config，再发 SSML 文本，接收 audio+ 二进制帧累积 mp3，
   * 收到 turn.end 后关闭连接并返回累积音频。
   */
  private static async synthesizeViaEdge(options: CloudTtsSynthesizeOptions): Promise<ArrayBuffer> {
    const token = '6A5AA1D4EAFF4E9FB37E23D68491D6F4';
    const connectionId = CloudTtsVoiceProvider.randomUuid();
    const url = 'wss://speech.platform.bing.com/consumer/speech/synthesize/readaloud/edge/v1' +
      '?TrustedClientToken=' + token + '&ConnectionId=' + connectionId;
    const ws = webSocket.createWebSocket();
    let audioChunks: ArrayBuffer[] = [];
    let textBuffer = '';
    let closedByError = false;
    try {
      const openResult = await CloudTtsVoiceProvider.withPromise(ws.connect(url, {}), 15000,
        '连接微软在线音色服务超时', () => {
          closedByError = true;
          try {
            ws.close();
          } catch (_) {
          }
        });
      if (!openResult) {
        throw new Error('连接微软在线音色服务失败（code=' + String(openResult) + '）');
      }
      // 发送 speech.config 二进制消息：4 字节头 + JSON 配置
      const config: EdgeSpeechConfigPayload = {
        'contexts': [{
          'synthesis': {
            'audio': {
              'metadataoptions': {
                'sentenceBoundaryEnabled': 'false',
                'wordBoundaryEnabled': 'true'
              },
              'outputFormat': 'audio-24khz-48kbitrate-mono-mp3'
            }
          },
          'tts': {
            'stream': 'turn-based'
          }
        }],
        'os': 'windows',
        'app': {
          'name': 'edge'
        },
        'secmsgecv': 'true'
      };
      const configJson = JSON.stringify(config);
      const configBytes = new ArrayBuffer(4 + configJson.length);
      const configView = new Uint8Array(configBytes);
      configView[0] = 0x01;
      configView[1] = 0x00;
      configView[2] = 0x00;
      configView[3] = 0x00;
      for (let i = 0; i < configJson.length; i++) {
        configView[4 + i] = configJson.charCodeAt(i) & 0xFF;
      }
      await CloudTtsVoiceProvider.withPromise(ws.send(configBytes), 10000,
        '发送微软在线音色配置超时', () => {
          closedByError = true;
          try {
            ws.close();
          } catch (_) {
          }
        });
      // 发送 SSML 文本消息
      const escapedText = CloudTtsVoiceProvider.escapeXml(options.text);
      const ssml = "<speak version='1.0' xmlns='http://www.w3.org/2001/10/synthesis' xml:lang='zh-CN'>" +
        "<prosody rate='+0%' volume='+0%' pitch='+0Hz'>" + escapedText + '</prosody></speak>';
      const ttsMessage = JSON.stringify({
        'type': 'tts',
        'voice': options.voice,
        'text': ssml
      });
      await CloudTtsVoiceProvider.withPromise(ws.send(ttsMessage), 10000,
        '发送微软在线音色请求超时', () => {
          closedByError = true;
          try {
            ws.close();
          } catch (_) {
          }
        });
      // 接收音频帧直至 turn.end
      const deadline = Date.now() + 120000;
      let receivedAny = false;
      while (Date.now() < deadline) {
        const message = await CloudTtsVoiceProvider.waitEdgeMessage(ws, 60000);
        receivedAny = true;
        if (message instanceof ArrayBuffer) {
          CloudTtsVoiceProvider.appendEdgeAudioFrame(message, audioChunks);
        } else if (typeof message === 'string') {
          textBuffer += message;
          CloudTtsVoiceProvider.consumeEdgeTextBuffer(textBuffer, audioChunks);
          if (CloudTtsVoiceProvider.edgeTurnEnded(textBuffer)) {
            break;
          }
        } else {
          throw new Error('微软在线音色返回未知数据类型');
        }
      }
      if (!receivedAny) {
        throw new Error('微软在线音色服务未返回任何数据');
      }
      if (audioChunks.length === 0) {
        throw new Error('微软在线音色合成失败：未收到音频数据');
      }
      // 合并所有音频块
      let total = 0;
      for (const chunk of audioChunks) {
        total += chunk.byteLength;
      }
      const merged = new ArrayBuffer(total);
      const mergedView = new Uint8Array(merged);
      let offset = 0;
      for (const chunk of audioChunks) {
        mergedView.set(new Uint8Array(chunk), offset);
        offset += chunk.byteLength;
      }
      return merged;
    } finally {
      if (!closedByError) {
        try {
          ws.close();
        } catch (_) {
        }
      }
    }
  }

  /** 等待下一帧 WebSocket 消息：注册一次性 message 回调，超时或出错时拒绝。 */
  private static waitEdgeMessage(ws: webSocket.WebSocket,
    timeoutMs: number): Promise<string | ArrayBuffer> {
    return new Promise<string | ArrayBuffer>((resolve: (value: string | ArrayBuffer) => void,
      reject: (reason: Object) => void) => {
      let settled = false;
      const timer = setTimeout(() => {
        if (!settled) {
          settled = true;
          reject(new Error('等待微软在线音色响应超时'));
        }
      }, timeoutMs);
      ws.on('message', (err: BusinessError, data: string | ArrayBuffer) => {
        if (settled) {
          return;
        }
        settled = true;
        clearTimeout(timer);
        if (err) {
          reject(new Error('微软在线音色连接异常：' + err.message));
          return;
        }
        resolve(data);
      });
    });
  }

  private static appendEdgeAudioFrame(message: ArrayBuffer, audioChunks: ArrayBuffer[]): void {
    // 二进制帧直接按 Path:xxx\r\n\r\n + 音频 解析
    const bytes = new Uint8Array(message);
    let headerEnd = -1;
    for (let i = 0; i < bytes.length - 3; i++) {
      if (bytes[i] === 0x0D && bytes[i + 1] === 0x0A && bytes[i + 2] === 0x0D && bytes[i + 3] === 0x0A) {
        headerEnd = i + 4;
        break;
      }
    }
    if (headerEnd < 0) {
      return;
    }
    let headerText = '';
    for (let i = 0; i < headerEnd; i++) {
      headerText += String.fromCharCode(bytes[i]);
    }
    if (headerText.indexOf('audio+24khz-48kbitrate-mono-mp3') >= 0 && headerEnd < bytes.length) {
      const audio = new ArrayBuffer(bytes.length - headerEnd);
      new Uint8Array(audio).set(bytes.subarray(headerEnd));
      audioChunks.push(audio);
    }
  }

  private static consumeEdgeTextBuffer(textBuffer: string, audioChunks: ArrayBuffer[]): void {
    // 文本帧可能包含 Path:xxx\r\n\r\n 前缀 + 音频（以字符串形式截断到达时，音频按 string 传入，
    // 这里仅处理 Path 头后跟音频文本的情况，按字符转字节保留）。
    const idx = textBuffer.indexOf('Path:audio+24khz-48kbitrate-mono-mp3');
    if (idx >= 0) {
      const headerEnd = textBuffer.indexOf('\r\n\r\n', idx);
      if (headerEnd >= 0 && headerEnd + 4 < textBuffer.length) {
        const audioText = textBuffer.substring(headerEnd + 4);
        if (audioText.length > 0) {
          const bytes = new ArrayBuffer(audioText.length);
          const view = new Uint8Array(bytes);
          for (let i = 0; i < audioText.length; i++) {
            view[i] = audioText.charCodeAt(i) & 0xFF;
          }
          audioChunks.push(bytes);
        }
      }
    }
  }

  private static edgeTurnEnded(textBuffer: string): boolean {
    return textBuffer.indexOf('turn.end') >= 0;
  }

  private static escapeXml(text: string): string {
    return (text || '')
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&apos;');
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
