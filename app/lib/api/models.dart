/// 서버와 주고받는 데이터 (SPEC.md §7.2, §9). 위젯·컨트롤러를 모른다.
library;

/// 메시지 작성자.
enum Role { user, assistant }

/// 대화 메시지 하나.
class Message {
  const Message(this.role, this.content);

  final Role role;
  final String content;

  Map<String, String> toJson() => {'role': role.name, 'content': content};

  @override
  bool operator ==(Object other) => other is Message && other.role == role && other.content == content;

  @override
  int get hashCode => Object.hash(role, content);

  @override
  String toString() => 'Message(${role.name}, $content)';
}

/// POST /api/chat 스트림에서 오는 사건.
sealed class ChatEvent {
  const ChatEvent();
}

/// 응답 조각 (SSE `delta`).
final class ChatDelta extends ChatEvent {
  const ChatDelta(this.text);
  final String text;
}

/// 정상 종료 (SSE `done`).
final class ChatDone extends ChatEvent {
  const ChatDone(this.stopReason);
  final String stopReason;
}

/// 실패. [message]는 화면에 그대로 보여도 되는 문장이다 (SSE `error`, 오류 JSON, 연결 실패).
final class ChatFailed extends ChatEvent {
  const ChatFailed(this.message);
  final String message;
}

/// GET /api/config 결과 (SPEC.md API-002).
class ServerConfig {
  const ServerConfig({required this.provider, required this.model});
  final String provider;
  final String model;

  bool get isMock => provider == 'mock';
}
