# AI Agent Chat — Overview

이 시스템은 **브라우저에서 AI 에이전트(Claude)와 실시간 스트리밍으로 대화하는 웹 서비스**를 담당합니다.  
API 키가 없으면 모의 모드로 동작해, 설치나 키 없이도 전체 흐름을 시연할 수 있습니다.

> 📄 기능 명세: [`SPEC.md`](./SPEC.md) — 기능 ID(F-xxx)와 수용 기준은 SPEC.md가 정의합니다.  
> 🧭 이 저장소는 [Project Blueprint Framework](https://github.com/kimtaesung98/Project-Blueprint-Framework) v2.0을 따릅니다.

## 빠른 실행

```bash
npm start                                   # 모의 모드 (키 불필요)
ANTHROPIC_API_KEY=sk-ant-... npm start      # 실제 Claude와 대화
npm test                                    # 테스트
```

브라우저에서 `http://localhost:3000`을 엽니다. 외부 패키지가 없어서 `npm install`이 필요 없습니다 (Node.js 22 이상).

| 환경변수 | 기본값 | 설명 |
|---|---|---|
| `PORT` | `3000` | 서버 포트 |
| `ANTHROPIC_API_KEY` | (없음) | 있으면 Claude 모드, 없으면 모의 모드 |
| `ANTHROPIC_MODEL` | `claude-sonnet-5-5` | Claude 모드에서 쓸 모델 |

---

## DFD — Level 0 (Context Diagram)

> 시스템 전체를 단일 버블로 표현합니다. 외부 액터와 시스템 경계만 나타냅니다.  
> 하위 폴더의 DFD는 이 버블을 순차적으로 분해(Decompose)합니다.

```mermaid
flowchart LR
    User([방문자<br>브라우저]) -->|"메시지 · 대화 내역"| System["AI Agent Chat<br>(Level 0)"]
    System -->|"응답 조각 (SSE)"| User
    Operator([운영자]) -->|"환경변수<br>API 키 · 모델"| System
    System -->|"Messages API 요청<br>stream: true"| Claude[[Claude API]]
    Claude -->|"스트리밍 이벤트"| System
```

---

## Tech Stack

- Node.js 22+ (ES Modules) — 기본 모듈만 사용: `node:http`, 전역 `fetch`, `node:test`
- 브라우저: HTML · CSS · JavaScript (빌드 도구 없음)
- 외부 서비스: Claude API (Messages API, 스트리밍)
- 외부 npm 패키지: 없음 (SPEC.md ADR-001)

---

## Agent Control

> 이 규칙은 전체 시스템에 적용되는 최상위 제약입니다. 하위 폴더는 이 규칙을 위반할 수 없습니다.

### 허용 (Allow)

- Node.js 기본 모듈과 브라우저 표준 API
- `node:test` 기반 테스트 추가

### 금지 (Prohibit)

- 외부 npm 패키지 추가 금지 (필요하면 SPEC.md ADR 갱신을 사용자에게 먼저 제안)
- `ANTHROPIC_API_KEY` 등 비밀값을 코드·로그·클라이언트 응답에 포함 금지
- 대화 메시지 본문을 서버 로그에 기록 금지
- SPEC.md에 없는 기능을 임의로 구현 금지 (먼저 사용자에게 제안)

### 필수 (Required)

- 기능 작업 전 SPEC.md에서 해당 기능 ID의 수용 기준 확인
- 수용 기준은 가능한 한 `tests/`의 자동 테스트로 옮기고, 테스트 이름에 기능 ID와 AC 번호 포함 (예: `F-001 AC3`)
- 모든 하위 폴더 작업 완료 시 이 파일의 **Progress Tracker** 업데이트
- 작업할 폴더에 README.md가 없으면 `templates/README_TEMPLATE_SUB.md` 기반으로 생성
- 구조 변경 시 관련 레벨의 DFD를 하위→상위 순서로 업데이트

---

## Sub-folder Map

<!-- /src는 묶음 폴더라 README가 없습니다 → 레벨을 소비하지 않으므로 /src/server, /src/agent가 Level 1입니다 -->

| 폴더 | DFD 레벨 | 담당 기능 ID | 설명 |
|------|----------|--------------|------|
| `/src/server` | Level 1 | F-001 ~ F-004 | HTTP 서버, 입력 검증, SSE 응답 |
| `/src/agent` | Level 1 | F-001, F-003, F-004 | AI 제공자 (Claude · 모의 모드) |
| `/public` | Level 1 | F-001 ~ F-004 | 채팅 화면 (브라우저) |

---

## Progress Tracker

<!-- 상태 이모지: ✅ Done | 🔄 In Progress | ⏳ Pending | ❌ Blocked -->

| ID | Feature | Status | Owner Folder | Last Updated | Notes |
|----|---------|--------|--------------|--------------|-------|
| F-001 | 실시간 스트리밍 채팅 | ✅ Done | `/src/server`, `/src/agent`, `/public` | 2026-11-02 | AC1~AC5 자동 테스트 통과 (28개). 화면 렌더링은 브라우저에서 수동 확인 |
| F-002 | 대화 맥락 유지 | ⏳ Pending | `/src/server`, `/public` | - | AC1은 F-001 구현으로 충족 (테스트 있음). AC2·AC3 남음 |
| F-003 | 응답 중단 | ⏳ Pending | `/src/server`, `/src/agent`, `/public` | - | 서버 쪽 취소 전달(AC2 기반)은 F-001에 포함 |
| F-004 | 오류 처리와 재시도 | ⏳ Pending | `/src/server`, `/src/agent`, `/public` | - | |
| F-005 | 에이전트 페르소나 설정 | ⏳ Pending | - | - | Phase 2 |
| F-006 | 도구 사용 (Tool use) | ⏳ Pending | - | - | Phase 2 |
| F-007 | 대화 기록 저장 | ⏳ Pending | - | - | Phase 2 |
| F-008 | 사용자 로그인 | ⏳ Pending | - | - | Phase 3 |

---

## Next Roadmap

1. F-002 대화 맥락 유지 (AC2 최근 20턴 정리 · AC3 새 대화 버튼) → `/src/server`, `/public`
2. F-003 응답 중단 → `/public` (중단 버튼), `/src/server`·`/src/agent` (취소 전달은 구현됨)
3. F-004 오류 처리와 재시도 → `/public` (다시 시도 버튼), `/src/agent` (오류 문구는 구현됨)
