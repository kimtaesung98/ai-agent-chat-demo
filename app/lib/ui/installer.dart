/// 플랫폼별 [Installer] (F-025): 웹은 `web/pwa.js`, 그 밖(네이티브·테스트)은 늘 설치됨으로 본다.
library;

export 'installer_io.dart' if (dart.library.js_interop) 'installer_web.dart';
