/// 앱이 부를 서버 주소 정하기 (SPEC.md F-017, ARCHITECTURE.md §6.3). `chat`·`ui`를 import하지 않는다.
library;

/// 개발용 서버 포트 (`chatd` 기본값 `PORT=3000`).
const devServerPort = 3000;

/// 앱이 실행되는 곳.
enum AppPlatform { web, android, ios, other }

/// 서버 주소를 정한다.
///
/// - [configured](빌드 때 `--dart-define=API_BASE_URL=...`)가 있으면 그대로 쓴다 — 실제 폰은 Mac의 LAN 주소나 배포 주소.
/// - 웹은 빈 문자열 = 같은 출처 (ADR-011).
/// - Android 에뮬레이터는 `10.0.2.2`가 개발 컴퓨터, iOS 시뮬레이터·데스크톱은 `localhost`가 개발 컴퓨터.
String resolveServerAddress({required String configured, required AppPlatform platform}) {
  final value = configured.trim();
  if (value.isNotEmpty) return value;
  return switch (platform) {
    AppPlatform.web => '',
    AppPlatform.android => 'http://10.0.2.2:$devServerPort',
    AppPlatform.ios || AppPlatform.other => 'http://localhost:$devServerPort',
  };
}
