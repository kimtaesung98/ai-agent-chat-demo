import 'package:ai_agent_chat/api/chat_api.dart';
import 'package:ai_agent_chat/chat/chat_controller.dart';
import 'package:ai_agent_chat/chat/memory_controller.dart';
import 'package:ai_agent_chat/chat/persona_controller.dart';
import 'package:ai_agent_chat/chat/start_settings.dart';
import 'package:ai_agent_chat/main.dart';
import 'package:ai_agent_chat/ui/voice_wave.dart';
import 'package:ai_agent_chat/voice/agent_voice_controller.dart';
import 'package:ai_agent_chat/voice/realtime_agent.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes.dart';

void main() {
  late FakeApi api;
  late ChatController chat;
  late PersonaController personas;
  late MemoryController memory;
  late FakeAgent agent;
  late AgentVoiceController voice;

  Future<void> open(WidgetTester tester, {bool supported = true}) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    api = FakeApi();
    personas = PersonaController();
    memory = MemoryController();
    chat = ChatController(api, personas: personas, memory: memory);
    (:voice, :agent) = fakeRealtimeVoice(chat, api, supported: supported);
    addTearDown(voice.dispose);
    await chat.loadConfig();
    await tester.pumpWidget(ChatApp(controller: chat, voice: voice));
    await tester.pump();
    await tester.tap(find.byKey(const Key('open-voice-page')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400)); // 화면 전환
  }

  String text(WidgetTester t, String key) => t.widget<Text>(find.byKey(Key(key))).data!;
  String label(WidgetTester t) => text(t, 'voice-page-label');
  String caption(WidgetTester t) => text(t, 'voice-page-caption');
  Future<void> tapScreen(WidgetTester t) async {
    await t.tap(find.byKey(const Key('voice-tap-area')));
    await t.pump();
  }

  testWidgets('F-018 음성이 없으면 음성 대화 화면 버튼을 그리지 않는다', (tester) async {
    await tester.pumpWidget(ChatApp(controller: ChatController(FakeApi())));
    expect(find.byKey(const Key('open-voice-page')), findsNothing);
  });

  testWidgets('F-018 AC1 채팅 화면에서 열면 바로 연결해 듣기 시작하고 지금 페르소나를 보여 준다', (tester) async {
    await open(tester);
    expect(find.byKey(const Key('voice-page')), findsOneWidget);
    expect(agent.starts, hasLength(1));
    expect(voice.state, VoiceState.listening);
    expect(text(tester, 'voice-persona'), personas.selected.name);
    expect(label(tester), '듣고 있어요');
  });

  testWidgets('F-018 AC2 AC3 F-024 AC5 버튼 없이 듣기 → 생각 → 말하기 → 다시 듣기로 이어지고 자막이 바뀐다', (tester) async {
    await open(tester);
    agent.emit(const AgentHeardPartial('3분기 기능'));
    await tester.pump();
    expect(caption(tester), '“3분기 기능”');

    agent.emit(const AgentHeard('3분기 기능 골라 줘'));
    await tester.pump();
    expect(label(tester), '생각하고 있어요');
    expect(caption(tester), '“3분기 기능 골라 줘”');

    agent.emit(const AgentMode(speaking: true));
    agent.emit(const AgentReply('좋아요. 매일 쓰는 기능부터 볼게요.'));
    await tester.pump();
    expect(label(tester), '말하고 있어요');
    expect(caption(tester), '좋아요. 매일 쓰는 기능부터 볼게요.');

    agent.emit(const AgentMode(speaking: false));
    await tester.pump();
    expect(label(tester), '듣고 있어요');
    expect(api.requests, isEmpty, reason: '음성 답은 OpenAI Realtime이 만든다');
  });

  double waveAmp(WidgetTester t) =>
      (t.widget<CustomPaint>(find.byKey(const Key('voice-wave-paint'))).painter! as VoiceWavePainter).amp;

  testWidgets('F-018 AC11 듣는 중 마이크 소리가 크면 파형이 높아지고, 조용해지면 가라앉는다', (tester) async {
    await open(tester);
    expect(find.byKey(const Key('voice-wave')), findsOneWidget);
    final quiet = waveAmp(tester);
    agent.level.value = 1;
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    final loud = waveAmp(tester);
    expect(loud, greaterThan(quiet + 0.5));
    agent.level.value = 0;
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(waveAmp(tester), lessThan(loud / 2));
  });

  testWidgets('F-018 AC11 대화가 멈추면 파형도 멈춘다', (tester) async {
    await open(tester);
    agent.level.value = 1;
    await tester.pump(const Duration(milliseconds: 16));
    voice.stop();
    agent.level.value = 0; // 실제 에이전트는 끊을 때 0으로 돌린다
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(waveAmp(tester), lessThan(0.01));
    await tester.pumpAndSettle(); // 멈춘 뒤엔 그리기가 끝난다 (반복 애니메이션 없음)
  });

  testWidgets('F-018 AC4 듣는 중·말하는 중에 화면을 눌러도 대화가 꺼지지 않는다 (끼어들기는 말로)', (tester) async {
    await open(tester);
    await tapScreen(tester);
    agent.emit(const AgentMode(speaking: true));
    await tester.pump();
    await tapScreen(tester);
    expect(voice.active, isTrue);
    expect(agent.ends, 0);
  });

  testWidgets('F-018 AC5 글자로 보기는 음성을 켠 채 채팅으로, 대화 끝내기는 음성을 끄고 채팅으로', (tester) async {
    await open(tester);
    agent.emit(const AgentHeard('안녕'));
    await tester.pump();

    await tester.tap(find.byKey(const Key('voice-to-text')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('voice-page')), findsNothing);
    expect(voice.active, isTrue);
    expect(find.text('안녕'), findsOneWidget, reason: '음성으로 한 말이 채팅 내역에 있다');

    await tester.tap(find.byKey(const Key('open-voice-page')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const Key('voice-page')), findsOneWidget);

    await tester.tap(find.byKey(const Key('voice-end')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('voice-page')), findsNothing);
    expect(voice.state, VoiceState.off);
    expect(agent.ends, 1);
  });

  testWidgets('F-019 AC3 대화 끝내기를 누르면 그때까지의 음성 대화를 정리해 기억에 넣는다', (tester) async {
    await open(tester);
    agent.emit(const AgentHeard('오늘 산책했어요'));
    agent.emit(const AgentReply('잘하셨어요.'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('voice-end')));
    await tester.pumpAndSettle();
    expect(api.summaryRequests.single.map((m) => m.content), ['오늘 산책했어요', '잘하셨어요.']);
    expect(memory.forPersona('planner'), hasLength(1));
    expect(find.text('오늘 산책했어요'), findsOneWidget, reason: '채팅 내역은 그대로 남는다');
  });

  testWidgets('F-018 AC6 F-024 AC6 연결이 잠깐 끊기면 손대지 않아도 다시 연결해 듣는다', (tester) async {
    await open(tester);
    agent.emit(const AgentDisconnected());
    await tester.pump();
    expect(caption(tester), AgentMessages.reconnecting);

    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump();
    expect(agent.starts, hasLength(2));
    expect(label(tester), '듣고 있어요');
    agent.emit(const AgentHeardPartial('다시 들려요'));
    await tester.pump();
    expect(caption(tester), '“다시 들려요”');
  });

  testWidgets('F-018 AC6 이 브라우저가 실시간 음성을 못 쓰면 이유를 보여 주고 글자로 대화할 수 있다', (tester) async {
    await open(tester, supported: false);
    expect(label(tester), '목소리를 들을 수 없어요');
    expect(caption(tester), AgentMessages.unsupported);

    await tester.tap(find.byKey(const Key('voice-to-text')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('input')), '텍스트 질문');
    await tester.tap(find.byKey(const Key('send')));
    await tester.pump();
    expect(api.modes.single, ChatMode.text);
  });

  testWidgets('F-018 AC6 F-025 AC4 마이크 권한을 거부하면 안내하고, 화면을 누르면 다시 시도한다', (tester) async {
    await open(tester);
    agent.emit(const AgentFailed(micDenied: true));
    await tester.pump();
    expect(caption(tester), AgentMessages.micDenied);
    expect(voice.state, VoiceState.off);

    await tapScreen(tester);
    await tester.pump();
    expect(agent.starts, hasLength(2));
    expect(voice.state, VoiceState.listening);
  });

  testWidgets('F-018 AC7 가로 모드처럼 낮은 화면에서도 넘치지 않는다', (tester) async {
    await open(tester);
    tester.view.physicalSize = const Size(844, 390);
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('voice-end')), findsOneWidget);
  });

  testWidgets('F-018 AC9 앱이 뒤로 갔다 돌아오면 버튼 없이 다시 듣는다', (tester) async {
    await open(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await tester.pump();
    expect(agent.muted, [true], reason: '뒤에서는 마이크를 끈다');
    expect(voice.active, isTrue);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(agent.muted, [true, false]);
    expect(label(tester), '듣고 있어요');
  });

  group('F-021 켜면 바로 음성 대화', () {
    Future<StartSettings> launch(WidgetTester tester, {required bool on, bool withVoice = true}) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      api = FakeApi();
      personas = PersonaController()..select('elder-care');
      chat = ChatController(api, personas: personas);
      (:voice, :agent) = fakeRealtimeVoice(chat, api);
      addTearDown(voice.dispose);
      final start = StartSettings(on);
      await tester.pumpWidget(ChatApp(controller: chat, voice: withVoice ? voice : null, start: start));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      return start;
    }

    testWidgets('AC1 켜 두면 앱을 열자마자 지금 페르소나와 음성 대화 화면으로 시작해 듣는다', (tester) async {
      await launch(tester, on: true);
      expect(find.byKey(const Key('voice-page')), findsOneWidget);
      expect(find.text('노인복지사 미소'), findsWidgets);
      expect(agent.starts, hasLength(1));
      expect(voice.state, VoiceState.listening);

      await tester.tap(find.byKey(const Key('voice-end')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('voice-page')), findsNothing, reason: '대화 끝내기로 채팅 화면에 돌아온다');
    });

    testWidgets('AC1 꺼 두면 지금처럼 채팅 화면으로 시작한다', (tester) async {
      await launch(tester, on: false);
      expect(find.byKey(const Key('voice-page')), findsNothing);
      expect(agent.starts, isEmpty);
    });

    testWidgets('AC2 서랍 → 설정에서 켤 수 있다 (F-023 S-006)', (tester) async {
      final start = await launch(tester, on: false);
      await tester.tap(find.byTooltip('Open navigation menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('open-settings')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('start-voice')));
      await tester.pump();
      expect(start.voiceOnStart, isTrue);
    });

    testWidgets('AC2 음성이 없으면 설정을 그리지 않는다', (tester) async {
      await launch(tester, on: true, withVoice: false);
      expect(find.byKey(const Key('voice-page')), findsNothing);
      await tester.tap(find.byTooltip('Open navigation menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('open-settings')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('settings-page')), findsOneWidget);
      expect(find.byKey(const Key('start-voice')), findsNothing);
    });
  });
}
