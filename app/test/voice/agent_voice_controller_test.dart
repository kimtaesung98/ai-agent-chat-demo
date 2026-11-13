import 'dart:async';

import 'package:ai_agent_chat/api/chat_api.dart';
import 'package:ai_agent_chat/chat/chat_controller.dart';
import 'package:ai_agent_chat/chat/memory_controller.dart';
import 'package:ai_agent_chat/chat/persona_controller.dart';
import 'package:ai_agent_chat/voice/agent_voice_controller.dart';
import 'package:ai_agent_chat/voice/realtime_agent.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes.dart';

void main() {
  late FakeApi api;
  late PersonaController personas;
  late MemoryController memory;
  late ChatController chat;
  late FakeAgent agent;
  late AgentVoiceController voice;

  Future<void> flush() => pumpEventQueue();

  Future<void> setUpWith({
    bool voiceAgent = true,
    bool withAgent = true,
    bool loadConfig = true,
    Duration connectTimeout = const Duration(seconds: 5),
  }) async {
    api = FakeApi()..serverConfig = ServerConfig(provider: 'mock', model: 'm', voiceAgent: voiceAgent);
    personas = PersonaController();
    memory = MemoryController();
    chat = ChatController(api, personas: personas, memory: memory);
    if (loadConfig) await chat.loadConfig();
    agent = FakeAgent();
    voice = AgentVoiceController(
      chat,
      api.voiceSession, // main.dart와 같은 연결 (API-007)
      agent: withAgent ? agent : null,
      retryDelay: const Duration(milliseconds: 1),
      connectTimeout: connectTimeout,
    );
  }

  tearDown(() {
    voice.dispose();
    chat.dispose();
  });

  test('F-024 AC4 서버가 켜 두었으면 맥락을 담아 임시 키(API-007)를 받고 그것으로만 연결하며, 연결되면 듣는다', () async {
    await setUpWith();
    await voice.start();
    expect(api.tokenRequests, 1);
    expect(agent.starts.single.token, 'ek-1');
    expect(api.lastSessionContext!['persona'], isNotNull, reason: '서버가 지시문을 만들 페르소나');
    expect(api.lastSessionContext!.containsKey('history'), isTrue);
    expect(agent.starts.single.context, same(api.lastSessionContext), reason: '같은 맥락으로 연결');
    expect(voice.state, VoiceState.thinking);
    expect(voice.notice, AgentMessages.connecting);
    agent.emit(const AgentConnected());
    expect(voice.state, VoiceState.listening);
    expect(voice.notice, isNull);
  });

  test('F-024 AC4 앱을 켜자마자 시작해 서버 설정이 아직 없으면 설정을 받아 본 뒤 연결한다', () async {
    await setUpWith(loadConfig: false);
    expect(chat.config, isNull);
    await voice.start();
    expect(chat.config?.voiceAgent, isTrue);
    expect(api.tokenRequests, 1);
    expect(agent.starts, hasLength(1));
  });

  test('F-024 AC4 앱 시작 때 설정 요청이 실패해도 음성 시작 때 다시 받아 연결한다', () async {
    await setUpWith(loadConfig: false);
    api.configFailures = 1;
    await chat.loadConfig();
    expect(chat.configFailed, isTrue);
    await voice.start();
    expect(chat.configFailed, isFalse, reason: '다시 받으면 실패 표시를 지운다');
    expect(agent.starts, hasLength(1));
    expect(voice.notice, AgentMessages.connecting);
  });

  test('F-024 AC2 페르소나(기본 지시 포함)·지난 대화 기억·이전 대화를 서버에 넘긴다', () async {
    await setUpWith();
    personas.select('elder-care');
    memory.put(
      SessionSummary(
        id: 's0',
        personaId: 'elder-care',
        endedAt: DateTime.utc(2026, 11, 10),
        turns: 1,
        summary: '무릎이 아프다고 하셨다',
        facts: const [],
        followUps: const [],
      ),
    );
    chat.addVoiceTurn(Role.user, '안녕');
    chat.addVoiceTurn(Role.assistant, '안녕하세요');
    await voice.start();
    final c = api.lastSessionContext!;
    final persona = c['persona']! as Map;
    expect(persona['name'], personas.selected.name);
    expect(persona['base'], personas.selected.base);
    expect((c['memory']! as List).single, containsPair('summary', '무릎이 아프다고 하셨다'));
    expect(c['history'], [
      {'role': 'user', 'content': '안녕'},
      {'role': 'assistant', 'content': '안녕하세요'},
    ]);
  });

  test('F-024 AC5 말한 것과 답을 대화 내역에 남기고, 상태·자막을 바꾼다', () async {
    await setUpWith();
    await voice.start();
    agent.emit(const AgentConnected());
    agent.emit(const AgentHeardPartial('오늘 날'));
    expect(voice.partial, '오늘 날');
    agent.emit(const AgentHeard('오늘 날씨 어때요'));
    expect(voice.partial, '');
    expect(voice.state, VoiceState.thinking);
    agent.emit(const AgentMode(speaking: true));
    agent.emit(const AgentReply('맑아요. 산책하기 좋아요.'));
    expect(voice.state, VoiceState.speaking);
    expect(voice.sentence, '맑아요. 산책하기 좋아요.');
    agent.emit(const AgentMode(speaking: false));
    expect(voice.state, VoiceState.listening);
    expect(voice.sentence, '');
    expect(chat.history.map((m) => (m.role, m.content)), [
      (Role.user, '오늘 날씨 어때요'),
      (Role.assistant, '맑아요. 산책하기 좋아요.'),
    ]);
    expect(api.requests, isEmpty, reason: '답은 OpenAI Realtime이 만든다 — 글 채팅(API-001)을 부르지 않는다');
  });

  test('F-024 AC5 대화를 끝내면 연결을 끊고, 그 대화를 요약해 기억에 넣는다 (F-019)', () async {
    await setUpWith();
    await voice.start();
    agent.emit(const AgentConnected());
    agent.emit(const AgentHeard('산책 다녀왔어요'));
    agent.emit(const AgentReply('잘하셨어요'));
    voice.stop();
    expect(agent.ends, 1);
    expect(voice.state, VoiceState.off);
    expect(chat.endSession(), isTrue);
    expect(api.summaryRequests.single.map((m) => m.content), ['산책 다녀왔어요', '잘하셨어요']);
    agent.emit(const AgentDisconnected(byUser: true));
    await flush();
    expect(agent.starts, hasLength(1), reason: '사용자가 끝내면 다시 연결하지 않는다');
  });

  test('F-024 AC6 서버에 실시간 음성이 꺼져 있으면 연결하지 않고, 한 번 알린 뒤 꺼진 채로 둔다', () async {
    await setUpWith(voiceAgent: false);
    await voice.start();
    expect(api.tokenRequests, 0);
    expect(voice.state, VoiceState.off);
    expect(voice.notice, AgentMessages.serverOff);
  });

  test('F-024 AC6 이 브라우저가 실시간 음성을 못 쓰면 안내만 한다', () async {
    await setUpWith(withAgent: false);
    expect(voice.supported, isFalse);
    await voice.start();
    expect(api.tokenRequests, 0);
    expect(voice.state, VoiceState.off);
    expect(voice.notice, AgentMessages.unsupported);
  });

  test('F-024 AC6 서버 설정을 받지 못하면 연결하지 않고 그 이유를 알린다', () async {
    await setUpWith(loadConfig: false);
    api.configFailures = 2; // 앱 시작 때 한 번, 음성 시작 때 한 번
    await chat.loadConfig();
    await voice.start();
    expect(api.tokenRequests, 0);
    expect(voice.state, VoiceState.off);
    expect(voice.notice, AgentMessages.noConfig);
  });

  test('F-024 AC6 임시 키를 받지 못하면 다시 시도하지 않고 알린 뒤 끈다', () async {
    await setUpWith();
    api.tokenFails = true;
    await voice.start();
    await flush();
    expect(agent.starts, isEmpty);
    expect(voice.state, VoiceState.off);
    expect(voice.notice, AgentMessages.failed);
  });

  test('F-024 AC6 연결이 연달아 3번 안 되면 알리고 끈다', () async {
    await setUpWith();
    agent.failStart = true;
    await voice.start();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await flush();
    expect(agent.starts, hasLength(3));
    expect(voice.state, VoiceState.off);
    expect(voice.notice, AgentMessages.failed);
  });

  test('F-024 AC6 연결이 알림 없이 멈추면 시간 초과로 다시 시도하고, 계속 안 되면 알리고 끈다', () async {
    await setUpWith(connectTimeout: const Duration(milliseconds: 20));
    agent.hang = true;
    unawaited(voice.start());
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(agent.starts.length, 3);
    expect(voice.state, VoiceState.off);
    expect(voice.notice, AgentMessages.failed);
  });

  test('F-024 AC6 끄고 다시 누르면 처음부터 다시 연결한다', () async {
    await setUpWith();
    api.tokenFails = true;
    await voice.start();
    await flush();
    expect(voice.notice, AgentMessages.failed);
    api.tokenFails = false;
    voice.tap();
    await flush();
    expect(agent.starts, hasLength(1));
    expect(voice.notice, AgentMessages.connecting);
  });

  test('F-024 AC6 대화 중 끊기면 버튼 없이 새 임시 키로 다시 연결하고, 대화 내역을 이어서 넘긴다', () async {
    await setUpWith();
    await voice.start();
    agent.emit(const AgentConnected());
    agent.emit(const AgentHeard('안녕'));
    agent.emit(const AgentReply('네 안녕하세요'));
    agent.emit(const AgentDisconnected());
    expect(voice.notice, AgentMessages.reconnecting);
    expect(voice.active, isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await flush();
    expect(agent.starts, hasLength(2));
    expect(agent.starts.last.token, 'ek-2');
    expect(agent.starts.last.context['history'], hasLength(2));
    agent.emit(const AgentConnected());
    expect(voice.state, VoiceState.listening);
    expect(voice.notice, isNull);
  });

  test('F-024 AC6 앱이 뒤로 가면 마이크만 끄고, 돌아오면 다시 켠다', () async {
    await setUpWith();
    await voice.start();
    agent.emit(const AgentConnected());
    voice.pause();
    expect(agent.muted, [true]);
    voice.resume();
    expect(agent.muted, [true, false]);
    expect(voice.active, isTrue);
  });

  test('F-024 화면 누르기는 켜져 있을 때 아무것도 끄지 않는다 (F-018)', () async {
    await setUpWith();
    voice.tap();
    await flush();
    expect(agent.starts, hasLength(1));
    agent.emit(const AgentConnected());
    voice.tap();
    expect(voice.active, isTrue);
    expect(agent.ends, 0);
  });

  test('F-024 AC5 파형은 에이전트가 주는 마이크 소리 크기로 그린다', () async {
    await setUpWith();
    await voice.start();
    agent.emit(const AgentConnected());
    agent.level.value = 0.6;
    expect(voice.level.value, 0.6);
  });

  test('F-025 AC4 마이크 권한이 없으면 다시 연결하지 않고 멈춘 뒤 브라우저 설정을 안내한다', () async {
    await setUpWith();
    await voice.start();
    agent.emit(const AgentFailed(micDenied: true));
    await flush();
    expect(voice.state, VoiceState.off);
    expect(voice.notice, AgentMessages.micDenied);
    expect(agent.starts, hasLength(1), reason: '다시 연결하지 않는다');
  });
}
