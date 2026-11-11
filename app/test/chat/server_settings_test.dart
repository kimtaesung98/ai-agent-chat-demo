import 'package:ai_agent_chat/chat/server_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('F-017 AC7 주소를 http(s)://호스트[:포트]로 고친다', () {
    expect(ServerSettings.normalize(' http://192.168.0.10:3000/ '), 'http://192.168.0.10:3000');
    expect(ServerSettings.normalize('https://chat.example.com/path?q=1'), 'https://chat.example.com');
    expect(ServerSettings.normalize('http://my-mac.local:3000'), 'http://my-mac.local:3000');
  });

  test('F-017 AC7 틀린 주소는 받지 않고 안내한다', () {
    for (final bad in ['192.168.0.10:3000', 'ftp://x', 'http://', 'http://user:pw@host:3000', '아무거나']) {
      expect(ServerSettings.normalize(bad), isNull, reason: bad);
    }
    final s = ServerSettings(fallback: 'http://localhost:3000');
    var notified = 0;
    s.addListener(() => notified++);
    expect(s.update('192.168.0.10'), ServerMessages.invalid);
    expect(s.address, 'http://localhost:3000');
    expect(notified, 0);
  });

  test('F-017 AC7 바뀔 때만 알린다', () {
    final s = ServerSettings(fallback: 'http://localhost:3000');
    var notified = 0;
    s.addListener(() => notified++);
    s.update('http://10.0.0.5:3000');
    s.update('http://10.0.0.5:3000/');
    expect(notified, 1);
    expect(s.address, 'http://10.0.0.5:3000');
  });
}
