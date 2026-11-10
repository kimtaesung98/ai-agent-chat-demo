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
| F-005 | 페르소나 설정 (피그마 시안 A·C → Flutter Material 3, API-001 `persona`) | `/app`, `/server`, `/src/server` | 사용자가 "Flutter에 바로 M3로 구현" 선택. 구현·자동 테스트·웹 빌드 캡처 완료. ADR-016 승인됨. 남은 것: AC8 실제 Claude 확인, Q-005 저장 유지 결정 |
| - | MVP HTML 디자인 → Flutter 반영 | `/app` | 디자인(claude.ai 비공개 Artifact, 7화면)에 있고 앱에 없는 것(첫 실행 페르소나 고르기, 음성 전용 화면 등)을 SPEC에 제안한 뒤 구현. Google 로그인(F-008)은 사용자가 보류 — Phase 3 (Q-006) |
| F-012 | 음성 대화 (듣기 → 자동 전송 → 문장별 읽기 → 끼어들기) | `/app`, `/server` | 사용자가 `speech_to_text`·`flutter_tts` 선택(ADR-014), F-012·ADR-015 승인. 구현·자동 테스트·가짜 음성 API 브라우저 확인 완료. 남은 것: AC8 실제 마이크 확인(사용자) → ✅ |

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
| 2026-11-04 | - | ARCHITECTURE.md 작성 (현재 Node MVP + 목표 Go·Flutter, ADR-001~013, 전환 5단계), SPEC ADR 이관, 프레임워크 v2.1 반영 | `ARCHITECTURE.md`, `SPEC.md`, `README.md`, `CLAUDE.md`, `templates/*` | Q-004 결정 전에는 F-003 착수 보류. 제안 ADR(007~013) 사용자 승인 대기 |
| 2026-11-04 | F-009 | 사용자 계획 승인(전환 먼저, 음성은 Flutter 뒤). Q-004 결정 기록, ADR-012 승인. `server/contract` Go 계약 테스트 17개 시나리오, `npm run test:contract`, CI 워크플로 추가. Node 서버에 통과, 모의 모드 아니면 실패 확인 | `server/**`, `scripts/contract-node.js`, `.github/workflows/ci.yml`, `package.json`, `SPEC.md`, `ARCHITECTURE.md`, `README.md`, `CLAUDE.md` | CI 초록 확인 후 ✅. ADR-007·008·013 등 나머지 제안 ADR은 단계 2 전에 사용자 승인 필요 |
| 2026-11-05 | F-010 | 사용자 ADR-007·008·013 승인. Go 서버 구현(config·chat·provider·mock·anthropic(SDK v2.6.0)·httpapi·cmd/chatd), 의존 규칙 테스트, `npm run test:contract:go`, CI 확장. 계약 테스트 Node·Go 둘 다 통과, 브라우저로 기존 화면 확인 | `server/**`, `scripts/contract.js`(이름 변경), `.github/workflows/ci.yml`, `package.json`, `SPEC.md`, `ARCHITECTURE.md`, `README.md`, `CLAUDE.md` | SDK v2는 `Authorization: Bearer`로 키 전송 — 실제 키로 Claude 모드 수동 확인 필요 (테스트는 가짜 업스트림) |
| 2026-11-05 | F-011, F-003 | 사용자 ADR-009·010·011 승인. Flutter 3.47.9 설치, `app/` 구현(api·chat·ui), 중단 버튼, 위젯·단위·의존 규칙 테스트 33개, Go 서버가 Flutter 빌드 파일 형식 제공, CI에 flutter 작업 추가, 브라우저로 Go 서버 + Flutter 스트리밍 확인 | `app/**`, `server/internal/httpapi/*`, `.github/workflows/ci.yml`, `SPEC.md`, `ARCHITECTURE.md`, `README.md`, `CLAUDE.md` | 한글 폰트를 gstatic에서 받음 (R-A08) — 공개 전 결정. `public/`·Node는 단계 4에서 제거 |
| 2026-11-07 | F-012 | PR #5 병합 확인. 음성 대화를 SPEC F-012로 제안, ARCHITECTURE ADR-014·015 제안 (STT·TTS 방식, 음성용 말투), `app/voice` 모듈·인터페이스·시나리오·위험 R-A09·R-A10 | `SPEC.md`, `ARCHITECTURE.md`, `README.md`, `AGENT_STATE.md` | 사용자 승인 전에는 계약(`mode`) 변경 코드 작성 안 함 |
| 2026-11-07 | F-012 | 사용자가 Flutter 음성 패키지 선택. `app/lib/voice`(문장 분리기·엔진·컨트롤러)·마이크 UI, Go·Node `mode: "voice"` + 말하기용 시스템 프롬프트, 계약 시나리오 2개. 브라우저 확인 중 웹 플러그인 특이점 3개 발견·처리 (R-A11) | `app/**`, `server/**`, `src/server/*`, `src/agent/anthropic.js`, `tests/*`, 문서 | 실제 마이크·실제 Claude로 AC8 확인 필요. 에코 끼어들기(R-A09)는 실제 스피커로만 판단 가능 |
| 2026-11-10 | F-012 | 로컬 알파테스트 가이드 작성 (Mac, 모의·Claude 모드, 텍스트·음성 체크리스트). Go 1.25·Flutter 3.47.9로 문서대로 빌드·실행·테스트 확인, 잘못된 키 인증 오류 문구 확인 | `docs/ALPHA_TEST_LOCAL.md`, `README.md` | 사용자가 실제 키·실제 마이크로 체크리스트 실행 → 결과로 AC8 판정·끝맺음 시간 조정 |
| 2026-11-10 | F-005 | 피그마 GUI 시안(현재 화면 + A~D) 작성 → Starter 플랜 MCP 한도로 M3 키트 작업 중단 → 사용자 선택으로 Flutter M3 구현. SPEC v1.6(F-005 재정의), ADR-016 제안, Go·Node `persona`, 사이드바·편집 화면 | `SPEC.md`, `ARCHITECTURE.md`, `server/internal/chat/*`, `src/server/*`, `app/lib/**`, 테스트 | 피그마 파일: figma.com/design/U9r2hj8EoRdBiiwP8daqLn (무료 플랜이라 MCP 호출 한도·변수 모드 1개). 페르소나는 앱 메모리만 — Q-005 |
| 2026-11-10 | F-004, F-008 | MVP HTML 디자인(Design 캔버스, 7화면) 작성 → 사용자가 "순서대로, 판단은 맡김". ADR-016 승인 반영, F-004 다시 시도(Flutter) 완료, F-008 Google 로그인 SPEC·ADR-017 제안 | `SPEC.md`, `ARCHITECTURE.md`, `app/lib/chat/chat_controller.dart`, `app/lib/ui/chat_page.dart`, 테스트 | 디자인은 claude.ai 비공개 Artifact. 네이티브 앱의 기준 화면으로 씀 |
| 2026-11-10 | F-013, F-008 | 사용자가 Google 로그인 보류(Phase 3) 선택 → §10 단계 4 진행. `src/`·`public/`·`tests/`·`scripts/`·`package.json` 삭제, 계약 테스트가 모의 모드 `chatd`를 직접 띄우게 바꿈(`go test ./...`에 포함), CI Node 작업 제거, 문서 갱신 | `server/contract/*`, `.github/workflows/ci.yml`, `README.md`, `CLAUDE.md`, `SPEC.md` v1.8, `ARCHITECTURE.md` v1.7, `server/README.md` | ADR-001 대체됨, ADR-017 보류, TD-001~003 해소 |

---

## 압축 기준 (Compaction Rules)

> 이 파일이 비대해지면 토큰 효율이 떨어집니다. 아래 기준으로 관리합니다.

| 섹션 | 압축 트리거 | 처리 방법 |
|------|-------------|-----------|
| Current Focus | 3행 초과 | 우선순위 낮은 항목 삭제 (루트 Roadmap에는 남아 있음) |
| 누적 사용자 요구사항 | 20행 초과 | 오래된 항목을 `AGENT_STATE_ARCHIVE.md`로 이동 |
| 세션 로그 | 10행 초과 | 가장 오래된 행 삭제 |
| Active Rules | 7개 초과 | 덜 중요한 규칙 삭제 (각 폴더 README에 상세 유지) |
