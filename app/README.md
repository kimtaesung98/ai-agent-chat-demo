# app — Overview

> **담당 기능**: `SPEC.md`의 `F-011` (Flutter 웹 클라이언트), `F-017` (Android·iOS 앱), `F-003` (응답 중단 — 화면), `F-012` (음성 대화), `F-018` (음성 전용 화면), `F-005` (페르소나 — 화면·상태), F-001 · F-002의 화면 부분  
> (진행 상태는 `/README.md` Progress Tracker에서 관리)

이 폴더는 **Flutter로 만든 채팅 화면(S-001)** 을 담당합니다. 웹 빌드는 Go 서버가 같은 출처로 제공합니다 (ARCHITECTURE.md ADR-011).  
같은 코드로 Android·iOS 앱도 빌드합니다 (`android/`·`ios/`, F-017). 앱은 `API_BASE_URL`로 같은 API를 부릅니다 (ADR-022).  
상태는 `ChatController`(`ChangeNotifier`)가 갖고, 위젯은 그리기와 입력 연결만 합니다 (ADR-010).  
음성 대화는 `VoiceController`가 `ChatController` 위에서 듣기 → 자동 전송 → 문장별 읽기 → 끼어들기를 진행합니다 (ADR-014·015).

---

## Context — 상위 흐름과의 연결

```
루트(/) — Level 0 DFD
└─ [AI Agent Chat] 버블 중 "방문자에게 보이는" 부분 (Flutter 구현)
       │  입력: 방문자의 키보드 입력·목소리, 서버의 SSE 스트림, /api/config
       ▼
app — Level 1 DFD (아래 상세)
       │  출력: POST /api/chat 요청 (대화 내역, 음성이면 mode: voice), 요청 중단, 화면 갱신, 읽어 주는 소리
       ▼
server (Go), 방문자
```

---

## DFD — Level 1 (Main Processes)

> Decomposed from: `/` Level 0 — `AI Agent Chat` 버블 (방문자와 만나는 부분)

```mermaid
flowchart LR
    User([방문자]) -->|"입력 · Enter · 중단 · 새 대화"| UI[ui/chat_page.dart<br>위젯]
    UI -->|"send · stop · reset"| Ctrl[chat/chat_controller.dart<br>ChangeNotifier]
    Ctrl -->|"빈 메시지면 무시"| UI
    Ctrl -->|"history[]"| Api[api/chat_api.dart<br>HttpChatApi]
    Api -->|"POST /api/chat<br>AbortableRequest"| Server[[server (Go)]]
    Server -->|"SSE"| Sse[api/sse.dart<br>parseSse]
    Sse -->|"ChatDelta · ChatDone · ChatFailed"| Ctrl
    Ctrl -.->|"구독 취소 = 요청 중단"| Api
    Ctrl -->|"notifyListeners"| UI
    UI -->|"화면 갱신 · liveRegion"| User
    Api -->|"GET /api/config"| Server
    User -->|"목소리"| Engine[voice/plugin_voice_engine.dart<br>speech_to_text · flutter_tts]
    UI -->|"마이크 버튼"| Voice[voice/voice_controller.dart<br>ChangeNotifier]
    Engine -->|"중간 · 확정 문장"| Voice
    Voice -->|"send(voice: true) · stop"| Ctrl
    Ctrl -->|"답 글자 변경"| Voice
    Voice -->|"문장 분리 (sentences.dart)<br>speak · cancelSpeech"| Engine
    Engine -->|"소리"| User
    Voice -->|"상태 · 미리 보기 · 안내"| UI
    UI -->|"음성 대화 화면 열기 · 글자로 보기 · 대화 끝내기"| VoicePage[ui/voice_page.dart<br>S-003]
    VoicePage -->|"start · tap(화면 누르기) · stop"| Voice
    Voice -->|"상태 · 미리 보기 · 읽는 문장 · 안내"| VoicePage
    VoicePage -->|"큰 상태 원 · 자막"| User
    VoicePage -->|"화면 꺼짐 막기 켜기·끄기"| Awake[ui/keep_awake.dart<br>Wake Lock · 네이티브 채널]
    UI -->|"앱 뒤로 · 돌아옴 (pause · resume)"| Voice
    User -->|"페르소나 선택 · 편집 · 내 프로필"| UI
    UI -->|"select · save · setAbout"| Persona[chat/persona_controller.dart<br>ChangeNotifier]
    Persona -->|"PersonaRequest (persona · about)"| Ctrl
    Persona <-->|"snapshot · restore"| Store[storage/app_storage.dart<br>shared_preferences]
    Ctrl -->|"endSession: 새 대화 · 페르소나 바꾸기 · 대화 끝내기 · 앱 뒤로"| Api
    Api -->|"POST /api/summary → 요약 JSON"| Ctrl
    Ctrl -->|"put(SessionSummary)"| Memory[chat/memory_controller.dart<br>ChangeNotifier]
    Memory -->|"recentFor(페르소나) → memory[] · longTermFor → longTerm"| Ctrl
    Ctrl -->|"pendingFold → POST /api/consolidate (F-020)"| Api
    Memory <-->|"snapshot · restore (memory.v1)"| Store
    UI -->|"편집 화면: 지난 대화 기억 보기 · 지우기"| Memory
    UI -->|"서버 주소 (모바일)"| Server2[chat/server_settings.dart]
    Server2 <-->|"주소 저장"| Store
    Server2 -.->|"main.dart: api.baseUrl"| Api
```

| 파일 | 역할 |
|---|---|
| `lib/main.dart` | 앱 조립: 서버 주소 정하기 → `HttpChatApi` → `ChatController` → `VoiceController`(`PluginVoiceEngine`) → `ChatApp` (`API_BASE_URL`은 빌드 때 주입, 웹은 비움) |
| `lib/api/server_address.dart` | 플랫폼별 서버 주소: 주입값 → 웹은 같은 출처, Android 에뮬레이터 `10.0.2.2:3000`, iOS 시뮬레이터 `localhost:3000` (F-017) |
| `lib/api/models.dart` | `Message`, `ChatEvent`(`ChatDelta`·`ChatDone`·`ChatFailed`), `ServerConfig`, `Persona`·`PersonaRequest`(API-001 `persona`) |
| `lib/api/sse.dart` | SSE 파서 (바이트 → 이벤트) |
| `lib/api/chat_api.dart` | `ChatApi` 인터페이스, `HttpChatApi` (구독 취소 시 요청 중단) |
| `lib/api/client_factory*.dart` | 웹은 `fetch_client`, 그 밖은 `package:http` (조건부 import, ADR-009) |
| `lib/chat/chat_controller.dart` | 말풍선 목록·바쁨·중단·새 대화·대화 내역, 요청에 선택한 페르소나와 지난 대화 기억 싣기, 대화 세션 끝에 요약(`endSession`, F-019) (위젯 없음, 테스트 대상) |
| `lib/chat/persona_controller.dart` | 페르소나 목록(기본 4개, 노인복지사 포함)·선택·저장·내 프로필, 저장용 `snapshot`·`restore` (F-005, Q-005). 탑재 페르소나의 기본 지시(`base`)는 고정 (F-019) |
| `lib/chat/start_settings.dart` | 앱 시작 설정: 켜면 바로 음성 대화 (F-021) |
| `lib/chat/memory_controller.dart` | 지난 대화 기억: 세션 요약을 페르소나별로 모으고(20개), 다음 요청용 최근 5개, 지우기, `snapshot`·`restore` (F-019) |
| `lib/chat/server_settings.dart` | 모바일 앱 서버 주소: 빌드 주소 + 앱에서 넣은 주소, 주소 검사 (F-017 AC7) |
| `lib/storage/app_storage.dart` | `KeyValueStore`·`MemoryStore`, 페르소나·서버 주소 불러오기와 바뀔 때 저장 (Q-005, ADR-023) |
| `lib/storage/prefs_store.dart` | `shared_preferences` 구현 — 패키지는 이 파일에서만 import |
| `lib/voice/voice_engine.dart` | `VoiceEngine` 인터페이스와 들은 것(`HeardPartial`·`HeardFinal`·`ListenEnded`·`ListenFailed`) |
| `lib/voice/plugin_voice_engine.dart` | `speech_to_text`·`flutter_tts`로 만든 엔진 — 패키지는 이 파일에서만 import (R-A11 특이점 처리) |
| `lib/voice/sentences.dart` | 스트리밍 답을 읽을 문장으로 나누고 마크다운·URL·코드를 빼는 순수 함수 |
| `lib/voice/voice_controller.dart` | 음성 대화 진행: 듣기 → 자동 전송 → 문장별 읽기 → 다시 듣기, 끼어들기·에코 무시, 지금 읽는 문장(`sentence`, F-018 자막), 화면 누르기(`tap`), 끊긴 인식 자동 복구(포기 안 함, 1~16초 간격), 앱이 뒤로 갔다 오면 `pause`·`resume` (위젯 없음, 테스트 대상) |
| `lib/ui/chat_page.dart` | S-001 화면 (페르소나 사이드바·서랍 · 상단 페르소나 · 모드 배지 · 편집 · 새 대화 · 대화 영역 · 음성 상태 · 입력창 · 마이크 · 전송/중단) |
| `lib/ui/voice_page.dart` | S-003 음성 대화 화면 (F-018, 어르신용 상시 대화): 상태 원 · 큰 상태 문구 · 큰 자막(인식 중 · 보낸 말 · 읽는 문장) · 안내. 모드 버튼 없음 — 화면 누르기 = 끼어들기(`tap`), 글자로 보기 · 대화 끝내기만. 채팅 화면 상단 바 버튼으로 열면 듣기 시작 |
| `lib/ui/keep_awake*.dart` | 음성 대화 화면 동안 화면 꺼짐 막기 (F-018 AC8): 웹은 Screen Wake Lock API(`dart:js_interop`), 앱은 채널 `ai_agent_chat/screen` → Android `MainActivity.kt` `FLAG_KEEP_SCREEN_ON` · iOS `AppDelegate.swift` `isIdleTimerDisabled`. 새 패키지 없음 |
| `lib/ui/persona_widgets.dart` | 페르소나 아바타 · 사이드바 · 내 프로필 대화상자 (900px 미만은 서랍) |
| `lib/ui/persona_editor.dart` | S-002 페르소나 편집 화면 (이름 · 역할 칩 · 말투 칩 최대 6개 · 추가 지시) |
| `lib/ui/server_dialog.dart` | 서버 주소 대화상자 (모바일 앱만, 사이드바 "서버 주소") |
| `lib/ui/theme.dart` | 라이트·다크 색 (MVP HTML 디자인과 같은 값) |
| `android/` · `ios/` | 네이티브 껍데기 (F-017): 권한(마이크·음성 인식·인터넷), 음성 엔진 조회(queries), 개발용 평문 HTTP 범위, 앱 이름. Dart 코드는 웹과 같음 |

**실행** (`app/`에서)
- 테스트: `flutter test` · 분석: `flutter analyze`
- 웹 빌드: `flutter build web --no-web-resources-cdn`
- 서버로 보기: `cd ../server && STATIC_DIR=../app/build/web go run ./cmd/chatd` → http://localhost:3000

**모바일 실행** (F-017 — 먼저 개발 컴퓨터에서 `cd ../server && go run ./cmd/chatd`, 키 없으면 모의 모드)
- 필요한 것: Android는 Android Studio(SDK·에뮬레이터) 또는 USB 디버깅을 켠 폰, iOS는 Mac의 Xcode + CocoaPods(`brew install cocoapods`)
- Android 에뮬레이터·iOS 시뮬레이터: `flutter run` (주소를 안 넣으면 개발 컴퓨터의 3000번을 부름)
- 실제 폰 (같은 Wi-Fi): Mac 주소 확인 `ipconfig getifaddr en0` → `flutter run --dart-define=API_BASE_URL=http://192.168.x.x:3000`, 또는 그냥 설치한 뒤 앱 사이드바(☰) > "서버 주소"에 넣기 (저장됨)
- Android APK만 만들기: `flutter build apk --debug --dart-define=API_BASE_URL=...` → `build/app/outputs/flutter-apk/app-debug.apk`를 폰에 설치
- iPhone: **처음 한 번은 Flutter 명령으로 빌드**해야 합니다 — `flutter_tts`는 CocoaPods로만 들어와서, Flutter가 `ios/Podfile`을 만들고 `pod install`을 해야 Xcode가 찾습니다 (Xcode에서 먼저 빌드하면 "Module 'flutter_tts' not found")
  1. `brew install cocoapods` → `flutter pub get` → `flutter build ios --simulator` (Podfile 생성 + pod install)
  2. `open ios/Runner.xcworkspace` → Runner > Signing & Capabilities에서 Team(내 Apple ID, 무료 개인 팀) 선택
  3. 폰 연결 후 `flutter run --dart-define=API_BASE_URL=...`. 폰에서 설정 > 일반 > VPN 및 기기 관리에서 개발자 앱 신뢰, 처음 연결 때 "로컬 네트워크" 허용
- 평문 `http://` 서버는 Android debug·profile 빌드와 iOS 로컬 네트워크에서만 됩니다. `--release` Android 빌드는 `https://` 서버 주소가 필요합니다 (ADR-022)
- 마이크 버튼을 처음 누르면 OS가 마이크(·iOS는 음성 인식) 권한을 묻습니다. 거부했다면 기기 설정 > 앱에서 허용

---

## Tech Stack

- Flutter SDK, `package:http`, `fetch_client` (웹만), `speech_to_text`·`flutter_tts` (음성), `shared_preferences` (기기 저장), `flutter_test`, `flutter_lints` (ARCHITECTURE.md §2.2)

---

## Agent Control

> 상위 규칙 참조: `/README.md` — Agent Control  
> 아래 규칙은 이 폴더에 추가 적용됩니다.

### 허용 (Allow)

- 화면 동작은 `test/fakes.dart`의 가짜 `ChatApi`·`FakeVoiceEngine`으로 위젯·단위 테스트

### 금지 (Prohibit)

- `lib/chat`·`lib/voice`에서 `material`·`widgets` import (`foundation`까지만), `lib/api`에서 `chat`·`ui`·Flutter import, `chat`·`api`에서 `voice` import, `plugin_voice_engine.dart` 밖에서 음성 패키지 import — `test/architecture_test.dart`가 검사
- 플러그인 객체를 생성자·전역에서 바로 만들기 (Flutter 바인딩 전이라 앱이 시작하지 못함 — 처음 쓸 때 만든다)
- 위젯에서 `HttpChatApi`를 직접 호출 (컨트롤러를 거침)
- 클라이언트에서 Claude API를 직접 호출하거나 키를 빌드에 넣기 (`--dart-define`으로 키 주입 금지)
- 상태 관리 패키지(Riverpod·Bloc·Provider), WebSocket 패키지 (ADR-010, ADR-002)
- 실제 서버·네트워크에 의존하는 테스트 (모바일 스트리밍 테스트는 테스트 안의 localhost 소켓만 씀)
- `android/app/src/main/AndroidManifest.xml`(release)에 `usesCleartextTraffic`, iOS `NSAllowsArbitraryLoads` 추가 (ADR-022 — `test/mobile/platform_config_test.dart`가 검사)

### 필수 (Required)

- 작업 완료 시 `/README.md` Progress Tracker 업데이트
- 이 폴더 내 구조 변경 시 위 DFD와 상위 DFD 동시 업데이트
- 새 패키지는 ARCHITECTURE.md §2.2 허용 목록에 있어야 함 (없으면 제안 먼저)
- 푸시 전 `flutter analyze`(경고 0)와 `flutter test` 통과
