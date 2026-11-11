# Agent State

> 이 파일은 에이전트가 **매 세션 시작 시 읽고, 작업 완료 후 갱신**합니다.  
> `BLUEPRINT.md`, `AGENT_BOOTSTRAP.md`는 읽지 않습니다.  
> 전체 진행 현황은 여기에 복사하지 않습니다 — 루트 `README.md` Progress Tracker가 유일한 원본입니다.

---

## 현재 집중 작업 (Current Focus)

> 지금 진행 중이거나 바로 이어받을 작업 **최대 3개**만 기록합니다.  
> 상태(✅🔄⏳❌)는 루트 Tracker에서 관리하므로 여기에는 적지 않습니다.  
> 작업이 끝나면 행을 지우고, 다음 작업은 루트 Next Roadmap에서 가져옵니다.

| 기능 ID | 작업 내용 | 담당 폴더 | 이어받을 지점 |
|---------|-----------|-----------|---------------|
| F-017 | 모바일 네이티브 앱 (Android·iOS) | `/app` | `android/`·`ios/`·권한·서버 주소(ADR-022)·자동 테스트·Android APK 빌드 완료. 남은 것: iOS 빌드(사용자 Mac, Xcode 서명), AC6 실제 폰 확인. Q-005는 사용자가 `shared_preferences` 선택 → 페르소나·서버 주소 기기 저장 구현(ADR-023). F-014 배포는 사용자 지시로 정지 |
| F-019~F-021 | 지시 두 층 · 대화 요약 · 장기 기억 · 켜면 바로 음성 대화 | `/app`, `/server` | 구현·자동 테스트 완료(PR #17). 남은 것: 실제 Claude 모드에서 기억이 이어지는지(F-019 AC8·F-020 AC5), 폰에서 켜면 바로 듣는지(F-021 AC4) — 사용자 |
| F-012, F-018 | 음성 대화 + 음성 전용 화면(S-003) | `/app`, `/server` | F-012 구현·자동 테스트 완료. F-018 음성 전용 화면을 MVP HTML 디자인대로 Flutter 구현(채팅 상단 바 버튼 → 바로 듣기, 글로 보기·끝내기). 남은 것: 둘 다 AC8 실제 마이크·폰 확인(사용자) → ✅ |

---

## 누적 사용자 요구사항 (Resolved Requirements)

> 사용자가 요청하고 이미 반영된 **구조적 결정**을 기록합니다.  
> 에이전트는 이 목록을 먼저 읽고 중복 작업을 방지합니다.  
> 기능 구현 자체는 Tracker가 기록하므로 여기에 적지 않습니다.  
> **20개 초과 시** → 오래된 항목을 `AGENT_STATE_ARCHIVE.md`로 이동.

| # | 요구사항 요약 | 반영 날짜 | 변경된 파일 |
|---|--------------|-----------|-------------|
| 1 | ~~현재 MVP는 외부 npm 패키지 없이 Node.js 22 기본 모듈만 사용 (ADR-001)~~ → F-013에서 Node 제거, ADR-001 대체됨 (2026-11-10) | 2026-11-02 | `SPEC.md`, `README.md`, `CLAUDE.md` |
| 2 | 화면 로직(`chat-controller.js`)과 DOM(`app.js`) 분리 — 화면 동작은 가짜 ui로 테스트 | 2026-11-02 | `public/*` |
| 3 | 기능 단위로 브랜치를 만들고 PR로 main에 합친다 (SPEC §13 GitHub Flow) | 2026-11-02 | — |
| 4 | 사용자 선호 언어(C/C++/Go/Flutter) 기준 목표 스택: 서버 Go, 클라이언트 Flutter (승인). C/C++ 미사용은 제안 상태. ADR은 ARCHITECTURE.md로 이동 | 2026-11-04 | `ARCHITECTURE.md`, `SPEC.md`, `README.md`, `CLAUDE.md` |
| 6 | 페르소나 지시는 두 층(탑재 페르소나 고정 기본 지시 + 사용자 요구 사항). 끝난 대화 세션은 요약해 기기에 페르소나별로 남기고 다음 대화에 최근 5개를 싣는다 (F-019, ADR-024). 대화 원문은 여전히 저장하지 않음 | 2026-11-11 | `SPEC.md`, `ARCHITECTURE.md`, `app/**`, `server/**` |
| 5 | 모바일 앱을 만든다 (SPEC §1.4 비목표 해제, F-017). AWS·Cloudflare 배포는 정지. 페르소나·내 프로필은 기기에 저장 (Q-005) | 2026-11-11 | `SPEC.md`, `ARCHITECTURE.md`, `app/**` |

---

## 핵심 규칙 스냅샷 (Active Rules)

> 전역 Agent Control에서 핵심 3~7개만 추출. 세부 규칙은 각 폴더 README.md 참조.  
> 규칙 변경 시 원본(루트 README.md Agent Control 또는 CLAUDE.md)을 먼저 고치고 이 목록을 맞춥니다.

**절대 금지:**
- ARCHITECTURE.md §2.2 허용 목록 밖의 의존성 추가 (Node MVP는 F-013에서 제거)
- 실제 Claude API를 부르는 테스트 (모의 제공자·가짜 업스트림만)
- 비밀값을 코드·로그·응답에 포함
- 대화 메시지 본문을 서버 로그에 기록

**반드시 할 것:**
- 기능 작업 전 SPEC.md 해당 기능 ID의 수용 기준 확인
- 작업 완료마다 루트 README.md Progress Tracker 업데이트
- 구조 변경 시 해당 레벨부터 루트까지 DFD 연쇄 업데이트

---

## DFD 드리프트 상태 (Drift Status)

> 에이전트는 구조적 변경 후 이 섹션을 업데이트합니다.  
> `⚠️ 드리프트 의심` 표시된 DFD는 다음 작업 전 검증 필요.

| 폴더 | DFD 레벨 | 마지막 검증일 | 상태 |
|------|----------|--------------|------|
| `/` | Level 0 | 2026-11-02 | ✅ 최신 |
| `/src/server` | Level 1 | 2026-11-02 | ✅ 최신 |
| `/src/agent` | Level 1 | 2026-11-02 | ✅ 최신 |
| `/public` | Level 1 | 2026-11-02 | ✅ 최신 |

---

## 세션 로그 (Session Log)

> 에이전트는 작업 완료 후 이 테이블에 행을 추가합니다.  
> **최근 10개 세션만 유지** — 초과 시 가장 오래된 행부터 삭제.  
> "다음 세션 인계 사항"에는 미완료 사항이나 주의점만 기재합니다.

| 날짜 | 기능 ID | 수행 작업 | 변경 파일 | 다음 세션 인계 사항 |
|------|---------|-----------|-----------|---------------------|
| 2026-11-10 | F-004, F-008 | MVP HTML 디자인(Design 캔버스, 7화면) 작성 → 사용자가 "순서대로, 판단은 맡김". ADR-016 승인 반영, F-004 다시 시도(Flutter) 완료, F-008 Google 로그인 SPEC·ADR-017 제안 | `SPEC.md`, `ARCHITECTURE.md`, `app/lib/chat/chat_controller.dart`, `app/lib/ui/chat_page.dart`, 테스트 | 디자인은 claude.ai 비공개 Artifact. 네이티브 앱의 기준 화면으로 씀 |
| 2026-11-10 | F-013, F-008 | 사용자가 Google 로그인 보류(Phase 3) 선택 → §10 단계 4 진행. `src/`·`public/`·`tests/`·`scripts/`·`package.json` 삭제, 계약 테스트가 모의 모드 `chatd`를 직접 띄우게 바꿈(`go test ./...`에 포함), CI Node 작업 제거, 문서 갱신 | `server/contract/*`, `.github/workflows/ci.yml`, `README.md`, `CLAUDE.md`, `SPEC.md` v1.8, `ARCHITECTURE.md` v1.7, `server/README.md` | ADR-001 대체됨, ADR-017 보류, TD-001~003 해소 |
| 2026-11-10 | - | AWS·Cloudflare 배포·음성 설계안(Claude 문서) 작성, ADR-018~021 제안, SPEC Q-003 방향·Q-007 추가 | `ARCHITECTURE.md`, `SPEC.md`, `README.md`, `CLAUDE.md`, `Dockerfile`, `deploy/*`, `.github/workflows/*` | 사용자 "추천안 전체" 선택 → ADR-018~021 승인, F-014~016 등록, F-014 배포 파일 작성. Current Focus에 F-014 추가, 'MVP HTML 디자인 반영'은 Roadmap 5번으로만 남김 |
| 2026-11-11 | F-017 | 사용자 "배포 정지, 모바일 앱 진행". SPEC §1.4 비목표 해제·F-017 등록, `flutter create --platforms=android,ios`, 매니페스트·Info.plist 권한, 플랫폼별 서버 주소, iOS 오디오 세션, 앱용 음성 안내, Q-005 `shared_preferences` 저장·앱 안 서버 주소(ADR-023), 테스트(서버 주소·dart:io 스트리밍·설정 파일·저장), CI `android` 작업 | `app/**`, `SPEC.md` v1.10, `ARCHITECTURE.md` v1.9, `README.md`, `.github/workflows/ci.yml` | 클라우드 환경에 `dl.google.com` 허용 추가(Android SDK). iOS는 이 컨테이너에서 빌드 불가 — 사용자 Mac |
| 2026-11-11 | F-005 | 사용자 "노인복지사 페르소나를 설정하자" → 기본 페르소나 4번째 `노인복지사 미소`(존댓말·천천히·쉽게·공감 먼저, 의료·응급 119·복지 129·자살예방 109·사기 경계 지시) 추가. 예전에 저장한 기기에도 빠진 기본 페르소나를 뒤에 붙이도록 `restore` 수정 | `app/lib/chat/persona_controller.dart`, `app/test/**`, `SPEC.md`, `README.md`, `app/README.md` | 이 세션은 Flutter 실행이 막혀 CI로 `flutter analyze`·`test` 확인. 실제 Claude 모드에서 어르신 말투 확인(AC8) 남음 |
| 2026-11-11 | F-018 | 사용자 "음성 전용 화면 만들자" → SPEC F-018·S-003 등록, `ui/voice_page.dart`(상태 원·자막·단계 칩·글로 보기·듣기/멈춤/끼어들기·끝내기), 채팅 상단 바 버튼, `VoiceController.sentence`(지금 읽는 문장). 위젯·단위 테스트 9개 추가(`flutter test` 119개), 모의 모드 웹 빌드 + 가짜 음성 API로 캡처 | `app/lib/ui/voice_page.dart`, `app/lib/ui/chat_page.dart`, `app/lib/voice/voice_controller.dart`, `app/test/**`, `SPEC.md` v1.12, `README.md`, `app/README.md` | 컨테이너 Flutter는 storage.googleapis.com에서 받아 씀. 실제 폰에서 화면 꺼짐 방지(wakelock)는 새 패키지라 안 넣음 — 필요하면 제안 |
| 2026-11-11 | F-018 | 사용자 "노인들은 토글·버튼·라디오식 UI가 불편, GPT 앱 같은 상시 대화" → 음성 화면 개정: 모드 버튼 제거(화면 누르기 = 끼어들기, 듣는 중 누르기는 무시), 큰 "대화 끝내기" 하나, 큰 글씨, 인식 끊김 자동 복구(최대 3번, `VoiceController.retryDelay`), 쉼 2초(`pauseFor`). SPEC v1.13 | `app/lib/ui/voice_page.dart`, `app/lib/voice/*`, `app/test/**`, `SPEC.md`, `docs/ALPHA_TEST_LOCAL.md` | 앱을 켜면 바로 음성 대화로 시작할지 사용자 결정 대기. 화면 꺼짐 방지(wakelock)는 새 패키지라 제안만 |
| 2026-11-11 | F-018 | 사용자 "해당 모드에서는 상시로 마이크를 듣는 것이 목표" → 끊김 무한 재시도(1~16초 백오프, 권한 거부만 멈춤), 화면 꺼짐 막기(웹 Wake Lock·Android `FLAG_KEEP_SCREEN_ON`·iOS `isIdleTimerDisabled`, 채널 `ai_agent_chat/screen`, 새 패키지 없음), 앱 뒤로/복귀 `pause`·`resume`. SPEC v1.14 | `app/lib/ui/keep_awake*.dart`, `app/lib/ui/*_page.dart`, `app/lib/voice/voice_controller.dart`, `android/.../MainActivity.kt`, `ios/Runner/AppDelegate.swift`, 테스트, 문서 | iOS `AppDelegate.swift` 채널 코드는 이 컨테이너에서 빌드 못 함 — 사용자 Mac에서 확인. 앱 시작을 음성 대화로 할지 결정 카드 대기 |
| 2026-11-11 | F-019 | 사용자 "추가 지시를 기본(탑재)·사용자 요구로 나누고, 대화 세션 요약을 다음 세션 기반으로" → SPEC F-019·API-003, ADR-024(적용). 서버 `persona.base`·`memory` 검증·프롬프트, `/api/summary`(모의 제공자는 요약 JSON). 앱 `Persona.base`(탑재 고정, 예전 저장 값 이관), `MemoryController`(`memory.v1`), `ChatController.endSession`(새 대화·페르소나 바꾸기·대화 끝내기·앱 뒤로), 편집 화면 기본 지시(자물쇠)·내 요구 사항·지난 대화 기억 | `server/internal/chat/*`, `server/internal/httpapi/*`, `server/internal/provider/mock/*`, `server/contract/*`, `app/lib/**`, `app/test/**`, 문서 | 이 컨테이너는 Flutter 3.47.9를 storage.googleapis.com에서 받아 씀(root라 `git config safe.directory` 필요). Playwright로 한국어 입력 후 Enter는 IME 때문에 안 먹음 — 전송 버튼을 누를 것. AC8 실제 Claude 확인 남음 |
| 2026-11-11 | F-020, F-021 | 사용자 "추천대로 진행"(다음 계획 1→2→3). F-020 장기 기억: API-004 `/api/consolidate`, API-001 `longTerm`, `MemoryController.pendingFold`·`setLongTerm`, 편집 화면 카드. F-021: `StartSettings`(`start.voice`), 서랍 스위치, 켜 두면 첫 프레임 뒤 음성 화면 열기. 3번: Android profile APK(arm64) 클라우드 빌드 | `server/internal/chat/consolidate.go`, `httpapi`, `mock`, `contract`, `app/lib/**`, `app/test/**`, 문서 | Android SDK는 dl.google.com에서 cmdline-tools를 받아 `/home/user/android-sdk`에 설치. profile 빌드라 같은 Wi-Fi의 http `chatd`로 접속 가능(ADR-022) |

---

## 압축 기준 (Compaction Rules)

> 이 파일이 비대해지면 토큰 효율이 떨어집니다. 아래 기준으로 관리합니다.

| 섹션 | 압축 트리거 | 처리 방법 |
|------|-------------|-----------|
| Current Focus | 3행 초과 | 우선순위 낮은 항목 삭제 (루트 Roadmap에는 남아 있음) |
| 누적 사용자 요구사항 | 20행 초과 | 오래된 항목을 `AGENT_STATE_ARCHIVE.md`로 이동 |
| 세션 로그 | 10행 초과 | 가장 오래된 행 삭제 |
| Active Rules | 7개 초과 | 덜 중요한 규칙 삭제 (각 폴더 README에 상세 유지) |
