import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:ai_agent_chat/api/account_api.dart';
import 'package:ai_agent_chat/api/chat_api.dart';
import 'package:ai_agent_chat/chat/chat_controller.dart';
import 'package:ai_agent_chat/chat/persona_controller.dart' show defaultPersonas;
import 'package:ai_agent_chat/voice/agent_voice_controller.dart';
import 'package:ai_agent_chat/voice/realtime_agent.dart';

/// 요청마다 StreamController를 하나 열어 두는 가짜 API. 테스트가 이벤트를 직접 흘린다.
class FakeApi implements ChatApi {
  final requests = <List<Message>>[];
  final modes = <ChatMode>[];
  final personas = <PersonaRequest?>[];
  final memories = <List<SessionSummary>>[];
  final longTerms = <LongTermMemory?>[];

  /// 요청마다 보낸 대화 id (F-028). 기기 대화면 null.
  final conversationIds = <String?>[];

  /// 장기 기억 요청 (F-020).
  final consolidateRequests = <List<SessionSummary>>[];
  final consolidatePrevious = <LongTermMemory?>[];
  final consolidateReplies = <Completer<Map<String, Object?>>>[];
  final streams = <StreamController<ChatEvent>>[];
  var cancels = 0;

  /// 요약 요청 (F-019). 테스트가 [summaryReplies]로 답을 정한다 — 비어 있으면 정해진 요약.
  final summaryRequests = <List<Message>>[];
  final summaryPersonas = <PersonaRequest?>[];
  final summaryReplies = <Completer<Map<String, Object?>>>[];

  StreamController<ChatEvent> get current => streams.last;

  @override
  Stream<ChatEvent> stream(
    List<Message> messages, {
    ChatMode mode = ChatMode.text,
    PersonaRequest? persona,
    List<SessionSummary> memory = const [],
    LongTermMemory? longTerm,
    String? conversationId,
  }) {
    requests.add(messages);
    conversationIds.add(conversationId);
    longTerms.add(longTerm);
    personas.add(persona);
    memories.add(memory);
    modes.add(mode);
    final c = StreamController<ChatEvent>(onCancel: () => cancels++);
    streams.add(c);
    return c.stream;
  }

  @override
  Future<Map<String, Object?>> summarize(List<Message> messages, {PersonaRequest? persona}) {
    summaryRequests.add(messages);
    summaryPersonas.add(persona);
    if (summaryReplies.isNotEmpty) return summaryReplies.removeAt(0).future;
    return Future.value({
      'summary': '요약 ${summaryRequests.length}: ${messages.first.content}',
      'facts': ['사실'],
      'followUps': <String>[],
    });
  }

  @override
  Future<Map<String, Object?>> consolidate(
    List<SessionSummary> sessions, {
    PersonaRequest? persona,
    LongTermMemory? longTerm,
  }) {
    consolidateRequests.add(sessions);
    consolidatePrevious.add(longTerm);
    if (consolidateReplies.isNotEmpty) return consolidateReplies.removeAt(0).future;
    return Future.value({
      'summary': '장기 ${consolidateRequests.length}: ${sessions.length}개',
      'facts': ['오래 기억할 것'],
    });
  }

  /// 서버 설정 (F-024: [voiceAgent]면 실시간 음성 대화를 쓴다).
  ServerConfig serverConfig = const ServerConfig(provider: 'mock', model: 'mock-echo', voiceAgent: true);

  /// 남은 횟수만큼 설정 요청이 실패한다.
  var configFailures = 0;

  @override
  Future<ServerConfig> config() async {
    if (configFailures > 0) {
      configFailures--;
      throw StateError('연결 실패');
    }
    return serverConfig;
  }

  /// 실시간 음성 임시 키 요청 수(API-007). [tokenFails]면 [VoiceTokenFailed].
  var tokenRequests = 0;
  var tokenFails = false;

  /// 마지막 API-007 요청의 context (F-024).
  Map<String, Object?>? lastSessionContext;

  @override
  Future<String> voiceSession(Map<String, Object?> context) async {
    tokenRequests++;
    lastSessionContext = context;
    if (tokenFails) throw const VoiceTokenFailed();
    return 'ek-$tokenRequests';
  }
}

/// 테스트가 사건을 직접 흘리는 가짜 실시간 에이전트 (F-024).
class FakeAgent implements RealtimeAgent {
  @override
  final ValueNotifier<double> level = ValueNotifier(0);

  final _events = StreamController<AgentEvent>.broadcast(sync: true);
  final starts = <({String token, Map<String, Object?> context})>[];
  final muted = <bool>[];
  var ends = 0;
  var failStart = false;
  var hang = false; // 실패도 끊김도 알리지 않고 멈춘다

  /// 연결 시작하면 바로 [AgentConnected]를 알린다 (화면 테스트용).
  var autoConnect = false;

  void emit(AgentEvent e) => _events.add(e);

  @override
  Stream<AgentEvent> get events => _events.stream;

  @override
  Future<void> start({required String token, required Map<String, Object?> context}) async {
    starts.add((token: token, context: context));
    if (failStart) throw StateError('연결 실패');
    if (hang) await Completer<void>().future;
    if (autoConnect) emit(const AgentConnected());
  }

  @override
  Future<void> end() async => ends++;

  @override
  Future<void> setMuted(bool m) async => muted.add(m);

  @override
  void dispose() => _events.close();
}

/// 화면 테스트용 실시간 음성: 가짜 에이전트가 연결을 바로 알린다. [chat]은 [api]를 써야 한다.
({AgentVoiceController voice, FakeAgent agent}) fakeRealtimeVoice(
  ChatController chat,
  FakeApi api, {
  bool supported = true,
}) {
  final agent = FakeAgent()..autoConnect = true;
  final voice = AgentVoiceController(
    chat,
    api.voiceSession,
    agent: supported ? agent : null,
    retryDelay: const Duration(milliseconds: 100),
  );
  return (voice: voice, agent: agent);
}

/// 메모리 안의 가짜 계정 서버 (F-026~F-028). 테스트가 [fail]로 다음 요청을 실패시킨다.
class FakeAccountApi implements AccountApi {
  FakeAccountApi({this.user, this.google = false});

  /// 지금 세션의 사람. null이면 로그인 전.
  ServerUser? user;
  bool google;
  String code = 'K7QM4XPH2R';
  final calls = <String>[];

  /// 이름 → 다음 한 번 그 요청을 실패시킬 오류.
  final fail = <String, AccountApiError>{};

  ServerProfile profileValue = const ServerProfile();
  final profileUpdates = <Map<String, Object?>>[];
  var _seq = 0;
  late final List<Persona> serverPersonas = [
    for (final p in defaultPersonas) p.copyWith(id: 'per_${p.id}', presetId: p.id, revision: 1),
  ];
  final summaries = <SessionSummary>[];
  final longTerms = <String, LongTermMemory>{};
  final opened = <({String personaId, String channel})>[];
  final ended = <({String id, List<Message> messages})>[];
  final imports = <Map<String, Object?>>[];

  /// 열린 대화 요청이 끝나지 않게 잡아 둘 때.
  Completer<void>? holdOpen;

  Future<T> _call<T>(String name, T Function() body) async {
    calls.add(name);
    await Future<void>.delayed(Duration.zero);
    if (fail.remove(name) case final e?) throw e;
    if (user == null && !name.startsWith('options') && !name.startsWith('login')) {
      throw const AccountApiError(401, 'UNAUTHENTICATED', '로그인이 필요해요.');
    }
    return body();
  }

  @override
  Future<AuthOptions> options() => _call(
    'options',
    () => AuthOptions(google: google, googleClientId: google ? 'cid.apps.googleusercontent.com' : ''),
  );

  static const badCode = AccountApiError(401, 'BAD_CODE', '코드를 다시 확인해 주세요.');

  @override
  Future<ServerUser> loginWithCode(String c) => _call('loginCode', () {
    if (c.replaceAll('-', '').toUpperCase() != code) throw badCode;
    return user = const ServerUser(id: 'usr_elder', name: '김순자', role: 'elder');
  });

  @override
  Future<ServerUser> loginWithGoogle(String idToken) => _call('loginGoogle', () {
    if (idToken != 'good-token') throw const AccountApiError(403, 'NOT_INVITED', '초대받지 않은 Google 계정이에요.');
    return user = const ServerUser(id: 'usr_guard', name: '김보호', role: 'guardian', google: true);
  });

  @override
  Future<ServerUser?> me() async {
    calls.add('me');
    await Future<void>.delayed(Duration.zero);
    if (fail.remove('me') case final e?) throw e;
    return user;
  }

  @override
  Future<void> logout() => _call('logout', () => user = null);

  @override
  Future<ServerProfile> profile() => _call('profile', () => profileValue);

  @override
  Future<void> updateProfile({String? about, String? textSize, bool? voiceOnStart, String? lastPersonaId}) =>
      _call('updateProfile', () {
        profileUpdates.add({
          'about': ?about,
          'textSize': ?textSize,
          'voiceOnStart': ?voiceOnStart,
          'lastPersonaId': ?lastPersonaId,
        });
      });

  @override
  Future<List<Persona>> personas() => _call('personas', () => [...serverPersonas]);

  @override
  Future<Persona> createPersona(Persona p) => _call('createPersona', () {
    final saved = p.copyWith(id: 'per_new${_seq++}', revision: 1);
    serverPersonas.add(saved);
    return saved;
  });

  @override
  Future<Persona> updatePersona(Persona p) => _call('updatePersona', () {
    final i = serverPersonas.indexWhere((e) => e.id == p.id);
    if (i < 0) throw const AccountApiError(404, 'NOT_FOUND', '찾을 수 없어요.');
    final current = serverPersonas[i];
    if (current.revision != p.revision) {
      throw AccountApiError(409, 'CONFLICT', '충돌', body: {'persona': _v1(current)});
    }
    return serverPersonas[i] = p.copyWith(revision: p.revision + 1);
  });

  static Map<String, Object?> _v1(Persona p) => {...p.toV1Json(), 'id': p.id, 'base': p.base};

  @override
  Future<void> deletePersona(String id) => _call('deletePersona', () => serverPersonas.removeWhere((p) => p.id == id));

  @override
  Future<ServerMemory> memory(String personaId) => _call(
    'memory',
    () =>
        ServerMemory(summaries: [...summaries.where((s) => s.personaId == personaId)], longTerm: longTerms[personaId]),
  );

  @override
  Future<void> clearMemory(String personaId) => _call('clearMemory', () {
    summaries.removeWhere((s) => s.personaId == personaId);
    longTerms.remove(personaId);
  });

  @override
  Future<void> deleteSummary(String id) => _call('deleteSummary', () => summaries.removeWhere((s) => s.id == id));

  @override
  Future<String> openConversation(String personaId, {String channel = 'text'}) async {
    if (holdOpen case final h?) await h.future;
    return _call('openConversation', () {
      opened.add((personaId: personaId, channel: channel));
      return 'cnv_${opened.length}';
    });
  }

  @override
  Future<EndedConversation> endConversation(String id, List<Message> messages) => _call('endConversation', () {
    ended.add((id: id, messages: messages));
    final personaId = opened[int.parse(id.substring(4)) - 1].personaId;
    final s = SessionSummary(
      id: 'sum_${ended.length}',
      personaId: personaId,
      endedAt: DateTime.utc(2026, 11, 15),
      summary: '서버 요약: ${messages.first.content}',
    );
    summaries
      ..removeWhere((e) => e.id == s.id)
      ..add(s);
    return EndedConversation(s);
  });

  @override
  Future<Map<String, Object?>> importDevice(Map<String, Object?> payload) => _call('import', () {
    imports.add(payload);
    return {'personasCreated': 0};
  });
}
