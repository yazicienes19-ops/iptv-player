package com.enesyazici.iptv_player

import android.app.UiModeManager
import android.content.res.Configuration
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Meldet der Flutter-Seite, ob die App auf einem Fernseher läuft
        // (Android TV, Google TV, Fire TV), damit sie auf Fernbedienung umschaltet.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "pulse_media/device").setMethodCallHandler { call, result ->
            when (call.method) {
                "isTelevision" -> {
                    val uiMode = getSystemService(UI_MODE_SERVICE) as UiModeManager
                    val leanback = packageManager.hasSystemFeature("android.software.leanback")
                    result.success(uiMode.currentModeType == Configuration.UI_MODE_TYPE_TELEVISION || leanback)
                }
                else -> result.notImplemented()
            }
        }
    }
}
