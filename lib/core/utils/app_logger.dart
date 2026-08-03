import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// App-wide diagnostic logger.
///
/// 2026-08: `debugPrint` is a NO-OP in release builds (it is wrapped in an
/// `assert`), so every `FILMKU_*` diagnostic line never reached the device
/// log on the installed release build — "pull logcat on the iPhone" came back
/// empty even while playback was failing with HTTP 403/428 CDN rejections.
///
/// [appLog] fixes that:
///  - it uses plain `print` (NOT `debugPrint`), which still emits in release
///    builds — visible in logcat on Android (`flutter` tag) and in the
///    terminal on Linux;
///  - on iOS it ALSO mirrors the line into the native system log (`NSLog`)
///    through the `filmku/log` MethodChannel (handled in Runner's
///    AppDelegate), so `idevicesyslog` / Console.app capture it in release
///    builds.
///
/// Logging must never break playback — failures are swallowed.
void appLog(String tag, String message) {
  final line = '$tag $message';
  // ignore: avoid_print
  print(line);
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
    try {
      _channel.invokeMethod<void>('log', {'tag': tag, 'msg': message});
    } catch (_) {
      // Best-effort — logging must never break playback.
    }
  }
}

const MethodChannel _channel = MethodChannel('filmku/log');
