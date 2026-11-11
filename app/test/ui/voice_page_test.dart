import 'package:ai_agent_chat/api/chat_api.dart';
import 'package:ai_agent_chat/chat/chat_controller.dart';
import 'package:ai_agent_chat/chat/persona_controller.dart';
import 'package:ai_agent_chat/main.dart';
import 'package:ai_agent_chat/voice/voice_controller.dart';
import 'package:ai_agent_chat/voice/voice_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes.dart';

void main() {
  late FakeApi api;
  late ChatController chat;
  late PersonaController personas;
  late FakeVoiceEngine engine;
  late VoiceController voice;

  Future<void> open(WidgetTester tester, {bool canListen = true}) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    api = FakeApi();
    personas = PersonaController();
    chat = ChatController(api, personas: personas);
    engine = FakeVoiceEngine(null, canListen);
    voice = VoiceController(chat, engine, retryDelay: const Duration(milliseconds: 100));
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

  testWidgets('F-018 AC1 채팅 화면에서 열면 바로 듣기 시작하고 지금 페르소나를 보여 준다', (tester) async {
    await open(tester);
    expect(find.byKey(const Key('voice-page')), findsOneWidget);
    expect(voice.state, VoiceState.listening);
    expect(engine.listening, isTrue);
    expect(text(tester, 'voice-persona'), personas.selected.name);
    expect(label(tester), '듣고 있어요');
  });

  testWidgets('F-018 AC2 AC3 버튼 없이 듣기 → 생각 → 읽기 → 다시 듣기로 계속 이어진다', (tester) async {
    await open(tester);
    engine.hear(const HeardPartial('3분기 기능'));
    await tester.pump();
    expect(caption(tester), '“3분기 기능”');

    engine.hear(const HeardFinal('3분기 기능 골라 줘'));
    await tester.pump();
    expect(label(tester), '생각하고 있어요');
    expect(caption(tester), '“3분기 기능 골라 줘”');
    expect(api.modes.single, ChatMode.voice);
    expect(api.personas.single?.persona.name, personas.selected.name, reason: '지금 페르소나로 묻는다');

    api.current.add(const ChatDelta('좋아요. 먼저'));
    await tester.pump();
    expect(label(tester), '말하고 있어요');
    expect(caption(tester), '좋아요.');

    api.current
      ..add(const ChatDelta(' 매일 쓰는 기능부터 볼게요.'))
      ..add(const ChatDone('end_turn'));
    await tester.pump();
    while (engine.hasPending) {
      engine.finishAll();
      await tester.pump();
    }
    expect(engine.spoken, ['좋아요.', '먼저 매일 쓰는 기능부터 볼게요.']);
    expect(label(tester), '듣고 있어요');
    expect(engine.listening, isTrue);
  });

  testWidgets('F-018 AC4 말하는 중 화면 아무 데나 누르면 말을 끊고 듣는다', (tester) async {
    await open(tester);
    engine.hear(const HeardFinal('길게 설명해 줘'));
    await tester.pump();
    api.current.add(const ChatDelta('첫 문장이에요. 두'));
    await tester.pump();
    expect(label(tester), '말하고 있어요');

    await tapScreen(tester);
    expect(label(tester), '듣고 있어요');
    expect(chat.entries.last.status, EntryStatus.stopped, reason: 'F-003 받은 데까지 중단됨');
  });

  testWidgets('F-018 AC4 듣는 중에 화면을 눌러도 대화가 꺼지지 않는다', (tester) async {
    await open(tester);
    await tapScreen(tester);
    await tapScreen(tester);
    expect(voice.state, VoiceState.listening);
    expect(engine.listening, isTrue);
  });

  testWidgets('F-018 AC5 글자로 보기는 음성을 켠 채 채팅으로, 대화 끝내기는 음성을 끄고 채팅으로', (tester) async {
    await open(tester);
    engine.hear(const HeardFinal('안녕'));
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
    expect(engine.listening, isFalse);
  });

  testWidgets('F-018 AC6 인식이 잠깐 끊기면 손대지 않아도 다시 듣는다', (tester) async {
    await open(tester);
    engine.hear(const ListenFailed(ListenFailure.network));
    await tester.pump();
    expect(voice.state, VoiceState.listening);
    expect(caption(tester), VoiceMessages.reconnecting);
    expect(engine.listening, isFalse);

    await tester.pump(const Duration(milliseconds: 150));
    expect(engine.listening, isTrue);
    engine.hear(const HeardPartial('다시 들려요'));
    await tester.pump();
    expect(caption(tester), '“다시 들려요”');
  });

  testWidgets('F-018 AC6 음성 인식을 못 쓰면 이유를 보여 주고 글자로 대화할 수 있다', (tester) async {
    await open(tester, canListen: false);
    expect(label(tester), '목소리를 들을 수 없어요');
    expect(caption(tester), VoiceMessages.unsupported);

    await tester.tap(find.byKey(const Key('voice-to-text')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('input')), '텍스트 질문');
    await tester.tap(find.byKey(const Key('send')));
    await tester.pump();
    expect(api.modes.single, ChatMode.text);
  });

  testWidgets('F-018 AC6 마이크 권한을 거부하면 안내하고, 화면을 누르면 다시 시도한다', (tester) async {
    await open(tester);
    engine.hear(const ListenFailed(ListenFailure.notAllowed));
    await tester.pump();
    expect(caption(tester), VoiceMessages.notAllowed);
    expect(voice.state, VoiceState.off);

    await tapScreen(tester);
    await tester.pump();
    expect(voice.state, VoiceState.listening);
  });

  testWidgets('F-018 AC7 가로 모드처럼 낮은 화면에서도 넘치지 않는다', (tester) async {
    await open(tester);
    tester.view.physicalSize = const Size(844, 390);
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('voice-end')), findsOneWidget);
  });
}
