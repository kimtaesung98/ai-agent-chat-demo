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

/// 실시간 음성 토큰을 받지 못함 (F-022, API-005). 앱은 기기 음성(F-012)으로 대화한다.
class VoiceTokenFailed implements Exception {
  const VoiceTokenFailed();
}

/// GET /api/config 결과 (SPEC.md API-002).
class ServerConfig {
  const ServerConfig({required this.provider, required this.model, this.voiceAgent = false});
  final String provider;
  final String model;

  /// 서버가 실시간 음성 대화(ElevenLabs Agents) 토큰을 줄 수 있는지 (F-022, API-002 `voiceAgent`).
  final bool voiceAgent;

  bool get isMock => provider == 'mock';
}

/// 대화 상대 페르소나 (F-005, SPEC.md API-001 `persona`). 값 객체 — 바꿀 때는 [copyWith].
/// 지시는 두 층이다 (F-019): [base]는 페르소나를 정하는 기본 지시(탑재 페르소나는 앱에 고정),
/// [instructions]는 사용자가 덧붙이는 요구 사항.
class Persona {
  const Persona({
    required this.id,
    required this.name,
    this.role = '',
    this.tones = const [],
    this.base = '',
    this.instructions = '',
  });

  /// 화면에서만 쓰는 구분자. 서버에는 보내지 않는다.
  final String id;
  final String name;
  final String role;
  final List<String> tones;

  /// 기본 지시 (API-001 `persona.base`).
  final String base;

  /// 사용자의 요구 사항 (API-001 `persona.instructions`).
  final String instructions;

  /// 서버 제한 (SPEC.md API-001). 화면 입력도 같은 값으로 막는다.
  static const maxName = 40,
      maxRole = 40,
      maxTones = 6,
      maxTone = 20,
      maxBase = 1000,
      maxInstructions = 1000,
      maxAbout = 1000;

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
    if (base.isNotEmpty) 'base': base,
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
      base: cut(json['base'], maxBase),
      instructions: cut(json['instructions'], maxInstructions),
    );
  }

  Persona copyWith({String? id, String? name, String? role, List<String>? tones, String? base, String? instructions}) =>
      Persona(
        id: id ?? this.id,
        name: name ?? this.name,
        role: role ?? this.role,
        tones: tones ?? this.tones,
        base: base ?? this.base,
        instructions: instructions ?? this.instructions,
      );

  @override
  bool operator ==(Object other) =>
      other is Persona &&
      other.id == id &&
      other.name == name &&
      other.role == role &&
      other.base == base &&
      other.instructions == instructions &&
      _listEquals(other.tones, tones);

  @override
  int get hashCode => Object.hash(id, name, role, base, instructions, Object.hashAll(tones));

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
    if (persona.base.trim().isNotEmpty) 'base': persona.base.trim(),
    if (persona.instructions.trim().isNotEmpty) 'instructions': persona.instructions.trim(),
    if (about.trim().isNotEmpty) 'about': about.trim(),
  };
}

/// 사람이 읽는 날짜 (기기 시간대) — `2026-11-11`.
String dayString(DateTime at) {
  final t = at.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)}';
}

/// 끝난 대화 세션 하나의 요약 (F-019, SPEC.md API-003). 기기에 저장해 두고 다음 대화 요청의 `memory`에 싣는다.
class SessionSummary {
  const SessionSummary({
    required this.id,
    required this.personaId,
    required this.endedAt,
    required this.summary,
    this.facts = const [],
    this.followUps = const [],
    this.turns = 0,
  });

  /// 대화 세션 구분자. 같은 세션을 다시 정리하면 같은 id로 바꾼다.
  final String id;

  /// 이 대화를 나눈 페르소나. 기억은 페르소나마다 따로 쌓인다.
  final String personaId;
  final DateTime endedAt;

  /// 무엇을 이야기했는지 (2~4문장).
  final String summary;

  /// 사용자에 대해 새로 알게 된 것.
  final List<String> facts;

  /// 다음에 이어 갈 것.
  final List<String> followUps;

  /// 정리할 때 사용자 메시지 수.
  final int turns;

  /// 서버 제한 (API-001 `memory`, API-003 응답과 같다).
  static const maxSummary = 600, maxFacts = 5, maxFollowUps = 3, maxItem = 100;

  /// 사람이 읽는 날짜 (기기 시간대) — `2026-11-11`.
  String get date => dayString(endedAt);

  /// API-003 응답을 읽는다. 모양이 틀리거나 요약이 비면 null.
  static SessionSummary? fromApiJson(
    Object? json, {
    required String id,
    required String personaId,
    required DateTime endedAt,
    int turns = 0,
  }) {
    if (json is! Map) return null;
    final summary = _cut(json['summary'], maxSummary).trim();
    if (summary.isEmpty) return null;
    return SessionSummary(
      id: id,
      personaId: personaId,
      endedAt: endedAt,
      summary: summary,
      facts: _list(json['facts'], maxFacts),
      followUps: _list(json['followUps'], maxFollowUps),
      turns: turns,
    );
  }

  /// API-001 `memory` 항목.
  Map<String, Object> toRequestJson() => {'date': date, 'summary': summary, 'facts': facts, 'followUps': followUps};

  /// 기기 저장용 (Q-005 · F-019).
  Map<String, Object> toStoreJson() => {
    'id': id,
    'personaId': personaId,
    'endedAt': endedAt.toUtc().toIso8601String(),
    'summary': summary,
    'facts': facts,
    'followUps': followUps,
    'turns': turns,
  };

  /// 저장된 값을 읽는다. 모양이 틀리면 null (저장소는 믿지 않는다).
  static SessionSummary? fromStoreJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'], personaId = json['personaId'], endedAt = json['endedAt'], turns = json['turns'];
    if (id is! String || id.isEmpty || personaId is! String || personaId.isEmpty || endedAt is! String) return null;
    final at = DateTime.tryParse(endedAt);
    if (at == null) return null;
    return fromApiJson(json, id: id, personaId: personaId, endedAt: at, turns: turns is int ? turns : 0);
  }

  static String _cut(Object? v, int max) => v is String ? (v.length > max ? v.substring(0, max) : v) : '';

  static List<String> _list(Object? v, int max) => [
    if (v is List)
      for (final s in v.whereType<String>().map((s) => _cut(s, maxItem).trim()).where((s) => s.isNotEmpty).take(max)) s,
  ];

  @override
  String toString() => 'SessionSummary($id, $personaId, $summary)';
}

/// 오래된 대화 요약을 묶은 장기 기억 (F-020, SPEC.md API-004). 페르소나마다 하나, 기기에 저장한다.
class LongTermMemory {
  const LongTermMemory({
    required this.personaId,
    required this.summary,
    this.facts = const [],
    required this.updatedAt,
    required this.coversUntil,
  });

  final String personaId;

  /// 지금까지 함께 나눈 이야기의 흐름 (1,000자).
  final String summary;

  /// 오래 기억할 사실 (최대 10개).
  final List<String> facts;
  final DateTime updatedAt;

  /// 이 시각까지 끝난 세션 요약을 묶었다. 그 뒤 세션만 다음에 묶는다.
  final DateTime coversUntil;

  /// 서버 제한 (API-001 `longTerm`, API-004 응답과 같다).
  static const maxSummary = 1000, maxFacts = 10, maxItem = 100;

  /// API-004 응답을 읽는다. 모양이 틀리거나 요약이 비면 null.
  static LongTermMemory? fromApiJson(
    Object? json, {
    required String personaId,
    required DateTime updatedAt,
    required DateTime coversUntil,
  }) {
    if (json is! Map) return null;
    final summary = SessionSummary._cut(json['summary'], maxSummary).trim();
    if (summary.isEmpty) return null;
    final facts = json['facts'];
    return LongTermMemory(
      personaId: personaId,
      summary: summary,
      facts: [
        if (facts is List)
          for (final f
              in facts
                  .whereType<String>()
                  .map((f) => SessionSummary._cut(f, maxItem).trim())
                  .where((f) => f.isNotEmpty)
                  .take(maxFacts))
            f,
      ],
      updatedAt: updatedAt,
      coversUntil: coversUntil,
    );
  }

  /// API-001 `longTerm` · API-004 `longTerm`.
  Map<String, Object> toRequestJson() => {'summary': summary, 'facts': facts};

  Map<String, Object> toStoreJson() => {
    'personaId': personaId,
    'summary': summary,
    'facts': facts,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'coversUntil': coversUntil.toUtc().toIso8601String(),
  };

  static LongTermMemory? fromStoreJson(Object? json) {
    if (json is! Map) return null;
    final personaId = json['personaId'];
    final updated = DateTime.tryParse(json['updatedAt'] is String ? json['updatedAt'] as String : '');
    final covers = DateTime.tryParse(json['coversUntil'] is String ? json['coversUntil'] as String : '');
    if (personaId is! String || personaId.isEmpty || updated == null || covers == null) return null;
    return fromApiJson(json, personaId: personaId, updatedAt: updated, coversUntil: covers);
  }

  @override
  String toString() => 'LongTermMemory($personaId, $summary)';
}
