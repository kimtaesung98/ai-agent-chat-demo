import 'package:flutter/services.dart';

const _channel = MethodChannel('ai_agent_chat/screen');

/// 화면 꺼짐 막기를 켜거나 끈다. 지원하지 않는 곳(테스트·데스크톱)에서는 조용히 넘어간다.
Future<void> setKeepAwake(bool on) async {
  try {
    await _channel.invokeMethod<void>('keepOn', on);
  } on MissingPluginException {
    // 채널이 없는 플랫폼
  } on PlatformException {
    // 실패해도 대화는 계속한다
  }
}
