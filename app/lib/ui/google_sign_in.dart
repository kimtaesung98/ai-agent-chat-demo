/// 플랫폼별 Google 로그인 창 (F-026): 웹은 `web/google.js`(Google Identity Services), 그 밖(테스트)은 없음.
library;

export 'google_sign_in_io.dart' if (dart.library.js_interop) 'google_sign_in_web.dart';
