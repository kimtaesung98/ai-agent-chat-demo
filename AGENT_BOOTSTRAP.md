# AGENT BOOTSTRAP — 최초 1회 읽고 삭제

> ⚠️ **이 파일은 일회용입니다.**  
> 에이전트는 이 파일을 읽은 즉시 아래 순서를 따르고, **마지막에 반드시 이 파일을 삭제**해야 합니다.  
> 이후 세션에서는 `CLAUDE.md`가 자동 로딩되고, `AGENT_STATE.md`로 맥락을 이어받습니다.

---

## 에이전트 실행 순서 (이 파일을 열었을 때)

```
1. 이 파일 전체를 읽는다
2. 루트 README.md → Progress Tracker · Next Roadmap 현재 상태 확인
3. SPEC.md 존재 여부 확인
     있으면 → §4.1 기능 목록과 Tracker의 ID·Feature가 일치하는지 확인, 불일치는 사용자에게 보고
     없으면 → templates/SPEC_TEMPLATE.md를 루트 SPEC.md로 복사하고 사용자에게 작성 요청
4. CLAUDE.md가 없으면 templates/CLAUDE_TEMPLATE.md를 복사해 루트에 CLAUDE.md 생성
5. templates/AGENT_STATE.md를 루트 AGENT_STATE.md로 복사하고 §4 지시대로 채운다
6. 이 파일(AGENT_BOOTSTRAP.md)을 삭제한다
7. 사용자에게 보고: "초기화 완료. CLAUDE.md + AGENT_STATE.md 생성. 이후 세션은 CLAUDE.md가 자동 로딩됩니다."
```

---

## §1. 이 프로젝트의 Blueprint Framework 적용 구조

> 사람이 이 파일을 프로젝트에 복사할 때 `[[ ]]`를 채웁니다.

```
[[ 프로젝트 루트 경로 ]]/
├── SPEC.md                    ← 기능 명세 · 수용 기준 (기능 ID의 원천)
├── README.md                  ← Level 0 DFD + Progress Tracker (소유자)
├── CLAUDE.md                  ← 세션 프로토콜 (자동 로딩)
├── AGENT_STATE.md             ← 세션 인계 파일 (이 파일 삭제 후 생성)
├── CONTRIBUTING.md            ← 에이전트 행동 강령
└── [[ 주요 폴더들 ]]/
    └── README.md              ← Level N DFD + Context (실행자, Tracker 없음)
```

**소유자 폴더** (Progress Tracker 보유): `[[ 경로 나열 ]]`  
**실행자 폴더** (DFD만 보유): `[[ 경로 나열 ]]`

---

## §2. DFD 레벨링 핵심 규칙 (요약)

| 레벨 | 정의 | 헤더 표기 |
|------|------|-----------|
| Level 0 | 소유자 폴더 — 시스템 전체, 외부 액터만 | `## DFD — Level 0 (Context Diagram)` |
| Level 1 | Level 0 버블을 분해한 폴더 | `## DFD — Level 1 (Main Processes)` |
| Level 2 | Level 1 버블 하나를 분해한 폴더 | `## DFD — Level 2 (Detailed Processes)` |
| Level 3+ | 함수 수준 | `## DFD — Level 3 (Function Level)` |

- **레벨 = 상위 README의 레벨 + 1** — 파일 시스템 깊이가 아님. README 없는 중간 폴더는 건너뜀
- 각 DFD는 `> Decomposed from: [상위 폴더] Level N — [버블명] 버블` 명시 필수
- 하위 DFD 외부 입출력 = 상위 DFD 해당 버블 화살표와 반드시 일치
- 새 외부 의존성 추가 시 Level N → N-1 → 0 순으로 상위 DFD 연쇄 업데이트

---

## §3. 이 프로젝트 전역 Agent Control (요약)

> 프로젝트 루트 README.md의 Agent Control에서 복사해 채우세요.  
> 초기화 시 에이전트가 이 내용을 AGENT_STATE.md Active Rules로 옮깁니다.

**허용:**
- [[ 전역 허용 규칙 ]]

**금지:**
- [[ 전역 금지 규칙 ]]

**필수:**
- 기능 작업 전 SPEC.md 해당 기능 ID의 수용 기준 확인
- 작업 완료마다 루트 README.md Progress Tracker 업데이트
- 구조 변경 시 해당 레벨부터 루트까지 DFD 연쇄 업데이트

---

## §4. AGENT_STATE.md 초기화 지시

`templates/AGENT_STATE.md`를 루트에 복사한 뒤(내용을 새로 쓰지 말고 **복사**), 아래만 채웁니다:

| 섹션 | 채우는 방법 |
|---|---|
| Current Focus | 루트 Next Roadmap의 첫 1~3개 항목 (기능 ID · 담당 폴더) |
| 누적 사용자 요구사항 | 비워 둠 |
| Active Rules | 위 §3의 금지·필수 규칙 중 핵심 3~7개 |
| Drift Status | 현재 README.md가 있는 폴더 목록 + 오늘 날짜 |
| 세션 로그 | 초기화 행 1개 (오늘 날짜) |

> 전체 Progress Tracker를 AGENT_STATE.md에 복사하지 않습니다. 루트 README.md가 유일한 원본입니다.

---

## 이 파일 삭제 확인

AGENT_STATE.md 생성이 완료되었으면 이 파일을 삭제하세요.  
삭제 명령: `rm AGENT_BOOTSTRAP.md` (또는 에디터에서 파일 삭제)

> 삭제 후 커밋하면 git에서도 제거됩니다.  
> 이후 세션에서는 절대 이 파일을 다시 만들지 않습니다.
