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
    // 음성 대화 화면이 떠 있는 동안 화면이 꺼지지 않게 한다 — 꺼지면 마이크가 끊긴다 (F-018 AC8)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "ScreenAwake") {
      let channel = FlutterMethodChannel(name: "ai_agent_chat/screen", binaryMessenger: registrar.messenger())
      channel.setMethodCallHandler { call, result in
        if call.method == "keepOn" {
          UIApplication.shared.isIdleTimerDisabled = (call.arguments as? Bool) ?? false
          result(nil)
        } else {
          result(FlutterMethodNotImplemented)
        }
      }
    }
  }
}
