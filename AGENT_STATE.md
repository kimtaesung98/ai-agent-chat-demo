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
| F-003 | 응답 중단 (Q-004 결정 대기) | `/public` | 서버 취소 전달은 완료. `streamChat`에 `signal` 연결, 중단 버튼, 부분 응답에 "중단됨" 표시. 중단 후 `reset()`이 동작하도록 busy 해제 확인 |
| F-004 | 오류 처리와 재시도 | `/public`, `/src/agent` | 사용자용 오류 문구는 완료. 컨트롤러가 실패한 질문을 내역에서 빼는 부분을 "다시 시도"용으로 보관하도록 변경 |

---

## 누적 사용자 요구사항 (Resolved Requirements)

> 사용자가 요청하고 이미 반영된 **구조적 결정**을 기록합니다.  
> 에이전트는 이 목록을 먼저 읽고 중복 작업을 방지합니다.  
> 기능 구현 자체는 Tracker가 기록하므로 여기에 적지 않습니다.  
> **20개 초과 시** → 오래된 항목을 `AGENT_STATE_ARCHIVE.md`로 이동.

| # | 요구사항 요약 | 반영 날짜 | 변경된 파일 |
|---|--------------|-----------|-------------|
| 1 | 현재 MVP는 외부 npm 패키지 없이 Node.js 22 기본 모듈만 사용 (ARCHITECTURE ADR-001) | 2026-11-02 | `SPEC.md`, `README.md`, `CLAUDE.md` |
| 2 | 화면 로직(`chat-controller.js`)과 DOM(`app.js`) 분리 — 화면 동작은 가짜 ui로 테스트 | 2026-11-02 | `public/*` |
| 3 | 기능 단위로 브랜치를 만들고 PR로 main에 합친다 (SPEC §13 GitHub Flow) | 2026-11-02 | — |
| 4 | 사용자 선호 언어(C/C++/Go/Flutter) 기준 목표 스택: 서버 Go, 클라이언트 Flutter (승인). C/C++ 미사용은 제안 상태. ADR은 ARCHITECTURE.md로 이동 | 2026-11-04 | `ARCHITECTURE.md`, `SPEC.md`, `README.md`, `CLAUDE.md` |

---

## 핵심 규칙 스냅샷 (Active Rules)

> 전역 Agent Control에서 핵심 3~7개만 추출. 세부 규칙은 각 폴더 README.md 참조.  
> 규칙 변경 시 원본(루트 README.md Agent Control 또는 CLAUDE.md)을 먼저 고치고 이 목록을 맞춥니다.

**절대 금지:**
- ARCHITECTURE.md §2.2 허용 목록 밖의 의존성 추가 (현재 Node MVP는 0개)
- §10 전환 단계가 SPEC에 등록되기 전에 Go·Flutter 코드 작성
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
| 2026-11-02 | - | 초기화 — BOOTSTRAP 실행, STATE 생성 | `AGENT_STATE.md` 생성, `AGENT_BOOTSTRAP.md` 삭제 | — |
| 2026-11-02 | F-001 | 폴더 README 3개 생성, SSE 서버·Claude/모의 제공자·채팅 화면 구현, 테스트 28개 통과, 실제 서버 구동 확인 | `src/**`, `public/**`, `tests/**`, `package.json`, `README.md` | 브라우저 화면 수동 확인 필요. 실제 Claude 모드는 API 키로 확인 필요 (테스트는 가짜 업스트림) |
| 2026-11-02 | F-002 | 사용자가 로컬 실행 완료를 알림. 최근 20턴 정리(`context.js`), 새 대화 버튼·`reset()` 구현, 테스트 35개 통과, DFD 갱신 | `src/server/*`, `public/*`, `tests/context.test.js`, `README.md` | 브랜치 `feat/F-002-context` PR 머지 후 F-003 착수 |
| 2026-11-04 | - | ARCHITECTURE.md 작성 (현재 Node MVP + 목표 Go·Flutter, ADR-001~013, 전환 5단계), SPEC ADR 이관, 프레임워크 v2.1 반영 | `ARCHITECTURE.md`, `SPEC.md`, `README.md`, `CLAUDE.md`, `templates/*` | Q-004 결정 전에는 F-003 착수 보류. 제안 ADR(007~013) 사용자 승인 대기 |

---

## 압축 기준 (Compaction Rules)

> 이 파일이 비대해지면 토큰 효율이 떨어집니다. 아래 기준으로 관리합니다.

| 섹션 | 압축 트리거 | 처리 방법 |
|------|-------------|-----------|
| Current Focus | 3행 초과 | 우선순위 낮은 항목 삭제 (루트 Roadmap에는 남아 있음) |
| 누적 사용자 요구사항 | 20행 초과 | 오래된 항목을 `AGENT_STATE_ARCHIVE.md`로 이동 |
| 세션 로그 | 10행 초과 | 가장 오래된 행 삭제 |
| Active Rules | 7개 초과 | 덜 중요한 규칙 삭제 (각 폴더 README에 상세 유지) |
