/// 서버와 주고받는 데이터 (SPEC.md §7.2, §9). 위젯·컨트롤러를 모른다.
library;

/// 메시지 작성자.
enum Role { user, assistant }

/// 답 말투 (API-001 `mode`, F-012). voice면 서버가 짧은 구어체로 답하게 한다.
enum ChatMode { text, voice }

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

/// 대화 상대 페르소나 (F-005, SPEC.md API-001 `persona`). 값 객체 — 바꿀 때는 [copyWith].
class Persona {
  const Persona({required this.id, required this.name, this.role = '', this.tones = const [], this.instructions = ''});

  /// 화면에서만 쓰는 구분자. 서버에는 보내지 않는다.
  final String id;
  final String name;
  final String role;
  final List<String> tones;
  final String instructions;

  /// 서버 제한 (SPEC.md API-001). 화면 입력도 같은 값으로 막는다.
  static const maxName = 40, maxRole = 40, maxTones = 6, maxTone = 20, maxInstructions = 1000, maxAbout = 1000;

  /// 아바타 글자: 이름 마지막 낱말의 첫 글자 ("기획 파트너 지은" → "지").
  String get initial {
    final words = name.trim().split(RegExp(r'\s+'));
    final last = words.isEmpty ? '' : words.last;
    return last.isEmpty ? '?' : String.fromCharCode(last.runes.first);
  }

  /// 상단 바·목록에 보여 줄 한 줄 요약 (역할 · 말투).
  String get summary => [if (role.isNotEmpty) role, ...tones.take(3)].join(' · ');

  /// 기기 저장용 (Q-005). 서버로 보내는 [PersonaRequest.toJson]과 다르게 id까지 담는다.
  Map<String, Object> toStoreJson() => {
    'id': id,
    'name': name,
    if (role.isNotEmpty) 'role': role,
    if (tones.isNotEmpty) 'tones': tones,
    if (instructions.isNotEmpty) 'instructions': instructions,
  };

  /// 저장된 값을 읽는다. 모양이 틀리면 null, 길이는 서버 제한으로 자른다 (저장소는 믿지 않는다).
  static Persona? fromStoreJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'], name = json['name'];
    if (id is! String || id.isEmpty || name is! String || name.trim().isEmpty) return null;
    String cut(Object? v, int max) => v is String ? (v.length > max ? v.substring(0, max) : v) : '';
    final tones = json['tones'];
    return Persona(
      id: id,
      name: cut(name, maxName),
      role: cut(json['role'], maxRole),
      tones: [
        if (tones is List)
          for (final t in tones.take(maxTones))
            if (t is String && t.trim().isNotEmpty) cut(t, maxTone),
      ],
      instructions: cut(json['instructions'], maxInstructions),
    );
  }

  Persona copyWith({String? id, String? name, String? role, List<String>? tones, String? instructions}) => Persona(
    id: id ?? this.id,
    name: name ?? this.name,
    role: role ?? this.role,
    tones: tones ?? this.tones,
    instructions: instructions ?? this.instructions,
  );

  @override
  bool operator ==(Object other) =>
      other is Persona &&
      other.id == id &&
      other.name == name &&
      other.role == role &&
      other.instructions == instructions &&
      _listEquals(other.tones, tones);

  @override
  int get hashCode => Object.hash(id, name, role, instructions, Object.hashAll(tones));

  @override
  String toString() => 'Persona($id, $name)';
}

bool _listEquals(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// 요청에 싣는 페르소나와 내 프로필 (API-001 `persona`).
class PersonaRequest {
  const PersonaRequest(this.persona, {this.about = ''});

  final Persona persona;

  /// 내 프로필 (나에 대해). 모든 페르소나에 공통.
  final String about;

  /// 빈 필드는 보내지 않는다.
  Map<String, Object> toJson() => {
    'name': persona.name.trim(),
    if (persona.role.trim().isNotEmpty) 'role': persona.role.trim(),
    if (persona.tones.isNotEmpty) 'tones': persona.tones,
    if (persona.instructions.trim().isNotEmpty) 'instructions': persona.instructions.trim(),
    if (about.trim().isNotEmpty) 'about': about.trim(),
  };
}
