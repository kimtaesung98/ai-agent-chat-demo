import 'package:ai_agent_chat/api/chat_api.dart';
import 'package:ai_agent_chat/chat/chat_controller.dart';
import 'package:ai_agent_chat/main.dart';
import 'package:ai_agent_chat/voice/voice_controller.dart';
import 'package:ai_agent_chat/voice/voice_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes.dart';

void main() {
  late FakeApi api;
  late ChatController chat;
  late FakeVoiceEngine engine;
  late VoiceController voice;

  Future<void> open(WidgetTester tester, {bool canListen = true}) async {
    api = FakeApi();
    chat = ChatController(api);
    engine = FakeVoiceEngine(null, canListen);
    voice = VoiceController(chat, engine);
    addTearDown(voice.dispose);
    await chat.loadConfig();
    await tester.pumpWidget(ChatApp(controller: chat, voice: voice));
    await tester.pump();
  }

  Finder mic() => find.byKey(const Key('mic'));
  String status(WidgetTester t) => t.widget<Text>(find.byKey(const Key('voice-status'))).data!;

  testWidgets('F-012 음성이 없으면 마이크 버튼을 그리지 않는다', (tester) async {
    final c = ChatController(FakeApi());
    await tester.pumpWidget(ChatApp(controller: c));
    expect(mic(), findsNothing);
  });

  testWidgets('F-012 AC1 마이크를 누르면 듣고, 인식 중인 문장을 보여 주고, 멈추면 보낸다', (tester) async {
    await open(tester);
    expect(find.byKey(const Key('voice-status')), findsNothing);

    await tester.tap(mic());
    await tester.pump();
    expect(status(tester), '듣는 중… 말씀하세요');

    engine.hear(const HeardPartial('오늘 날씨'));
    await tester.pump();
    expect(status(tester), '오늘 날씨');

    engine.hear(const HeardFinal('오늘 날씨 어때?'));
    await tester.pump();
    expect(find.text('오늘 날씨 어때?'), findsOneWidget, reason: '내 말풍선');
    expect(status(tester), '생각 중…');
    expect(api.modes.single, ChatMode.voice);

    api.current.add(const ChatDelta('맑아요. 따'));
    await tester.pump();
    expect(status(tester), startsWith('말하는 중'));
  });

  testWidgets('F-012 AC5 말하는 중 마이크(손) 버튼을 누르면 끼어들어 중단된다', (tester) async {
    await open(tester);
    await tester.tap(mic());
    await tester.pump();
    engine.hear(const HeardFinal('길게 설명해 줘'));
    await tester.pump();
    api.current.add(const ChatDelta('첫 문장이에요. 두'));
    await tester.pump();
    expect(find.byIcon(Icons.front_hand_outlined), findsOneWidget);

    await tester.tap(mic());
    await tester.pump();
    expect(find.byKey(const Key('stopped')), findsOneWidget, reason: 'F-003 중단됨 표시');
    expect(status(tester), '듣는 중… 말씀하세요');
  });

  testWidgets('F-012 AC4 듣는 중 마이크를 누르면 음성 모드가 꺼진다', (tester) async {
    await open(tester);
    await tester.tap(mic());
    await tester.pump();
    await tester.tap(mic());
    await tester.pump();
    expect(voice.state, VoiceState.off);
    expect(find.byKey(const Key('voice-status')), findsNothing);
    expect(engine.listening, isFalse);
  });

  testWidgets('F-012 AC7 음성 인식 미지원이면 안내하고 텍스트 채팅은 그대로', (tester) async {
    await open(tester, canListen: false);
    await tester.tap(mic());
    await tester.pump();
    expect(find.text(VoiceMessages.unsupported), findsOneWidget);

    await tester.enterText(find.byKey(const Key('input')), '텍스트 질문');
    await tester.tap(find.byKey(const Key('send')));
    await tester.pump();
    expect(api.requests, hasLength(1));
    expect(api.modes.single, ChatMode.text);
  });

  testWidgets('F-012 AC7 마이크 권한을 거부하면 안내한다', (tester) async {
    await open(tester);
    await tester.tap(mic());
    await tester.pump();
    engine.hear(const ListenFailed(ListenFailure.notAllowed));
    await tester.pump();
    expect(find.text(VoiceMessages.notAllowed), findsOneWidget);
    expect(voice.state, VoiceState.off);
  });
}
