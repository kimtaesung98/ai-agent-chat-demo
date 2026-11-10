import 'package:ai_agent_chat/api/chat_api.dart';
import 'package:ai_agent_chat/chat/chat_controller.dart';
import 'package:ai_agent_chat/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes.dart';

void main() {
  late FakeApi api;
  late ChatController chat;

  Future<void> open(WidgetTester tester) async {
    api = FakeApi();
    chat = ChatController(api);
    await chat.loadConfig();
    await tester.pumpWidget(ChatApp(controller: chat));
    await tester.pump();
  }

  Finder input() => find.byKey(const Key('input'));
  TextField field(WidgetTester t) => t.widget<TextField>(input());

  testWidgets('F-001 AC4 빈 화면 안내와 모드 배지를 보여 준다', (tester) async {
    await open(tester);
    expect(find.byKey(const Key('empty')), findsOneWidget);
    expect(find.text('모의 모드'), findsOneWidget);
    expect(find.text('AI Agent Chat'), findsOneWidget);
  });

  testWidgets('F-001 AC1·AC2 보내면 입력이 잠기고, 조각이 이어 붙고, done이면 다시 열린다', (tester) async {
    await open(tester);
    await tester.enterText(input(), '안녕하세요');
    await tester.tap(find.byKey(const Key('send')));
    await tester.pump();

    expect(find.text('안녕하세요'), findsOneWidget);
    expect(field(tester).enabled, isFalse);
    expect(find.byKey(const Key('stop')), findsOneWidget);

    api.current.add(const ChatDelta('반가'));
    await tester.pump();
    expect(find.text('반가▍'), findsOneWidget);
    api.current.add(const ChatDelta('워요'));
    await tester.pump();
    expect(find.text('반가워요▍'), findsOneWidget);

    api.current.add(const ChatDone('end_turn'));
    await tester.pump();
    expect(find.text('반가워요'), findsOneWidget);
    expect(field(tester).enabled, isTrue);
    expect(find.byKey(const Key('send')), findsOneWidget);
    expect(field(tester).controller!.text, isEmpty);
  });

  testWidgets('F-001 Enter로 보내고 Shift+Enter는 보내지 않는다', (tester) async {
    await open(tester);
    await tester.tap(input());
    await tester.enterText(input(), '줄');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(api.requests, isEmpty);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(api.requests, hasLength(1));
  });

  testWidgets('F-001 AC3 빈 메시지는 보내지 않는다', (tester) async {
    await open(tester);
    await tester.enterText(input(), '   ');
    await tester.tap(find.byKey(const Key('send')));
    await tester.pump();
    expect(api.requests, isEmpty);
    expect(find.byKey(const Key('empty')), findsOneWidget);
  });

  testWidgets('F-003 AC1·AC3 중단하면 받은 내용과 "중단됨"이 남고 입력이 열린다', (tester) async {
    await open(tester);
    await tester.enterText(input(), '길게');
    await tester.tap(find.byKey(const Key('send')));
    await tester.pump();
    api.current.add(const ChatDelta('앞부분'));
    await tester.pump();

    await tester.tap(find.byKey(const Key('stop')));
    await tester.pump();
    expect(find.text('앞부분'), findsOneWidget);
    expect(find.byKey(const Key('stopped')), findsOneWidget);
    expect(field(tester).enabled, isTrue);
    expect(api.cancels, 1);
  });

  testWidgets('F-002 AC3 새 대화를 누르면 대화 영역이 비워진다', (tester) async {
    await open(tester);
    await tester.enterText(input(), '질문');
    await tester.tap(find.byKey(const Key('send')));
    await tester.pump();
    api.current.add(const ChatDone('end_turn'));
    await tester.pump();

    await tester.tap(find.byKey(const Key('new-chat')));
    await tester.pump();
    expect(find.byKey(const Key('empty')), findsOneWidget);
    expect(chat.history, isEmpty);
  });

  testWidgets('F-004 AC1 오류 문장을 응답 말풍선에 보여 준다', (tester) async {
    await open(tester);
    await tester.enterText(input(), '질문');
    await tester.tap(find.byKey(const Key('send')));
    await tester.pump();
    api.current.add(const ChatFailed('요청이 너무 많아요. 잠시 후 다시 시도해 주세요.'));
    await tester.pump();
    expect(find.text('요청이 너무 많아요. 잠시 후 다시 시도해 주세요.'), findsOneWidget);
    expect(field(tester).enabled, isTrue);
  });

  testWidgets('F-004 AC2 오류 말풍선의 다시 시도 버튼이 같은 질문을 다시 보낸다', (tester) async {
    await open(tester);
    await tester.enterText(input(), '질문');
    await tester.tap(find.byKey(const Key('send')));
    await tester.pump();
    expect(find.byKey(const Key('retry')), findsNothing);
    api.current.add(const ChatFailed('AI 서비스에 일시적인 문제가 있어요.'));
    await tester.pump();

    final sent = api.requests.length;
    await tester.tap(find.byKey(const Key('retry')));
    await tester.pump();
    expect(api.requests.length, sent + 1);
    expect(api.requests.last, const [Message(Role.user, '질문')]);
    expect(find.text('AI 서비스에 일시적인 문제가 있어요.'), findsNothing);
    expect(find.byKey(const Key('retry')), findsNothing);
  });

  testWidgets('F-011 AC4 스트리밍 중인 말풍선은 liveRegion으로 알린다', (tester) async {
    await open(tester);
    final handle = tester.ensureSemantics();
    await tester.enterText(input(), '질문');
    await tester.tap(find.byKey(const Key('send')));
    await tester.pump();
    api.current.add(const ChatDelta('답'));
    await tester.pump();

    final live = find.byWidgetPredicate((w) => w is Semantics && w.properties.liveRegion == true);
    expect(live, findsOneWidget);
    api.current.add(const ChatDone('end_turn'));
    await tester.pump();
    expect(live, findsNothing);
    handle.dispose();
  });
}
