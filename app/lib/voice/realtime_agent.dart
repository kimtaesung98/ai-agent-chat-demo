/// 실시간 음성 대화 에이전트 인터페이스 (F-022, ARCHITECTURE.md ADR-025).
/// 듣기·말하기·끼어들기·말이 끝났는지 판단은 에이전트(ElevenLabs Agents)가 하고, 앱은 상태와 자막만 받는다.
/// 컨트롤러는 이것만 알고, 테스트는 가짜를 쓴다. 구현은 `elevenlabs_agent.dart`.
library;

/// 에이전트가 알려 주는 일.
sealed class AgentEvent {
  const AgentEvent();
}

/// 연결됨 — 이제 듣는다.
final class AgentConnected extends AgentEvent {
  const AgentConnected();
}

/// 연결이 끊김. [byUser]면 앱이 끊었다.
final class AgentDisconnected extends AgentEvent {
  const AgentDisconnected({this.byUser = false});
  final bool byUser;
}

/// 에이전트가 말하기 시작함([speaking]) 또는 다시 듣기 시작함.
final class AgentMode extends AgentEvent {
  const AgentMode({required this.speaking});
  final bool speaking;
}

/// 사용자가 말하는 중 — 인식 중인 문장.
final class AgentHeardPartial extends AgentEvent {
  const AgentHeardPartial(this.text);
  final String text;
}

/// 사용자 말이 끝남 — 확정된 문장.
final class AgentHeard extends AgentEvent {
  const AgentHeard(this.text);
  final String text;
}

/// 에이전트 답 (확정). 끼어들기로 잘렸으면 말한 데까지일 수 있다.
final class AgentReply extends AgentEvent {
  const AgentReply(this.text);
  final String text;
}

/// 오류. 원문은 화면에 보이지 않는다.
final class AgentFailed extends AgentEvent {
  const AgentFailed();
}

abstract interface class RealtimeAgent {
  /// 에이전트가 알려 주는 일 (broadcast).
  Stream<AgentEvent> get events;

  /// [token](서버가 발급, API-005)으로 연결한다. [context]는 Custom LLM 요청의 `elevenlabs_extra_body`로,
  /// [variables]는 에이전트 설정의 `{{이름}}` 동적 변수로 간다. 실패하면 예외.
  Future<void> start({
    required String token,
    required Map<String, Object?> context,
    required Map<String, String> variables,
  });

  /// 연결을 끊는다.
  Future<void> end();

  /// 마이크를 잠깐 끈다/켠다 (앱이 뒤로 갔을 때).
  Future<void> setMuted(bool muted);

  void dispose();
}
