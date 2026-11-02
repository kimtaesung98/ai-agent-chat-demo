# 기존 프로젝트 마이그레이션 가이드

> 코드가 이미 존재하는 프로젝트에 Blueprint Framework를 적용하는 단계별 가이드입니다.  
> 새 프로젝트라면 이 파일 대신 `README_TEMPLATE_TOP.md`부터 시작하세요.

---

## 마이그레이션 전략: 점진적 적용 (Top-Down)

한 번에 모든 폴더를 바꾸려 하지 마세요.  
**루트부터 시작해 한 단계씩 내려가며** 적용합니다.

```
Phase 1 ── 루트 세팅 (1~2시간)
Phase 2 ── 주요 모듈 README 작성 (모듈당 30분)
Phase 3 ── 하위 폴더 확장 (점진적)
```

---

## Phase 1 — 루트 세팅

### Step 1-1. 현재 구조 파악

Claude Code에 다음 프롬프트를 입력하세요:

```
이 프로젝트의 폴더 구조를 분석해서 다음을 알려줘:
1. 주요 도메인/모듈 목록 (최대 7개)
2. 외부 의존성 목록 (DB, 외부 API, 메시지큐 등)
3. 주요 데이터 흐름 (어디서 들어와서 어디로 나가는지)
```

### Step 1-2. 루트 README.md 생성

`templates/README_TEMPLATE_TOP.md`를 복사해 루트에 `README.md`를 만듭니다.

- **DFD Level 0**: Step 1-1에서 파악한 외부 의존성과 시스템 경계를 그립니다
- **Progress Tracker**: 현재 구현된 기능을 `✅ Done`으로, 알려진 미구현/개선 항목을 `⏳ Pending`으로 채웁니다.  
  SPEC.md가 아직 없으면 ID를 `T-001`처럼 임시로 붙입니다 (Step 1-3에서 `F-`로 교체)
- **Sub-folder Map**: 주요 모듈 폴더를 나열합니다

> 처음부터 완벽하지 않아도 됩니다. DFD는 에이전트가 코드를 읽으며 보완합니다.

### Step 1-3. SPEC.md 작성 (최소 범위)

`templates/SPEC_TEMPLATE.md`를 복사해 루트에 `SPEC.md`를 만듭니다.  
기존 프로젝트는 전부 채우려 하지 말고 아래만 작성합니다:

- §1 개요, §4.1 기능 목록 (Tracker 항목을 `F-` ID로 옮김)
- **앞으로 작업할 기능**의 §4.2 수용 기준 (이미 끝난 기능은 생략 가능)

역공학 프롬프트:

```
이 코드베이스를 분석해서 SPEC.md §4.1 기능 목록 초안을 만들어줘.
이미 구현된 기능과 미완성 기능을 구분하고, 루트 README.md Tracker의 임시 ID(T-xxx)를 F-xxx로 바꿔줘.
수용 기준은 내가 확인할 수 있게 초안으로만 제안해줘.
```

### Step 1-4. CLAUDE.md 설치

`templates/CLAUDE_TEMPLATE.md`를 복사해 프로젝트 루트에 `CLAUDE.md`로 저장합니다.  
"이 프로젝트 전용 규칙" 섹션의 `[[ ]]`를 이 프로젝트에 맞게 채웁니다.

### Step 1-5. AGENT_BOOTSTRAP.md 설치

`templates/AGENT_BOOTSTRAP.md`를 복사해 루트에 저장합니다.  
§1~§3을 이 프로젝트 구조로 채웁니다.

**Phase 1 완료 기준**: 루트에 `README.md`, `SPEC.md`, `CLAUDE.md`, `AGENT_BOOTSTRAP.md` 네 파일 존재

---

## Phase 2 — 주요 모듈 README 작성

우선순위가 높은 폴더부터 `templates/README_TEMPLATE_SUB.md`를 복사해 README.md를 만듭니다.

### 우선순위 결정 기준

```
에이전트가 자주 수정하는 폴더    → 먼저
버그가 자주 발생하는 폴더        → 먼저
여러 모듈이 의존하는 공통 모듈   → 먼저
거의 변경되지 않는 폴더         → 나중에
```

### DFD 역공학 프롬프트

각 폴더에 README.md를 만들 때 Claude Code에 다음 프롬프트를 입력하세요:

```
[폴더 경로]의 코드를 분석해서 README.md를 작성해줘.
- 이 폴더로 들어오는 데이터와 나가는 데이터를 DFD로 그려줘
  (레벨 = 상위 README의 레벨 + 1, README 없는 중간 폴더는 건너뜀)
- 담당 기능 줄에 이 폴더가 구현하는 기능 ID(F-xxx)를 연결해줘
- Agent Control은 이 폴더 코드에서 발견된 실제 패턴을 기반으로 작성해줘
```

**Phase 2 완료 기준**: 에이전트가 자주 접근하는 상위 3~5개 폴더에 README.md 존재

---

## Phase 3 — 하위 폴더 확장

에이전트가 실제로 작업을 수행할 때 README.md가 없는 폴더를 발견하면  
그 시점에 즉시 생성합니다. 미리 모두 만들 필요 없습니다.

이 규칙은 `CONTRIBUTING.md §2`(작업 중 6번)와 `CLAUDE.md` 핵심 규칙에 포함되어 있습니다:  
*"작업할 폴더에 README.md가 없으면 `templates/README_TEMPLATE_SUB.md`로 즉시 생성"*

---

## 마이그레이션 체크리스트

### Phase 1 완료 여부

- [ ] 루트 `README.md` 존재 (Level 0 DFD + Progress Tracker)
- [ ] `SPEC.md` 존재 (기능 목록 + 앞으로 작업할 기능의 수용 기준), Tracker ID와 일치
- [ ] `CLAUDE.md` 존재 (세션 자동 로딩용)
- [ ] `AGENT_BOOTSTRAP.md` 존재 (최초 에이전트 세션용)
- [ ] `CONTRIBUTING.md` 존재
- [ ] `BLUEPRINT.md` 존재

### Phase 2 완료 여부

- [ ] 주요 모듈 폴더 3개 이상에 README.md 존재
- [ ] 각 README.md에 `Decomposed from:` 명시
- [ ] 루트 `Sub-folder Map`에 각 폴더 등록

### 마이그레이션 완료 기준

에이전트에게 다음 질문을 해보세요:

```
이 프로젝트에서 [기능 ID]를 수정하려면 어느 폴더를 봐야 하고,
완료 기준은 무엇이며, 무엇이 허용/금지되어 있고, 현재 진행 상태는 어떻게 돼?
```

에이전트가 `AGENT_STATE.md`, 루트 `README.md`, `SPEC.md`의 해당 기능 블록, 해당 폴더 `README.md`만 읽고 정확히 답할 수 있으면 마이그레이션 완료입니다.

---

## 자주 발생하는 문제

### "기존 코드가 DFD와 맞지 않는다"

괜찮습니다. **코드가 진실, DFD는 설명**입니다.  
코드를 기준으로 DFD를 그리세요. DFD를 맞추려고 코드를 바꾸지 마세요.

### "폴더가 너무 많아서 다 못 만들겠다"

Phase 3 원칙을 따르세요: 에이전트가 접근할 때 그때그때 만듭니다.  
지금 당장 모든 폴더에 README.md가 없어도 프레임워크는 작동합니다.

### "Progress Tracker에 뭘 넣어야 할지 모르겠다"

현재 이슈 트래커(GitHub Issues, Jira 등)의 열린 항목을 그대로 옮기세요.  
없다면 에이전트에게 물어보세요: *"이 코드베이스에서 명백히 미완성이거나 개선이 필요한 부분을 찾아줘"*
