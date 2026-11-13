/// OpenAI Realtime 에이전트 (F-024, ADR-026): `web/realtime.js`가 알려 주는 사건을 [AgentEvent]로 바꾼다.
/// JS와는 [RealtimeBridge]로만 이야기해서, 위젯·브라우저 없이 가짜 다리로 단위 테스트한다.
/// 실제 다리(`dart:js_interop`)는 `openai_realtime_agent.dart`(웹 전용).
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'realtime_agent.dart';

/// JS 쪽과 이야기하는 얇은 다리. 테스트는 가짜를 넣는다.
abstract interface class RealtimeBridge {
  Future<void> start(String secret, bool greet, void Function(String type, String text) onEvent);
  void stop();
  void setMuted(bool muted);
}

class OpenAiRealtimeAgent implements RealtimeAgent {
  OpenAiRealtimeAgent(this._bridge);

  final RealtimeBridge _bridge;
  final _events = StreamController<AgentEvent>.broadcast();
  final _level = ValueNotifier<double>(0);
  var _gen = 0; // 연결마다 늘려, 끊은 연결의 늦은 사건을 버린다

  @override
  Stream<AgentEvent> get events => _events.stream;

  @override
  ValueListenable<double> get level => _level;

  void _emit(AgentEvent e) {
    if (!_events.isClosed) _events.add(e);
  }

  void _onEvent(int gen, String type, String text) {
    if (gen != _gen) return;
    switch (type) {
      case 'connected':
        _emit(const AgentConnected());
      case 'disconnected':
        _level.value = 0;
        _emit(const AgentDisconnected());
      case 'user_speaking':
        _emit(const AgentHeardPartial(''));
      case 'heard_partial':
        _emit(AgentHeardPartial(text));
      case 'heard':
        _emit(AgentHeard(text));
      case 'speaking':
        _emit(const AgentMode(speaking: true));
      case 'listening':
        _emit(const AgentMode(speaking: false));
      case 'reply':
        _emit(AgentReply(text));
      case 'level':
        _level.value = double.tryParse(text) ?? 0;
      case 'mic_denied':
        _emit(const AgentFailed(micDenied: true));
      case 'error':
        debugPrint('실시간 음성 오류'); // 원문에 대화 내용이 섞일 수 있어 남기지 않는다
        _emit(const AgentFailed());
    }
  }

  @override
  Future<void> start({required String token, required Map<String, Object?> context}) {
    final gen = ++_gen;
    final history = context['history'];
    final greet = history is! List || history.isEmpty; // 처음 연결이면 먼저 인사, 다시 연결이면 이어서
    return _bridge.start(token, greet, (t, x) => _onEvent(gen, t, x));
  }

  @override
  Future<void> end() async {
    _gen++;
    _level.value = 0;
    _bridge.stop();
    _emit(const AgentDisconnected(byUser: true));
  }

  @override
  Future<void> setMuted(bool muted) async => _bridge.setMuted(muted);

  @override
  void dispose() {
    _gen++;
    _bridge.stop();
    unawaited(_events.close());
    _level.dispose();
  }
}
