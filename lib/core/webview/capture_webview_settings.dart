import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../constants/app_constants.dart';

/// Shared WebView settings for every capture-capable WebView in the app
/// (hidden auto-capture, visible WebView fallback, and the headless
/// extractor).
///
/// **Why interception flags are mandatory here (on-device evidence 2026-08):**
/// on Android, `shouldInterceptRequest`/`shouldInterceptFetchRequest`/
/// `shouldInterceptAjaxRequest` fire by default, so the hidden capture sees
/// the player's `.m3u8`/`.mp4` requests and jumps straight into the native
/// (mpv) player. On iOS these callbacks are **disabled by default** —
/// `flutter_inappwebview_ios` ships `useShouldInterceptFetchRequest = false`
/// and `useShouldInterceptAjaxRequest = false` — so without explicitly
/// enabling them the capture times out on every provider and the app falls
/// back to the visible (ad-rendering) WebView. Setting them explicitly fixes
/// the iOS "finding stream → play in WebView" detour while being a no-op on
/// Android.
///
/// [captureEnabled] can be turned off for plain browsing WebViews that should
/// never observe or block requests.
InAppWebViewSettings buildCaptureWebViewSettings({bool captureEnabled = true}) {
  return InAppWebViewSettings(
    userAgent: AppConstants.defaultUserAgent,
    javaScriptEnabled: true,
    mediaPlaybackRequiresUserGesture: false,
    allowsInlineMediaPlayback: true,
    // Some players open a popup/blank target for their player iframe — the
    // visible WebView proves this setting is needed, so mirror it everywhere.
    javaScriptCanOpenWindowsAutomatically: true,
    // iOS defaults these to false (Android defaults them on) — explicit here
    // so the native interception callbacks fire on BOTH platforms.
    useShouldInterceptRequest: captureEnabled,
    useShouldInterceptFetchRequest: captureEnabled,
    useShouldInterceptAjaxRequest: captureEnabled,
  );
}
