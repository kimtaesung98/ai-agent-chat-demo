package dev.kimtaesung98.ai_agent_chat

import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // 음성 대화 화면이 떠 있는 동안 화면이 꺼지지 않게 한다 — 꺼지면 마이크가 끊긴다 (F-018 AC8)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "ai_agent_chat/screen").setMethodCallHandler { call, result ->
            if (call.method == "keepOn") {
                if (call.arguments == true) {
                    window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                } else {
                    window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                }
                result.success(null)
            } else {
                result.notImplemented()
            }
        }
    }
}
