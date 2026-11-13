import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// ARCHITECTURE.md §3.3 Flutter 의존 규칙 (SPEC.md F-011 AC3).
void main() {
  final importRe = RegExp(r'''^\s*(?:import|export)\s+['"]([^'"]+)['"]''', multiLine: true);

  Map<String, List<String>> importsOf(String dir) => {
    for (final f in Directory(
      'lib/$dir',
    ).listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart')))
      f.path: importRe.allMatches(f.readAsStringSync()).map((m) => m.group(1)!).toList(),
  };

  test('F-011 AC3 chat은 위젯을 import하지 않는다 (foundation까지만)', () {
    for (final MapEntry(:key, :value) in importsOf('chat').entries) {
      for (final p in value) {
        final sameFolder = !p.contains(':') && !p.contains('/'); // 예: chat_controller → persona_controller (F-005)
        final ok =
            p.startsWith('dart:') || p == 'package:flutter/foundation.dart' || p.startsWith('../api/') || sameFolder;
        expect(ok, isTrue, reason: '$key → $p');
      }
    }
  });

  test('F-011 AC3 api는 chat·ui·flutter를 import하지 않는다', () {
    for (final MapEntry(:key, :value) in importsOf('api').entries) {
      for (final p in value) {
        expect(
          p.contains('chat/') || p.contains('ui/') || p.startsWith('package:flutter/'),
          isFalse,
          reason: '$key → $p',
        );
      }
    }
  });

  test('F-011 AC3 ui는 api 구현을 직접 부르지 않는다 (controller를 거친다)', () {
    for (final MapEntry(:key, :value) in importsOf('ui').entries) {
      for (final p in value) {
        expect(p.contains('api/'), isFalse, reason: '$key → $p');
      }
    }
  });

  test('F-012 chat·api는 voice를 import하지 않는다', () {
    for (final dir in ['chat', 'api']) {
      for (final MapEntry(:key, :value) in importsOf(dir).entries) {
        for (final p in value) {
          expect(p.contains('voice/'), isFalse, reason: '$key → $p');
        }
      }
    }
  });

  test('F-012 voice는 위젯·ui를 import하지 않는다 (foundation까지만, chat·api 모델만)', () {
    for (final MapEntry(:key, :value) in importsOf('voice').entries) {
      for (final p in value) {
        final ok =
            p.startsWith('dart:') ||
            p == 'package:flutter/foundation.dart' ||
            p.startsWith('../chat/') ||
            p.startsWith('../api/models.dart') ||
            p.startsWith('package:speech_to_text/') ||
            p.startsWith('package:flutter_tts/') ||
            p.startsWith('package:elevenlabs_agents/') ||
            !p.contains('/');
        expect(ok, isTrue, reason: '$key → $p');
      }
    }
  });

  test('F-017 storage는 chat 모델까지만 알고, 다른 모듈은 storage를 모른다 (ADR-023)', () {
    for (final MapEntry(:key, :value) in importsOf('storage').entries) {
      for (final p in value) {
        final ok =
            p.startsWith('dart:') ||
            p == 'package:flutter/foundation.dart' ||
            p.startsWith('../chat/') ||
            p.startsWith('package:shared_preferences/') ||
            !p.contains('/');
        expect(ok, isTrue, reason: '$key → $p');
      }
    }
    for (final dir in ['chat', 'api', 'voice', 'ui']) {
      for (final MapEntry(:key, :value) in importsOf(dir).entries) {
        for (final p in value) {
          expect(p.contains('storage/'), isFalse, reason: '$key → $p');
        }
      }
    }
  });

  test('F-017 shared_preferences는 storage/prefs_store.dart에서만 import한다 (ADR-023)', () {
    for (final f in Directory(
      'lib',
    ).listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      final uses = importRe
          .allMatches(f.readAsStringSync())
          .any((m) => m.group(1)!.startsWith('package:shared_preferences/'));
      if (uses) expect(f.path.replaceAll(r'\\', '/'), endsWith('storage/prefs_store.dart'));
    }
  });

  test('F-012 음성 패키지는 plugin_voice_engine.dart에서만 import한다 (ADR-014)', () {
    for (final f in Directory(
      'lib',
    ).listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      final imports = importRe.allMatches(f.readAsStringSync()).map((m) => m.group(1)!);
      final usesPackage = imports.any(
        (p) => p.startsWith('package:speech_to_text/') || p.startsWith('package:flutter_tts/'),
      );
      if (usesPackage) expect(f.path, endsWith('voice/plugin_voice_engine.dart'));
    }
  });

  test('F-022 elevenlabs_agents는 voice/elevenlabs_agent.dart에서만 import하고, 앱에 ElevenLabs 키를 두지 않는다 (ADR-025)', () {
    for (final f in Directory(
      'lib',
    ).listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      final text = f.readAsStringSync();
      final uses = importRe.allMatches(text).any((m) => m.group(1)!.startsWith('package:elevenlabs_agents/'));
      if (uses) expect(f.path, endsWith('voice/elevenlabs_agent.dart'));
      expect(text.contains('xi-api-key'), isFalse, reason: f.path);
      expect(text.contains('api.elevenlabs.io'), isFalse, reason: f.path);
    }
  });

  test('F-011 클라이언트에서 Claude API를 직접 부르지 않는다 (원칙 2)', () {
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      expect(f.readAsStringSync().contains('api.anthropic.com'), isFalse, reason: f.path);
    }
  });

  test('F-024 AC4 앱에 OpenAI 키·주소·지시문 틀이 없고, dart:js_interop은 웹 전용 파일에서만 쓴다 (ADR-026)', () {
    for (final f in Directory(
      'lib',
    ).listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      final text = f.readAsStringSync();
      expect(text.contains('api.openai.com'), isFalse, reason: '${f.path}: OpenAI는 web/realtime.js가 임시 키로만 부른다');
      expect(text.contains('OPENAI_API_KEY'), isFalse, reason: f.path);
      expect(text.contains('client_secrets'), isFalse, reason: f.path);
      final js = importRe.allMatches(text).any((m) => m.group(1)!.startsWith('dart:js_interop'));
      if (js) {
        expect(
          f.path.endsWith('_web.dart') || f.path.endsWith('voice/openai_realtime_agent.dart'),
          isTrue,
          reason: f.path,
        );
      }
    }
    final js = File('web/realtime.js').readAsStringSync();
    expect(js.contains('client_secrets'), isFalse, reason: '임시 키 발급은 서버만');
    expect(js.contains("'Bearer ' + secret"), isTrue, reason: '브라우저는 받은 임시 키로만 연결');
  });
}
