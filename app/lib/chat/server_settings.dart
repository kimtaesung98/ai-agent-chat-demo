/// 앱 안에서 바꾸는 서버 주소 (SPEC.md F-017 AC7). 모바일 앱에서만 쓴다 — 웹은 같은 출처.
/// `package:flutter/foundation.dart`까지만 import한다. 저장은 바깥(`storage/`)이 한다.
library;

import 'package:flutter/foundation.dart';

/// 주소 입력 안내 문장.
abstract final class ServerMessages {
  static const invalid = 'http:// 또는 https://로 시작하는 주소를 넣어 주세요. 예) http://192.168.0.10:3000';
}

class ServerSettings extends ChangeNotifier {
  /// [fallback]은 빌드 때 정한 주소(ADR-022), [saved]는 사용자가 앱에서 넣은 주소.
  ServerSettings({required this.fallback, String saved = ''}) : _custom = normalize(saved) ?? '';

  /// 사용자가 넣은 주소가 없을 때 쓰는 주소.
  final String fallback;
  String _custom;

  /// 사용자가 넣은 주소. 없으면 빈 문자열.
  String get custom => _custom;

  /// 지금 쓰는 주소.
  String get address => _custom.isEmpty ? fallback : _custom;

  /// 주소를 검사해 고친 값을 돌려준다. 틀리면 null. 끝의 `/`와 경로는 버린다.
  static String? normalize(String input) {
    final v = input.trim();
    if (v.isEmpty) return null;
    final uri = Uri.tryParse(v);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https') || uri.host.isEmpty) return null;
    if (uri.userInfo.isNotEmpty) return null; // 주소에 계정·비밀값을 넣지 않는다
    return uri.hasPort ? '${uri.scheme}://${uri.host}:${uri.port}' : '${uri.scheme}://${uri.host}';
  }

  /// 새 주소를 쓴다. 빈 값이면 기본 주소로 돌아간다. 틀리면 안내 문장을 돌려주고 바꾸지 않는다.
  String? update(String input) {
    final String next;
    if (input.trim().isEmpty) {
      next = '';
    } else {
      final n = normalize(input);
      if (n == null) return ServerMessages.invalid;
      next = n;
    }
    if (next != _custom) {
      _custom = next;
      notifyListeners();
    }
    return null;
  }
}
