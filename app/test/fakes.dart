import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:ai_agent_chat/api/chat_api.dart';
import 'package:ai_agent_chat/chat/chat_controller.dart';
import 'package:ai_agent_chat/voice/agent_voice_controller.dart';
import 'package:ai_agent_chat/voice/realtime_agent.dart';

/// 요청마다 StreamController를 하나 열어 두는 가짜 API. 테스트가 이벤트를 직접 흘린다.
class FakeApi implements ChatApi {
  final requests = <List<Message>>[];
  final modes = <ChatMode>[];
  final personas = <PersonaRequest?>[];
  final memories = <List<SessionSummary>>[];
  final longTerms = <LongTermMemory?>[];

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
  }) {
    requests.add(messages);
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
