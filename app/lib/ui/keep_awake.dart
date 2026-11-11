/// 음성 대화 화면이 떠 있는 동안 화면이 꺼지지 않게 한다 (SPEC.md F-018 AC8).
/// 화면이 꺼지면 OS가 마이크를 끊어 "늘 듣기"가 멈추기 때문이다. 새 패키지 없이 플랫폼 기능만 쓴다:
/// 웹은 Screen Wake Lock API, Android는 `FLAG_KEEP_SCREEN_ON`, iOS는 `isIdleTimerDisabled` (네이티브 채널).
library;

export 'keep_awake_io.dart' if (dart.library.js_interop) 'keep_awake_web.dart';
