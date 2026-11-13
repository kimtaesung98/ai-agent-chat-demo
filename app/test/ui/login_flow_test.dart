import 'package:ai_agent_chat/chat/auth_controller.dart';
import 'package:ai_agent_chat/chat/chat_controller.dart';
import 'package:ai_agent_chat/chat/display_settings.dart';
import 'package:ai_agent_chat/chat/memory_controller.dart';
import 'package:ai_agent_chat/chat/persona_controller.dart';
import 'package:ai_agent_chat/chat/start_settings.dart';
import 'package:ai_agent_chat/main.dart';
import 'package:ai_agent_chat/voice/agent_voice_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../chat/auth_controller_test.dart' show FakeGoogle;
import '../fakes.dart';

void main() {
  late AuthController auth;
  late PersonaController personas;
  late ChatController chat;
  late StartSettings start;
  late DisplaySettings display;
  late FakeAgent agent;
  late AgentVoiceController voice;

  Future<void> launch(WidgetTester tester, {Account? account, bool onboarded = false, bool withVoice = true}) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    auth = AuthController(google: FakeGoogle(), account: account, onboarded: onboarded);
    personas = PersonaController();
    final api = FakeApi();
    chat = ChatController(api, personas: personas, memory: MemoryController());
    await chat.loadConfig();
    start = StartSettings();
    display = DisplaySettings();
    (:voice, :agent) = fakeRealtimeVoice(chat, api);
    addTearDown(voice.dispose);
    await tester.pumpWidget(
      ChatApp(
        controller: chat,
        voice: withVoice ? voice : null,
        start: start,
        auth: auth,
        display: display,
        mockGoogle: true,
      ),
    );
    await tester.pump();
  }

  const guest = Account(name: '순자', kind: AccountKind.guest);

  testWidgets('F-023 AC1 로그인 전에는 로그인 화면 — 큰 버튼 두 개와 모의 안내', (tester) async {
    await launch(tester);
    expect(find.byKey(const Key('login-page')), findsOneWidget);
    expect(find.byKey(const Key('login-google')), findsOneWidget);
    expect(find.byKey(const Key('login-guest')), findsOneWidget);
    expect(find.byKey(const Key('login-mock-note')), findsOneWidget);
    expect(tester.getSize(find.byKey(const Key('login-google'))).height, greaterThanOrEqualTo(64));
  });

  testWidgets('F-023 AC2 Google로 시작하면 첫 실행(대화 상대 고르기)으로 간다', (tester) async {
    await launch(tester);
    await tester.tap(find.byKey(const Key('login-google')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('onboarding-page')), findsOneWidget);
    expect(find.textContaining('김순자님'), findsOneWidget);
  });

  testWidgets('F-023 AC3 이름만 적고 시작 — 빈 이름은 안내하고, 적으면 첫 실행으로', (tester) async {
    await launch(tester);
    await tester.tap(find.byKey(const Key('login-guest')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('login-guest-start')));
    await tester.pump();
    expect(find.text(AuthMessages.emptyName), findsOneWidget);

    await tester.enterText(find.byKey(const Key('login-name')), '순자');
    await tester.tap(find.byKey(const Key('login-guest-start')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('onboarding-page')), findsOneWidget);
    expect(auth.account!.kind, AccountKind.guest);
  });

  testWidgets('F-023 AC4 첫 실행은 미소를 추천하고, 말로 시작하면 미소와 음성 대화 화면이 열린다', (tester) async {
    await launch(tester, account: guest);
    expect(find.byKey(const Key('onboarding-page')), findsOneWidget);
    expect(find.text('추천'), findsOneWidget);

    await tester.tap(find.byKey(const Key('onboarding-voice')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400)); // 음성 화면은 원이 계속 숨 쉬어 settle하지 않는다
    expect(auth.onboarded, isTrue);
    expect(personas.selected.id, 'elder-care');
    expect(start.voiceOnStart, isTrue, reason: '다음에도 켜면 바로 음성 대화');
    expect(find.byKey(const Key('voice-page')), findsOneWidget);
    expect(voice.state, VoiceState.listening);
    expect(agent.starts, hasLength(1));
  });

  testWidgets('F-023 AC4 다른 상대를 고르고 글자로 시작하면 채팅 화면', (tester) async {
    await launch(tester, account: guest);
    await tester.tap(find.byKey(const Key('onboarding-friend')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('onboarding-text')));
    await tester.pumpAndSettle();
    expect(personas.selected.id, 'friend');
    expect(start.voiceOnStart, isFalse);
    expect(find.byKey(const Key('voice-page')), findsNothing);
    expect(find.byKey(const Key('input')), findsOneWidget);
  });

  testWidgets('F-023 AC4 음성이 없으면 첫 실행 버튼은 "시작하기" 하나다', (tester) async {
    await launch(tester, account: guest, withVoice: false);
    expect(find.byKey(const Key('onboarding-voice')), findsNothing);
    expect(find.text('시작하기'), findsOneWidget);
  });

  testWidgets('F-023 AC1 이미 로그인하고 첫 실행을 마쳤으면 바로 채팅 화면', (tester) async {
    await launch(tester, account: guest, onboarded: true);
    expect(find.byKey(const Key('login-page')), findsNothing);
    expect(find.byKey(const Key('onboarding-page')), findsNothing);
    expect(find.byKey(const Key('input')), findsOneWidget);
  });

  Future<void> openSettings(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-settings')));
    await tester.pumpAndSettle();
  }

  testWidgets('F-023 AC5 설정 화면에 내 계정·시작 방식·기억·글자 크기·앱 정보가 모인다', (tester) async {
    await launch(tester, account: guest, onboarded: true);
    await openSettings(tester);
    expect(find.byKey(const Key('settings-page')), findsOneWidget);
    expect(find.text('순자'), findsOneWidget);
    expect(find.text('이 기기에서만 쓰는 이름'), findsOneWidget);
    expect(find.byKey(const Key('start-voice')), findsOneWidget);
    expect(find.byKey(const Key('text-size')), findsOneWidget);
    expect(find.textContaining('모의 모드'), findsOneWidget);
    expect(find.byKey(const Key('server')), findsNothing, reason: '웹(서버 설정 없음)은 주소 칸이 없다');

    await tester.scrollUntilVisible(find.byKey(const Key('settings-memory')), 100);
    await tester.tap(find.byKey(const Key('settings-memory')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('memory-page')), findsOneWidget);
    expect(find.byKey(const Key('memory-empty')), findsOneWidget);
  });

  testWidgets('F-023 AC5 글자 크기를 고르면 앱 전체 글자가 커진다', (tester) async {
    await launch(tester, account: guest, onboarded: true);
    await openSettings(tester);
    final before = tester.getSize(find.text('글자 크기')).height;
    await tester.tap(find.byKey(const Key('text-size-xlarge')));
    await tester.pumpAndSettle();
    expect(display.textSize, TextSize.xlarge);
    expect(tester.getSize(find.text('글자 크기')).height, greaterThan(before));
  });

  testWidgets('F-023 AC6 로그아웃은 한 번 더 묻고, 하면 로그인 화면으로 돌아간다', (tester) async {
    await launch(tester, account: guest, onboarded: true);
    await openSettings(tester);
    await tester.tap(find.byKey(const Key('settings-logout')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('아니요'));
    await tester.pumpAndSettle();
    expect(auth.signedIn, isTrue);

    await tester.tap(find.byKey(const Key('settings-logout')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-logout')));
    await tester.pumpAndSettle();
    expect(auth.signedIn, isFalse);
    expect(find.byKey(const Key('login-page')), findsOneWidget);
    expect(find.byKey(const Key('settings-page')), findsNothing);
  });
}
