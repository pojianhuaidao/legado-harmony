/**
 * 轻量广告拦截器 —— 「订阅源浏览器去广告」开关的核心规则模块
 *
 * 双层黑名单：
 *  1) 请求拦截（onInterceptRequest）：命中「广告域名后缀」或「URL 路径/参数广告特征」即返回空响应；
 *  2) 弹窗拦截（onAlert）：弹窗消息含广告特征词，或弹窗来源页面命中广告域名时取消弹窗。
 *
 * 放行策略：非广告弹窗一律放行（如书山等聚合订阅源的更新公告弹窗），
 * 避免误伤订阅源自身功能。
 */
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

  /**
   * 判断请求是否命中广告黑名单（host 后缀或路径特征）。
   */
  static shouldBlockRequest(url: string): boolean {
    if (!url || url.length === 0) {
      return false;
    }
    const host = AdBlocker.extractHost(url);
    if (host.length > 0) {
      for (let i = 0; i < AdBlocker.AD_HOST_SUFFIXES.length; i++) {
        if (host === AdBlocker.AD_HOST_SUFFIXES[i] ||
          host.endsWith('.' + AdBlocker.AD_HOST_SUFFIXES[i])) {
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
      for (let i = 0; i < AdBlocker.AD_HOST_SUFFIXES.length; i++) {
        if (host === AdBlocker.AD_HOST_SUFFIXES[i] ||
          host.endsWith('.' + AdBlocker.AD_HOST_SUFFIXES[i])) {
          return true;
        }
      }
    }
    return false;
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
