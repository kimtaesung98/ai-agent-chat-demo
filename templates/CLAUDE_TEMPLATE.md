# Blueprint Framework — Project Rules

> 이 파일은 프로젝트 루트에 `CLAUDE.md`로 복사해 사용합니다.  
> Claude Code는 이 파일을 **매 세션 자동으로 읽습니다** — 짧고 최신 상태로 유지하세요.

---

## 세션 시작 프로토콜 (매번 실행)

```
AGENT_BOOTSTRAP.md 존재?
    YES → AGENT_BOOTSTRAP.md의 지시대로 초기화 (최초 1회)
    NO  → AGENT_STATE.md 전체 읽기
              ↓
         Current Focus 확인 (이어받을 기능 ID)
         Resolved Requirements 확인 (중복 작업 방지)
         Active Rules 확인 (이번 세션 제약)
              ↓
         루트 README.md Progress Tracker · Next Roadmap 확인
```

---

## 문서 역할 (같은 정보를 두 곳에 쓰지 않는다)

| 질문 | 정의 위치 |
|---|---|
| 무엇을 만드나? 언제 완료인가? | `SPEC.md` (기능 ID · 수용 기준) |
| 얼마나 됐나? 다음은? | 루트 `README.md` Progress Tracker · Next Roadmap |
| 어떻게 흐르나? 무엇이 금지인가? | 각 폴더 `README.md` DFD · Agent Control |
| 지난 세션에서 무엇을 했나? | `AGENT_STATE.md` |

---

## 핵심 규칙 (모든 세션에 적용)

**작업 순서**
1. 루트 README.md Tracker → 작업할 기능 ID와 Owner Folder 확인
2. `SPEC.md` → **해당 기능 ID 블록만** 읽고 수용 기준 확인 (전체를 읽지 않음)
3. Owner Folder `README.md` → Context · DFD · Agent Control 확인
4. 코드 작업 → 수용 기준 확인
5. 루트 Tracker 업데이트 → AGENT_STATE.md 갱신

**명세**
- SPEC.md에 없는 기능은 구현하지 않고 먼저 사용자에게 제안
- 명세가 모호하면 추측하지 말고 SPEC.md §16 미결 사항에 기록 후 질문
- 수용 기준을 모두 통과해야 `✅ Done`

**폴더 구조**
- Progress Tracker · Roadmap은 **소유자(최상위) 폴더 README.md에만** 존재
- 하위 폴더 README.md는 `Context` + `DFD` + `Agent Control`만 보유
- 작업할 폴더에 README.md가 없으면 `templates/README_TEMPLATE_SUB.md`로 그때 생성 (미리 전부 만들지 않음)

**DFD**
- 레벨 = 상위 README의 레벨 + 1 (파일 시스템 깊이가 아님). 소유자 = Level 0
- 모든 하위 DFD에 `> Decomposed from: [상위 폴더] Level N — [버블명] 버블` 명시
- 하위 DFD 외부 입출력 = 상위 DFD 해당 버블 화살표와 일치

---

## 세션 종료 시 필수 갱신

- [ ] 루트 README.md Progress Tracker 갱신
- [ ] AGENT_STATE.md Current Focus · 세션 로그 갱신
- [ ] 구조 변경 시 DFD 연쇄 업데이트 (하위 → 루트)

---

## 이 프로젝트 전용 규칙

<!-- 프로젝트마다 꼭 지켜야 할 규칙 3~7개만. 상세 규칙은 각 폴더 README.md Agent Control에 둡니다 -->

- [[ 예: 패키지 매니저는 pnpm만 사용 ]]
- [[ 예: 테스트 실행 명령: pnpm test ]]

---

## 상세 문서 위치

| 문서 | 내용 |
|------|------|
| `AGENT_STATE.md` | 현재 집중 작업 · 누적 요구사항 · 세션 로그 |
| `SPEC.md` | 기능 명세 · 수용 기준 (기능 ID 블록 단위로 읽음) |
| `BLUEPRINT.md` | 프레임워크 전체 명세 (세션 중 읽지 않음) |
| `CONTRIBUTING.md` | 상세 프로토콜 · DFD 드리프트 감지 · 팀 규칙 (세션 중 읽지 않음) |
