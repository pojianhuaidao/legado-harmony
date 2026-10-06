/**
 * 去广告规则动态更新器（方案B）
 *
 * 职责：
 *  1) 从 AdGuard / EasyList 规则源抓取过滤规则文本（多源容错，任一成功即用）；
 *  2) 在后台线程（TaskPool）解析为三类本地规则：域名后缀黑名单 / CSS 选择器 / 白名单；
 *  3) 写入应用沙箱（filesDir/adblock_rules.json），并注入 AdBlocker 实现「内置 + 动态」合并生效。
 *
 * 解析策略（AdGuard / ABP 语法子集，保守过滤，避免误伤）：
 *  - `||example.com^` / `||example.com/path` → 域名后缀黑名单
 *  - `@@||example.com^` → 白名单（可信域名放行）
 *  - `example.com##.ad` / `##.ad` → CSS 选择器（限定域名或通用）
 *  - 含 `$` 修饰符、正则 `/.../`、`#?#` / `#$#` / `#@#` 等复杂规则一律跳过
 */
import { Context } from '@kit.AbilityKit';
import http from '@ohos.net.http';
import fs from '@ohos.file.fs';
import taskpool from '@ohos.taskpool';
import { util } from '@kit.ArkTS';
import { AdBlocker, AdCssRule } from './AdBlocker';

const RULES_FILE_NAME: string = 'adblock_rules.json';
// 规则源：AdGuard 中文过滤器（优化版）→ EasyList China → anti-AD，任一成功即用
const RULE_SOURCES: string[] = [
  'https://filters.adtidy.org/extension/ublock/filters/224_optimized.txt',
  'https://raw.githubusercontent.com/easylist/easylistchina/master/easylistchina.txt',
  'https://raw.githubusercontent.com/privacy-protection-tools/anti-AD/master/anti-ad-adguard.txt'
];
const MAX_HOST_SUFFIXES: number = 5000;
const MAX_CSS_SELECTORS: number = 3000;
const MAX_WHITELIST_SUFFIXES: number = 500;
const SCHEMA_VERSION: number = 1;

/**
 * 动态规则包：与沙箱 JSON 结构一一对应。
 */
export class AdRulesBundle {
  hostSuffixes: string[] = [];
  whitelistSuffixes: string[] = [];
  cssSelectors: AdCssRule[] = [];
  updatedAt: number = 0;
}

interface CssRuleShape {
  domain?: string;
  selector?: string;
}

interface AdRulesFileShape {
  updatedAt?: number;
  hostSuffixes?: string[];
  whitelistSuffixes?: string[];
  cssSelectors?: CssRuleShape[];
}

/**
 * TaskPool 后台解析任务：输入规则文本，输出序列化后的 JSON 字符串。
 * @Concurrent 函数自包含：不引用任何外部变量/类型/函数，所需常量与辅助逻辑全部内联。
 */
@Concurrent
function parseAdGuardRulesTask(rawText: string): string {
  const hostSuffixes: string[] = [];
  const whitelistSuffixes: string[] = [];
  const cssKeys: string[] = [];
  const seenHost: Set<string> = new Set<string>();
  const seenWhite: Set<string> = new Set<string>();
  const seenCss: Set<string> = new Set<string>();
  const maxHost = 5000;
  const maxCss = 3000;
  const maxWhite = 500;
  const lines: string[] = rawText.split('\n');
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i].trim();
    if (line.length === 0) {
      continue;
    }
    const c0 = line.charAt(0);
    if (c0 === '!' || c0 === '[' || c0 === '/') {
      continue;
    }
    if (line.indexOf('$') >= 0) {
      continue;
    }
    if (line.indexOf('##') >= 0) {
      if (line.indexOf('#@#') >= 0 || line.indexOf('#$#') >= 0 || line.indexOf('#?#') >= 0) {
        continue;
      }
      const idx = line.indexOf('##');
      const prefix = line.substring(0, idx).trim();
      const selector = line.substring(idx + 2).trim();
      if (selector.length === 0) {
        continue;
      }
      let domain = '';
      if (prefix.length > 0 && prefix.charAt(0) !== '#') {
        const first = prefix.split(',')[0].trim();
        if (first.length === 0 || first.indexOf('#') >= 0 || first.indexOf('~') >= 0) {
          continue;
        }
        domain = first.toLowerCase();
      }
      const key = domain + '##' + selector;
      if (seenCss.has(key) || cssKeys.length >= maxCss) {
        continue;
      }
      seenCss.add(key);
      cssKeys.push(key);
      continue;
    }
    if (line.startsWith('@@||')) {
      let host = line.substring(4);
      const caret = host.indexOf('^');
      if (caret >= 0) {
        host = host.substring(0, caret);
      }
      const slash = host.indexOf('/');
      if (slash >= 0) {
        host = host.substring(0, slash);
      }
      host = host.toLowerCase();
      let valid = host.length > 0;
      for (let ci = 0; ci < host.length; ci++) {
        const c = host.charCodeAt(ci);
        const isOk = (c >= 97 && c <= 122) || (c >= 48 && c <= 57) || c === 46 || c === 45;
        if (!isOk) {
          valid = false;
          break;
        }
      }
      if (valid && !seenWhite.has(host) && whitelistSuffixes.length < maxWhite) {
        seenWhite.add(host);
        whitelistSuffixes.push(host);
      }
      continue;
    }
    if (line.startsWith('||')) {
      let host = line.substring(2);
      const caret = host.indexOf('^');
      if (caret >= 0) {
        host = host.substring(0, caret);
      }
      const slash = host.indexOf('/');
      if (slash >= 0) {
        host = host.substring(0, slash);
      }
      host = host.toLowerCase();
      let valid = host.length > 0;
      for (let ci = 0; ci < host.length; ci++) {
        const c = host.charCodeAt(ci);
        const isOk = (c >= 97 && c <= 122) || (c >= 48 && c <= 57) || c === 46 || c === 45;
        if (!isOk) {
          valid = false;
          break;
        }
      }
      if (valid && !seenHost.has(host) && hostSuffixes.length < maxHost) {
        seenHost.add(host);
        hostSuffixes.push(host);
      }
      continue;
    }
  }
  const cssArr: Array<Record<string, string>> = [];
  for (let i = 0; i < cssKeys.length; i++) {
    const key = cssKeys[i];
    const idx = key.indexOf('##');
    const item: Record<string, string> = {};
    if (idx > 0) {
      item['domain'] = key.substring(0, idx);
      item['selector'] = key.substring(idx + 2);
    } else {
      item['selector'] = key.substring(2);
    }
    cssArr.push(item);
  }
  const result: Record<string, Object> = {
    'schema': 1,
    'updatedAt': Date.now(),
    'hostSuffixes': hostSuffixes,
    'whitelistSuffixes': whitelistSuffixes,
    'cssSelectors': cssArr
  };
  return JSON.stringify(result);
}

/**
 * 动态规则更新入口。
 */
export class AdRuleUpdater {
  private static cachedBundle: AdRulesBundle | null = null;

  /**
   * 应用启动 / 进入订阅源浏览器时调用：从沙箱恢复动态规则并注入 AdBlocker。
   * 无沙箱规则或文件损坏时静默跳过（仅用内置静态兜底）。
   */
  static async ensureLoaded(context: Context): Promise<void> {
    if (AdRuleUpdater.cachedBundle) {
      AdRuleUpdater.applyToBlocker(AdRuleUpdater.cachedBundle);
      return;
    }
    const bundle = await AdRuleUpdater.loadFromSandbox(context);
    if (bundle) {
      AdRuleUpdater.cachedBundle = bundle;
      AdRuleUpdater.applyToBlocker(bundle);
    }
  }

  /**
   * 完整更新流程：抓取 → 后台解析 → 写沙箱 → 注入 AdBlocker。
   * 任一步骤失败抛出 Error，由 UI 层提示用户。
   */
  static async update(context: Context): Promise<AdRulesBundle> {
    let rawText: string = '';
    let lastError: Error | null = null;
    for (let i = 0; i < RULE_SOURCES.length; i++) {
      try {
        rawText = await AdRuleUpdater.fetchRuleText(RULE_SOURCES[i]);
        if (rawText.length > 0) {
          break;
        }
      } catch (e) {
        lastError = e as Error;
      }
    }
    if (rawText.length === 0) {
      throw lastError ? lastError : new Error('所有规则源均不可达');
    }
    const json = await taskpool.execute(parseAdGuardRulesTask, rawText) as string;
    const bundle = AdRuleUpdater.parseBundle(json);
    await AdRuleUpdater.saveToSandbox(context, bundle);
    AdRuleUpdater.cachedBundle = bundle;
    AdRuleUpdater.applyToBlocker(bundle);
    return bundle;
  }

  /**
   * 当前内存中的动态规则包（未加载/未更新时为 null）。
   */
  static getLastBundle(): AdRulesBundle | null {
    return AdRuleUpdater.cachedBundle;
  }

  private static applyToBlocker(bundle: AdRulesBundle): void {
    AdBlocker.setDynamicRules(bundle.hostSuffixes, bundle.whitelistSuffixes, bundle.cssSelectors);
  }

  private static async fetchRuleText(source: string): Promise<string> {
    const httpRequest = http.createHttp();
    try {
      const response = await httpRequest.request(source, {
        method: http.RequestMethod.GET,
        connectTimeout: 15000,
        readTimeout: 60000,
        header: {
          'User-Agent': 'Mozilla/5.0 (Linux; Android 12; HarmonyOS) AppleWebKit/537.36'
        },
        expectDataType: http.HttpDataType.STRING
      });
      if (response.responseCode === 200) {
        const text = response.result as string;
        return text ? text : '';
      }
      return '';
    } finally {
      httpRequest.destroy();
    }
  }

  private static async loadFromSandbox(context: Context): Promise<AdRulesBundle | null> {
    const path = `${context.filesDir}/${RULES_FILE_NAME}`;
    let json: string = '';
    try {
      json = await AdRuleUpdater.readText(path);
    } catch (e) {
      return null;
    }
    if (json.length === 0) {
      return null;
    }
    try {
      return AdRuleUpdater.parseBundle(json);
    } catch (e) {
      return null;
    }
  }

  private static parseBundle(json: string): AdRulesBundle {
    const data = JSON.parse(json) as AdRulesFileShape;
    const bundle = new AdRulesBundle();
    if (typeof data.updatedAt === 'number') {
      bundle.updatedAt = data.updatedAt;
    }
    if (data.hostSuffixes !== undefined && data.hostSuffixes instanceof Array) {
      const arr = data.hostSuffixes;
      for (let i = 0; i < arr.length && i < MAX_HOST_SUFFIXES; i++) {
        if (typeof arr[i] === 'string' && arr[i].length > 0) {
          bundle.hostSuffixes.push(arr[i]);
        }
      }
    }
    if (data.whitelistSuffixes !== undefined && data.whitelistSuffixes instanceof Array) {
      const arr = data.whitelistSuffixes;
      for (let i = 0; i < arr.length && i < MAX_WHITELIST_SUFFIXES; i++) {
        if (typeof arr[i] === 'string' && arr[i].length > 0) {
          bundle.whitelistSuffixes.push(arr[i]);
        }
      }
    }
    if (data.cssSelectors !== undefined && data.cssSelectors instanceof Array) {
      const arr = data.cssSelectors;
      for (let i = 0; i < arr.length && i < MAX_CSS_SELECTORS; i++) {
        const item = arr[i];
        if (item === undefined || item === null) {
          continue;
        }
        const rule = new AdCssRule();
        if (typeof item.domain === 'string') {
          rule.domain = item.domain;
        }
        if (typeof item.selector === 'string') {
          rule.selector = item.selector;
        }
        if (rule.selector.length > 0) {
          bundle.cssSelectors.push(rule);
        }
      }
    }
    return bundle;
  }

  private static async saveToSandbox(context: Context, bundle: AdRulesBundle): Promise<void> {
    const path = `${context.filesDir}/${RULES_FILE_NAME}`;
    const bytes = new util.TextEncoder().encodeInto(JSON.stringify(bundle));
    const file = await fs.open(path, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
    try {
      await fs.write(file.fd, bytes.buffer, { offset: 0, length: bytes.byteLength });
    } finally {
      await fs.close(file);
    }
  }

  private static async readText(path: string): Promise<string> {
    const stat = await fs.stat(path);
    const file = await fs.open(path, fs.OpenMode.READ_ONLY);
    try {
      const buffer = new ArrayBuffer(stat.size);
      await fs.read(file.fd, buffer, { offset: 0, length: stat.size });
      return util.TextDecoder.create('utf-8').decodeWithStream(new Uint8Array(buffer), { stream: false });
    } finally {
      await fs.close(file);
    }
  }
}
