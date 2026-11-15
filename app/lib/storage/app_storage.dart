/// 기기 저장 (SPEC.md Q-005, ARCHITECTURE.md ADR-023). 웹은 localStorage.
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
import '../chat/server_sync.dart';
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
  static const memory = 'memory.v1';
  static const voiceOnStart = 'start.voice';
  static const auth = 'auth.v1';
  static const textSize = 'display.textSize';

  /// 기기 데이터를 서버 계정으로 옮겼는지 (F-026 상세 동작 9). `done`이면 옮김, `skipped`면 옮기지 않기로 함.
  static const migrated = 'migrated.v1';
  static const all = {personas, memory, voiceOnStart, auth, textSize, migrated};
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
  // 서버 계정에 붙어 있는 동안은 기기에 쓰지 않는다 (서버가 진실 원천, F-027)
  personas.addListener(() {
    if (!personas.serverBacked) _write(store, StoreKeys.personas, jsonEncode(personas.snapshot()));
  });
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
  memory.addListener(() {
    if (!memory.serverBacked) _write(store, StoreKeys.memory, jsonEncode(memory.snapshot()));
  });
  return memory;
}

/// 저장된 시작 설정을 읽고, 바뀔 때마다 저장한다 (F-021).
StartSettings loadStart(KeyValueStore store) {
  final settings = StartSettings(store.read(StoreKeys.voiceOnStart) == 'true');
  settings.addListener(() => _write(store, StoreKeys.voiceOnStart, settings.voiceOnStart ? 'true' : null));
  return settings;
}

/// 저장된 첫 실행 여부로 시작하고, 바뀔 때마다 저장한다 (F-023·F-026). 토큰·이름은 저장하지 않는다 — 세션은 서버 쿠키.
AuthController loadAuth(KeyValueStore store, {required AccountApi api, GoogleSignIn? google}) {
  Object? saved;
  try {
    final raw = store.read(StoreKeys.auth);
    if (raw != null) saved = jsonDecode(raw);
  } catch (_) {
    saved = null; // 깨진 값은 무시하고 로그인 전으로
  }
  final auth = AuthController.restore(saved, api: api, google: google);
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

void _write(KeyValueStore store, String key, String? value) {
  store.write(key, value).catchError((Object e) {
    debugPrint('저장 실패: $key'); // 값은 로그에 남기지 않는다
  });
}

/// 기기에 남은 예전 페르소나·기억을 서버로 한 번 옮길 데이터 (F-026 상세 동작 9, API-014).
/// 이미 옮겼거나 옮기지 않기로 했으면, 또는 옮길 만한 것이 없으면(손대지 않은 탑재 페르소나뿐) null.
/// 앱을 켤 때 컨트롤러가 기기 값을 바꾸기 전에 부른다.
DeviceData? loadDeviceData(KeyValueStore store) {
  if (store.read(StoreKeys.migrated) != null) return null;
  Object? decode(String key) {
    try {
      final raw = store.read(key);
      return raw == null ? null : jsonDecode(raw);
    } catch (_) {
      return null;
    }
  }

  final personasRaw = decode(StoreKeys.personas), memoryRaw = decode(StoreKeys.memory);
  if (personasRaw == null && memoryRaw == null) return null;
  final personas = PersonaController.restore(personasRaw);
  final memory = MemoryController.restore(memoryRaw);
  final payload = deviceImportPayload(personas, memory);
  final hasContent =
      (payload['personas'] as List).isNotEmpty ||
      (payload['summaries'] as List).isNotEmpty ||
      (payload['longTerm'] as List).isNotEmpty ||
      personas.about.trim().isNotEmpty;
  Future<void> mark(String value, {required bool clear}) async {
    if (clear) {
      await store.write(StoreKeys.personas, null);
      await store.write(StoreKeys.memory, null);
    }
    await store.write(StoreKeys.migrated, value);
  }

  if (!hasContent) {
    // 손대지 않은 기본값뿐이면 묻지 않고 정리한다
    _write(store, StoreKeys.migrated, 'done');
    return null;
  }
  return DeviceData(
    payload: payload,
    markMigrated: () => mark('done', clear: true),
    markSkipped: () => mark('skipped', clear: false),
  );
}

/// API-014 본문. 탑재 페르소나는 사용자가 손댄 것(요구 사항·이름·말투)만, 만든 페르소나는 모두 싣는다.
/// 기기 id를 `clientId`로 보내 두 번 올려도 늘지 않게 한다.
Map<String, Object?> deviceImportPayload(PersonaController personas, MemoryController memory) {
  final sent = <String>{};
  final list = <Map<String, Object>>[];
  for (final p in personas.personas) {
    final builtIn = defaultPersonas.where((b) => b.id == p.id).firstOrNull;
    final hasMemory = memory.forPersona(p.id).isNotEmpty || memory.longTermFor(p.id) != null;
    if (builtIn != null) {
      final touched =
          p.instructions.trim().isNotEmpty ||
          p.name != builtIn.name ||
          p.role != builtIn.role ||
          p.tones.join('|') != builtIn.tones.join('|');
      if (!touched && !hasMemory) continue;
      list.add(p.copyWith(presetId: p.id, base: '').toV1Json(clientId: p.id));
    } else {
      list.add(p.copyWith(presetId: '').toV1Json(clientId: p.id));
    }
    sent.add(p.id);
  }
  return {
    if (personas.about.trim().isNotEmpty) 'profile': {'about': personas.about.trim()},
    'personas': list,
    'summaries': [
      for (final id in sent)
        for (final s in memory.forPersona(id).reversed)
          {
            'clientId': s.id,
            'personaClientId': id,
            'endedAt': s.endedAt.toUtc().toIso8601String(),
            'summary': s.summary,
            'facts': s.facts,
            'followUps': s.followUps,
            'turns': s.turns,
          },
    ],
    'longTerm': [
      for (final id in sent)
        if (memory.longTermFor(id) case final l?)
          {
            'personaClientId': id,
            'summary': l.summary,
            'facts': l.facts,
            'coversUntil': l.coversUntil.toUtc().toIso8601String(),
          },
    ],
  };
}
