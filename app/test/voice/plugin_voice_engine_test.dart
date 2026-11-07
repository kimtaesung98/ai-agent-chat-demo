import 'package:ai_agent_chat/voice/plugin_voice_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // main()에서 runApp 전에 엔진을 만든다. 플러그인을 생성자에서 만들면 바인딩이 없어 앱이 시작하자마자 멈춘다.
  test('F-012 음성 엔진은 Flutter 바인딩 전에 만들어도 된다 (플러그인은 처음 쓸 때 생성)', () {
    final engine = PluginVoiceEngine();
    expect(engine.canListen, isFalse, reason: 'prepare 전에는 쓸 수 없다고 답한다');
    expect(engine.canSpeak, isFalse);
    engine.dispose();
  });
}
