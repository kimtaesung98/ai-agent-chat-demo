/// 기기 저장 (SPEC.md Q-005 · F-017 AC7, ARCHITECTURE.md ADR-023).
/// 페르소나·내 프로필·서버 주소를 키-값 저장소에 JSON 글자로 둔다. 대화 내용은 저장하지 않는다 (F-007).
/// `shared_preferences`는 [PrefsStore] 파일(`prefs_store.dart`)에서만 import한다.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../chat/persona_controller.dart';
import '../chat/server_settings.dart';

/// 문자열 키-값 저장소. 읽기는 바로, 쓰기는 비동기. 테스트는 [MemoryStore].
abstract interface class KeyValueStore {
  String? read(String key);
  Future<void> write(String key, String? value);
}

/// 앱 메모리 저장소 — 테스트용이고, 기기 저장소를 열지 못했을 때 대신 쓴다.
class MemoryStore implements KeyValueStore {
  MemoryStore([Map<String, String>? initial]) : values = {...?initial};
  final Map<String, String> values;

  @override
  String? read(String key) => values[key];

  @override
  Future<void> write(String key, String? value) async {
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }
}

abstract final class StoreKeys {
  static const personas = 'personas.v1';
  static const server = 'server.address';
  static const all = {personas, server};
}

/// 저장된 페르소나로 컨트롤러를 만들고, 바뀔 때마다 저장한다.
PersonaController loadPersonas(KeyValueStore store) {
  Object? saved;
  try {
    final raw = store.read(StoreKeys.personas);
    if (raw != null) saved = jsonDecode(raw);
  } catch (_) {
    saved = null; // 깨진 값은 무시하고 기본값으로
  }
  final personas = PersonaController.restore(saved);
  personas.addListener(() => _write(store, StoreKeys.personas, jsonEncode(personas.snapshot())));
  return personas;
}

/// 저장된 서버 주소로 설정을 만들고, 바뀔 때마다 저장한다.
ServerSettings loadServer(KeyValueStore store, {required String fallback}) {
  final settings = ServerSettings(fallback: fallback, saved: store.read(StoreKeys.server) ?? '');
  settings.addListener(() => _write(store, StoreKeys.server, settings.custom.isEmpty ? null : settings.custom));
  return settings;
}

void _write(KeyValueStore store, String key, String? value) {
  store.write(key, value).catchError((Object e) {
    debugPrint('저장 실패: $key'); // 값은 로그에 남기지 않는다
  });
}
