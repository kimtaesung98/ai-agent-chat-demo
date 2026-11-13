# app — Overview

> **담당 기능**: `SPEC.md`의 `F-011` (Flutter 웹 클라이언트), `F-025` (웹앱 PWA), `F-003` (응답 중단 — 화면), `F-024` (실시간 음성 — 웹 쪽), `F-018` (음성 전용 화면), `F-005` (페르소나 — 화면·상태), F-001 · F-002의 화면 부분  
> (진행 상태는 `/README.md` Progress Tracker에서 관리)

이 폴더는 **Flutter로 만든 채팅 화면(S-001)** 을 담당합니다. 웹 빌드는 Go 서버가 같은 출처로 제공합니다 (ARCHITECTURE.md ADR-011).  
같은 웹 빌드를 폰 홈 화면에 설치하는 PWA로 냅니다 (F-025, ADR-027) — 네이티브 Android·iOS 빌드는 없습니다.  
상태는 `ChatController`(`ChangeNotifier`)가 갖고, 위젯은 그리기와 입력 연결만 합니다 (ADR-010).  
음성 대화는 `AgentVoiceController`가 서버(API-007)에서 임시 키를 받아 브라우저가 OpenAI Realtime과 WebRTC로 직접 합니다 (F-024, ADR-026). 안 되면 한 번 알리고 글 채팅으로 계속합니다.

---

## Context — 상위 흐름과의 연결

```
루트(/) — Level 0 DFD
└─ [AI Agent Chat] 버블 중 "방문자에게 보이는" 부분 (Flutter 구현)
       │  입력: 방문자의 키보드 입력·목소리, 서버의 SSE 스트림, /api/config, 임시 키(API-007), OpenAI Realtime 소리·전사
       ▼
app — Level 1 DFD (아래 상세)
       │  출력: POST /api/chat · /api/voice/session 요청, 요청 중단, 화면 갱신, 마이크 소리(WebRTC)
       ▼
server (Go), OpenAI Realtime, 방문자
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
    User -->|"Google로 시작 · 이름 · 대화 상대 고르기"| Shell[ui/app_shell.dart<br>S-004 로그인 · S-005 첫 실행]
    Shell -->|"signInWithGoogle(모의) · continueAsGuest · completeOnboarding"| Auth[chat/auth_controller.dart<br>ChangeNotifier]
    Auth -->|"로그인 · 첫 실행 상태"| Shell
    Shell -->|"로그인·첫 실행 뒤"| UI
    UI -->|"서랍 → 설정 (S-006 · S-007)"| Auth
    UI -->|"마이크 버튼 · 음성 대화 화면 열기 · 글자로 보기 · 대화 끝내기"| VoicePage[ui/voice_page.dart<br>S-003]
    VoicePage -->|"start · tap(화면 누르기) · stop"| Agent[voice/agent_voice_controller.dart<br>ChangeNotifier]
    UI -->|"마이크 버튼 · 앱 뒤로 · 돌아옴 (pause · resume)"| Agent
    Agent -->|"voiceContext: persona·memory·longTerm·history"| Ctrl
    Agent -->|"POST /api/voice/session (API-007)"| Server
    Server -->|"임시 키 ek_…"| Agent
    Agent -->|"임시 키 · 처음 연결인지"| RT[voice/openai_realtime.dart<br>+ openai_realtime_agent.dart · web/realtime.js]
    User <-->|"목소리 ↔ 답 소리 (WebRTC, 에코 제거)"| OAI[[OpenAI Realtime]]
    RT <-->|"SDP · oai-events 데이터 채널"| OAI
    RT -->|"연결 · 말하는 중 · 들은 말 · 답 · 소리 크기"| Agent
    Agent -->|"addVoiceTurn"| Ctrl
    Agent -->|"상태 · 미리 보기 · 자막 · 안내 · 파형"| VoicePage
    VoicePage -->|"큰 상태 원 · 자막"| User
    VoicePage -->|"화면 꺼짐 막기 켜기·끄기"| Awake[ui/keep_awake.dart<br>Screen Wake Lock]
    UI -->|"홈 화면 추가 안내"| Inst[ui/install_hint.dart · installer_web.dart<br>web/pwa.js · sw.js]
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
```

| 파일 | 역할 |
|---|---|
| `lib/main.dart` | 앱 조립: `HttpChatApi`(같은 출처, 개발 때만 `API_BASE_URL`) → `ChatController` → `AgentVoiceController`(`createRealtimeAgent()`) → `ChatApp` |
| `lib/api/models.dart` | `Message`, `ChatEvent`(`ChatDelta`·`ChatDone`·`ChatFailed`), `ServerConfig`, `Persona`·`PersonaRequest`(API-001 `persona`) |
| `lib/api/sse.dart` | SSE 파서 (바이트 → 이벤트) |
| `lib/api/chat_api.dart` | `ChatApi` 인터페이스, `HttpChatApi` (구독 취소 시 요청 중단) |
| `lib/api/client_factory*.dart` | 웹은 `fetch_client`, 그 밖은 `package:http` (조건부 import, ADR-009) |
| `lib/chat/chat_controller.dart` | 말풍선 목록·바쁨·중단·새 대화·대화 내역, 요청에 선택한 페르소나와 지난 대화 기억 싣기, 대화 세션 끝에 요약(`endSession`, F-019) (위젯 없음, 테스트 대상) |
| `lib/chat/persona_controller.dart` | 페르소나 목록(기본 4개, 노인복지사 포함)·선택·저장·내 프로필, 저장용 `snapshot`·`restore` (F-005, Q-005). 탑재 페르소나의 기본 지시(`base`)는 고정 (F-019) |
| `lib/chat/start_settings.dart` | 앱 시작 설정: 켜면 바로 음성 대화 (F-021) |
| `lib/chat/memory_controller.dart` | 지난 대화 기억: 세션 요약을 페르소나별로 모으고(20개), 다음 요청용 최근 5개, 지우기, `snapshot`·`restore` (F-019) |
| `lib/storage/app_storage.dart` | `KeyValueStore`·`MemoryStore`, 페르소나·기억·시작 방식·로그인(`auth.v1`)·글자 크기 불러오기와 바뀔 때 저장 (Q-005, ADR-023, F-023) |
| `lib/storage/prefs_store.dart` | `shared_preferences` 구현 — 패키지는 이 파일에서만 import |
| `lib/voice/voice_session.dart` | 화면이 보는 음성 대화 모양: `VoiceState`(off·listening·thinking·speaking), `VoiceSession` 인터페이스 |
| `lib/voice/agent_voice_controller.dart` | 실시간 음성 진행 (F-024): 설정 확인 → 임시 키 → 연결, 들은 말·답을 대화 내역에, 끊기면 1~16초 간격 다시 연결(내역 이어 넘김), 연결 3번 실패·임시 키 실패·설정 없음·브라우저 미지원·마이크 거부는 한 번 알리고 끔, `pause`·`resume`은 마이크만 (위젯 없음, 가짜 에이전트로 테스트) |
| `lib/voice/realtime_agent.dart` | `RealtimeAgent` 인터페이스와 사건(`AgentConnected`·`AgentHeard`·`AgentReply`·`AgentFailed` …) |
| `lib/voice/openai_realtime.dart` | `web/realtime.js` 사건 → `AgentEvent` (가짜 다리로 테스트). `openai_realtime_agent.dart`는 `dart:js_interop` 다리 (웹 전용) |
| `lib/voice/realtime_agent_factory.dart` | 웹은 OpenAI Realtime, 그 밖(테스트 VM)은 없음 (`realtime_agent_none.dart`) |
| `web/realtime.js` | 브라우저 WebRTC: 마이크(에코 제거·잡음 억제), 임시 키로 SDP 교환, `oai-events` 사건 정리, 소리 크기 |
| `web/manifest.json` · `sw.js` · `pwa.js` · `flutter_bootstrap.js` | PWA (F-025): 매니페스트, 화면 파일만 네트워크 먼저 캐시하는 서비스 워커(`/api` 제외), 설치 안내·Wake Lock, Flutter 기본 서비스 워커 끄기 |
| `lib/ui/chat_page.dart` | S-001 화면 (페르소나 사이드바·서랍 · 상단 페르소나 · 모드 배지 · 편집 · 새 대화 · 대화 영역 · 음성 상태 · 입력창 · 마이크 · 전송/중단) |
| `lib/ui/voice_page.dart` | S-003 음성 대화 화면 (F-018, 어르신용 상시 대화): 상태 원 · 큰 상태 문구 · 큰 자막(인식 중 · 보낸 말 · 읽는 문장) · 안내. 모드 버튼 없음 — 끼어들기는 말로, 꺼져 있을 때 화면 누르기 = 다시 연결(`tap`), 글자로 보기 · 대화 끝내기만. 채팅 화면 상단 바 버튼으로 열면 듣기 시작 |
| `lib/ui/keep_awake*.dart` | 음성 대화 화면 동안 화면 꺼짐 막기 (F-018 AC8): 웹 Screen Wake Lock API(`dart:js_interop`), 테스트 VM은 아무것도 안 함. 새 패키지 없음 |
| `lib/ui/install_hint.dart` · `installer*.dart` | 홈 화면 추가 안내 (F-025 AC3): Android Chrome 설치 버튼, iPhone Safari 공유 → 홈 화면에 추가 |
| `lib/ui/persona_widgets.dart` | 페르소나 아바타 · 사이드바 · 내 프로필 대화상자 (900px 미만은 서랍) |
| `lib/ui/persona_editor.dart` | S-002 페르소나 편집 화면 (이름 · 역할 칩 · 말투 칩 최대 6개 · 추가 지시) |
| `lib/chat/auth_controller.dart` | 로그인 상태·첫 실행 여부 (F-023). `GoogleSignIn` 인터페이스 — 지금은 `MockGoogleSignIn`, 진짜는 F-008. 이름만 적고 시작 |
| `lib/chat/display_settings.dart` | 글자 크기 보통·크게·아주 크게 (F-023, `MaterialApp.builder`가 앱 전체에 곱함) |
| `lib/ui/app_shell.dart` | 첫 화면 고르기: 로그인 전 S-004 · 첫 실행 S-005 · 그 뒤 S-001 (F-023) |
| `lib/ui/login_page.dart` | S-004 로그인 (큰 버튼 두 개 · 이름 적기 · 모의 안내) |
| `lib/ui/onboarding_page.dart` | S-005 첫 실행 대화 상대 고르기 (큰 카드 · 미소 추천 · 말로/글자로 시작) |
| `lib/ui/settings_page.dart` | S-006 설정 (계정·로그아웃 확인 · 내 프로필 · 시작 방식 · 기억 · 글자 크기 · 앱 정보) |
| `lib/ui/memory_page.dart` | S-007 지난 대화 기억 (페르소나 칩 + 편집 화면과 같은 `MemoryList`) |
| `lib/ui/big_button.dart` | 어르신용 큰 버튼 (높이 64 · 글자 20) |
| `lib/ui/theme.dart` | 라이트·다크 색 (MVP HTML 디자인과 같은 값) |

**실행** (`app/`에서)
- 테스트: `flutter test` · 분석: `flutter analyze`
- 웹 빌드: `flutter build web --no-web-resources-cdn`
- 서버로 보기: `cd ../server && STATIC_DIR=../app/build/web go run ./cmd/chatd` → http://localhost:3000

**폰에서 보기** (F-025 — 마이크는 HTTPS 또는 `localhost`에서만 됨)
- 실시간 음성: 서버에 `OPENAI_API_KEY`를 넣고 띄움 (`docs/OPENAI_REALTIME_SETUP.md`). 없으면 음성 버튼은 안내만 하고 글 채팅은 그대로
- 터널 HTTPS 주소로 열고, iPhone Safari는 공유 → 홈 화면에 추가, Android Chrome은 화면의 설치 버튼
- 마이크 권한을 거부했다면 브라우저(또는 홈 화면 앱) 설정에서 이 사이트의 마이크를 허용

---

## Tech Stack

- Flutter SDK, `package:http`, `fetch_client` (웹만), `shared_preferences` (기기 저장), `flutter_test`, `flutter_lints` (ARCHITECTURE.md §2.2)

---

## Agent Control

> 상위 규칙 참조: `/README.md` — Agent Control  
> 아래 규칙은 이 폴더에 추가 적용됩니다.

### 허용 (Allow)

- 화면 동작은 `test/fakes.dart`의 가짜 `ChatApi`·`FakeAgent`(`fakeRealtimeVoice`)로 위젯·단위 테스트

### 금지 (Prohibit)

- `lib/chat`·`lib/voice`에서 `material`·`widgets` import (`foundation`까지만), `lib/api`에서 `chat`·`ui`·Flutter import, `chat`·`api`에서 `voice` import, 웹 전용 파일 밖에서 `dart:js_interop`, 앱 코드에 OpenAI 키·주소·지시문 틀, 기기 음성·ElevenLabs 패키지·네이티브 채널 — `test/architecture_test.dart`가 검사
- 플러그인 객체를 생성자·전역에서 바로 만들기 (Flutter 바인딩 전이라 앱이 시작하지 못함 — 처음 쓸 때 만든다)
- 위젯에서 `HttpChatApi`를 직접 호출 (컨트롤러를 거침)
- 클라이언트에서 Claude API를 직접 호출하거나 키를 빌드에 넣기 (`--dart-define`으로 키 주입 금지)
- 상태 관리 패키지(Riverpod·Bloc·Provider), WebSocket 패키지 (ADR-010, ADR-002)
- 실제 서버·네트워크·OpenAI에 의존하는 테스트 (`dart:io` 스트리밍 테스트는 테스트 안의 localhost 소켓만 씀)
- 네이티브 `android/`·`ios/` 다시 만들기 (ADR-027 — 바꾸려면 ADR 제안 먼저)

### 필수 (Required)

- 작업 완료 시 `/README.md` Progress Tracker 업데이트
- 이 폴더 내 구조 변경 시 위 DFD와 상위 DFD 동시 업데이트
- 새 패키지는 ARCHITECTURE.md §2.2 허용 목록에 있어야 함 (없으면 제안 먼저)
- 푸시 전 `flutter analyze`(경고 0)와 `flutter test` 통과
