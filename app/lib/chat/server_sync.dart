/// 로그인한 뒤 서버 계정 데이터로 앱을 맞춘다 (SPEC.md F-026 상세 동작 8·9, F-027, F-028, 단계 7-⑤).
///
///   로그인 ──▶ 프로필·페르소나 받기 ──▶ 페르소나·기억·대화 컨트롤러를 서버에 붙임 ──▶ (기기 데이터가 있으면) 옮길지 묻기
///   로그아웃 ──▶ 서버에서 뗌 (화면에 남의 데이터가 남지 않게)
///
/// 프로필(나에 대해·글자 크기·켜면 바로 음성·마지막 페르소나)은 바뀔 때마다 서버에 보낸다. 기기에는 화면 캐시만.
/// `package:flutter/foundation.dart`까지만 import한다.
library;

import 'package:flutter/foundation.dart';

import '../api/account_api.dart';
import 'auth_controller.dart';
import 'chat_controller.dart';
import 'display_settings.dart';
import 'start_settings.dart';

/// 이 기기에 남은 예전 데이터 (`personas.v1`·`memory.v1`). 저장소(`storage/`)가 만든다.
class DeviceData {
  const DeviceData({required this.payload, required this.markMigrated, required this.markSkipped});

  /// `POST /api/import` 본문 (API-014).
  final Map<String, Object?> payload;

  /// 옮긴 뒤 기기 키를 지우고 `migrated.v1`을 남긴다 (성공한 뒤에만).
  final Future<void> Function() markMigrated;

  /// 옮기지 않기로 했다 — 기기 키는 남기고 다시 묻지 않는다.
  final Future<void> Function() markSkipped;
}

enum SyncState { idle, loading, ready, failed }

/// 기기 데이터 옮기기 안내 문장.
abstract final class SyncMessages {
  static const loadFailed = '내 정보를 불러오지 못했어요. 네트워크를 확인하고 다시 해 주세요.';
  static const importFailed = '옮기지 못했어요. 잠시 뒤 다시 해 주세요. 기기 데이터는 그대로 있어요.';
}

class ServerSync extends ChangeNotifier {
  ServerSync({required this.api, required this.auth, required this.chat, this.start, this.display, this._device}) {
    auth.addListener(_onAuth);
    start?.addListener(_pushSettings);
    display?.addListener(_pushSettings);
    chat.personas?.addListener(_onPersonas);
    _onAuth();
  }

  final AccountApi api;
  final AuthController auth;
  final ChatController chat;
  final StartSettings? start;
  final DisplaySettings? display;
  DeviceData? _device;

  SyncState _state = SyncState.idle;
  SyncState get state => _state;
  String? _error;
  String? get error => _error;

  /// 기기에 옮길 데이터가 있어 물어봐야 하는지 (F-026 상세 동작 9).
  bool get importPending => _state == SyncState.ready && _device != null;
  bool _importing = false;
  bool get importing => _importing;

  // 서버에 마지막으로 보낸(또는 받은) 값 — 같은 값을 다시 보내지 않는다
  String? _sentAbout, _sentPersona, _sentTextSize;
  bool? _sentVoice;
  var _gen = 0;

  void _onAuth() {
    if (auth.onboarded) _onPersonas(); // 첫 실행에서 고른 상대(추천 그대로여도)를 남긴다
    if (auth.signedIn && _state == SyncState.idle) {
      load();
    } else if (!auth.signedIn && _state != SyncState.idle) {
      _gen++;
      _state = SyncState.idle;
      _error = null;
      chat.detachServer();
      chat.personas?.detachServer();
      chat.memory?.detachServer();
      _sentAbout = _sentPersona = _sentTextSize = null;
      _sentVoice = null;
      notifyListeners();
    }
  }

  /// 프로필·페르소나를 받아 컨트롤러를 서버에 붙인다. 실패하면 [SyncState.failed] — 화면이 다시 하기를 보여 준다.
  Future<void> load() async {
    final gen = ++_gen;
    _state = SyncState.loading;
    _error = null;
    notifyListeners();
    try {
      final profile = await api.profile();
      final list = await api.personas();
      if (gen != _gen) return;
      final personas = chat.personas;
      _sentAbout = profile.about;
      _sentPersona = profile.lastPersonaId;
      if (personas != null && list.isNotEmpty) {
        personas.attachServer(api, list, about: profile.about, selectedId: profile.lastPersonaId);
      }
      chat.memory?.attachServer(api);
      chat.attachServer(api);
      if (profile.saved) {
        // 서버에 저장된 설정이 기기보다 먼저다 (다른 기기에서 바꾼 것)
        if (display case final d?) d.textSize = TextSize.parse(profile.textSize);
        start?.voiceOnStart = profile.voiceOnStart;
      }
      _sentTextSize = display?.textSize.name;
      _sentVoice = start?.voiceOnStart;
      if (profile.lastPersonaId.isNotEmpty) auth.completeOnboarding(); // 이미 대화 상대를 고른 계정
      _state = SyncState.ready;
    } on AccountApiError catch (e) {
      if (gen != _gen) return;
      if (e.unauthenticated) return auth.sessionExpired();
      _state = SyncState.failed;
      _error = e.network ? SyncMessages.loadFailed : e.message;
    } catch (_) {
      if (gen != _gen) return;
      _state = SyncState.failed;
      _error = SyncMessages.loadFailed;
    }
    notifyListeners();
  }

  /// 기기 데이터를 내 계정으로 옮긴다 (`POST /api/import`). 성공한 뒤에만 기기 키를 지운다. 실패하면 안내 문장.
  Future<String?> importDevice() async {
    final device = _device;
    if (device == null || _importing) return null;
    _importing = true;
    notifyListeners();
    try {
      await api.importDevice(device.payload);
      await device.markMigrated();
      _device = null;
      _importing = false;
      await load(); // 옮긴 페르소나·기억을 다시 받는다
      return null;
    } catch (e) {
      _importing = false;
      notifyListeners();
      return e is AccountApiError && !e.network ? e.message : SyncMessages.importFailed;
    }
  }

  /// 옮기지 않는다. 기기 데이터는 남기고 다시 묻지 않는다.
  Future<void> skipImport() async {
    final device = _device;
    if (device == null) return;
    _device = null;
    notifyListeners();
    await device.markSkipped();
  }

  void _onPersonas() {
    final personas = chat.personas;
    if (_state != SyncState.ready || personas == null || !personas.serverBacked) return;
    final about = personas.about;
    final selected = personas.selected.id;
    final aboutChanged = about != _sentAbout;
    final personaChanged = selected != _sentPersona && selected.startsWith('per_');
    if (!aboutChanged && !personaChanged) return;
    _sentAbout = about;
    if (personaChanged) _sentPersona = selected;
    _send(() => api.updateProfile(about: aboutChanged ? about : null, lastPersonaId: personaChanged ? selected : null));
  }

  void _pushSettings() {
    if (_state != SyncState.ready) return;
    final size = display?.textSize.name;
    final voice = start?.voiceOnStart;
    final sizeChanged = size != _sentTextSize, voiceChanged = voice != _sentVoice;
    if (!sizeChanged && !voiceChanged) return;
    _sentTextSize = size;
    _sentVoice = voice;
    _send(() => api.updateProfile(textSize: sizeChanged ? size : null, voiceOnStart: voiceChanged ? voice : null));
  }

  void _send(Future<void> Function() call) {
    call().catchError((Object e) {
      if (e is AccountApiError && e.unauthenticated) auth.sessionExpired();
      debugPrint('프로필 저장 실패'); // 값은 로그에 남기지 않는다
    });
  }

  @override
  void dispose() {
    auth.removeListener(_onAuth);
    start?.removeListener(_pushSettings);
    display?.removeListener(_pushSettings);
    chat.personas?.removeListener(_onPersonas);
    super.dispose();
  }
}
