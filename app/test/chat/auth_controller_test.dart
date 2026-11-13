import 'package:ai_agent_chat/chat/auth_controller.dart';
import 'package:ai_agent_chat/chat/display_settings.dart';
import 'package:ai_agent_chat/storage/app_storage.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeGoogle implements GoogleSignIn {
  Account? result = const Account(name: '김순자', kind: AccountKind.google, email: 'a@example.com');
  bool fail = false;
  int calls = 0;

  @override
  Future<Account?> signIn() async {
    calls++;
    if (fail) throw StateError('network');
    return result;
  }
}

Future<void> settle() => Future<void>.delayed(Duration.zero);

void main() {
  test('F-023 AC2 Google 로그인에 성공하면 계정이 생기고, 창을 닫으면 그대로다', () async {
    final google = FakeGoogle();
    final auth = AuthController(google: google);
    expect(auth.signedIn, isFalse);

    google.result = null; // 사용자가 창을 닫음
    expect(await auth.signInWithGoogle(), isFalse);
    expect(auth.signedIn, isFalse);
    expect(auth.error, isNull);

    google.result = const Account(name: '김순자', kind: AccountKind.google);
    expect(await auth.signInWithGoogle(), isTrue);
    expect(auth.account!.name, '김순자');
  });

  test('F-023 AC2 Google 로그인이 실패하면 안내 문장을 보이고 로그인 전으로 남는다', () async {
    final google = FakeGoogle()..fail = true;
    final auth = AuthController(google: google);
    expect(await auth.signInWithGoogle(), isFalse);
    expect(auth.error, AuthMessages.googleFailed);
    expect(auth.busy, isFalse);
  });

  test('F-023 AC2 모의 Google 로그인은 모의 계정을 돌려준다', () async {
    final a = await const MockGoogleSignIn(delay: Duration.zero).signIn();
    expect(a!.mock, isTrue);
    expect(a.kind, AccountKind.google);
  });

  test('F-023 AC3 이름만 적고 시작 — 빈 이름은 막고, 긴 이름은 자른다', () {
    final auth = AuthController(google: FakeGoogle());
    expect(auth.continueAsGuest('   '), AuthMessages.emptyName);
    expect(auth.signedIn, isFalse);
    expect(auth.continueAsGuest(' 순자 '), isNull);
    expect(auth.account!.name, '순자');
    expect(auth.account!.kind, AccountKind.guest);
    expect(auth.continueAsGuest('가' * 40), isNull);
    expect(auth.account!.name.length, Account.maxName);
  });

  test('F-023 AC6 로그인·첫 실행 여부가 기기에 남고, 로그아웃해도 첫 실행은 다시 하지 않는다', () async {
    final store = MemoryStore();
    final auth = loadAuth(store, google: FakeGoogle());
    auth.continueAsGuest('순자');
    auth.completeOnboarding();
    await settle();

    final again = loadAuth(store, google: FakeGoogle());
    expect(again.account!.name, '순자');
    expect(again.onboarded, isTrue);

    again.signOut();
    await settle();
    final third = loadAuth(store, google: FakeGoogle());
    expect(third.signedIn, isFalse);
    expect(third.onboarded, isTrue);
  });

  test('F-023 AC6 깨진 저장 값은 무시하고 로그인 전으로 시작한다', () {
    for (final broken in ['{', '[]', '{"account": {"name": ""}}', '{"account": {"name": "a", "kind": "x"}}']) {
      final auth = loadAuth(MemoryStore({StoreKeys.auth: broken}), google: FakeGoogle());
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
