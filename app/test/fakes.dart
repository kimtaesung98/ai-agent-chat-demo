import 'dart:async';

import 'package:ai_agent_chat/api/chat_api.dart';
import 'package:ai_agent_chat/voice/voice_engine.dart';

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

  @override
  Future<ServerConfig> config() async => const ServerConfig(provider: 'mock', model: 'mock-echo');
}

/// 테스트가 들은 것을 직접 흘리고, 읽기 완료를 직접 정하는 가짜 엔진.
class FakeVoiceEngine implements VoiceEngine {
  FakeVoiceEngine([List<String>? log, this.canListen = true]) : log = log ?? [];

  final List<String> log;
  final _heard = StreamController<Heard>.broadcast(sync: true);
  final spoken = <String>[];
  final _pending = <Completer<void>>[];
  var listening = false;
  var cancels = 0;

  @override
  Future<bool> prepare() async => canListen;

  @override
  final bool canListen;
  @override
  bool get canSpeak => true;
  @override
  Stream<Heard> get heard => _heard.stream;

  void hear(Heard h) {
    if (h is HeardFinal || h is ListenEnded || h is ListenFailed) listening = false;
    _heard.add(h);
  }

  bool get hasPending => _pending.isNotEmpty;

  /// 지금 대기 중인 읽기를 끝낸다.
  void finishAll() {
    while (_pending.isNotEmpty) {
      _pending.removeAt(0).complete();
    }
  }

  @override
  void startListening() => listening = true;
  @override
  void stopListening() => listening = false;

  @override
  Future<void> speak(String sentence) {
    spoken.add(sentence);
    log.add('speak:$sentence');
    final c = Completer<void>();
    _pending.add(c);
    return c.future;
  }

  @override
  void cancelSpeech() {
    cancels++;
    finishAll();
  }

  @override
  void dispose() => _heard.close();
}
