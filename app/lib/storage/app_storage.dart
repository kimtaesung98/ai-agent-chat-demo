/// 기기 저장 (SPEC.md Q-005 · F-017 AC7, ARCHITECTURE.md ADR-023).
/// 페르소나·내 프로필·서버 주소·지난 대화 요약(F-019)·로그인 이름과 첫 실행 여부·글자 크기(F-023)를 키-값 저장소에 JSON 글자로 둔다.
/// 대화 내용 자체는 저장하지 않는다 (F-007) — 끝난 세션의 요약만 남긴다.
/// `shared_preferences`는 [PrefsStore] 파일(`prefs_store.dart`)에서만 import한다.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../chat/auth_controller.dart';
import '../chat/display_settings.dart';
import '../chat/memory_controller.dart';
import '../chat/persona_controller.dart';
import '../chat/server_settings.dart';
import '../chat/start_settings.dart';

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
  static const memory = 'memory.v1';
  static const voiceOnStart = 'start.voice';
  static const auth = 'auth.v1';
  static const textSize = 'display.textSize';
  static const all = {personas, server, memory, voiceOnStart, auth, textSize};
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

/// 저장된 대화 요약으로 기억을 만들고, 바뀔 때마다 저장한다 (F-019 AC5).
MemoryController loadMemory(KeyValueStore store) {
  Object? saved;
  try {
    final raw = store.read(StoreKeys.memory);
    if (raw != null) saved = jsonDecode(raw);
  } catch (_) {
    saved = null; // 깨진 값은 무시하고 빈 기억으로
  }
  final memory = MemoryController.restore(saved);
  memory.addListener(() => _write(store, StoreKeys.memory, jsonEncode(memory.snapshot())));
  return memory;
}

/// 저장된 시작 설정을 읽고, 바뀔 때마다 저장한다 (F-021).
StartSettings loadStart(KeyValueStore store) {
  final settings = StartSettings(store.read(StoreKeys.voiceOnStart) == 'true');
  settings.addListener(() => _write(store, StoreKeys.voiceOnStart, settings.voiceOnStart ? 'true' : null));
  return settings;
}

/// 저장된 로그인 상태(이름·첫 실행 여부)로 시작하고, 바뀔 때마다 저장한다 (F-023). 토큰은 저장하지 않는다.
AuthController loadAuth(KeyValueStore store, {required GoogleSignIn google}) {
  Object? saved;
  try {
    final raw = store.read(StoreKeys.auth);
    if (raw != null) saved = jsonDecode(raw);
  } catch (_) {
    saved = null; // 깨진 값은 무시하고 로그인 전으로
  }
  final auth = AuthController.restore(saved, google: google);
  auth.addListener(() => _write(store, StoreKeys.auth, jsonEncode(auth.snapshot())));
  return auth;
}

/// 저장된 글자 크기를 읽고, 바뀔 때마다 저장한다 (F-023).
DisplaySettings loadDisplay(KeyValueStore store) {
  final settings = DisplaySettings(TextSize.parse(store.read(StoreKeys.textSize)));
  settings.addListener(
    () => _write(store, StoreKeys.textSize, settings.textSize == TextSize.normal ? null : settings.textSize.name),
  );
  return settings;
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
