/// 플랫폼별 HTTP 클라이언트 (ARCHITECTURE.md ADR-009).
/// 웹은 응답을 스트리밍으로 받기 위해 `fetch_client`, 그 밖에는 `package:http` 기본 클라이언트.
library;

export 'client_factory_io.dart' if (dart.library.js_interop) 'client_factory_web.dart';
