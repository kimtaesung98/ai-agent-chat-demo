# Blueprint Framework — Master Document

> 이 문서는 Project Blueprint Framework의 전체 명세입니다.  
> 프레임워크 규칙에 대한 **단일 진실 공급원(Single Source of Truth)** 입니다.  
> ⚠️ 에이전트는 이 문서를 **세션 중 읽지 않습니다** — 필요한 규칙은 `CLAUDE.md`와 각 폴더 `README.md`에 요약되어 있습니다.

---

## DFD — Level 1 (Main Processes)

> Decomposed from: `/` Level 0 — `Blueprint Framework` 버블  
> 이 레벨은 Blueprint Framework 내부의 **주요 구성 문서들이 어떻게 연동**되는지를 나타냅니다.

```mermaid
flowchart TD
    Developer([Developer])
    AgentSession([AI Agent Session])

    subgraph Templates ["templates/ — 프레임워크가 제공하는 원본"]
        SPECT["SPEC_TEMPLATE.md"]
        TOPT["README_TEMPLATE_TOP.md"]
        SUBT["README_TEMPLATE_SUB.md"]
        CHKL["FOLDER_CHECKLIST.md"]
        CLT["CLAUDE_TEMPLATE.md"]
        BOOT["AGENT_BOOTSTRAP.md"]
        STATET["AGENT_STATE.md"]
    end

    subgraph Project ["적용 프로젝트"]
        SPEC["SPEC.md<br>(무엇을 · 수용 기준)"]
        RootREADME["README.md<br>(Level 0 DFD · Tracker)"]
        CLAUDE["CLAUDE.md<br>(세션 프로토콜)"]
        STATE["AGENT_STATE.md<br>(세션 인계)"]
        FolderREADME["[folder]/README.md<br>(Level 1+ DFD · Control)"]
    end

    Developer -->|"① 명세 작성"| SPECT --> SPEC
    Developer -->|"② 템플릿 복사"| TOPT --> RootREADME
    CLT --> CLAUDE
    BOOT -->|"③ 최초 1회 초기화"| STATE
    STATET -.->|"복사 원본"| BOOT
    CHKL -->|"④ 새 폴더 생성 시"| SUBT --> FolderREADME

    CLAUDE -->|"⑤ 자동 로딩"| AgentSession
    STATE -->|"⑥ 이어받기"| AgentSession
    SPEC -->|"⑦ 해당 F-ID 수용 기준"| AgentSession
    FolderREADME -->|"⑧ DFD · Agent Control"| AgentSession
    AgentSession -->|"⑨ Tracker 갱신"| RootREADME
    AgentSession -->|"⑩ 세션 로그"| STATE
```

---

## 목차

1. [프레임워크 개요](#1-프레임워크-개요)
2. [SPEC.md 명세 규칙](#2-specmd-명세-규칙)
3. [폴더 README 구조 명세](#3-폴더-readme-구조-명세)
4. [DFD 작성 가이드](#4-dfd-작성-가이드)
   - [4-1. DFD 레벨링 규칙](#4-1-dfd-레벨링-규칙)
5. [Progress Tracker 규칙](#5-progress-tracker-규칙)
6. [Agent Control 섹션 규칙](#6-agent-control-섹션-규칙)
7. [폴더 소유권 모델](#7-폴더-소유권-모델)
8. [전체 적용 예시](#8-전체-적용-예시)

---

## 1. 프레임워크 개요

### 배경

AI 에이전트는 단일 파일 수준에서는 탁월한 성능을 보이지만,  
**프로젝트 전체 맥락**을 유지하면서 작업할 때 다음 문제가 발생합니다:

- 무엇을 만들어야 하는지(완료 기준)가 불분명해 방향 없이 반복 수정
- 데이터 흐름을 오해해 의도치 않은 사이드 이펙트 발생
- 이미 구현된 기능을 중복 구현하거나 미구현 기능을 건너뜀
- 폴더별 아키텍처 원칙(Pure Function, 의존성 제한 등)을 무시

### 해결책

Blueprint Framework는 정보를 **세 층으로 나누고, 각 정보를 한 곳에서만 정의**합니다.

| 층 | 질문 | 정의 위치 |
|---|---|---|
| 명세 | 무엇을 만드는가? 언제 완료인가? | 루트 `SPEC.md` |
| 진행 | 얼마나 됐는가? 다음은 무엇인가? | 소유자 `README.md` Progress Tracker · Next Roadmap |
| 흐름 | 어떻게 흐르는가? 무엇이 금지인가? | 각 폴더 `README.md` DFD · Agent Control |

세 층은 **기능 ID(F-001)** 로 연결됩니다. 에이전트는 작업할 기능 ID를 기준으로 필요한 부분만 읽습니다.

### 프레임워크 구성 파일

| 파일 | 역할 | 에이전트가 읽는 시점 |
|------|------|-----------|
| `CLAUDE.md` | Claude Code 자동 로딩 — 세션 프로토콜·핵심 규칙 | **매 세션 자동** |
| `AGENT_STATE.md` | 현재 집중 작업·누적 요구사항·세션 로그 | 매 세션 시작 (CLAUDE.md 지시) |
| 루트 `README.md` | Level 0 DFD · Progress Tracker · Roadmap | 매 세션 시작 |
| `SPEC.md` | 기능 명세 · 수용 기준 | 작업할 **기능 ID 블록만** |
| `[폴더]/README.md` | 폴더별 Context·DFD·Agent Control | 작업 대상 폴더 진입 시 |
| `AGENT_BOOTSTRAP.md` | 최초 1회 초기화 지시 | **최초 1회 후 삭제** |
| `BLUEPRINT.md` | 프레임워크 전체 명세 (이 파일) | **세션 중 읽지 않음** |
| `CONTRIBUTING.md` | 상세 프로토콜·드리프트 감지·팀 규칙 | **세션 중 읽지 않음** |

---

## 2. SPEC.md 명세 규칙

### 목적

Progress Tracker의 Feature가 "이름"만 있으면 에이전트는 **언제 끝났는지** 판단할 수 없습니다.  
`SPEC.md`는 기능마다 사용자 스토리와 **수용 기준(Acceptance Criteria)** 을 정의해 "완료"의 기준을 고정합니다.

템플릿: `templates/SPEC_TEMPLATE.md` → 프로젝트 루트 `SPEC.md`

### 기능 ID 규칙

- 형식: `F-001`, `F-002`, … (3자리, 순차 증가)
- **SPEC.md §4.1 기능 목록이 ID의 원천**입니다. 새 기능은 SPEC에 먼저 추가하고, Tracker에 같은 ID로 행을 추가합니다.
- ID는 재사용하지 않습니다. 삭제된 기능의 ID는 비워 둡니다.
- 화면(`S-001`), API(`API-001`), 결정(`ADR-001`), 리스크(`R-001`), 질문(`Q-001`)도 같은 방식으로 ID를 붙입니다.

### 중복 금지 규칙

| 정보 | SPEC.md에 쓰는가? | 쓰는 곳 |
|---|---|---|
| 기능 정의 · 수용 기준 | ✅ | SPEC.md |
| 진행 상태 (✅🔄⏳❌) | ❌ | 소유자 README Tracker |
| 기술 스택 · 시스템 구성도 | ❌ (선택 이유인 ADR만) | 루트 README Tech Stack · Level 0 DFD |
| 다음 작업 순서 | ❌ (날짜 있는 마일스톤만) | 소유자 README Next Roadmap |
| 모듈 내부 데이터 흐름 | ❌ (사용자 흐름만) | 폴더 README DFD |

### 에이전트 사용 규칙

- 세션마다 SPEC.md 전체를 읽지 않습니다. **작업할 기능 ID의 §4.2 블록**과 그 블록이 참조하는 항목만 읽습니다.
- 명세가 모호하면 추측해서 구현하지 않고, SPEC.md §16 미결 사항에 질문을 추가한 뒤 사용자에게 묻습니다.
- 수용 기준을 바꾸는 것은 **사용자의 결정**입니다. 에이전트는 변경을 제안만 합니다.

---

## 3. 폴더 README 구조 명세

폴더 유형에 따라 **두 가지 구조** 중 하나를 사용합니다.  
유형 결정은 `templates/FOLDER_CHECKLIST.md Step 1`을 참고하세요.

### 최상위(소유자) 폴더 — `README_TEMPLATE_TOP.md` 사용

Progress Tracker와 Roadmap을 **소유**하는 폴더입니다.

```
## [시스템명] Overview         # 시스템 전체 책임 (1~2문장) + SPEC.md 링크
## DFD — Level 0 (Context)    # 시스템을 단일 버블로, 외부 액터만 표시
## Tech Stack                  # 전체 스택 정의
## Agent Control               # 전체 시스템 최상위 제약 (하위 상속)
## Sub-folder Map              # 하위 폴더 ↔ 기능 ID 매핑 테이블
## Progress Tracker            # ← 진행도 유일 정의 지점 (기능 ID 기준)
## Next Roadmap                # ← 방향성 유일 정의 지점
```

### 하위(실행자) 폴더 — `README_TEMPLATE_SUB.md` 사용

DFD로 구현 흐름을 상세화하는 폴더입니다. **Tracker·Roadmap 없음.**

```
## [폴더명] Overview           # 이 폴더의 책임 (1~2문장)
## Context — 상위 흐름과의 연결 # 담당 기능 ID + 입출력 명시
## DFD — Level N (레벨명)      # 상위 버블을 분해한 상세 흐름
## Tech Stack                  # 상위에서 미명시된 추가 스택만
## Agent Control               # 상위 규칙 상속 + 이 폴더 추가 제약
```

> ⚠️ 에이전트는 BLUEPRINT.md를 세션 중 읽지 않습니다.  
> 세션 시작 시 `CLAUDE.md` → `AGENT_STATE.md` → 루트 `README.md` → (해당 기능의 `SPEC.md` 블록) → 작업 대상 폴더 `README.md` 순으로만 읽습니다.

### README가 없는 폴더

모든 폴더에 README.md를 미리 만들 필요는 없습니다.  
**에이전트가 작업할 폴더에 README.md가 없으면 그 시점에 `README_TEMPLATE_SUB.md`로 생성**합니다 (CONTRIBUTING.md §2 규칙).  
묶음 역할만 하는 중간 폴더(예: `/src`)는 README 없이 두어도 되며, 이 경우 DFD 레벨을 소비하지 않습니다.

---

## 4. DFD 작성 가이드

### 목적

mermaid `flowchart` 또는 `sequenceDiagram`을 사용해 이 폴더가 처리하는  
**데이터의 진입점(Input) → 처리(Process) → 출력(Output)** 을 명시합니다.

에이전트는 이 다이어그램을 읽고, 자신이 수정할 코드가 이 흐름을 깨는지 검토해야 합니다.

---

### 4-1. DFD 레벨링 규칙

DFD 레벨은 **파일 시스템 깊이가 아니라 "분해 깊이"** 로 정합니다.  
상위 DFD의 버블(Process) 하나를 하위 DFD 전체로 확대(Decompose)할 때마다 레벨이 1 증가합니다.

> **레벨 = 상위 README의 레벨 + 1**  
> 소유자(최상위) README가 Level 0입니다. README가 없는 중간 폴더는 건너뜁니다.

#### 레벨별 정의

| 레벨 | 정의 | 예시 경로 | 헤더 표기 |
|------|------|-----------|-----------|
| **Level 0** | 소유자 폴더. 시스템 전체를 단일 버블로, 외부 액터와 경계만 표시 | `/` | `## DFD — Level 0 (Context Diagram)` |
| **Level 1** | Level 0 버블을 분해한 폴더 — 주요 서브시스템 | `/src/auth` (`/src`는 README 없음) | `## DFD — Level 1 (Main Processes)` |
| **Level 2** | Level 1 버블 하나를 분해한 폴더 — 모듈 내부 흐름 | `/src/auth/handlers` | `## DFD — Level 2 (Detailed Processes)` |
| **Level 3+** | Level 2 이하를 분해한 폴더 — 함수/컴포넌트 수준 입출력 | `/src/auth/handlers/oauth` | `## DFD — Level 3 (Function Level)` |

> 💡 같은 파일 시스템 깊이라도 레벨이 다를 수 있습니다.  
> 예: `/templates`(깊이 1)와 `/src/auth`(깊이 2)는 둘 다 루트 버블을 분해하므로 둘 다 **Level 1**입니다.

#### 필수 표기 규칙

각 DFD 섹션 헤더 바로 아래에 **어느 상위 버블을 분해했는지** 반드시 명시합니다:

```markdown
## DFD — Level 2 (Detailed Processes)

> Decomposed from: `/src/auth` Level 1 — `LoginHandler` 버블
```

#### 레벨 간 일관성 규칙

- 하위 DFD의 **외부 입력/출력**은 상위 DFD에서 해당 버블로 들어오고 나가는 화살표와 **정확히 일치**해야 합니다.
- 상위 DFD에 없는 외부 의존성이 하위 DFD에 등장할 경우, **상위 DFD도 함께 업데이트**해야 합니다.
- 에이전트는 하위 폴더 작업 전 상위 폴더의 DFD를 읽어 자신이 수정할 버블의 입출력을 확인해야 합니다.

#### 레벨링 시각화 예시

```
/                          (Level 0 — 소유자)
└─ [ my-api ] ─────────────────────────────────────────────── 단일 버블
        │
        ▼ Decompose        (/src는 README 없음 → 레벨 소비 안 함)
/src/auth                  (Level 1)
└─ [ LoginHandler ] → [ JWTService ] → [ AuthMiddleware ] ── 서브프로세스 분해
        │
        ▼ Decompose
/src/auth/handlers         (Level 2)
└─ [ Input Validator ] → [ AuthService 호출 ] → [ ErrorFormatter ] ── 내부 상세
        │
        ▼ Decompose
/src/auth/handlers/oauth   (Level 3)
└─ [ state 검증 ] → [ code 교환 ] → [ 사용자 매핑 ] ── 함수 수준
```

#### Level 3+ 작성 지침

Level 3부터는 **함수/컴포넌트 단위**로 DFD를 그립니다.  
모든 폴더가 Level 3 DFD를 가질 필요는 없습니다 — 아래 조건일 때만 작성합니다:

- 이 폴더 내부에 **5개 이상의 함수/클래스**가 상호작용하는 경우
- 에이전트가 반복적으로 이 폴더에서 버그를 발생시킨 경우
- 보안·성능상 흐름이 정확해야 하는 폴더 (인증, 결제, 암호화 등)

Level 3+ DFD는 `sequenceDiagram`을 사용해도 됩니다:

```mermaid
sequenceDiagram
    participant Req as HTTP Request
    participant Val as Validator
    participant Svc as AuthService
    participant DB as PostgreSQL
    Req->>Val: credentials
    Val-->>Req: 400 (invalid)
    Val->>Svc: validated data
    Svc->>DB: SELECT user
    DB-->>Svc: user record
    Svc-->>Req: 401 (wrong password)
    Svc-->>Req: 200 + token
```

---

### 작성 규칙 (공통)

- `mermaid` 코드 블록 안에 작성
- 노드 이름은 영어, 화살표 레이블은 한/영 혼용 가능
- 라벨 줄바꿈은 `\n` 대신 `<br>`을 사용 (렌더러 호환성)
- 외부 시스템(DB, API, 다른 모듈)은 `[[ ]]` 또는 `[(DB)]` 표기
- 변경 시 반드시 에이전트가 업데이트하며, 하위→상위 일관성 검토 포함

### 예시 — REST API 서버의 `/api` 폴더

```mermaid
flowchart LR
    Client([Client]) -->|HTTP Request| Router[Router]
    Router --> AuthMiddleware[Auth Middleware]
    AuthMiddleware -->|인증 통과| Controller[Controller]
    AuthMiddleware -->|인증 실패| ErrorHandler[Error Handler]
    Controller -->|Query| DB[(PostgreSQL)]
    DB -->|Result| Controller
    Controller -->|HTTP Response| Client
    Controller -->|에러| ErrorHandler
```

### 예시 — React 컴포넌트 폴더

```mermaid
flowchart TD
    Props([Props / Context]) --> Component[Component]
    Component -->|useEffect| ExternalAPI[[External API]]
    ExternalAPI -->|data| LocalState[Local State]
    LocalState --> Component
    Component -->|render| DOM([DOM])
    Component -->|event| ParentCallback([Parent Callback])
```

### 예시 — Python 데이터 파이프라인

```mermaid
flowchart LR
    RawCSV([Raw CSV]) --> Loader[DataLoader]
    Loader -->|DataFrame| Cleaner[DataCleaner]
    Cleaner -->|Cleaned DF| Transformer[Transformer]
    Transformer -->|Feature Matrix| Model[[ML Model]]
    Model -->|Predictions| Exporter[Exporter]
    Exporter --> OutputJSON([output.json])
```

---

## 5. Progress Tracker 규칙

### 목적

`git log` 없이도 **무엇이 구현되었고, 무엇이 남았는지** 즉시 파악할 수 있게 합니다.

### 테이블 형식

```markdown
| ID | Feature | Status | Owner Folder | Last Updated | Notes |
|----|---------|--------|--------------|--------------|-------|
| F-001 | 기능명 | ✅ Done / 🔄 In Progress / ⏳ Pending / ❌ Blocked | `/src/auth` | YYYY-MM-DD | 비고 |
```

- `ID`와 `Feature`는 `SPEC.md` §4.1 기능 목록과 **반드시 일치**합니다.
- SPEC.md가 없는 프로젝트(마이그레이션 초기 등)는 ID를 `T-001`처럼 임시로 붙이고, SPEC 작성 시 `F-`로 교체합니다.

### 상태 이모지 기준

| 이모지 | 상태 | 의미 |
|--------|------|------|
| ✅ | Done | SPEC.md의 **수용 기준을 모두 통과** |
| 🔄 | In Progress | 현재 작업 중 |
| ⏳ | Pending | 아직 시작 안 함 |
| ❌ | Blocked | 외부 의존성 또는 버그로 차단 |

### 에이전트 업데이트 의무

- 작업을 시작하면 해당 행의 상태를 `🔄 In Progress`로 변경
- 수용 기준을 모두 확인한 뒤에만 `✅ Done`으로 변경하고 `Last Updated`를 오늘 날짜로 수정
- 새 기능은 SPEC.md §4.1에 먼저 추가한 뒤 같은 ID로 Tracker에 행을 삽입
- 블로커 발견 시 `❌ Blocked`로 변경하고 Notes에 이유 기재

---

## 6. Agent Control 섹션 규칙

### 목적

이 섹션은 에이전트에 대한 **폴더 수준의 System Prompt**입니다.  
에이전트는 이 섹션의 규칙을 코드 생성 전 반드시 읽고 준수해야 합니다.

### 작성 형식

```markdown
## Agent Control

> 이 섹션의 규칙은 에이전트가 이 폴더의 코드를 수정할 때 반드시 따라야 합니다.

### 허용 (Allow)
- ...

### 금지 (Prohibit)
- ...

### 필수 (Required)
- ...
```

### 상속 규칙

- 하위 폴더의 Agent Control은 상위 규칙을 **상속**합니다.
- 하위 폴더는 규칙을 **추가하거나 강화**할 수 있지만, **완화할 수 없습니다.**

### 예시 — 유틸리티 함수 폴더

```markdown
## Agent Control

### 허용
- 순수 함수(Pure Function) 작성
- TypeScript 내장 타입 사용
- 단위 테스트 파일 추가

### 금지
- 외부 npm 패키지 import 금지
- 전역 상태(global state) 참조 금지
- 비동기(async/await) 함수 금지

### 필수
- 모든 함수는 JSDoc 주석 포함
- 함수 하나당 단일 책임 원칙 준수
- 에러는 throw 대신 Result 타입으로 반환
```

### 예시 — API 라우터 폴더

```markdown
## Agent Control

### 허용
- Express Router 사용
- 기존 미들웨어 체인 활용

### 금지
- 라우터 파일 내 비즈니스 로직 직접 작성 금지 (Controller로 위임)
- DB 직접 쿼리 금지 (Service 레이어 경유 필수)

### 필수
- 새 엔드포인트 추가 시 DFD와 SPEC.md §9 API 명세 업데이트
- 모든 라우트에 인증 미들웨어 적용
- HTTP 상태 코드는 RFC 9110 표준 준수
```

---

## 7. 폴더 소유권 모델

### 핵심 원칙

> **"무엇을 만드나(What)"는 SPEC.md에서, "얼마나 됐나(Progress)"는 소유자 폴더에서만 정의하고,**  
> **"어떻게 흐르는가(How)"는 하위로 내려갈수록 상세해진다.**

Progress Tracker와 Roadmap은 **최상위 폴더(소유자)에만 존재**합니다.  
하위 폴더는 상위의 정의를 참조하며, DFD를 통해 자신의 구현 흐름을 상세화합니다.

### 폴더 유형별 README 구성

```
┌─────────────────────────────────────────────────────────────┐
│  📄 SPEC.md (루트)                                           │
│     ✅ 기능 목록 (F-ID)        ← 기능 ID의 원천              │
│     ✅ 수용 기준               ← "Done"의 정의               │
└──────────────────┬──────────────────────────────────────────┘
                   │  기능 ID로 연결
┌──────────────────▼──────────────────────────────────────────┐
│  📁 최상위 폴더 (소유자) — Level 0                            │
│     템플릿: README_TEMPLATE_TOP.md                           │
│                                                             │
│     ✅ DFD — Level 0 (Context)    ← 시스템 경계 정의         │
│     ✅ Tech Stack                 ← 전체 스택 정의            │
│     ✅ Agent Control              ← 전체 시스템 규칙 (최상위) │
│     ✅ Sub-folder Map             ← 하위 폴더 ↔ 기능 ID 매핑  │
│     ✅ Progress Tracker           ← 유일한 진행도 정의        │
│     ✅ Next Roadmap               ← 유일한 방향성 정의        │
└──────────────────┬──────────────────────────────────────────┘
                   │  DFD 분해(Decompose) + 작업 위임
┌──────────────────▼──────────────────────────────────────────┐
│  📁 하위 폴더 — Level 1                                       │
│     템플릿: README_TEMPLATE_SUB.md                          │
│                                                             │
│     ✅ Context (담당 기능 ID 참조)      ← 상위와 연결        │
│     ✅ DFD — Level 1 (Main Processes)  ← Level 0 버블 분해   │
│     ✅ Tech Stack (추가분만)                                  │
│     ✅ Agent Control (상위 규칙 상속 + 추가)                  │
│     ❌ Progress Tracker 없음            ← 상위가 소유         │
│     ❌ Next Roadmap 없음               ← 상위가 소유          │
└──────────────────┬──────────────────────────────────────────┘
                   │  DFD 분해(Decompose)
┌──────────────────▼──────────────────────────────────────────┐
│  📁 하위 폴더 — Level 2                                       │
│     템플릿: README_TEMPLATE_SUB.md (동일)                   │
│                                                             │
│     ✅ Context (Level 1 DFD 버블 참조)  ← Level 1과 연결     │
│     ✅ DFD — Level 2 (Detailed)       ← Level 1 버블 분해    │
│     ✅ Tech Stack (추가분만)                                  │
│     ✅ Agent Control (상속 + 추가)                            │
│     ❌ Progress Tracker 없음                                  │
│     ❌ Next Roadmap 없음                                      │
└─────────────────────────────────────────────────────────────┘
```

### 에이전트 작업 흐름

```
① 루트 README.md 열기
   └─ Progress Tracker에서 작업할 기능 ID 확인
   └─ Owner Folder에서 담당 하위 폴더 확인
         │
② SPEC.md에서 해당 기능 ID 블록만 읽기
   └─ 사용자 스토리 · 수용 기준 · 예외 처리 확인
         │
③ 담당 하위 폴더 README.md 열기
   └─ Context 섹션: 상위 흐름에서 내 위치 파악
   └─ DFD: 이 폴더 내부의 구현 흐름 파악
   └─ Agent Control: 이 폴더의 제약 확인
         │
④ 코드 작업 → 수용 기준 확인
         │
⑤ 루트 README.md로 돌아와
   └─ Progress Tracker 업데이트 (🔄 → ✅)
   └─ Next Roadmap 갱신
```

### 새 외부 의존성 발생 시 연쇄 업데이트 규칙

하위 폴더에서 상위 DFD에 없는 외부 시스템과 연결이 생기면:

```
Level 2 DFD 업데이트 (새 노드 추가)
    → Level 1 DFD 업데이트 (버블의 입출력 화살표 반영)
        → Level 0 DFD 업데이트 (외부 시스템 노드 추가)
            → SPEC.md §10 외부 연동 표에 행 추가
                → 최상위 Progress Tracker Notes에 의존성 기재
```

---

## 8. 전체 적용 예시

Node.js API 프로젝트를 기준으로 **SPEC 발췌 + 루트(TOP) + 하위(SUB)** 파일을 함께 보여줍니다.  
`/src`는 묶음 폴더라 README가 없으므로, `/src/auth`가 Level 1입니다.

---

### 예시 0 — `SPEC.md` 발췌

````markdown
### 4.1 기능 목록
| ID | 기능명 | 설명 | 우선순위 | 단계 |
|---|---|---|---|---|
| F-001 | JWT 발급 | 이메일/비밀번호 로그인 시 토큰 발급 | P0 | MVP |
| F-002 | JWT 검증 미들웨어 | 보호된 라우트 접근 제어 | P0 | MVP |
| F-003 | Refresh Token | 액세스 토큰 갱신 | P0 | MVP |
| F-004 | OAuth Google | 구글 계정 로그인 | P1 | Phase 2 |
| F-005 | 게시물 CRUD | 게시물 생성·조회·수정·삭제 | P0 | MVP |

#### F-003. Refresh Token
- **사용자 스토리**: 로그인한 사용자로서, 나는 다시 로그인하지 않고 계속 서비스를 쓰고 싶다.
- **수용 기준**:
  - [ ] Given 유효한 refresh token, When `POST /auth/refresh`, Then 새 access token과 200
  - [ ] Given 만료되거나 폐기된 refresh token, When `POST /auth/refresh`, Then 401
  - [ ] Given 로그아웃, When 같은 refresh token으로 갱신 시도, Then 401
- **관련 항목**: API `API-003` · 데이터 `refresh_tokens`
- **Owner Folder**: `/src/auth`
````

---

### 예시 A — 루트 `README.md` (최상위, TOP 유형)

````markdown
# my-api — Overview

사용자 인증과 게시물 관리를 제공하는 REST API 서버입니다.

> 📄 기능 명세: [`SPEC.md`](./SPEC.md) — 기능 ID(F-xxx)와 수용 기준은 SPEC.md가 정의합니다.

---

## DFD — Level 0 (Context Diagram)

```mermaid
flowchart LR
    Client([Client]) -->|HTTP| API["my-api<br>(Level 0)"]
    API -->|query| DB[(PostgreSQL)]
    API -->|cache| Cache[(Redis)]
    API -->|response| Client
```

## Tech Stack
- Node.js 20 / Express 4 / TypeScript 5
- PostgreSQL 16, Redis 7

## Agent Control
### 금지
- 환경변수를 코드에 하드코딩 금지
- DB 직접 쿼리를 라우터에서 작성 금지 (Service 레이어 경유)
### 필수
- 새 외부 의존성 추가 시 이 DFD와 담당 하위 DFD 동시 업데이트

## Sub-folder Map
| 폴더 | DFD 레벨 | 담당 기능 ID |
|------|----------|--------------|
| `/src/auth` | Level 1 | F-001, F-002, F-003, F-004 |
| `/src/posts` | Level 1 | F-005 |

## Progress Tracker
| ID | Feature | Status | Owner Folder | Last Updated | Notes |
|----|---------|--------|--------------|--------------|-------|
| F-001 | JWT 발급 | ✅ Done | `/src/auth` | 2026-01-10 | RS256 |
| F-002 | JWT 검증 미들웨어 | ✅ Done | `/src/auth` | 2026-01-10 | |
| F-003 | Refresh Token | 🔄 In Progress | `/src/auth` | 2026-01-12 | Redis 연동 필요 |
| F-004 | OAuth Google | ⏳ Pending | `/src/auth` | - | |
| F-005 | 게시물 CRUD | ⏳ Pending | `/src/posts` | - | |

## Next Roadmap
1. F-003 Refresh Token 완성 → `/src/auth`
2. F-005 게시물 CRUD 구현 → `/src/posts`
````

---

### 예시 B — `src/auth/README.md` (하위, SUB 유형, Level 1)

````markdown
# auth — Overview

> **담당 기능**: `SPEC.md`의 `F-001`, `F-002`, `F-003`, `F-004`  
> (진행 상태는 루트 `README.md` Progress Tracker에서 관리)

JWT 발급/검증, Refresh Token, OAuth 콜백 처리를 담당합니다.

---

## Context — 상위 흐름과의 연결

```
루트(/) — Level 0 DFD
└─ [my-api] 버블
       │  입력: Client의 HTTP 인증 요청 (credentials, Bearer token)
       ▼
src/auth — Level 1 DFD (아래 상세)
       │  출력: access_token, decoded payload 또는 401
       ▼
Client, NextHandler
```

## DFD — Level 1 (Main Processes)

> Decomposed from: `/` Level 0 — `my-api` 버블

```mermaid
flowchart LR
    Client([Client]) -->|credentials| Login[LoginHandler]
    Login -->|verify| DB[(PostgreSQL)]
    DB -->|user record| Login
    Login -->|sign| JWT[JWTService]
    JWT -->|access_token| Client
    Client -->|Bearer token| Middleware[AuthMiddleware]
    Middleware -->|decoded payload| Next([NextHandler])
    Middleware -->|401| Client
    JWT -->|store| Cache[(Redis)]
```

## Tech Stack
- jsonwebtoken 9.x, bcrypt 5.x (상위 스택 외 추가분)

## Agent Control
> 상위 규칙 참조: `/README.md` — Agent Control
### 금지
- JWT secret 하드코딩 금지 (`process.env.JWT_SECRET` 사용)
- 비밀번호 평문 저장 금지
### 필수
- 새 엔드포인트 추가 시 이 DFD와 루트 Level 0 DFD 동시 업데이트
- 작업 완료 시 루트 `/README.md` Progress Tracker 업데이트
````

---

### 예시 C — `src/auth/handlers/README.md` (하위, SUB 유형, Level 2)

````markdown
# handlers — Overview

> **담당 기능**: `SPEC.md`의 `F-001`, `F-002` 중 HTTP 처리 부분  
> **분해 대상**: `src/auth` Level 1 DFD의 `LoginHandler`, `AuthMiddleware` 버블

HTTP 요청을 파싱해 인증 서비스로 위임하고 응답을 조립합니다.

---

## Context — 상위 흐름과의 연결

```
src/auth — Level 1 DFD
└─ [LoginHandler], [AuthMiddleware] 버블
       │  입력: req.body.credentials / req.headers.authorization
       ▼
src/auth/handlers — Level 2 DFD (아래 상세)
       │  출력: { access_token } / { payload } / 401 response
       ▼
Client, JWTService
```

## DFD — Level 2 (Detailed Processes)

> Decomposed from: `src/auth` Level 1 — `LoginHandler`, `AuthMiddleware` 버블

```mermaid
flowchart LR
    Req([HTTP Request]) --> Validate[Input Validator]
    Validate -->|valid| AuthService[[AuthService]]
    Validate -->|invalid| Error[ErrorFormatter]
    AuthService -->|token| Res([HTTP Response])
    AuthService -->|fail| Error
    Error --> Res
```

## Tech Stack
- express-validator 7.x (상위 스택 외 추가분)

## Agent Control
> 상위 규칙 참조: `src/auth/README.md` — Agent Control
### 금지
- 핸들러에서 비즈니스 로직 직접 작성 금지 (AuthService 위임)
### 필수
- 작업 완료 시 루트 `/README.md` Progress Tracker 업데이트
````
