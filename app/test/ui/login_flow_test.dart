import 'dart:async';

import 'package:ai_agent_chat/api/account_api.dart';
import 'package:ai_agent_chat/chat/auth_controller.dart';
import 'package:ai_agent_chat/chat/chat_controller.dart';
import 'package:ai_agent_chat/chat/display_settings.dart';
import 'package:ai_agent_chat/chat/memory_controller.dart';
import 'package:ai_agent_chat/chat/persona_controller.dart';
import 'package:ai_agent_chat/chat/server_sync.dart';
import 'package:ai_agent_chat/chat/start_settings.dart';
import 'package:ai_agent_chat/main.dart';
import 'package:ai_agent_chat/voice/agent_voice_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../chat/auth_controller_test.dart' show FakeGoogle;
import '../fakes.dart';

void main() {
  late AuthController auth;
  late FakeAccountApi accounts;
  late ServerSync sync;
  late PersonaController personas;
  late ChatController chat;
  late StartSettings start;
  late DisplaySettings display;
  late FakeAgent agent;
  late AgentVoiceController voice;

  const elder = ServerUser(id: 'usr_elder', name: '순자', role: 'elder');

  Future<void> launch(
    WidgetTester tester, {
    ServerUser? user,
    bool onboarded = false,
    bool withVoice = true,
    bool google = false,
    DeviceData? device,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    accounts = FakeAccountApi(user: user, google: google);
    auth = AuthController(api: accounts, google: FakeGoogle(), onboarded: onboarded);
    personas = PersonaController();
    final api = FakeApi();
    chat = ChatController(api, personas: personas, memory: MemoryController());
    await chat.loadConfig();
    start = StartSettings();
    display = DisplaySettings();
    sync = ServerSync(api: accounts, auth: auth, chat: chat, start: start, display: display, device: device);
    addTearDown(sync.dispose);
    (:voice, :agent) = fakeRealtimeVoice(chat, api);
    addTearDown(voice.dispose);
    await tester.pumpWidget(
      ChatApp(
        controller: chat,
        voice: withVoice ? voice : null,
        start: start,
        auth: auth,
        sync: sync,
        display: display,
      ),
    );
    unawaited(auth.start()); // 가짜 서버는 타이머로 답한다 — pumpAndSettle이 시간을 흘린다
    await tester.pumpAndSettle();
  }

  testWidgets('F-026 AC1 로그인 전에는 코드 넣는 칸과 큰 들어가기 버튼, Google은 서버가 켰을 때만', (tester) async {
    await launch(tester);
    expect(find.byKey(const Key('login-page')), findsOneWidget);
    expect(find.byKey(const Key('login-code')), findsOneWidget);
    expect(find.byKey(const Key('login-google')), findsNothing);
    expect(tester.getSize(find.byKey(const Key('login-code-start'))).height, greaterThanOrEqualTo(64));
    expect(find.textContaining('이름만'), findsNothing, reason: '이름만으로 만드는 계정은 없다 (F-026)');

    await launch(tester, google: true);
    expect(find.byKey(const Key('login-google')), findsOneWidget);
  });

  testWidgets('F-026 AC1 틀린 코드는 안내하고, 맞는 코드면 내 대화 상대를 받아 첫 실행으로 간다', (tester) async {
    await launch(tester);
    await tester.tap(find.byKey(const Key('login-code-start')));
    await tester.pumpAndSettle();
    expect(find.text(AuthMessages.emptyCode), findsOneWidget);

    await tester.enterText(find.byKey(const Key('login-code')), 'AAAA-BBBB-CC');
    await tester.tap(find.byKey(const Key('login-code-start')));
    await tester.pumpAndSettle();
    expect(find.text('코드를 다시 확인해 주세요.'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('login-code')), 'K7QM-4XPH-2R');
    await tester.tap(find.byKey(const Key('login-code-start')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('onboarding-page')), findsOneWidget);
    expect(find.textContaining('김순자님'), findsOneWidget);
    expect(personas.serverBacked, isTrue);
    expect(personas.selected.id, 'per_elder-care', reason: '서버 페르소나, 미소 추천');
  });

  testWidgets('F-026 AC3 Google로 들어가면 첫 실행으로 간다', (tester) async {
    await launch(tester, google: true);
    await tester.tap(find.byKey(const Key('login-google')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('onboarding-page')), findsOneWidget);
    expect(auth.account!.kind, AccountKind.google);
  });

  testWidgets('F-026 내 정보를 받지 못하면 다시 하기 화면, 다시 하면 들어간다', (tester) async {
    await launch(tester);
    accounts.fail['personas'] = const AccountApiError(0, 'NETWORK', 'x');
    unawaited(auth.signInWithCode('K7QM4XPH2R'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('sync-failed')), findsOneWidget);
    await tester.tap(find.byKey(const Key('sync-retry')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('onboarding-page')), findsOneWidget);
  });

  testWidgets('F-026 AC8 기기 데이터가 있으면 처음 로그인 뒤 한 번 묻고, 옮기면 기기 키를 지운다', (tester) async {
    var migrated = 0, skipped = 0;
    final device = DeviceData(
      payload: const {'personas': [], 'summaries': [], 'longTerm': []},
      markMigrated: () async => migrated++,
      markSkipped: () async => skipped++,
    );
    await launch(tester, user: elder, onboarded: true, device: device);
    expect(find.byKey(const Key('import-page')), findsOneWidget);

    accounts.fail['import'] = const AccountApiError(500, 'INTERNAL', '서버 오류가 발생했어요.');
    await tester.tap(find.byKey(const Key('import-yes')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('import-error')), findsOneWidget);
    expect(migrated, 0, reason: '실패하면 기기 키를 지우지 않는다');

    await tester.tap(find.byKey(const Key('import-yes')));
    await tester.pumpAndSettle();
    expect(accounts.imports, hasLength(1));
    expect(migrated, 1);
    expect(find.byKey(const Key('import-page')), findsNothing);
    expect(find.byKey(const Key('input')), findsOneWidget);
  });

  testWidgets('F-026 AC8 옮기지 않기로 하면 기기 데이터는 남기고 다시 묻지 않는다', (tester) async {
    var skipped = 0;
    final device = DeviceData(payload: const {}, markMigrated: () async {}, markSkipped: () async => skipped++);
    await launch(tester, user: elder, onboarded: true, device: device);
    await tester.tap(find.byKey(const Key('import-no')));
    await tester.pumpAndSettle();
    expect(skipped, 1);
    expect(accounts.imports, isEmpty);
    expect(find.byKey(const Key('input')), findsOneWidget);
  });

  testWidgets('F-023 AC4 첫 실행은 미소를 추천하고, 말로 시작하면 미소와 음성 대화 화면이 열린다', (tester) async {
    await launch(tester, user: elder);
    expect(find.byKey(const Key('onboarding-page')), findsOneWidget);
    expect(find.text('추천'), findsOneWidget);

    await tester.tap(find.byKey(const Key('onboarding-voice')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400)); // 음성 화면은 원이 계속 숨 쉬어 settle하지 않는다
    expect(auth.onboarded, isTrue);
    expect(personas.selected.id, 'per_elder-care');
    expect(start.voiceOnStart, isTrue, reason: '다음에도 켜면 바로 음성 대화');
    expect(find.byKey(const Key('voice-page')), findsOneWidget);
    expect(voice.state, VoiceState.listening);
    expect(agent.starts, hasLength(1));
  });

  testWidgets('F-023 AC4 다른 상대를 고르고 글자로 시작하면 채팅 화면', (tester) async {
    await launch(tester, user: elder);
    await tester.tap(find.byKey(const Key('onboarding-per_friend')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('onboarding-text')));
    await tester.pumpAndSettle();
    expect(personas.selected.id, 'per_friend');
    expect(start.voiceOnStart, isFalse);
    expect(find.byKey(const Key('voice-page')), findsNothing);
    expect(find.byKey(const Key('input')), findsOneWidget);
  });

  testWidgets('F-023 AC4 음성이 없으면 첫 실행 버튼은 "시작하기" 하나다', (tester) async {
    await launch(tester, user: elder, withVoice: false);
    expect(find.byKey(const Key('onboarding-voice')), findsNothing);
    expect(find.text('시작하기'), findsOneWidget);
  });

  testWidgets('F-023 AC1 이미 로그인하고 첫 실행을 마쳤으면 바로 채팅 화면', (tester) async {
    await launch(tester, user: elder, onboarded: true);
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
    await launch(tester, user: elder, onboarded: true);
    await openSettings(tester);
    expect(find.byKey(const Key('settings-page')), findsOneWidget);
    expect(find.text('순자'), findsOneWidget);
    expect(find.text('어르신 · 로그인 코드로 로그인'), findsOneWidget);
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
    await launch(tester, user: elder, onboarded: true);
    await openSettings(tester);
    final before = tester.getSize(find.text('글자 크기')).height;
    await tester.tap(find.byKey(const Key('text-size-xlarge')));
    await tester.pumpAndSettle();
    expect(display.textSize, TextSize.xlarge);
    expect(tester.getSize(find.text('글자 크기')).height, greaterThan(before));
  });

  testWidgets('F-023 AC6 로그아웃은 한 번 더 묻고, 하면 로그인 화면으로 돌아간다', (tester) async {
    await launch(tester, user: elder, onboarded: true);
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
    expect(accounts.calls, contains('logout'));
    expect(personas.serverBacked, isFalse, reason: '화면에 남의 페르소나가 남지 않게 서버에서 뗀다');
  });
}
