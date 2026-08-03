import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // FilmKU diagnostic logging bridge: mirrors Dart-side FILMKU_* lines into
    // the native system log (NSLog) so idevicesyslog / Console.app capture
    // them even in RELEASE builds — debugPrint is a no-op in release, which
    // made every "pull logcat on the iPhone" attempt come back empty while
    // playback was failing (see lib/core/utils/app_logger.dart).
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "FilmKULogger") {
      let channel = FlutterMethodChannel(name: "filmku/log", binaryMessenger: registrar.messenger())
      channel.setMethodCallHandler { call, result in
        if call.method == "log" {
          let args = call.arguments as? [String: Any]
          let tag = args?["tag"] as? String ?? ""
          let msg = args?["msg"] as? String ?? ""
          NSLog("[%@] %@", tag, msg)
          result(nil)
        } else {
          result(FlutterMethodNotImplemented)
        }
      }
    }
  }
}
