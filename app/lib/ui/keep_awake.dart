/// 음성 대화 화면이 떠 있는 동안 화면이 꺼지지 않게 한다 (SPEC.md F-018 AC8, F-025).
/// 화면이 꺼지면 브라우저가 마이크를 끊어 "늘 듣기"가 멈추기 때문이다. 새 패키지 없이 웹 Screen Wake Lock API만 쓴다.
library;

export 'keep_awake_none.dart' if (dart.library.js_interop) 'keep_awake_web.dart';
