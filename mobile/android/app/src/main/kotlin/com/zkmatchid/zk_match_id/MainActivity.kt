package com.zkmatchid.zk_match_id

import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.view.WindowManager

class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "zk_matchid/secure_screen")
            .setMethodCallHandler { call, result ->
                if (call.method == "setSecure") {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    if (enabled) window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    else window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    result.success(null)
                } else result.notImplemented()
            }
    }
}
