/// `shared_preferences`로 만든 [KeyValueStore] (ARCHITECTURE.md ADR-023). 패키지는 이 파일에서만 import한다.
/// Android는 SharedPreferences, iOS는 NSUserDefaults, 웹은 브라우저 localStorage.
library;

import 'package:shared_preferences/shared_preferences.dart';

import 'app_storage.dart';

class PrefsStore implements KeyValueStore {
  PrefsStore._(this._prefs);
  final SharedPreferencesWithCache _prefs;

  /// 앱 시작 때 한 번 연다 (`runApp` 전, 바인딩 초기화 뒤).
  static Future<PrefsStore> open() async => PrefsStore._(
    await SharedPreferencesWithCache.create(
      cacheOptions: const SharedPreferencesWithCacheOptions(allowList: StoreKeys.all),
    ),
  );

  @override
  String? read(String key) => _prefs.getString(key);

  @override
  Future<void> write(String key, String? value) => value == null ? _prefs.remove(key) : _prefs.setString(key, value);
}
