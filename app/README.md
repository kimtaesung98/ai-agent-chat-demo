# app — Overview

> **담당 기능**: `SPEC.md`의 `F-011` (Flutter 웹 클라이언트), `F-003` (응답 중단 — 화면), F-001 · F-002의 화면 부분  
> (진행 상태는 `/README.md` Progress Tracker에서 관리)

이 폴더는 **Flutter로 만든 채팅 화면(S-001)** 을 담당합니다. 웹 빌드는 Go 서버가 같은 출처로 제공합니다 (ARCHITECTURE.md ADR-011).  
상태는 `ChatController`(`ChangeNotifier`)가 갖고, 위젯은 그리기와 입력 연결만 합니다 (ADR-010).

---

## Context — 상위 흐름과의 연결

```
루트(/) — Level 0 DFD
└─ [AI Agent Chat] 버블 중 "방문자에게 보이는" 부분 (Flutter 구현)
       │  입력: 방문자의 키보드 입력, 서버의 SSE 스트림, /api/config
       ▼
app — Level 1 DFD (아래 상세)
       │  출력: POST /api/chat 요청 (대화 내역), 요청 중단, 화면 갱신
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
```

| 파일 | 역할 |
|---|---|
| `lib/main.dart` | 앱 조립: `HttpChatApi` → `ChatController` → `ChatApp` (`API_BASE_URL`은 빌드 때 주입, 웹은 비움) |
| `lib/api/models.dart` | `Message`, `ChatEvent`(`ChatDelta`·`ChatDone`·`ChatFailed`), `ServerConfig` |
| `lib/api/sse.dart` | SSE 파서 (바이트 → 이벤트) |
| `lib/api/chat_api.dart` | `ChatApi` 인터페이스, `HttpChatApi` (구독 취소 시 요청 중단) |
| `lib/api/client_factory*.dart` | 웹은 `fetch_client`, 그 밖은 `package:http` (조건부 import, ADR-009) |
| `lib/chat/chat_controller.dart` | 말풍선 목록·바쁨·중단·새 대화·대화 내역 (위젯 없음, 테스트 대상) |
| `lib/ui/chat_page.dart` | S-001 화면 (헤더 · 모드 배지 · 새 대화 · 대화 영역 · 입력창 · 전송/중단) |
| `lib/ui/theme.dart` | 라이트·다크 색 (`public/styles.css`와 같은 값) |

**실행** (`app/`에서)
- 테스트: `flutter test` · 분석: `flutter analyze`
- 웹 빌드: `flutter build web --no-web-resources-cdn`
- 서버로 보기: `cd ../server && STATIC_DIR=../app/build/web go run ./cmd/chatd` → http://localhost:3000

---

## Tech Stack

- Flutter SDK, `package:http`, `fetch_client` (웹만), `flutter_test`, `flutter_lints` (ARCHITECTURE.md §2.2)

---

## Agent Control

> 상위 규칙 참조: `/README.md` — Agent Control  
> 아래 규칙은 이 폴더에 추가 적용됩니다.

### 허용 (Allow)

- 화면 동작은 `test/fakes.dart`의 가짜 `ChatApi`로 위젯·단위 테스트

### 금지 (Prohibit)

- `lib/chat`에서 `material`·`widgets` import (`foundation`까지만), `lib/api`에서 `chat`·`ui`·Flutter import — `test/architecture_test.dart`가 검사
- 위젯에서 `HttpChatApi`를 직접 호출 (컨트롤러를 거침)
- 클라이언트에서 Claude API를 직접 호출하거나 키를 빌드에 넣기 (`--dart-define`으로 키 주입 금지)
- 상태 관리 패키지(Riverpod·Bloc·Provider), WebSocket 패키지 (ADR-010, ADR-002)
- 실제 서버·네트워크에 의존하는 테스트

### 필수 (Required)

- 작업 완료 시 `/README.md` Progress Tracker 업데이트
- 이 폴더 내 구조 변경 시 위 DFD와 상위 DFD 동시 업데이트
- 새 패키지는 ARCHITECTURE.md §2.2 허용 목록에 있어야 함 (없으면 제안 먼저)
- 푸시 전 `flutter analyze`(경고 0)와 `flutter test` 통과
