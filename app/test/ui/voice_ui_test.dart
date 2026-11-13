import 'package:ai_agent_chat/api/chat_api.dart';
import 'package:ai_agent_chat/chat/chat_controller.dart';
import 'package:ai_agent_chat/main.dart';
import 'package:ai_agent_chat/voice/agent_voice_controller.dart';
import 'package:ai_agent_chat/voice/realtime_agent.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes.dart';

void main() {
  late FakeApi api;
  late ChatController chat;
  late FakeAgent agent;
  late AgentVoiceController voice;

  Future<void> open(WidgetTester tester, {bool supported = true, bool serverOn = true}) async {
    api = FakeApi();
    if (!serverOn) api.serverConfig = const ServerConfig(provider: 'mock', model: 'mock-echo');
    chat = ChatController(api);
    (:voice, :agent) = fakeRealtimeVoice(chat, api, supported: supported);
    addTearDown(voice.dispose);
    await chat.loadConfig();
    await tester.pumpWidget(ChatApp(controller: chat, voice: voice));
    await tester.pump();
  }

  Finder mic() => find.byKey(const Key('mic'));
  String status(WidgetTester t) => t.widget<Text>(find.byKey(const Key('voice-status'))).data!;

  testWidgets('F-024 음성이 없으면 마이크 버튼을 그리지 않는다', (tester) async {
    final c = ChatController(FakeApi());
    await tester.pumpWidget(ChatApp(controller: c));
    expect(mic(), findsNothing);
  });

  testWidgets('F-024 AC5 마이크를 누르면 연결해 듣고, 인식 중인 말을 보여 주고, 말과 답이 말풍선에 남는다', (tester) async {
    await open(tester);
    expect(find.byKey(const Key('voice-status')), findsNothing);

    await tester.tap(mic());
    await tester.pump();
    expect(agent.starts, hasLength(1));
    expect(status(tester), '듣는 중… 말씀하세요');

    agent.emit(const AgentHeardPartial('오늘 날씨'));
    await tester.pump();
    expect(status(tester), '오늘 날씨');

    agent.emit(const AgentHeard('오늘 날씨 어때?'));
    await tester.pump();
    expect(find.text('오늘 날씨 어때?'), findsOneWidget, reason: '내 말풍선');

    agent.emit(const AgentMode(speaking: true));
    agent.emit(const AgentReply('맑아요.'));
    await tester.pump();
    expect(status(tester), startsWith('말하는 중'));
    expect(find.text('맑아요.'), findsOneWidget, reason: '답 말풍선');
    expect(api.requests, isEmpty, reason: '음성 답은 OpenAI Realtime이 만든다');
  });

  testWidgets('F-024 AC5 듣는 중 마이크를 누르면 연결을 끊고 음성이 꺼진다', (tester) async {
    await open(tester);
    await tester.tap(mic());
    await tester.pump();
    await tester.tap(mic());
    await tester.pump();
    expect(voice.state, VoiceState.off);
    expect(agent.ends, 1);
    expect(find.byKey(const Key('voice-status')), findsNothing);
  });

  testWidgets('F-024 AC6 서버에 실시간 음성이 꺼져 있으면 안내하고 글 채팅은 그대로', (tester) async {
    await open(tester, serverOn: false);
    await tester.tap(mic());
    await tester.pump();
    expect(find.text(AgentMessages.serverOff), findsOneWidget);
    expect(agent.starts, isEmpty);

    await tester.enterText(find.byKey(const Key('input')), '텍스트 질문');
    await tester.tap(find.byKey(const Key('send')));
    await tester.pump();
    expect(api.requests, hasLength(1));
    expect(api.modes.single, ChatMode.text);
  });

  testWidgets('F-025 AC4 마이크 권한을 거부하면 브라우저 설정을 안내한다', (tester) async {
    await open(tester);
    await tester.tap(mic());
    await tester.pump();
    agent.emit(const AgentFailed(micDenied: true));
    await tester.pump();
    expect(find.text(AgentMessages.micDenied), findsOneWidget);
    expect(voice.state, VoiceState.off);
  });
}
