/**
 * 云端 LLM 角色标注器（分角色朗读专用）。
 *
 * 多厂商抽象：OpenAI 兼容接口，内置 智谱/阿里/小米/DeepSeek/硅基流动 预设，
 * 支持自定义 base-url + model + api-key，未来可继续扩展厂商。
 *
 * 后处理规则（与验证脚本 role_tag_v3.py 对齐）：
 *  1. 内嵌引语切分：旁白/角色段中「引导句 + 引号对白」拆分为两段，引导句归旁白、引语归说话人
 *  2. 心理活动归旁白：XX沉默了/心想/觉得/想道 等
 *  3. 整段纯叙述归旁白：无引号且含叙述特征词（窗外/雨/风/身影/脚步…）
 */
import http from '@ohos.net.http';

export interface RoleTagRole {
  name: string;
  gender: string; // male | female | unknown
}

export interface RoleTagSegment {
  role: string;
  text: string;
}

export interface RoleTagResult {
  roles: RoleTagRole[];
  segments: RoleTagSegment[];
}

export interface RoleTaggerOptions {
  provider: string;
  baseUrl: string;
  model: string;
  apiKey: string;
}

export interface RoleProviderInfo {
  baseUrl: string;
  defaultModel: string;
  label: string;
}

interface RoleLlmMessage {
  role: string;
  content: string;
}

interface RoleLlmPayload {
  model: string;
  messages: RoleLlmMessage[];
  temperature: number;
  max_tokens: number;
}

interface RoleLlmChoice {
  message: RoleLlmMessage | null;
}

interface RoleLlmBody {
  choices: RoleLlmChoice[] | null;
}

interface EmbeddedQuote {
  lead: string;
  quote: string;
  pre: string;
  post: string;
}

interface RawTagRole {
  name?: string;
  gender?: string;
}

interface RawTagSegment {
  role?: string;
  text?: string;
}

interface RawTagPayload {
  roles?: RawTagRole[];
  segments?: RawTagSegment[];
}

export class RoleTagger {
  static readonly PROVIDER_ZHIPU = 'zhipu';
  static readonly PROVIDER_ALIYUN = 'aliyun';
  static readonly PROVIDER_XIAOMI = 'xiaomi';
  static readonly PROVIDER_DEEPSEEK = 'deepseek';
  static readonly PROVIDER_SILICONFLOW = 'siliconflow';

  static readonly PROVIDERS: Record<string, RoleProviderInfo> = {
    'zhipu': { baseUrl: 'https://open.bigmodel.cn/api/paas/v4', defaultModel: 'glm-4-flash', label: '智谱' },
    'aliyun': { baseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1', defaultModel: 'qwen-plus', label: '阿里百炼' },
    'xiaomi': { baseUrl: 'https://api.xiaomi.com/v1', defaultModel: 'mimo-7b', label: '小米' },
    'deepseek': { baseUrl: 'https://api.deepseek.com/v1', defaultModel: 'deepseek-chat', label: 'DeepSeek' },
    'siliconflow': { baseUrl: 'https://api.siliconflow.cn/v1', defaultModel: 'Qwen/Qwen2.5-7B-Instruct', label: '硅基流动' },
  };

  static readonly NARRATOR = '旁白';

  private static readonly SYSTEM_PROMPT: string = [
    '你是小说有声书的角色标注引擎。把给定章节文本按"谁在说话"逐段切分并标注角色，供多音色 TTS 朗读使用。',
    '输出必须是合法 JSON，禁止输出 JSON 以外的任何文字。结构固定为：',
    '{"roles":[{"name":"角色名","gender":"male|female|unknown"}],"segments":[{"role":"角色名","text":"原文片段"}]}',
    '标注规则：',
    '1. "旁白"必须是第一个角色，负责叙述、场景描写、心理活动、回忆、群体发声等一切非角色对话。',
    '2. 对话归属依据：显式"XX说/道/问/喊/回答"标签优先，其次上下文语义，最后引号内容。',
    '3. 同一说话人连续多句合并为一个 segment，禁止跨角色合并。',
    '4. 旁白段内嵌角色对白必须拆分：如"陆沉说：\'你好。\'"应拆成 [旁白]="陆沉说：" 与 [陆沉]="你好。" 两段。',
    '5. 心理活动一律归旁白："XX沉默了/XX心想/XX觉得/想道/暗自盘算"及其后续内心内容归旁白。',
    '6. 段末叙述收尾一律归旁白：段尾的天气、动作、场景描写即使紧跟对白之后也是旁白。',
    '7. 整段不含引号、纯场景/动作描写的叙述段一律归旁白（如"窗外风雨依旧，两人并肩走进黑暗里"）。',
    '8. 无明确归属的引号对话：上下文能推断则标具体角色，否则归"旁白"并保留引号。',
    '9. text 必须原文原样，禁止改写、增删字。',
    '10. 角色性别依据文本推断，无法确定写 unknown。'
  ].join('\n');

  private static readonly OPEN_QUOTES = ['“', '"', '「', '『', '\'', '‘', '’'];
  private static readonly CLOSE_QUOTES = ['”', '"', '」', '』', '\'', '‘', '’'];
  private static readonly SPEAKER_HINT_WORDS: string[] = [
    '说', '道', '问', '喊', '答', '开口', '接话', '附和', '沉声道', '低声道',
    '怒道', '笑道', '叹道', '应道', '目光', '看着', '望向', '盯着', '瞅着', '注视着', '看向'
  ];
  private static readonly MENTAL_MARKERS: string[] = [
    '沉默了', '心想', '想道', '觉得', '感觉', '暗自', '暗暗', '心里', '心中', '暗想', '想着'
  ];
  private static readonly NARRATION_MARKERS: string[] = [
    '窗外', '天', '雨', '风', '夜', '灯', '城市', '街道', '山', '水', '雪',
    '太阳', '月亮', '阳光', '目光', '身影', '脚步声', '空气', '时间', '世界',
    '一切', '两人', '三个人', '众人', '黑暗', '光线', '声音', '安静', '沉默',
    '夜色', '清晨', '黄昏', '黎明', '房间', '屋子', '走廊', '门', '窗', '桌'
  ];

  static providerList(): string[] {
    return Object.keys(RoleTagger.PROVIDERS);
  }

  static providerLabel(provider: string): string {
    const p = RoleTagger.PROVIDERS[provider];
    return p ? p.label : (provider || '');
  }

  static effectiveBaseUrl(provider: string, customBaseUrl: string): string {
    if (customBaseUrl && customBaseUrl.trim().length > 0) {
      return customBaseUrl.trim();
    }
    const p = RoleTagger.PROVIDERS[provider];
    return p ? p.baseUrl : '';
  }

  static effectiveModel(provider: string, customModel: string): string {
    if (customModel && customModel.trim().length > 0) {
      return customModel.trim();
    }
    const p = RoleTagger.PROVIDERS[provider];
    return p ? p.defaultModel : '';
  }

  static async tag(text: string, options: RoleTaggerOptions): Promise<RoleTagResult> {
    const baseUrl = RoleTagger.effectiveBaseUrl(options.provider, options.baseUrl);
    const model = RoleTagger.effectiveModel(options.provider, options.model);
    const raw = await RoleTagger.callLlm(baseUrl, options.apiKey, model, text);
    const parsed = RoleTagger.parseJson(raw);
    return RoleTagger.postProcess(parsed);
  }

  private static async callLlm(baseUrl: string, apiKey: string, model: string, text: string): Promise<string> {
    const url = baseUrl.replace(/\/+$/, '') + '/chat/completions';
    const messages: RoleLlmMessage[] = [
      { role: 'system', content: RoleTagger.SYSTEM_PROMPT },
      { role: 'user', content: text }
    ];
    const payload: RoleLlmPayload = {
      model: model,
      messages: messages,
      temperature: 0.1,
      max_tokens: 4096
    };
    const httpRequest = http.createHttp();
    try {
      const response = await RoleTagger.withTimeout(
        httpRequest.request(url, {
          method: http.RequestMethod.POST,
          header: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ' + apiKey
          },
          extraData: JSON.stringify(payload),
          connectTimeout: 20000,
          readTimeout: 60000
        }),
        70000,
        '角色标注请求超时（70s 无响应）',
        () => {
          // 超时兜底：主动销毁底层请求，避免连接悬挂导致 UI 一直停在"正在标注角色…"
          httpRequest.destroy();
        }
      );
      if (response.responseCode !== 200) {
        const bodyText = typeof response.result === 'string' ? response.result : '';
        throw new Error('LLM HTTP ' + response.responseCode + ': ' + bodyText.substring(0, 500));
      }
      const body = JSON.parse(typeof response.result === 'string' ? response.result : String(response.result)) as RoleLlmBody;
      if (!body.choices || body.choices.length === 0) {
        throw new Error('LLM 返回空 choices');
      }
      const firstChoice: RoleLlmChoice = body.choices[0];
      const content = firstChoice.message && firstChoice.message.content;
      if (!content) {
        throw new Error('LLM 返回空 content');
      }
      return String(content);
    } finally {
      httpRequest.destroy();
    }
  }

  private static withTimeout<T>(promise: Promise<T>, ms: number, message: string,
    onTimeout: () => void): Promise<T> {
    return new Promise<T>((resolve, reject) => {
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

  private static parseJson(content: string): RoleTagResult {
    let value = content.trim();
    if (value.startsWith('```')) {
      const parts = value.split('```');
      if (parts.length >= 2) {
        value = parts[1].trim();
        if (value.startsWith('json')) {
          value = value.substring(4).trim();
        }
      }
    }
    const parsed = JSON.parse(value) as RawTagPayload;
    const roles: RoleTagRole[] = [];
    const segments: RoleTagSegment[] = [];
    if (parsed.roles && Array.isArray(parsed.roles)) {
      for (const r of parsed.roles) {
        roles.push({ name: String(r.name || '旁白'), gender: String(r.gender || 'unknown') });
      }
    }
    if (parsed.segments && Array.isArray(parsed.segments)) {
      for (const s of parsed.segments) {
        segments.push({ role: String(s.role || '旁白'), text: String(s.text || '') });
      }
    }
    if (roles.length === 0) {
      roles.push({ name: RoleTagger.NARRATOR, gender: 'unknown' });
    }
    return { roles: roles, segments: segments };
  }

  private static containsQuote(text: string): boolean {
    const all = RoleTagger.OPEN_QUOTES.concat(RoleTagger.CLOSE_QUOTES);
    for (const q of all) {
      if (text.indexOf(q) >= 0) {
        return true;
      }
    }
    return false;
  }

  private static guessSpeaker(lead: string, role: string, roleNames: string[]): string | null {
    // 1) 引导词前 10 字窗口内找角色名
    for (const kw of RoleTagger.SPEAKER_HINT_WORDS) {
      const idx = lead.lastIndexOf(kw);
      if (idx < 0) {
        continue;
      }
      const start = Math.max(0, idx - 10);
      const window = lead.substring(start, idx);
      for (const name of roleNames) {
        if (name && name !== RoleTagger.NARRATOR && window.indexOf(name) >= 0) {
          return name;
        }
      }
    }
    // 2) 引导句全文中最后出现的角色名
    let bestName: string | null = null;
    let bestIdx = -1;
    for (const name of roleNames) {
      if (!name || name === RoleTagger.NARRATOR) {
        continue;
      }
      const idx = lead.lastIndexOf(name);
      if (idx > bestIdx) {
        bestName = name;
        bestIdx = idx;
      }
    }
    if (bestName) {
      return bestName;
    }
    // 3) 原段非旁白角色兜底
    if (role && role !== RoleTagger.NARRATOR) {
      return role;
    }
    return null;
  }

  /** 在 text 中查找「：'...'」形式的内嵌引语，返回 lead 与 quote。 */
  private static findEmbeddedQuote(text: string): EmbeddedQuote | null {
    let colonIdx = -1;
    for (let i = 0; i < text.length; i++) {
      const ch = text.charAt(i);
      if (ch === '：' || ch === ':') {
        // lead 内不能含句末标点
        const lead = text.substring(0, i);
        if (lead.indexOf('。') >= 0 || lead.indexOf('！') >= 0 || lead.indexOf('？') >= 0) {
          continue;
        }
        colonIdx = i;
        break;
      }
    }
    if (colonIdx < 0) {
      return null;
    }
    const quoteStart = colonIdx + 1;
    if (quoteStart >= text.length) {
      return null;
    }
    const quoteChar = text.charAt(quoteStart);
    if (RoleTagger.OPEN_QUOTES.indexOf(quoteChar) < 0) {
      return null;
    }
    const quoteEnd = text.indexOf(quoteChar, quoteStart + 1);
    if (quoteEnd < 0) {
      return null;
    }
    const lead = text.substring(0, colonIdx + 1);
    const quote = text.substring(quoteStart, quoteEnd + 1);
    return { lead: lead, quote: quote, pre: '', post: text.substring(quoteEnd + 1) };
  }

  private static splitEmbeddedQuote(role: string, text: string, roleNames: string[]): RoleTagSegment[] {
    const found = RoleTagger.findEmbeddedQuote(text);
    if (!found) {
      const seg: RoleTagSegment = { role: role, text: text };
      return [seg];
    }
    const pre = text.substring(0, text.indexOf(found.lead));
    const speaker = RoleTagger.guessSpeaker(found.lead, role, roleNames);
    const parts: RoleTagSegment[] = [];
    const preText = pre.trim();
    if (preText.length > 0) {
      parts.push({ role: RoleTagger.NARRATOR, text: preText });
    }
    if (speaker) {
      const leadText = found.lead.trim();
      if (leadText.length > 0) {
        parts.push({ role: RoleTagger.NARRATOR, text: leadText });
      }
      parts.push({ role: speaker, text: found.quote });
    } else {
      parts.push({ role: RoleTagger.NARRATOR, text: (preText + found.lead + found.quote).trim() });
    }
    const postText = found.post.trim();
    if (postText.length > 0) {
      parts.push({ role: RoleTagger.NARRATOR, text: postText });
    }
    return parts;
  }

  private static isMentalText(text: string): boolean {
    for (const marker of RoleTagger.MENTAL_MARKERS) {
      if (text.startsWith(marker)) {
        return true;
      }
    }
    // "XX沉默了/XX心想/XX觉得" 带主语形式（主语 1-4 字）
    if (text.length > 4) {
      const head = text.substring(0, 4);
      for (const marker of RoleTagger.MENTAL_MARKERS) {
        if (head.endsWith(marker) || (head + text.substring(4, 5)).indexOf(marker) === head.length - marker.length) {
          return true;
        }
      }
    }
    return false;
  }

  private static isNarration(text: string): boolean {
    const value = text.trim();
    if (value.length === 0 || RoleTagger.containsQuote(value)) {
      return false;
    }
    for (const marker of RoleTagger.NARRATION_MARKERS) {
      if (value.startsWith(marker)) {
        return true;
      }
    }
    if (value.length >= 20) {
      for (const marker of RoleTagger.NARRATION_MARKERS) {
        if (value.indexOf(marker) >= 0) {
          return true;
        }
      }
    }
    return false;
  }

  static postProcess(result: RoleTagResult): RoleTagResult {
    const roles = result.roles.slice();
    const roleNames: string[] = roles.map(r => r.name);
    const out: RoleTagSegment[] = [];
    const ensureRole = (name: string, gender: string | null): void => {
      if (name === RoleTagger.NARRATOR || roleNames.indexOf(name) >= 0) {
        return;
      }
      roles.push({ name: name, gender: gender || 'unknown' });
      roleNames.push(name);
    };
    const genderOf = (name: string): string | null => {
      for (const r of roles) {
        if (r.name === name) {
          return r.gender;
        }
      }
      return null;
    };
    for (const seg of result.segments) {
      let role = seg.role || RoleTagger.NARRATOR;
      let text = seg.text.trim();
      if (text.length === 0) {
        continue;
      }
      // 规则2：心理活动归旁白
      if (role !== RoleTagger.NARRATOR && RoleTagger.isMentalText(text)) {
        role = RoleTagger.NARRATOR;
      }
      // 规则3：整段纯叙述归旁白
      if (role !== RoleTagger.NARRATOR && RoleTagger.isNarration(text)) {
        role = RoleTagger.NARRATOR;
      }
      // 规则1：内嵌引语切分
      const pieces = RoleTagger.splitEmbeddedQuote(role, text, roleNames);
      for (const piece of pieces) {
        const pieceText = piece.text.trim();
        if (pieceText.length === 0) {
          continue;
        }
        ensureRole(piece.role, genderOf(piece.role));
        out.push({ role: piece.role, text: pieceText });
      }
    }
    return { roles: roles, segments: out };
  }
}
