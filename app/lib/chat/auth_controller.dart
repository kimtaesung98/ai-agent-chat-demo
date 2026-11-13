/// 로그인 상태와 첫 실행 여부 (SPEC.md F-023, S-004·S-005). F-008 Google 로그인의 화면 쪽 기반이다.
/// 지금은 서버 인증이 없다 — Google 로그인은 [MockGoogleSignIn]이 흉내만 내고, 계정은 기기에만 남는다.
/// 진짜 Google 로그인(F-008)은 [GoogleSignIn]을 갈아 끼우고 서버 세션(`POST /api/auth/google`)을 붙인다.
/// `package:flutter/foundation.dart`까지만 import한다. 저장은 바깥(`storage/`)이 한다.
library;

import 'package:flutter/foundation.dart';

/// 로그인 방법.
enum AccountKind {
  /// Google 계정 (F-008). 지금은 모의.
  google,

  /// 이름만 적고 이 기기에서 쓰기.
  guest,
}

/// 로그인한 사람. 화면에 보일 이름만 갖는다 — 토큰·비밀번호는 여기에 두지 않는다.
@immutable
class Account {
  const Account({required this.name, required this.kind, this.email = '', this.mock = false});

  static const maxName = 20;

  final String name;
  final AccountKind kind;

  /// Google 계정 이메일. 손님은 빈 값.
  final String email;

  /// 모의 로그인으로 만든 계정인지 — 화면에 "모의"로 알린다.
  final bool mock;

  String get initial => name.trim().isEmpty ? '?' : String.fromCharCode(name.trim().runes.first);

  Map<String, Object> toJson() => {'name': name, 'kind': kind.name, 'email': email, 'mock': mock};

  static Account? fromJson(Object? json) {
    if (json is! Map) return null;
    final name = json['name'];
    final kind = AccountKind.values.where((k) => k.name == json['kind']).firstOrNull;
    if (name is! String || name.trim().isEmpty || kind == null) return null;
    final email = json['email'];
    return Account(name: name, kind: kind, email: email is String ? email : '', mock: json['mock'] == true);
  }
}

/// Google 로그인 창. 사용자가 닫으면 null.
abstract interface class GoogleSignIn {
  Future<Account?> signIn();
}

/// 모의 Google 로그인 — 창 없이 체험 계정을 돌려준다 (F-023 AC2). 진짜는 F-008.
class MockGoogleSignIn implements GoogleSignIn {
  const MockGoogleSignIn({this.delay = const Duration(milliseconds: 600)});
  final Duration delay;

  @override
  Future<Account?> signIn() async {
    await Future<void>.delayed(delay);
    return const Account(name: '체험 사용자', kind: AccountKind.google, email: 'demo@example.com', mock: true);
  }
}

/// 로그인 안내 문장.
abstract final class AuthMessages {
  static const emptyName = '어떻게 불러 드릴지 이름을 적어 주세요.';
  static const googleFailed = 'Google 로그인을 하지 못했어요. 잠시 뒤 다시 눌러 주세요.';
}

class AuthController extends ChangeNotifier {
  AuthController({required this._google, this._account, this._onboarded = false});

  /// 저장해 둔 값으로 시작한다. 모양이 틀리면 로그인 전으로.
  factory AuthController.restore(Object? saved, {required GoogleSignIn google}) {
    if (saved is! Map) return AuthController(google: google);
    return AuthController(
      google: google,
      account: Account.fromJson(saved['account']),
      onboarded: saved['onboarded'] == true,
    );
  }

  /// 저장할 값 — [AuthController.restore]가 읽는다.
  Map<String, Object> snapshot() => {
    'v': 1,
    if (_account case final a?) 'account': a.toJson(),
    'onboarded': _onboarded,
  };

  final GoogleSignIn _google;
  Account? _account;
  bool _onboarded;
  bool _busy = false;
  String? _error;

  Account? get account => _account;
  bool get signedIn => _account != null;

  /// 첫 실행(페르소나 고르기)을 마쳤는지. 기기에 남고 로그아웃해도 그대로다.
  bool get onboarded => _onboarded;

  /// Google 로그인 창이 떠 있는 동안 true — 버튼을 잠근다.
  bool get busy => _busy;
  String? get error => _error;

  /// Google로 로그인한다. 성공하면 true.
  Future<bool> signInWithGoogle() async {
    if (_busy) return false;
    _busy = true;
    _error = null;
    notifyListeners();
    Account? a;
    try {
      a = await _google.signIn();
    } catch (_) {
      a = null;
      _error = AuthMessages.googleFailed;
    }
    _busy = false;
    if (a != null) _account = a;
    notifyListeners();
    return a != null;
  }

  /// 이름만 적고 시작한다. 이름이 비면 안내 문장을 돌려주고 바꾸지 않는다.
  String? continueAsGuest(String name) {
    final n = name.trim();
    if (n.isEmpty) {
      _error = AuthMessages.emptyName;
      notifyListeners();
      return AuthMessages.emptyName;
    }
    _account = Account(name: n.length > Account.maxName ? n.substring(0, Account.maxName) : n, kind: AccountKind.guest);
    _error = null;
    notifyListeners();
    return null;
  }

  /// 첫 실행을 마쳤다.
  void completeOnboarding() {
    if (_onboarded) return;
    _onboarded = true;
    notifyListeners();
  }

  void signOut() {
    if (_account == null) return;
    _account = null;
    _error = null;
    notifyListeners();
  }
}
