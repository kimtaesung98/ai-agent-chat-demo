/// OpenAI GPT Realtime(WebRTC) 구현 (F-024, ADR-026). 웹 전용 — 브라우저의 `web/realtime.js`를 `dart:js_interop`으로 부른다.
/// 브라우저는 서버(API-007)가 지시문을 담아 발급한 임시 키만 쓴다. 대화 내용은 로그에 남기지 않는다.
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'openai_realtime.dart';
import 'realtime_agent.dart';

@JS('aiRealtime')
extension type _Realtime._(JSObject _) implements JSObject {
  external JSBoolean supported();
  external JSPromise<JSAny?> start(JSString secret, JSBoolean greet, JSFunction onEvent);
  external void stop();
  external void setMuted(JSBoolean muted);
}

@JS('aiRealtime')
external _Realtime get _realtime;

/// 이 플랫폼의 실시간 음성 에이전트. `realtime.js`가 없거나 브라우저가 WebRTC·마이크를 못 쓰면 null.
RealtimeAgent? createRealtimeAgent() {
  if (!globalContext.has('aiRealtime')) return null;
  try {
    if (!_realtime.supported().toDart) return null;
  } catch (_) {
    return null;
  }
  return OpenAiRealtimeAgent(_JsBridge());
}

class _JsBridge implements RealtimeBridge {
  @override
  Future<void> start(String secret, bool greet, void Function(String type, String text) onEvent) =>
      _realtime.start(secret.toJS, greet.toJS, ((JSString t, JSString x) => onEvent(t.toDart, x.toDart)).toJS).toDart;
  @override
  void stop() => _realtime.stop();
  @override
  void setMuted(bool muted) => _realtime.setMuted(muted.toJS);
}
