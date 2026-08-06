package com.filmku.filmku

import android.content.pm.ActivityInfo
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Explicit (non-sensor) orientation lock. Flutter's
        // setPreferredOrientations maps to SCREEN_ORIENTATION_SENSOR_LANDSCAPE,
        // which MIUI ignores when the system auto-rotate is off — the player
        // stayed PORTRAIT on-device (Redmi Note 8 Pro, 2026-08): the 16:9
        // video rendered small in the middle and the bottom control bar never
        // reached the screen bottom ("controls in the middle" complaint).
        // Explicit setRequestedOrientation(LANDSCAPE) is honored regardless.
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "filmku/orientation",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "forceLandscape" -> {
                    requestedOrientation =
                        ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE
                    result.success(null)
                }
                "restore" -> {
                    requestedOrientation =
                        ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }
}
