/// 로그인 상태와 첫 실행 여부 (SPEC.md F-026 상세 동작 2~4, F-023, S-004·S-005).
/// 계정은 관리자가 만든다 — 앱은 관리자가 알려 준 **로그인 코드** 또는 연결된 **Google 계정**으로만 들어간다.
/// 세션은 서버가 주는 `HttpOnly` 쿠키라 앱은 토큰을 보지도 저장하지도 않는다. 기기에는 첫 실행 여부만 남긴다.
/// `package:flutter/foundation.dart`까지만 import한다. 저장은 바깥(`storage/`)이 한다.
library;

import 'package:flutter/foundation.dart';

import '../api/account_api.dart';

export '../api/account_api.dart' show AccountApi, AuthOptions;

/// 로그인 방법.
enum AccountKind {
  /// 관리자가 알려 준 10자리 코드 (F-026 상세 동작 2).
  code,

  /// 연결된 Google 계정 (F-026 상세 동작 3).
  google,
}

/// 로그인한 사람. 화면에 보일 이름·역할만 갖는다 — 토큰은 여기에 두지 않는다.
@immutable
class Account {
  const Account({required this.name, required this.role, this.kind = AccountKind.code, this.googleLinked = false});

  factory Account.fromServer(ServerUser u, {AccountKind kind = AccountKind.code}) =>
      Account(name: u.name, role: u.role, kind: kind, googleLinked: u.google);

  final String name;

  /// `super_admin` · `caregiver` · `elder` · `guardian` (F-029).
  final String role;
  final AccountKind kind;

  /// Google 계정이 연결되어 있는지.
  final bool googleLinked;

  String get initial => name.trim().isEmpty ? '?' : String.fromCharCode(name.trim().runes.first);

  /// 화면에 보일 역할 이름.
  String get roleLabel => switch (role) {
    'super_admin' => '최고 관리자',
    'caregiver' => '요양사',
    'guardian' => '보호자',
    _ => '어르신',
  };
}

/// Google 로그인 창 (Google Identity Services). ID 토큰을 돌려주고, 사용자가 닫으면 null.
abstract interface class GoogleSignIn {
  Future<String?> idToken(String clientId);
}

/// 로그인 안내 문장.
abstract final class AuthMessages {
  static const emptyCode = '받으신 로그인 코드 10자리를 넣어 주세요.';
  static const googleFailed = 'Google 로그인을 하지 못했어요. 잠시 뒤 다시 눌러 주세요.';
  static const connect = '서버에 연결할 수 없어요. 네트워크를 확인하고 다시 해 주세요.';
}

/// 앱이 시작할 때 세션을 확인하는 중인지, 로그인 전인지, 로그인했는지.
enum AuthPhase { checking, signedOut, signedIn }

class AuthController extends ChangeNotifier {
  AuthController({required this._api, this._google, this._onboarded = false});

  /// 저장해 둔 첫 실행 여부로 시작한다 (`auth.v1`). 예전 판의 이름·방법은 버린다 — 이제 계정은 서버에 있다.
  factory AuthController.restore(Object? saved, {required AccountApi api, GoogleSignIn? google}) =>
      AuthController(api: api, google: google, onboarded: saved is Map && saved['onboarded'] == true);

  /// 저장할 값 — [AuthController.restore]가 읽는다. 토큰·이름은 저장하지 않는다.
  Map<String, Object> snapshot() => {'v': 2, 'onboarded': _onboarded};

  final AccountApi _api;
  final GoogleSignIn? _google;
  Account? _account;
  bool _onboarded;
  bool _busy = false;
  String? _error;
  AuthPhase _phase = AuthPhase.checking;
  AuthOptions _options = const AuthOptions();

  AuthPhase get phase => _phase;
  Account? get account => _account;
  bool get signedIn => _account != null;

  /// 로그인 화면에 보일 방법. Google은 서버에 클라이언트 ID가 있고 앱에 Google 창이 있을 때만.
  AuthOptions get options => _options;
  bool get googleAvailable => _options.google && _google != null;

  /// 첫 실행(페르소나 고르기)을 마쳤는지. 기기에 남고 로그아웃해도 그대로다.
  bool get onboarded => _onboarded;

  /// 로그인 요청 중이면 true — 버튼을 잠근다.
  bool get busy => _busy;
  String? get error => _error;

  /// 앱 시작 때 한 번: 로그인 방법과 지금 세션을 확인한다. 세션이 살아 있으면 바로 들어간다.
  Future<void> start() async {
    _phase = AuthPhase.checking;
    _error = null;
    notifyListeners();
    try {
      _options = await _api.options();
    } catch (_) {
      _options = const AuthOptions(); // 코드 로그인은 언제나 있다
    }
    try {
      final user = await _api.me();
      if (user != null) _account = Account.fromServer(user);
    } on AccountApiError catch (e) {
      _error = e.network ? AuthMessages.connect : e.message;
    } catch (_) {
      _error = AuthMessages.connect;
    }
    _phase = _account == null ? AuthPhase.signedOut : AuthPhase.signedIn;
    notifyListeners();
  }

  /// 관리자가 알려 준 코드로 들어간다. 성공하면 true. 하이픈·공백·소문자는 서버가 맞춘다.
  Future<bool> signInWithCode(String code) async {
    if (_busy) return false;
    final c = code.trim();
    if (c.isEmpty) {
      _error = AuthMessages.emptyCode;
      notifyListeners();
      return false;
    }
    return _signIn(() => _api.loginWithCode(c), AccountKind.code);
  }

  /// Google로 들어간다. 창을 닫으면 그대로 false.
  Future<bool> signInWithGoogle() async {
    final google = _google;
    if (_busy || google == null || !_options.google) return false;
    _busy = true;
    _error = null;
    notifyListeners();
    String? token;
    try {
      token = await google.idToken(_options.googleClientId);
    } catch (_) {
      _busy = false;
      _error = AuthMessages.googleFailed;
      notifyListeners();
      return false;
    }
    _busy = false;
    if (token == null || token.isEmpty) {
      notifyListeners();
      return false;
    }
    return _signIn(() => _api.loginWithGoogle(token!), AccountKind.google);
  }

  Future<bool> _signIn(Future<ServerUser> Function() login, AccountKind kind) async {
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      _account = Account.fromServer(await login(), kind: kind);
      _phase = AuthPhase.signedIn;
    } on AccountApiError catch (e) {
      _error = e.network ? AuthMessages.connect : e.message; // 서버 문장: 코드를 다시 확인해 주세요 · 초대되지 않은 계정 · 잠시 뒤
    } catch (_) {
      _error = AuthMessages.connect;
    }
    _busy = false;
    notifyListeners();
    return _account != null;
  }

  /// 첫 실행을 마쳤다.
  void completeOnboarding() {
    if (_onboarded) return;
    _onboarded = true;
    notifyListeners();
  }

  /// 로그아웃한다. 화면은 바로 로그인으로 가고, 서버 세션은 뒤에서 끝낸다.
  Future<void> signOut() async {
    if (_account == null) return;
    _account = null;
    _error = null;
    _phase = AuthPhase.signedOut;
    notifyListeners();
    try {
      await _api.logout();
    } catch (_) {
      debugPrint('로그아웃 요청 실패'); // 쿠키는 서버가 만료시킨다
    }
  }

  /// 서버가 세션이 끝났다고 알렸다 (401). 로그인 화면으로.
  void sessionExpired() {
    if (_account == null) return;
    _account = null;
    _phase = AuthPhase.signedOut;
    _error = '다시 로그인해 주세요.';
    notifyListeners();
  }
}
