import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 웹앱(PWA) 설정 파일 검사 (SPEC.md F-025 AC1·AC2).
void main() {
  test('F-025 AC1 매니페스트: 이름·한국어·standalone·아이콘 192·512·maskable', () {
    final m = jsonDecode(File('web/manifest.json').readAsStringSync()) as Map<String, dynamic>;
    expect(m['name'], 'AI 말벗');
    expect(m['lang'], 'ko');
    expect(m['display'], 'standalone');
    expect(m['start_url'], '/');
    final icons = (m['icons'] as List).cast<Map<String, dynamic>>();
    for (final size in ['192x192', '512x512']) {
      expect(icons.any((i) => i['sizes'] == size && i['purpose'] == null), isTrue, reason: size);
      expect(icons.any((i) => i['sizes'] == size && i['purpose'] == 'maskable'), isTrue, reason: '$size maskable');
    }
    for (final i in icons) {
      expect(File('web/${i['src']}').existsSync(), isTrue, reason: i['src'] as String);
    }
  });

  test('F-025 AC1 index.html은 한국어·매니페스트·홈 화면 아이콘·pwa.js·realtime.js를 싣는다', () {
    final html = File('web/index.html').readAsStringSync();
    expect(html, contains('<html lang="ko">'));
    expect(html, contains('rel="manifest"'));
    expect(html, contains('<title>AI 말벗</title>'));
    expect(html, contains('src="pwa.js"'));
    expect(html, contains('src="realtime.js"'));
    final apple = RegExp(r'rel="apple-touch-icon" href="([^"]+)"').firstMatch(html)!.group(1)!;
    expect(File('web/$apple').existsSync(), isTrue);
  });

  test('F-025 AC2 서비스 워커는 /api·다른 출처를 캐시하지 않고, 네트워크를 먼저 써서 새 빌드가 바로 보인다', () {
    final sw = File('web/sw.js').readAsStringSync();
    expect(sw, contains("url.pathname.startsWith('/api/')"));
    expect(sw, contains('url.origin !== self.location.origin'));
    expect(sw, contains("request.method !== 'GET'"));
    expect(sw.indexOf('await fetch(request)'), lessThan(sw.indexOf('caches.match(request)')), reason: '네트워크 먼저');
    expect(File('web/pwa.js').readAsStringSync(), contains("register('sw.js')"));
  });

  test('F-025 AC2 Flutter 기본 서비스 워커(스스로 지우고 새로 고침)는 등록하지 않는다', () {
    final boot = File('web/flutter_bootstrap.js').readAsStringSync();
    expect(boot, contains('_flutter.loader.load()'));
    expect(boot.contains('serviceWorkerSettings'), isFalse);
  });
}
