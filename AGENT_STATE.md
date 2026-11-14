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
| F-024·F-025 | OpenAI Realtime 실시간 음성 + Flutter 웹 PWA (F-022·F-017·F-012 대체) | `/app`, `/server` | 6-①~④ 끝(6-④ 정리: ElevenLabs·기기 음성·`android/`·`ios/`·앱 서버 주소 설정 제거, 실패하면 알리고 글 채팅). 남은 것: 터널 HTTPS로 iPhone·Android 홈 화면 설치·실시간 음성 확인(F-024 AC7·F-025 AC6, 사용자). Q-008 대기 |
| F-026~F-031 | 서비스화(노치원 먼저) | `/server`, `/app` | 7-②·7-③·7-④ 서버 완료(계정·로그인·역할·사용량·관리 API, `chatd admin bootstrap`, 프리셋 카탈로그·`/api/personas`). 7-④ 서버도 완료(`/api/conversations`·`/end`, `conversationId`, 기억 API). 다음: 7-⑤ 앱(로그인 화면·서버 페르소나·기기 원문 IndexedDB·`/end` 연결), 프로필 API-013, 어르신 페르소나 기본 설정·`learned`(F-031, 노치원 기획서 대기). 7-⑤ 앱 로그인 화면이 나오면 `REQUIRE_LOGIN` 기본을 on으로. 다른 스레드가 ElevenLabs·기기 음성·네이티브 코드를 지우는 중 — `voiceagent.go`·`internal/elevenlabs`·앱 `voice/` 건드리지 않기 |

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
| 7 | ~~앱 음성 대화는 ElevenLabs Agents 실시간 음성, Claude는 우리 chatd를 Custom LLM(`/v1/chat/completions`, Bearer)으로 — 키는 서버에만, 앱은 토큰만. 안 되면 기기 음성 (F-022, ADR-025)~~ → #8로 대체, 코드 제거 (2026-11-13) | 2026-11-12 | `SPEC.md`, `ARCHITECTURE.md`, `server/**`, `app/**`, `docs/ELEVENLABS_SETUP.md` |
| 10 | 대화 원문은 폰에 계속 보관하고 서버엔 두지 않는다. 어르신 페르소나는 요양사·보호자의 기초 통합 설정 + 대화로 강화되는 알고리즘. 배포 유형은 노치원 먼저, 요양원·자택 홀로는 나중 (F-031, ADR-034·035) | 2026-11-13 | `SPEC.md`, `ARCHITECTURE.md` |
| 9 | 서비스 계정은 위에서 만든다: 관리자 발급 로그인 코드 또는 연결된 Google 로그인(이름만 가입 없음), 역할 계층 최고 관리자(개발자·원장) > 요양사 > 어르신·보호자, 게스트는 기본 꺼짐·엄격한 사용량 상한 (F-026·F-029·F-030, ADR-029·032·033) | 2026-11-13 | `SPEC.md`, `ARCHITECTURE.md` |
| 8 | 개발 방향 전향: 실시간 음성은 OpenAI GPT Realtime(브라우저 WebRTC 직접, 서버는 지시문 담은 임시 키만), 앱은 Flutter 웹 PWA(네이티브·ElevenLabs·기기 음성·앱 서버 주소 설정 제거 완료 — 6-④). 실시간 음성이 안 되면 한 번 알리고 글 채팅. 페르소나·기억·화면 개념은 유지 (F-024·F-025, ADR-026·027 적용) | 2026-11-13 | `SPEC.md`, `ARCHITECTURE.md`, `README.md` |
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
| 2026-11-13 | F-024 | PR #27 머지 → 단계 6-①: 서버 `chat.ParseVoiceSession`·`Instructions`(페르소나→기억→음성 말투→내역), `internal/openai`(client_secrets, 표준 라이브러리), API-007, API-002 `voiceAgent: openai`, 가짜 OpenAI 계약 테스트. 앱 `web/realtime.js`(WebRTC·oai-events·전사·파형), `OpenAiRealtimeAgent`(+`RealtimeBridge` 가짜로 테스트), `RealtimeAgent.kind`·`level`, `ChatApi.voiceSession` | `server/**`, `app/lib/voice/*`, `app/web/*`, `app/test/**`, `docs/OPENAI_REALTIME_SETUP.md`, 문서 | 실제 OpenAI WebRTC는 이 컨테이너에서 못 붙임(가짜 OpenAI로 SDP 요청까지 브라우저 확인). 이벤트 이름은 GA 기준 + 베타 이름 같이 받음 — 실제 연결에서 자막 확인 필요. Flutter는 storage.googleapis.com에서 3.47.9 받음 |
| 2026-11-13 | F-025 | 사용자 "웹 테스트에서 원하는 수준의 상호작용" → "좋아 부탁해"(PWA 마무리). 매니페스트·새 아이콘(PIL로 그림)·index.html, `web/sw.js`(네트워크 먼저, /api 제외), `web/flutter_bootstrap.js`(Flutter 기본 SW 끔 — 스스로 등록을 지우고 새로 고침하기 때문), `web/pwa.js`(beforeinstallprompt·standalone·iOS 판별·Wake Lock 지원), `InstallBanner`, VoicePage Wake Lock 미지원 안내 | `app/web/*`, `app/lib/ui/*`, `app/lib/main.dart`, `app/test/**`, 문서 | 사용자가 실제 키로 웹 실시간 음성 확인(Mac/폰 어느 쪽인지 답 대기). Playwright 헤드리스는 beforeinstallprompt가 안 와서 가짜 이벤트로 확인. 스크린샷 `/mnt/project-files/screenshots/pwa/` |
| 2026-11-13 | F-026~F-028 | 사용자 "개개인의 사용을 위한 서비스 수준 내부 데이터 백엔드 + 백엔드에 맞물리는 프론트 페르소나 형식" → 설계 제안만(코드 없음): 계정(게스트+서버 세션 쿠키), SQLite(순수 Go), 페르소나 v1(`schema`·`kind`·`presetId`·`instructions`·`revision`, 프리셋 `base`는 서버), 대화·요약·기억 서버 처리, 기기 데이터 한 번 옮기기 | `SPEC.md`, `ARCHITECTURE.md`, `README.md` | Q-009(원문 저장)·Q-010(게스트 먼저) 사용자 결정 대기. 승인 전 큰 코드 금지 |
| 2026-11-13 | F-026~F-030 | 사용자 "로그인은 관리자 발송 코드 또는 Google, DB 라이브러리 추가, 역할 계층(최고 관리자·요양사·어르신·보호자, 상위→하위 추가·권한), 게스트는 토큰 누수 없게" → 문서 개정: 이름만 계정 없앰, F-029·F-030, ADR-029 개정·032·033, ADR-028 승인 | `SPEC.md`, `ARCHITECTURE.md`, `README.md` | Q-009(원문 30일)·Q-011(보는 범위)·Q-012(코드 전달) 추천안으로 진행 중 |
| 2026-11-13 | F-026, F-029, F-031 | 7-② 첫 코드: `internal/store`(인터페이스·역할), `store/sqlite`(modernc v1.59.0 — v1.60은 go 1.26 요구라 피함, 마이그레이션 embed, 연결 1개), `account`(코드 10자리·해시, 세션, Google JWKS, 역할 계층 Can·범위·감사). archtest에 새 패키지·SQLite 드라이버 규칙. 사용자 방향 반영: 원문 기기 보관, F-031 어르신 페르소나, ADR-034·035 | `server/internal/{store,account}/**`, `SPEC.md`, `ARCHITECTURE.md` | HTTP 연결 전이라 앱 동작은 그대로. 노치원 기획서(Q-014) 기다림 |
| 2026-11-13 | F-026, F-029, F-030 | 사용자 "남은 일 마무리, 다음 진행" → 7-② 완료: `internal/usage`, `config.LoadAccounts`, httpapi `auth.go`(withAccounts 미들웨어 — httpapi.go는 두 줄만 바꿈), `cmd/chatd/accounts.go`(조립·청소·`admin bootstrap`), 계약 테스트 `accounts_test.go`(X-Test-IP로 IP 분리) | `server/**`, `SPEC.md`, `ARCHITECTURE.md`, `README.md` | `REQUIRE_LOGIN` 기본 off(지금 앱이 로그인 없이 쓰므로). Q-011·Q-012 추천안 |
| 2026-11-13 | F-024, F-025 | 사용자 "남은일을 마무리 짓자, 코드를 걷어내고 다음 진행"(6-④). 서버: `internal/elevenlabs`·API-005·006·`chat/completion.go`·`ELEVENLABS_*` 제거, 배포 스크립트는 SSM `/chatd/openai-api-key`. 앱: `elevenlabs_agents`·`speech_to_text`·`flutter_tts`·`VoiceController`·에코 거르기·`android/`·`ios/`·네이티브 화면 꺼짐 채널·서버 주소 설정 제거, `voice_session.dart` 신설, `AgentVoiceController`는 실패하면 알리고 끔. CI `android` 작업 제거. `go test ./...`·`flutter analyze`·`flutter test` 168개·웹 빌드 통과 | `server/**`, `app/**`, `deploy/*`, `.github/workflows/ci.yml`, `SPEC.md` v1.28, `ARCHITECTURE.md` v1.17, `README.md`, `app/README.md`, `server/README.md`, `deploy/README.md` | 폰 확인(F-024 AC7·F-025 AC6) 남음. `docs/ELEVENLABS_SETUP.md` 지움 — SSM에 ElevenLabs 값이 남아 있으면 사용자가 지워도 됨 |
| 2026-11-13 | F-027 | 단계 7-③ 서버: `chat/presets.go`(탑재 4개, 노치원 추천 미소)·`chat/persona_v1.go`(형식 v1 검증·프롬프트 매핑), 마이그레이션 002 `personas`·`users.personas_seeded`, `store` 페르소나 메서드, `account.PersonaOwner`(대리 범위), httpapi `personas.go`(API-015·016, `?userId=`, 409에 서버 값). 공통 예시 `server/contract/testdata/persona_v1.json` | `server/internal/{chat,store,account,httpapi}/**`, `server/contract/personas_test.go`, `SPEC.md` v1.29, `ARCHITECTURE.md` v1.18, `README.md` | 앱은 아직 기기 `personas.v1`을 씀 — 7-⑤에서 `/api/personas`로. F-029 AC3의 요약 부분은 7-④ |
| 2026-11-13 | F-028 | 단계 7-④ 서버: 마이그레이션 003, `store` 대화·요약·장기 기억 메서드, httpapi `conversations.go`(대화 열기·끝내기 → 요약 저장·6번째부터 묶기·페르소나마다 20개, API-001·007 `conversationId`, 기억 보기·지우기). 테스트: 프롬프트가 DB 값과 같음, DB 파일에 원문 없음, 보호자 보기만 | `server/internal/{store,httpapi}/**`, `server/contract/conversations_test.go`, `SPEC.md` v1.31, `ARCHITECTURE.md` v1.20, `README.md` | 프로필(`about`) 없음 — API-013 때 `conversationPrompt`에 붙이기. 요약 실패는 앱이 `/end` 재시도(서버 원문 없음) |
| 2026-11-14 | F-025 | 사용자 "web build가 되지 않는데 이유를 찾아서 고쳐" → 원인: 새 Flutter 3.50(Dart 3.14)에서 `fetch_api` 2.3.1의 `@JS` 확장 타입 생성자가 컴파일 오류. `pubspec.lock`의 `fetch_api`를 2.3.2(“Dart 3.14 호환” 수정판)로 올림(`pubspec.yaml`은 그대로). `architecture_test` F-011 검사가 `.DS_Store` 같은 비텍스트 파일에서 멈추지 않게 바이트로 읽음 | `app/pubspec.lock`, `app/test/architecture_test.dart`, `AGENT_STATE.md` | CI는 Flutter 3.47.9, 사용자 Mac은 3.50 — 3.50의 `material.dart` 폐기 안내(info)는 `material_ui` 옮기기 제안 대기 |
---

## 압축 기준 (Compaction Rules)

> 이 파일이 비대해지면 토큰 효율이 떨어집니다. 아래 기준으로 관리합니다.

| 섹션 | 압축 트리거 | 처리 방법 |
|------|-------------|-----------|
| Current Focus | 3행 초과 | 우선순위 낮은 항목 삭제 (루트 Roadmap에는 남아 있음) |
| 누적 사용자 요구사항 | 20행 초과 | 오래된 항목을 `AGENT_STATE_ARCHIVE.md`로 이동 |
| 세션 로그 | 10행 초과 | 가장 오래된 행 삭제 |
| Active Rules | 7개 초과 | 덜 중요한 규칙 삭제 (각 폴더 README에 상세 유지) |

