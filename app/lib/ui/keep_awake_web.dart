import 'dart:js_interop';

@JS('navigator.wakeLock')
external _WakeLock? get _wakeLock;

extension type _WakeLock._(JSObject _) implements JSObject {
  external JSPromise<_Sentinel> request(JSString type);
}

extension type _Sentinel._(JSObject _) implements JSObject {
  external JSPromise<JSAny?> release();
}

_Sentinel? _held;

/// 화면 꺼짐 막기를 켜거나 끈다. 브라우저가 지원하지 않거나 거절하면 조용히 넘어간다.
/// 탭이 가려지면 브라우저가 스스로 풀기 때문에, 돌아올 때 다시 켠다 (VoicePage가 부른다).
Future<void> setKeepAwake(bool on) async {
  try {
    if (on) {
      final lock = _wakeLock;
      if (lock == null) return;
      _held = await lock.request('screen'.toJS).toDart;
    } else {
      final held = _held;
      _held = null;
      if (held != null) await held.release().toDart;
    }
  } catch (_) {
    // 지원 안 함 · 거절
  }
}
