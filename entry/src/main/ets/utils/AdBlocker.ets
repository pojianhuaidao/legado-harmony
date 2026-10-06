/**
 * 轻量广告拦截器 —— 「订阅源浏览器去广告」开关的核心规则模块
 *
 * 双层黑名单：
 *  1) 请求拦截（onInterceptRequest）：命中「广告域名后缀」或「URL 路径/参数广告特征」即返回空响应；
 *  2) 弹窗拦截（onAlert）：弹窗消息含广告特征词，或弹窗来源页面命中广告域名时取消弹窗。
 *
 * 规则来源（方案B 动态更新）：
 *  - 内置静态规则（本文件内硬编码），保证开箱即用的兜底拦截；
 *  - 沙箱动态规则（AdRuleUpdater 从 AdGuard/EasyList 抓取解析后写入 filesDir，
 *    通过 setDynamicRules 注入），实现「内置 + 动态」双层合并；
 *  - CSS 选择器规则由 buildCssHideScript 生成注入脚本，在页面加载完成后隐藏广告元素。
 *
 * 放行策略：白名单域名（内置可信域名 + 动态 @@ 例外规则）一律放行；非广告弹窗
 * （如书山等聚合订阅源的更新公告弹窗）按内容策略放行，避免误伤订阅源自身功能。
 */

/**
 * 动态 CSS 选择器规则：domain 为空表示通用规则（所有页面生效），否则仅匹配该域名。
 */
export class AdCssRule {
  domain: string = '';
  selector: string = '';
}

export class AdBlocker {
  private static readonly AD_HOST_SUFFIXES: string[] = [
    // Google 系广告 / 统计
    'doubleclick.net',
    'googlesyndication.com',
    'googletagmanager.com',
    'googleadservices.com',
    'google-analytics.com',
    'adservice.google.com',
    'pagead2.googlesyndication.com',
    // 百度系广告 / 统计
    'hm.baidu.com',
    'pos.baidu.com',
    'cpro.baidu.com',
    // 腾讯 / 360 系
    'ads.qq.com',
    'gdt.qq.com',
    'union.360.cn',
    // 海外常见广告网络
    'adnxs.com',
    'adsafeprotected.com',
    'moatads.com',
    'scorecardresearch.com',
    'quantserve.com',
    'taboola.com',
    'outbrain.com',
    'amazon-adsystem.com',
    'serving-sys.com',
    'tribalfusion.com',
    'mediaplex.com',
    'zedo.com',
    'yieldmanager.com',
    'adsymptotic.com',
    'casalemedia.com',
    'pubmatic.com',
    'openx.net',
    'rubiconproject.com',
    'appnexus.com',
    'criteo.com',
    'bidvertiser.com',
    'popads.net',
    'propellerads.com',
    'adsterra.com',
    'adcash.com',
    'exoclick.com',
    'juicyads.com',
    'onclck.ru'
  ];

  /**
   * 内置可信域名白名单：命中后请求 / 弹窗一律放行（书山等聚合订阅源域名可在此补充）。
   */
  private static readonly TRUSTED_HOST_SUFFIXES: string[] = [];

  private static readonly AD_PATH_KEYWORDS: string[] = [
    '/ads/',
    '/ad/',
    'adunit',
    'adframe',
    'ad_banner',
    'banner_ad',
    'ad-click',
    'adclick',
    'adserv',
    'pagead',
    'advert',
    'ad_content',
    'ad_frame',
    'ad_js',
    'ad.js',
    'ad_iframe',
    'dfp_',
    'ads_',
    'doubleclick',
    'googlesyndication'
  ];

  private static readonly AD_ALERT_KEYWORDS: string[] = [
    '广告',
    '推广',
    '抽奖',
    '红包',
    '优惠券',
    '返利',
    '领福利',
    '立即领取',
    '限时优惠',
    '下载 App',
    '下载APP',
    '邀请有礼',
    '砍一刀',
    '游戏礼包'
  ];

  // 沙箱动态规则（AdRuleUpdater 更新后注入；订阅源浏览器打开时从 filesDir 恢复）
  private static dynamicHostSuffixes: string[] = [];
  private static dynamicWhitelistSuffixes: string[] = [];
  private static dynamicCssSelectors: AdCssRule[] = [];

  /**
   * 注入动态规则（域名后缀黑名单 / 白名单 / CSS 选择器），与内置静态规则合并生效。
   */
  static setDynamicRules(hostSuffixes: string[], whitelistSuffixes: string[], cssSelectors: AdCssRule[]): void {
    AdBlocker.dynamicHostSuffixes = hostSuffixes;
    AdBlocker.dynamicWhitelistSuffixes = whitelistSuffixes;
    AdBlocker.dynamicCssSelectors = cssSelectors;
  }

  /**
   * 清空动态规则（仅保留内置静态兜底）。
   */
  static clearDynamicRules(): void {
    AdBlocker.dynamicHostSuffixes = [];
    AdBlocker.dynamicWhitelistSuffixes = [];
    AdBlocker.dynamicCssSelectors = [];
  }

  /**
   * 判断请求是否命中广告黑名单（host 后缀或路径特征）。
   * 白名单域名优先放行。
   */
  static shouldBlockRequest(url: string): boolean {
    if (!url || url.length === 0) {
      return false;
    }
    const host = AdBlocker.extractHost(url);
    if (host.length > 0) {
      if (AdBlocker.isTrustedHost(host)) {
        return false;
      }
      for (let i = 0; i < AdBlocker.AD_HOST_SUFFIXES.length; i++) {
        if (host === AdBlocker.AD_HOST_SUFFIXES[i] ||
          host.endsWith('.' + AdBlocker.AD_HOST_SUFFIXES[i])) {
          return true;
        }
      }
      for (let i = 0; i < AdBlocker.dynamicHostSuffixes.length; i++) {
        if (host === AdBlocker.dynamicHostSuffixes[i] ||
          host.endsWith('.' + AdBlocker.dynamicHostSuffixes[i])) {
          return true;
        }
      }
    }
    const lowered = url.toLowerCase();
    for (let i = 0; i < AdBlocker.AD_PATH_KEYWORDS.length; i++) {
      if (lowered.indexOf(AdBlocker.AD_PATH_KEYWORDS[i]) >= 0) {
        return true;
      }
    }
    return false;
  }

  /**
   * 判断 alert 弹窗是否属于广告弹窗（命中则取消）。
   * 非广告弹窗（如书山源更新公告）返回 false，由 Web 组件正常展示。
   */
  static shouldBlockAlert(url: string, message: string): boolean {
    if (message && message.length > 0) {
      const lowered = message.toLowerCase();
      for (let i = 0; i < AdBlocker.AD_ALERT_KEYWORDS.length; i++) {
        if (lowered.indexOf(AdBlocker.AD_ALERT_KEYWORDS[i].toLowerCase()) >= 0) {
          return true;
        }
      }
    }
    if (url && url.length > 0) {
      const host = AdBlocker.extractHost(url);
      if (AdBlocker.isTrustedHost(host)) {
        return false;
      }
      for (let i = 0; i < AdBlocker.AD_HOST_SUFFIXES.length; i++) {
        if (host === AdBlocker.AD_HOST_SUFFIXES[i] ||
          host.endsWith('.' + AdBlocker.AD_HOST_SUFFIXES[i])) {
          return true;
        }
      }
      for (let i = 0; i < AdBlocker.dynamicHostSuffixes.length; i++) {
        if (host === AdBlocker.dynamicHostSuffixes[i] ||
          host.endsWith('.' + AdBlocker.dynamicHostSuffixes[i])) {
          return true;
        }
      }
    }
    return false;
  }

  /**
   * 生成用于隐藏页面广告元素的注入脚本；无可匹配规则时返回空串。
   * 命中白名单域名时不注入，避免干扰可信源页面。
   */
  static buildCssHideScript(url: string): string {
    if (!url || url.length === 0) {
      return '';
    }
    const host = AdBlocker.extractHost(url);
    if (host.length === 0 || AdBlocker.isTrustedHost(host)) {
      return '';
    }
    const parts: string[] = [];
    for (let i = 0; i < AdBlocker.dynamicCssSelectors.length; i++) {
      const rule = AdBlocker.dynamicCssSelectors[i];
      if (rule.domain.length === 0 || host === rule.domain || host.endsWith('.' + rule.domain)) {
        const literal = AdBlocker.toJsStringLiteral(rule.selector);
        parts.push('document.querySelectorAll(' + literal + ').forEach(function(e){e.remove()})');
      }
    }
    return parts.length > 0 ? parts.join(';') : '';
  }

  /**
   * host 是否命中白名单（内置可信域名 + 动态例外规则）。
   */
  private static isTrustedHost(host: string): boolean {
    for (let i = 0; i < AdBlocker.TRUSTED_HOST_SUFFIXES.length; i++) {
      if (host === AdBlocker.TRUSTED_HOST_SUFFIXES[i] ||
        host.endsWith('.' + AdBlocker.TRUSTED_HOST_SUFFIXES[i])) {
        return true;
      }
    }
    for (let i = 0; i < AdBlocker.dynamicWhitelistSuffixes.length; i++) {
      if (host === AdBlocker.dynamicWhitelistSuffixes[i] ||
        host.endsWith('.' + AdBlocker.dynamicWhitelistSuffixes[i])) {
        return true;
      }
    }
    return false;
  }

  /**
   * 将任意字符串转义为可安全放入 JS 双引号字符串字面量的形式。
   */
  private static toJsStringLiteral(value: string): string {
    let escaped = value.replace(/\\/g, '\\\\');
    escaped = escaped.replace(/"/g, '\\"');
    escaped = escaped.replace(/[\r\n]+/g, ' ');
    return '"' + escaped + '"';
  }

  /**
   * 从 URL 中提取主机名（兼容带协议/无协议、带端口、带路径的常见形态）。
   */
  private static extractHost(url: string): string {
    let rest = url;
    const schemeIdx = rest.indexOf('://');
    if (schemeIdx >= 0) {
      rest = rest.substring(schemeIdx + 3);
    }
    const pathIdx = rest.indexOf('/');
    if (pathIdx >= 0) {
      rest = rest.substring(0, pathIdx);
    }
    const queryIdx = rest.indexOf('?');
    if (queryIdx >= 0) {
      rest = rest.substring(0, queryIdx);
    }
    const hashIdx = rest.indexOf('#');
    if (hashIdx >= 0) {
      rest = rest.substring(0, hashIdx);
    }
    const portIdx = rest.lastIndexOf(':');
    if (portIdx > 0) {
      rest = rest.substring(0, portIdx);
    }
    return rest.toLowerCase();
  }
}
