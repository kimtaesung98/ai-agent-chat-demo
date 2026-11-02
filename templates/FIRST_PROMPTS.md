# 프로젝트 유형별 첫 프롬프트 모음

> Claude Code 첫 세션에서 복사-붙여넣기해 사용하세요.  
> `[[ ]]` 부분만 프로젝트에 맞게 바꾸면 됩니다.  
> 아래 프롬프트들은 **루트 `SPEC.md`의 개요·기능 목록이 먼저 작성되어 있다**고 가정합니다.  
> 아직이라면 "SPEC.md 함께 작성하기" 프롬프트부터 시작하세요.

---

## SPEC.md 함께 작성하기 (코딩 전)

명세가 비어 있을 때 에이전트와 함께 채웁니다. 이 세션에서는 코드를 작성하지 않습니다.

```
이 프로젝트는 Blueprint Framework를 따릅니다. 오늘은 코드를 작성하지 않고 SPEC.md만 채운다.
프로젝트 설명: [[ 프로젝트 한 줄 설명 ]]
대상 사용자: [[ 사용자 ]]
꼭 있어야 하는 기능: [[ 기능 나열 ]]

1. SPEC.md §1 개요와 §2 범위(MVP / 이후 단계 / 비목표)를 초안으로 써줘.
2. §4.1 기능 목록을 F-001부터 ID를 붙여 만들고 우선순위를 제안해줘.
3. MVP 기능마다 §4.2 수용 기준을 Given/When/Then으로 제안해줘.
4. 결정이 필요한 것은 추측하지 말고 §16 미결 사항에 질문으로 남겨줘.
```

---

## 공통 — 신규 프로젝트 초기화

어떤 기술 스택이든 새 프로젝트를 시작할 때 사용합니다.

```
이 프로젝트는 Blueprint Framework를 따릅니다.
CLAUDE.md와 AGENT_BOOTSTRAP.md가 루트에 있으니 세션 시작 프로토콜을 먼저 실행해.

초기화가 끝나면:
1. SPEC.md §4.1 기능 목록과 같은 ID로 루트 README.md Progress Tracker를 초기화해.
2. SPEC.md §10 외부 연동을 반영해 루트 README.md의 Level 0 DFD를 작성해.
3. 기능별 Owner Folder를 제안하고 Sub-folder Map을 채워줘.
4. 첫 작업은 SPEC.md의 [[ F-001 ]]이야. 수용 기준을 읽고 구현 계획을 3줄로 요약해줘.
```

---

## React / Next.js 프론트엔드

```
이 프로젝트는 Blueprint Framework를 따르는 [[ React / Next.js ]] 프론트엔드입니다.
CLAUDE.md를 읽고 세션 시작 프로토콜을 실행해.

초기화 후 아래 구조로 폴더별 README.md를 생성해:

루트 README.md (Level 0 DFD):
- 외부 액터: User(브라우저), Backend API, CDN
- 시스템: 이 React 앱 전체

주요 폴더 (Level 1 DFD 각각 작성):
- /src/components  → UI 컴포넌트 렌더링 흐름 (Props → Component → DOM)
- /src/hooks       → 상태/사이드이펙트 흐름 (API 호출, 전역 상태 연동)
- /src/pages       → 라우팅 및 레이아웃 흐름
- /src/services    → API 클라이언트 추상화 흐름

Agent Control 전역 규칙:
- 비즈니스 로직을 컴포넌트에 직접 작성 금지 (hooks 또는 services로 분리)
- 전역 상태는 [[ Zustand / Redux / Context ]]만 사용

첫 번째 구현할 기능: SPEC.md의 [[ F-001 ]] (수용 기준을 읽고 구현 계획부터 요약해줘)
```

---

## Node.js REST API

```
이 프로젝트는 Blueprint Framework를 따르는 Node.js REST API입니다.
CLAUDE.md를 읽고 세션 시작 프로토콜을 실행해.

초기화 후 아래 구조로 폴더별 README.md를 생성해:

루트 README.md (Level 0 DFD):
- 외부 액터: Client(HTTP), [[ PostgreSQL / MongoDB ]], [[ Redis 등 ]]
- 시스템: 이 API 서버 전체

주요 폴더 (Level 1 DFD 각각 작성):
- /src/routes      → HTTP 요청 라우팅 흐름
- /src/controllers → 요청 파싱 및 응답 조립 흐름
- /src/services    → 비즈니스 로직 흐름
- /src/repositories → DB 접근 추상화 흐름
- /src/middlewares → 인증/검증/로깅 흐름

Agent Control 전역 규칙:
- routes에서 비즈니스 로직 직접 작성 금지
- DB 직접 쿼리는 repositories에서만
- 모든 에러는 중앙 에러 핸들러로 전달

첫 번째 구현할 기능: SPEC.md의 [[ F-001 ]] (수용 기준을 읽고 구현 계획부터 요약해줘)
```

---

## Python 데이터 파이프라인 / ML

```
이 프로젝트는 Blueprint Framework를 따르는 Python [[ 데이터 파이프라인 / ML ]] 프로젝트입니다.
CLAUDE.md를 읽고 세션 시작 프로토콜을 실행해.

초기화 후 아래 구조로 폴더별 README.md를 생성해:

루트 README.md (Level 0 DFD):
- 외부 액터: Raw Data Source([[ S3 / DB / CSV ]]), Output Sink([[ DB / 파일 / API ]])
- 시스템: 이 파이프라인 전체

주요 폴더 (Level 1 DFD 각각 작성):
- /src/ingestion   → 원시 데이터 수집 및 검증 흐름
- /src/processing  → 변환/정제 흐름
- /src/features    → 피처 엔지니어링 흐름 (ML인 경우)
- /src/models      → 모델 학습/추론 흐름 (ML인 경우)
- /src/export      → 결과 저장/전송 흐름

Agent Control 전역 규칙:
- 각 단계(ingestion/processing/export)는 독립 실행 가능해야 함
- 외부 서비스 접근은 각 폴더의 최상단 모듈에서만
- [[ pandas / polars / spark ]] 이외의 DataFrame 라이브러리 추가 금지

첫 번째 구현할 기능: SPEC.md의 [[ F-001 ]] (수용 기준을 읽고 구현 계획부터 요약해줘)
```

---

## 풀스택 (프론트엔드 + 백엔드 모노레포)

```
이 프로젝트는 Blueprint Framework를 따르는 풀스택 모노레포입니다.
CLAUDE.md를 읽고 세션 시작 프로토콜을 실행해.

초기화 후 아래 구조로 폴더별 README.md를 생성해:

루트 README.md (Level 0 DFD):
- 외부 액터: User(브라우저), [[ PostgreSQL ]], [[ 외부 서비스 ]]
- 시스템 경계: 이 모노레포 전체 (frontend + backend)

1단계 폴더 (Level 1 DFD 각각 작성):
- /frontend → 프론트엔드 서브시스템 (내부는 React 구조)
- /backend  → 백엔드 서브시스템 (내부는 Node.js API 구조)
- /shared   → 공통 타입/유틸리티 (Pure Function 원칙)

Agent Control 전역 규칙:
- /shared에는 외부 라이브러리 의존성 없는 순수 함수만
- frontend ↔ backend 직접 파일 import 금지 (shared 경유만 허용)
- DB 스키마 변경은 반드시 마이그레이션 파일로

첫 번째 구현할 기능: SPEC.md의 [[ F-001 ]] (수용 기준을 읽고 구현 계획부터 요약해줘)
```

---

## 기존 프로젝트 마이그레이션 시작

```
이 프로젝트는 기존 코드베이스에 Blueprint Framework를 적용합니다.
MIGRATION_GUIDE.md의 Phase 1을 따라 초기화해줘.

현재 프로젝트 정보:
- 기술 스택: [[ 스택 ]]
- 주요 폴더: [[ 폴더 나열 ]]
- 가장 자주 수정되는 폴더: [[ 폴더 ]]
- 알려진 미구현/개선 필요 항목: [[ 목록 ]]

Phase 1 작업:
1. 기존 폴더 구조를 분석해서 루트 README.md Level 0 DFD를 역공학으로 작성해
2. 구현된 기능과 위 미구현 항목으로 SPEC.md §4.1 기능 목록 초안(F-ID)을 만들고,
   같은 ID로 Progress Tracker를 채워줘 (수용 기준은 초안으로만 제안)
3. 루트 README.md의 Agent Control 전역 규칙을 이 코드베이스의 실제 패턴 기반으로 작성해
```

---

## 세션 재시작 (이미 초기화된 프로젝트)

Blueprint Framework가 이미 적용된 프로젝트의 후속 세션에서 사용합니다.

```
CLAUDE.md를 읽고 세션 시작 프로토콜을 실행해.
오늘 작업: [[ F-00X ]] [[ 요청 사항 ]]
```

> CLAUDE.md가 있으면 이것만으로 충분합니다. 에이전트가 AGENT_STATE.md를 읽고 맥락을 복원합니다.
