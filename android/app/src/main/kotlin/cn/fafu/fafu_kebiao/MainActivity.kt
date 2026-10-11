package cn.fafu.fafu_kebiao

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.app.NotificationManager
import android.os.Build

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "cn.fafu/reminder_permissions")
            .setMethodCallHandler { call, result ->
                if (call.method == "canUseFullScreenIntent") {
                    val allowed = if (Build.VERSION.SDK_INT >= 34) {
                        getSystemService(NotificationManager::class.java).canUseFullScreenIntent()
                    } else true
                    result.success(allowed)
                } else result.notImplemented()
            }
    }
}
