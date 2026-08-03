import 'package:flutter/foundation.dart';

/// A direct stream URL discovered inside an embed WebView (visible fallback
/// or hidden auto-capture), handed to the native (libmpv) player.
@immutable
class WebViewNativeStream {
  const WebViewNativeStream({
    required this.url,
    required this.position,
    this.httpHeaders = const <String, String>{},
  });

  /// Plain `.m3u8`/`.mp4` (or any non-`blob:`) URL played by the embed page's
  /// `<video>` element.
  final String url;

  /// Where playback was, so the native player can resume.
  final Duration position;

  /// Extra HTTP headers for the native player (e.g. the `Cookie` header from
  /// the WebView's browser session, which some CDNs require — without it the
  /// handed-off URL would get 403/428 in mpv).
  final Map<String, String> httpHeaders;
}

/// Host fragments of known ad/tracker networks. Used both by the request
/// interceptor (kills ad sub-resources) and the navigation override (kills
/// main-frame hijacks to ad landing pages).
const List<String> embedAdHostFragments = [
  'doubleclick',
  'googlesyndication',
  'googleads',
  'adservice.google',
  'taboola',
  'outbrain',
  'adsterra',
  'exoclick',
  'popads',
  'popcash',
  'propellerads',
  'adcash',
  'mgid.com',
  'bidvertiser',
  'criteo',
  'pubmatic',
  'rubiconproject',
  'openx.net',
  'adsafeprotected',
  'amazon-adsystem',
  'quantserve',
  'scorecardresearch',
  'mopub',
  'inmobi',
  'unityads',
  'applovin',
  'vungle',
  'ironsrc',
  'tapjoy',
  'chartboost',
  'adjust.com',
  'appsflyer',
  'tapdaq',
  'traficjunky',
  'juicyads',
  'smartyads',
  'onclickads',
  'adbrite',
  'adnxs',
  'adform',
  'smartadserver',
  'zedo',
  'revcontent',
  'spotxchange',
  'springserve',
  'gumgum',
  'indexexchange',
  'sharethrough',
  'triplelift',
  'sovrn',
  'teads',
  'loopme',
  'adcolony',
  'smaato',
  'startapp',
  'onetag',
];

/// Whether a request host targets a known ad network.
bool embedIsAdHost(String host) =>
    embedAdHostFragments.any((fragment) => host.contains(fragment));

/// Whether a `<video>` URL can be handed to the native player: a plain
/// http(s) media URL — not MSE `blob:`, and not the embed page itself.
bool embedIsNativeStreamCandidate(String url, {required String embedUrl}) {
  if (url.isEmpty) return false;
  if (!url.startsWith('http://') && !url.startsWith('https://')) return false;
  if (url.startsWith('blob:')) return false;
  if (url == embedUrl) return false;
  return true;
}

/// Whether a network request URL is a direct media manifest/file worth
/// capturing for native playback: `.m3u8`/`.mp4` only (ignoring query &
/// fragment). `.ts` segments, scripts, CSS and images are never candidates.
bool embedIsMediaUrl(String url) {
  final lower = url.toLowerCase();
  final path = lower.split('?').first.split('#').first;
  return path.endsWith('.m3u8') || path.endsWith('.mp4');
}

/// Injected at document-start into EVERY frame (including cross-origin
/// iframes) via `addUserScript(forMainFrameOnly: false)`, and re-injected
/// into the top frame after each load via `evaluateJavascript` (idempotent
/// guard `__filmkuA`):
/// - removes ad overlay elements (class/id match) and ad-host iframes
///   (posting `{__filmkuAd: 1}` per removal so the top page can count them),
/// - blocks `window.open` popups,
/// - relays the playing `<video>` URL + time to the top page via
///   `postMessage({__filmku: {url, t}})` (MSE `blob:` URLs are skipped — they
///   cannot play natively),
/// - the top frame stores the relayed value in `window.__filmku` and the
///   accumulated ad count in `window.__filmkuAds` for Dart polling.
const String embedAllFramesScript = '(function(){'
    'if(window.__filmkuA)return;window.__filmkuA=true;'
    'var ADRE=/(^|[-_ ])(ad|ads|advert|banner|popup|popunder|overlay|sponsor)([-_ ]|\$)/i;'
    'var SKIPRE=/player|video|movie|jw|plyr|menu|quality|setting|control|modal/i;'
    'function adlike(e){if(!e||e.nodeType!==1)return false;'
    'var s=(e.id||"")+" "+(typeof e.className==="string"?e.className:"");'
    'if(!ADRE.test(s))return false;if(SKIPRE.test(s))return false;'
    'if(e.querySelector&&e.querySelector("video"))return false;return true;}'
    'function kill(e){try{'
    'if(adlike(e)){if(e.parentNode){e.parentNode.removeChild(e);'
    'try{window.parent.postMessage({__filmkuAd:1},"*");}catch(err){}}'
    'return;}'
    'if(e.querySelectorAll){var f=e.querySelectorAll("iframe");'
    'for(var i=0;i<f.length;i++){var src=f[i].getAttribute("src")||"";'
    'if(/doubleclick|googlesyndication|popads|popcash|taboola|outbrain|propellerads|adsterra|adcash|exoclick/i.test(src)){'
    'if(f[i].parentNode){f[i].parentNode.removeChild(f[i]);'
    'try{window.parent.postMessage({__filmkuAd:1},"*");}catch(err){}}}}'
    '}catch(err){}}'
    'if(window.MutationObserver){new MutationObserver(function(m){'
    'for(var i=0;i<m.length;i++){var n=m[i].addedNodes;'
    'for(var j=0;j<n.length;j++){if(n[j]&&n[j].nodeType===1)kill(n[j]);}}'
    '}).observe(document.documentElement,{childList:true,subtree:true});}'
    'setInterval(function(){var a=document.querySelectorAll("div,iframe");'
    'for(var i=0;i<a.length;i++)kill(a[i]);},2500);'
    'try{window.open=function(){return null;};}catch(err){}'
    'function report(){try{var v=document.querySelector("video");'
    'if(!v)return;var u=v.currentSrc||v.src||"";'
    'if(!u||u.indexOf("blob:")===0)return;'
    'window.parent.postMessage({__filmku:{url:u,t:v.currentTime||0}},"*");'
    '}catch(err){}}'
    'setInterval(report,1200);'
    'document.addEventListener("play",report,true);'
    'if(window===window.top){window.__filmku=null;window.__filmkuAds=0;'
    'window.addEventListener("message",function(ev){'
    'var d=ev.data;if(d&&d.__filmku&&d.__filmku.url)window.__filmku=d.__filmku;'
    'if(d&&d.__filmkuAd){window.__filmkuAds=(window.__filmkuAds||0)+1;}});}'
    '})();';

/// Injected alongside [embedAllFramesScript] at document-start into EVERY
/// frame (via `addUserScript(forMainFrameOnly: false)`) of the HIDDEN
/// capture WebView only. Some embed players sit behind a play-button overlay
/// or never autoplay without a gesture; this nudge programmatically clicks
/// common play affordances and calls `video.play()` so the player actually
/// starts and requests its `.m3u8`/`.mp4` (which the network interceptors
/// then capture). Idempotent guard `__filmkuNudge`.
const String embedAutoPlayNudgeScript = '(function(){'
    'if(window.__filmkuNudge)return;window.__filmkuNudge=true;'
    'function nudge(){try{'
    'var v=document.querySelector("video");'
    'if(v&&v.paused){var p=v.play();if(p&&p.catch)p.catch(function(){});}'
    'var els=document.querySelectorAll("[class*=play],[id*=play],button");'
    'for(var i=0;i<els.length;i++){var e=els[i];'
    'var s=((e.className&&e.className.toString)||"")+(e.id||"");'
    'if(/(play|start|watch)/i.test(s)&&e.offsetParent!==null){'
    'try{e.click();}catch(err){}}}}catch(err){}}'
    'nudge();setInterval(nudge,1500);'
    'document.addEventListener("play",function(){},true);'
    '})();';

/// Reads the relayed video (from any frame) or, as a fallback, a top-frame
/// `<video>` directly, plus the JS-side ad-strip counter. Returns
/// `JSON.stringify({url, t, ads})` (url may be `''` when nothing plays).
const String embedProbeScript = '(function(){'
    'var a=window.__filmkuAds||0;'
    'var f=window.__filmku;if(f&&f.url)return JSON.stringify({url:f.url,t:f.t||0,ads:a});'
    'var v=document.querySelector("video");'
    'if(v){var u=v.currentSrc||v.src||"";'
    'if(u&&u.indexOf("blob:")!==0&&u.indexOf("http")===0)'
    'return JSON.stringify({url:u,t:v.currentTime||0,ads:a});}'
    'return JSON.stringify({url:"",t:0,ads:a});'
    '})()';
