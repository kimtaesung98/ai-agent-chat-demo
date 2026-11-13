{{flutter_js}}
{{flutter_build_config}}

// Flutter 기본 서비스 워커(지원 중단, 스스로 등록을 지우고 페이지를 새로 고침)는 쓰지 않는다.
// 앱 화면 캐시는 web/sw.js가 맡는다 (SPEC.md F-025, ARCHITECTURE.md ADR-027).
_flutter.loader.load();
