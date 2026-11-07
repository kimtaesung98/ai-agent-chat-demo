# Blueprint Framework — Project Rules

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
| 무엇으로, 어떤 구조로? 왜? | `ARCHITECTURE.md` (기술 스택 · 모듈 · 의존 규칙 · ADR) |
| 얼마나 됐나? 다음은? | 루트 `README.md` Progress Tracker · Next Roadmap |
| 폴더 안에서 어떻게 흐르나? 무엇이 금지인가? | 각 폴더 `README.md` DFD · Agent Control |
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

**구조** (`ARCHITECTURE.md` — 세션마다 읽지 않고, 아래 작업 때 해당 절만)
- 라이브러리 추가·버전 변경 → §2 확인. **허용 목록에 없으면 추가하지 않고 제안**
- 새 모듈·폴더, 다른 모듈 import → §3 모듈 맵·의존 규칙 확인. 규칙을 어기는 import 금지
- 설정·환경변수·배포 변경 → §6 · 공통 처리(오류·로그·인증) 변경 → §7
- 기존 ADR과 다른 방식이 필요하면 코드보다 먼저 §9에 "제안" ADR을 추가하고 사용자에게 묻는다

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

- 실행: `npm start` (키 없으면 모의 모드) · 테스트: `npm test` (네트워크 없이 통과해야 함) · 계약 테스트: `npm run test:contract` / `npm run test:contract:go` (Go 1.25+, 모의 모드 Node·Go 서버) · Go: `server/`에서 `go test ./...` · Flutter: `app/`에서 `flutter analyze` · `flutter test`
- 현재 Node MVP: 외부 npm 패키지 추가 금지 — 기본 모듈만 (ARCHITECTURE.md ADR-001)
- 목표 스택은 Go 서버 + Flutter 클라이언트 (ADR-005·006). C/C++·cgo 사용 안 함 (ADR-007). Go·Flutter 코드는 ARCHITECTURE.md §10 단계가 SPEC.md에 등록된 뒤에만 작성
- `ANTHROPIC_API_KEY`를 코드·로그·응답·테스트 픽스처에 넣지 않음
- 테스트 이름에 기능 ID와 AC 번호 포함 (예: `F-001 AC3 ...`)
- 테스트는 모의 제공자 또는 가짜 업스트림 서버로 작성, 실제 Claude API 호출 금지

---

## 상세 문서 위치

| 문서 | 내용 |
|------|------|
| `AGENT_STATE.md` | 현재 집중 작업 · 누적 요구사항 · 세션 로그 |
| `SPEC.md` | 기능 명세 · 수용 기준 (기능 ID 블록 단위로 읽음) |
| `ARCHITECTURE.md` | 기술 스택 · 모듈 구조 · ADR · 전환 계획 (작업 종류별로 해당 절만 읽음) |
| `BLUEPRINT.md` | 프레임워크 전체 명세 (세션 중 읽지 않음) |
| `CONTRIBUTING.md` | 상세 프로토콜 · DFD 드리프트 감지 · 팀 규칙 (세션 중 읽지 않음) |
