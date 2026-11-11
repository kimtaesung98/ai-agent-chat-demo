import 'package:ai_agent_chat/api/server_address.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('F-017 AC2 빌드 때 넣은 주소가 있으면 어느 플랫폼이든 그 주소를 쓴다', () {
    for (final p in AppPlatform.values) {
      expect(resolveServerAddress(configured: ' http://192.168.0.10:3000 ', platform: p), 'http://192.168.0.10:3000');
    }
  });

  test('F-017 AC2 주소가 없으면 웹은 같은 출처, Android 에뮬레이터는 10.0.2.2, iOS 시뮬레이터는 localhost', () {
    expect(resolveServerAddress(configured: '', platform: AppPlatform.web), '');
    expect(resolveServerAddress(configured: '', platform: AppPlatform.android), 'http://10.0.2.2:3000');
    expect(resolveServerAddress(configured: '', platform: AppPlatform.ios), 'http://localhost:3000');
    expect(resolveServerAddress(configured: '', platform: AppPlatform.other), 'http://localhost:3000');
  });
}
