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
        final ok = p.startsWith('dart:') || p == 'package:flutter/foundation.dart' || p.startsWith('../api/');
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
            !p.contains('/');
        expect(ok, isTrue, reason: '$key → $p');
      }
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

  test('F-011 클라이언트에서 Claude API를 직접 부르지 않는다 (원칙 2)', () {
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      expect(f.readAsStringSync().contains('api.anthropic.com'), isFalse, reason: f.path);
    }
  });
}
