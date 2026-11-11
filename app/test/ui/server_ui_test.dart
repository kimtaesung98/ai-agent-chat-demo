import 'package:ai_agent_chat/chat/chat_controller.dart';
import 'package:ai_agent_chat/chat/persona_controller.dart';
import 'package:ai_agent_chat/chat/server_settings.dart';
import 'package:ai_agent_chat/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes.dart';

void main() {
  Future<ServerSettings?> open(WidgetTester tester, {bool mobile = true}) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final chat = ChatController(FakeApi(), personas: PersonaController());
    final server = mobile ? ServerSettings(fallback: 'http://10.0.2.2:3000') : null;
    await tester.pumpWidget(ChatApp(controller: chat, server: server));
    await tester.pump();
    return server;
  }

  testWidgets('F-017 AC7 앱에서 서버 주소를 바꾸면 사이드바에 새 주소가 보인다', (tester) async {
    final server = (await open(tester))!;
    expect(find.text('http://10.0.2.2:3000'), findsOneWidget);

    await tester.tap(find.byKey(const Key('server')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('server-address')), 'http://192.168.0.10:3000');
    await tester.tap(find.byKey(const Key('save-server')));
    await tester.pumpAndSettle();

    expect(server.address, 'http://192.168.0.10:3000');
    expect(find.text('http://192.168.0.10:3000'), findsOneWidget);
  });

  testWidgets('F-017 AC7 틀린 주소는 대화상자에 안내하고 닫지 않는다', (tester) async {
    final server = (await open(tester))!;
    await tester.tap(find.byKey(const Key('server')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('server-address')), '192.168.0.10');
    await tester.tap(find.byKey(const Key('save-server')));
    await tester.pumpAndSettle();

    expect(find.text(ServerMessages.invalid), findsOneWidget);
    expect(server.address, 'http://10.0.2.2:3000');
  });

  testWidgets('F-017 AC7 웹(설정 없음)에는 서버 주소 항목이 없다', (tester) async {
    await open(tester, mobile: false);
    expect(find.byKey(const Key('server')), findsNothing);
  });
}
