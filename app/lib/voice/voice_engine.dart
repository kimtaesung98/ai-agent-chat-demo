/// 음성 인식(STT)·합성(TTS) 엔진 인터페이스 (ARCHITECTURE.md §4.2, ADR-014).
/// 컨트롤러는 이것만 알고, 테스트는 가짜 엔진을 쓴다. 웹 구현은 `web_speech_engine.dart`.
library;

/// 엔진이 들은 것.
sealed class Heard {
  const Heard();
}

/// 아직 말하는 중 — 인식 중인 문장 (미리 보기, 끼어들기 감지).
final class HeardPartial extends Heard {
  const HeardPartial(this.text);
  final String text;
}

/// 사용자가 말을 멈춤 — 확정된 문장 (자동 전송).
final class HeardFinal extends Heard {
  const HeardFinal(this.text);
  final String text;
}

/// 듣기가 결과 없이 끝남 (조용해서 시간 초과 등). 음성 모드면 다시 듣는다.
final class ListenEnded extends Heard {
  const ListenEnded();
}

/// 듣기 실패.
final class ListenFailed extends Heard {
  const ListenFailed(this.reason);
  final ListenFailure reason;
}

enum ListenFailure {
  /// 마이크 권한 거부
  notAllowed,

  /// 마이크 없음
  noMicrophone,

  /// 음성 인식 서버에 연결할 수 없음 (브라우저 음성 인식은 서버를 쓸 수 있다, R-A10)
  network,

  /// 그 밖의 오류
  other,
}

abstract interface class VoiceEngine {
  /// 엔진을 준비한다 (처음 한 번, 사용자가 마이크 버튼을 눌렀을 때). 듣기·읽기를 모두 쓸 수 있으면 true.
  Future<bool> prepare();

  /// 음성 인식을 쓸 수 있는지 (예: Firefox는 false). [prepare] 뒤에 의미가 있다.
  bool get canListen;

  /// 음성 합성을 쓸 수 있는지.
  bool get canSpeak;

  /// 들은 것 (broadcast).
  Stream<Heard> get heard;

  /// 한 번 듣기 시작한다. 말을 멈추면 [HeardFinal] 하나를 내고 끝난다. 이미 듣는 중이면 아무것도 하지 않는다.
  void startListening();

  void stopListening();

  /// 문장 하나를 읽는다. 다 읽거나 [cancelSpeech]로 멈추면 완료된다. 앞 문장이 남아 있으면 뒤에 이어 읽는다.
  Future<void> speak(String sentence);

  /// 읽는 중인 문장과 대기 중인 문장을 모두 멈춘다.
  void cancelSpeech();

  void dispose();
}

/// 음성을 지원하지 않는 플랫폼용 엔진.
class UnsupportedVoiceEngine implements VoiceEngine {
  @override
  Future<bool> prepare() async => false;
  @override
  bool get canListen => false;
  @override
  bool get canSpeak => false;
  @override
  Stream<Heard> get heard => const Stream.empty();
  @override
  void startListening() {}
  @override
  void stopListening() {}
  @override
  Future<void> speak(String sentence) async {}
  @override
  void cancelSpeech() {}
  @override
  void dispose() {}
}
