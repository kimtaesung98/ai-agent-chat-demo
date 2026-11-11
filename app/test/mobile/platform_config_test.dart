// 모바일 플랫폼 설정 파일 검사 (F-017). 기기·SDK 없이 매니페스트와 Info.plist 내용만 본다.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String read(String path) => File(path).readAsStringSync();

void main() {
  final main = read('android/app/src/main/AndroidManifest.xml');
  final plist = read('ios/Runner/Info.plist');

  test('F-017 AC4 Android 릴리스 매니페스트에 인터넷·마이크 권한이 있다', () {
    expect(main, contains('android.permission.INTERNET'));
    expect(main, contains('android.permission.RECORD_AUDIO'));
  });

  test('F-017 AC4 Android 11+에서 음성 인식·합성 엔진을 찾을 수 있다 (queries)', () {
    expect(main, contains('android.speech.RecognitionService'));
    expect(main, contains('android.intent.action.TTS_SERVICE'));
  });

  test('F-017 AC5 평문 HTTP는 debug·profile 빌드에서만 허용한다', () {
    expect(main, isNot(contains('usesCleartextTraffic')), reason: 'release는 HTTPS만');
    for (final kind in ['debug', 'profile']) {
      expect(read('android/app/src/$kind/AndroidManifest.xml'), contains('android:usesCleartextTraffic="true"'));
    }
  });

  test('F-017 AC4 iOS는 마이크·음성 인식 사용 이유를 한국어로 밝힌다', () {
    for (final key in ['NSMicrophoneUsageDescription', 'NSSpeechRecognitionUsageDescription']) {
      final m = RegExp('<key>$key</key>\\s*<string>([^<]+)</string>').firstMatch(plist);
      expect(m, isNotNull, reason: key);
      expect(m!.group(1), matches(RegExp('[가-힣]')));
    }
  });

  test('F-017 AC5 iOS는 로컬 네트워크(개발 서버)만 평문 HTTP 예외로 둔다', () {
    expect(plist, contains('NSAllowsLocalNetworking'));
    expect(plist, isNot(contains('NSAllowsArbitraryLoads')));
  });

  test('F-017 AC1 앱 이름은 AI Agent Chat', () {
    expect(main, contains('android:label="AI Agent Chat"'));
    expect(plist, contains('<string>AI Agent Chat</string>'));
  });
}
