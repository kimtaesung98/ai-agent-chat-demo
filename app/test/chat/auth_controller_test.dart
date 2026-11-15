import 'package:ai_agent_chat/api/account_api.dart';
import 'package:ai_agent_chat/chat/auth_controller.dart';
import 'package:ai_agent_chat/chat/display_settings.dart';
import 'package:ai_agent_chat/storage/app_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes.dart';

/// 가짜 Google 창: [token]을 돌려준다. null이면 사용자가 창을 닫은 것.
class FakeGoogle implements GoogleSignIn {
  String? token = 'good-token';
  bool fail = false;
  final clientIds = <String>[];

  @override
  Future<String?> idToken(String clientId) async {
    clientIds.add(clientId);
    if (fail) throw StateError('network');
    return token;
  }
}

Future<void> settle() => Future<void>.delayed(Duration.zero);

void main() {
  test('F-026 AC1 앱을 켜면 세션을 확인하고, 살아 있으면 바로 들어간다', () async {
    final api = FakeAccountApi(
      user: const ServerUser(id: 'usr_a', name: '김순자', role: 'elder'),
    );
    final auth = AuthController(api: api);
    expect(auth.phase, AuthPhase.checking);
    await auth.start();
    expect(auth.phase, AuthPhase.signedIn);
    expect(auth.account!.name, '김순자');
    expect(auth.account!.roleLabel, '어르신');
  });

  test('F-026 AC4 세션이 없으면 로그인 전, 서버에 닿지 않으면 안내 문장', () async {
    final api = FakeAccountApi();
    final auth = AuthController(api: api);
    await auth.start();
    expect(auth.phase, AuthPhase.signedOut);
    expect(auth.error, isNull);

    api.fail['me'] = const AccountApiError(0, 'NETWORK', 'x');
    await auth.start();
    expect(auth.phase, AuthPhase.signedOut);
    expect(auth.error, AuthMessages.connect);
  });

  test('F-026 AC1 로그인 코드: 빈 코드는 막고, 틀리면 서버 문장, 맞으면 들어간다 (하이픈 무관)', () async {
    final api = FakeAccountApi();
    final auth = AuthController(api: api);
    await auth.start();
    expect(await auth.signInWithCode('  '), isFalse);
    expect(auth.error, AuthMessages.emptyCode);
    expect(api.calls, isNot(contains('loginCode')));

    expect(await auth.signInWithCode('AAAA-BBBB-CC'), isFalse);
    expect(auth.error, '코드를 다시 확인해 주세요.');
    expect(auth.signedIn, isFalse);
    expect(auth.busy, isFalse);

    expect(await auth.signInWithCode('k7qm-4xph-2r'), isTrue);
    expect(auth.account!.kind, AccountKind.code);
    expect(auth.error, isNull);
  });

  test('F-026 AC2 너무 많이 틀리면 서버의 429 문장을 그대로 보인다', () async {
    final api = FakeAccountApi();
    final auth = AuthController(api: api);
    api.fail['loginCode'] = const AccountApiError(429, 'RATE_LIMITED', '잠시 뒤 다시 해 주세요.');
    expect(await auth.signInWithCode('K7QM4XPH2R'), isFalse);
    expect(auth.error, '잠시 뒤 다시 해 주세요.');
  });

  test('F-026 AC3 Google 버튼은 서버가 켰고 Google 창이 있을 때만, 연결 안 된 계정은 안내', () async {
    final google = FakeGoogle();
    final off = AuthController(api: FakeAccountApi(), google: google);
    await off.start();
    expect(off.googleAvailable, isFalse);
    expect(await off.signInWithGoogle(), isFalse);

    final noWindow = AuthController(api: FakeAccountApi(google: true));
    await noWindow.start();
    expect(noWindow.googleAvailable, isFalse);

    final auth = AuthController(api: FakeAccountApi(google: true), google: google);
    await auth.start();
    expect(auth.googleAvailable, isTrue);

    google.token = null; // 창을 닫음
    expect(await auth.signInWithGoogle(), isFalse);
    expect(auth.error, isNull);

    google.token = 'stranger';
    expect(await auth.signInWithGoogle(), isFalse);
    expect(auth.error, '초대받지 않은 Google 계정이에요.');

    google.token = 'good-token';
    expect(await auth.signInWithGoogle(), isTrue);
    expect(google.clientIds.last, 'cid.apps.googleusercontent.com');
    expect(auth.account!.kind, AccountKind.google);
    expect(auth.account!.roleLabel, '보호자');
  });

  test('F-026 AC3 Google 창이 실패하면 안내 문장을 보이고 로그인 전으로 남는다', () async {
    final auth = AuthController(api: FakeAccountApi(google: true), google: FakeGoogle()..fail = true);
    await auth.start();
    expect(await auth.signInWithGoogle(), isFalse);
    expect(auth.error, AuthMessages.googleFailed);
    expect(auth.busy, isFalse);
  });

  test('F-026 AC4 로그아웃하면 서버 세션도 끝낸다', () async {
    final api = FakeAccountApi(
      user: const ServerUser(id: 'usr_a', name: '김순자', role: 'elder'),
    );
    final auth = AuthController(api: api);
    await auth.start();
    await auth.signOut();
    expect(auth.signedIn, isFalse);
    expect(api.calls, contains('logout'));
    expect(api.user, isNull);
  });

  test('F-023 AC6 첫 실행 여부만 기기에 남고(이름·토큰은 없음), 로그아웃해도 첫 실행은 다시 하지 않는다', () async {
    final store = MemoryStore();
    final api = FakeAccountApi();
    final auth = loadAuth(store, api: api);
    await auth.signInWithCode('K7QM4XPH2R');
    auth.completeOnboarding();
    await settle();
    final saved = store.read(StoreKeys.auth)!;
    expect(saved, isNot(contains('김순자')));

    final again = loadAuth(store, api: api);
    expect(again.onboarded, isTrue);
    await again.signOut();
    expect(loadAuth(store, api: api).onboarded, isTrue);
  });

  test('F-023 AC6 깨진·예전 저장 값은 무시하고 로그인 전으로 시작한다', () async {
    for (final broken in ['{', '[]', '{"account": {"name": "순자", "kind": "guest"}}']) {
      final auth = loadAuth(MemoryStore({StoreKeys.auth: broken}), api: FakeAccountApi());
      await auth.start();
      expect(auth.signedIn, isFalse, reason: broken);
    }
  });

  test('F-023 AC5 글자 크기가 기기에 남고, 보통이면 지운다', () async {
    final store = MemoryStore();
    final d = loadDisplay(store);
    expect(d.textSize, TextSize.normal);
    d.textSize = TextSize.xlarge;
    await settle();
    expect(loadDisplay(store).textSize, TextSize.xlarge);
    d.textSize = TextSize.normal;
    await settle();
    expect(store.read(StoreKeys.textSize), isNull);
    expect(loadDisplay(MemoryStore({StoreKeys.textSize: 'huge'})).textSize, TextSize.normal);
  });
}
