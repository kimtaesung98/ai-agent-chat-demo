# 로컬 알파테스트 가이드

> 대상: 내 Mac(Apple Silicon)에서 Go 서버 + Flutter 웹 화면을 띄워 텍스트·음성 대화를 직접 확인하는 사람.  
> 기준 커밋: `main` (PR #6 병합 후, F-012 음성 대화 포함). 기능 상태는 루트 `README.md` Progress Tracker가 원본입니다.  
> 2026-11-10 확인: Go 1.25 · Flutter 3.47.9로 이 문서 그대로 빌드·실행, `go test ./...` · `flutter test`(65개) · 계약 테스트 통과, 모의 모드 스트리밍과 화면 확인, 잘못된 키로 인증 오류 문구 확인. **실제 키로 정상 답을 받는 것은 아직 확인 전.**

---

## 0. 지금 무엇을 테스트할 수 있나

| 기능 | 상태 | 알파테스트에서 할 일 |
|---|---|---|
| F-001 실시간 스트리밍 채팅 | ✅ | 글자가 만들어지는 대로 보이는지 |
| F-002 대화 맥락 유지 · 새 대화 | ✅ | 앞 질문을 기억하는지, 새 대화 버튼 |
| F-003 응답 중단 | ✅ | 답하는 중 중단 버튼 |
| F-012 음성 대화 | 🔄 (AC8만 남음) | **실제 마이크로 3턴 + 끼어들기** — 이 테스트가 끝나야 ✅ |
| 실제 Claude 모드 | ⚠️ 자동 테스트만 | **실제 API 키로 답이 오는지** — 아직 아무도 확인 안 함 |
| F-005 페르소나 설정 | ⏳ 미구현 | 테스트 불가 (Phase 2). 지금은 고정 시스템 프롬프트만 |
| F-004 오류 재시도 · F-007 기록 저장 · F-008 로그인 | ⏳ 미구현 | 새로고침하면 대화가 사라지는 게 정상 |

---

## 1. 준비물

| 항목 | 버전 | 확인 명령 | 없을 때 |
|---|---|---|---|
| Go | **1.25 이상** (`server/go.mod`) | `go version` | `brew install go` (1.24 이하면 `GOTOOLCHAIN=auto`를 앞에 붙이면 자동으로 받아요) |
| Flutter | **3.47.9** (CI와 같은 버전) | `flutter --version` | https://docs.flutter.dev/get-started/install/macos |
| Chrome 또는 Edge | 최신 | — | 음성 인식(Web Speech API)은 이 두 브라우저에서만 확인 |
| Anthropic API 키 | — | — | 없어도 됩니다 (모의 모드). 실제 답을 보려면 필요 → §4 |
| 이어폰 | — | — | 권장. 스피커로 들으면 마이크가 답 소리를 다시 들을 수 있어요 (R-A09) |

필요한 계정·서버는 **Anthropic 콘솔 계정(API 키) 하나뿐**입니다. 별도 서버, DB, 클라우드 배포는 필요 없습니다 — 모두 내 컴퓨터의 `localhost:3000`에서 돕니다.

---

## 2. 코드 받기

```bash
cd ~/ai-agent-chat-demo          # 이미 클론돼 있으면
git checkout main && git pull
# 처음이면: git clone https://github.com/kimtaesung98/ai-agent-chat-demo.git ~/ai-agent-chat-demo
```

---

## 3. 모의 모드로 먼저 실행 (키 없이, 약 3분)

모의 모드는 Claude 대신 정해진 답을 스트리밍합니다. 화면·음성 흐름 확인용입니다.

```bash
# 3-1. Flutter 웹 빌드 (처음 한 번, 코드를 바꿀 때마다 다시)
cd ~/ai-agent-chat-demo/app
flutter pub get
flutter build web --no-web-resources-cdn

# 3-2. Go 서버 실행 (빌드한 웹 화면을 같이 제공)
cd ~/ai-agent-chat-demo/server
STATIC_DIR=../app/build/web go run ./cmd/chatd
```

터미널에 아래 두 줄이 보이면 성공입니다.

```
{"level":"INFO","msg":"모드: 모의(mock) — ANTHROPIC_API_KEY가 없어 모의 응답을 사용합니다","provider":"mock",...}
{"level":"INFO","msg":"AI Agent Chat → http://localhost:3000","static_dir":"../app/build/web"}
```

Chrome에서 **http://localhost:3000** 을 엽니다. 오른쪽 위 배지가 **모의 모드**로 보이면 정상입니다 (`서버 연결 안 됨`이면 서버가 꺼진 것). 끄려면 터미널에서 `Ctrl+C`.

> `localhost`는 브라우저가 보안 출처로 취급해서 마이크 권한을 받을 수 있어요. 같은 와이파이의 다른 기기에서 `http://192.168.x.x:3000`으로 열면 마이크가 막힙니다 (HTTPS 필요).

---

## 4. 실제 Claude 모드로 실행

1. https://console.anthropic.com → **API Keys** → 새 키 생성 (결제 수단 등록 필요). `sk-ant-...`로 시작합니다.
2. 키는 **터미널 환경변수로만** 넣습니다. 코드·채팅·깃에 붙여 넣지 마세요.

```bash
cd ~/ai-agent-chat-demo/server
export ANTHROPIC_API_KEY='sk-ant-...'        # 이 터미널 창에서만 유효
# export ANTHROPIC_MODEL=claude-sonnet-5-5   # 기본값. 바꾸고 싶을 때만
STATIC_DIR=../app/build/web go run ./cmd/chatd
```

시작 로그가 `"msg":"모드: Claude — 모델 claude-sonnet-5-5","provider":"anthropic"`이고, 화면 배지가 **Claude · claude-sonnet-5-5**이면 Claude 모드입니다. 키는 로그에 찍히지 않습니다.

매번 입력하기 귀찮으면 저장소 밖에 파일을 두고 불러오세요 (`.env`는 `.gitignore`에 있지만, 서버가 자동으로 읽지는 않습니다).

```bash
echo "export ANTHROPIC_API_KEY='sk-ant-...'" > ~/keys/anthropic.env && chmod 600 ~/keys/anthropic.env
source ~/keys/anthropic.env
```

---

## 5. 환경변수 요약

| 변수 | 기본값 | 설명 |
|---|---|---|
| `ANTHROPIC_API_KEY` | (없음) | 있으면 Claude 모드, 없으면 모의 모드 |
| `ANTHROPIC_MODEL` | `claude-sonnet-5-5` | Claude 모드에서 쓸 모델 |
| `PORT` | `3000` | 서버 포트 (1~65535, 잘못되면 기동 중단) |
| `STATIC_DIR` | `./web` | 화면 파일 폴더 — Flutter 웹 빌드 `../app/build/web` |

---

## 6. 알파테스트 체크리스트

결과를 표에 ✅/❌와 메모로 적어 알려 주세요.

### A. 텍스트 대화 (모의 모드 → Claude 모드 각각)

| # | 할 일 | 기대 결과 |
|---|---|---|
| A1 | "안녕" 입력 후 Enter | 답이 한 글자씩 흘러나옴 |
| A2 | "내 이름은 ○○야" → "내 이름이 뭐지?" | (Claude 모드) 이름을 기억 |
| A3 | 긴 답을 부탁한 뒤 중단 버튼 | 즉시 멈추고 다시 입력 가능 |
| A4 | 새 대화 버튼 | 화면이 비고, 앞 내용을 기억하지 않음 |
| A5 | 빈 칸으로 Enter | 아무 일도 안 일어남 |

### B. 음성 대화 (F-012 AC8 — Chrome과 Edge 각각, 이어폰 권장)

| # | 할 일 | 기대 결과 |
|---|---|---|
| B1 | 마이크 버튼 → 브라우저 권한 허용 | 듣는 중 표시, 말하는 내용이 미리 보기로 보임 |
| B2 | 말하고 멈춤 | 약 1.2초 뒤 버튼 없이 자동 전송 |
| B3 | 답 듣기 | 첫 문장이 완성되자마자 읽기 시작, 다 읽으면 다시 듣기 |
| B4 | 손대지 않고 3턴 주고받기 | 끊기지 않고 이어짐 |
| B5 | 읽는 중에 말하기 (끼어들기) | 읽기를 멈추고 새 질문을 들음 |
| B6 | 스피커로 B3 반복 (이어폰 없이) | 답 소리를 내 말로 착각하는지 (에코) 메모 |
| B7 | 느낌 | 끝맺음 대기(1.2초)가 짧다/길다, 목소리 품질, 답 길이 |

---

## 7. 자주 생기는 문제

| 증상 | 원인 · 해결 |
|---|---|
| `go: go.mod requires go >= 1.25` | Go를 올리거나 `GOTOOLCHAIN=auto go run ./cmd/chatd` |
| 브라우저에 404 / 빈 화면 | `flutter build web`을 안 했거나 `STATIC_DIR` 경로가 틀림 (`server/`에서 실행했는지 확인) |
| `address already in use` | 3000 포트 사용 중 → `PORT=3001`로 실행하고 `localhost:3001` |
| "AI 서비스 인증에 실패했어요. 운영자에게 API 키 설정을 확인해 달라고 알려 주세요." | 키 오타·만료·삭제. 콘솔에서 키를 다시 만들어 `export` |
| 크레딧·한도 관련 오류 | 콘솔 → Billing에서 결제 수단·크레딧 확인 |
| 마이크 버튼이 안 보이거나 반응 없음 | Chrome/Edge가 아님, 권한 거부(주소창 왼쪽 자물쇠 → 마이크 허용), macOS 설정 → 개인정보 보호 → 마이크에서 Chrome 허용 |
| 처음 한글이 잠깐 깨짐 | 한글 폰트를 실행 중에 `fonts.gstatic.com`에서 받음 (R-A08). 오프라인이면 글자가 네모로 보일 수 있음 |
| 코드를 바꿨는데 화면이 그대로 | `flutter build web` 다시, 브라우저 강력 새로고침(`Cmd+Shift+R`) |

---

## 8. 개발자용 확인 명령 (선택)

```bash
cd ~/ai-agent-chat-demo/server && go test ./...          # Go 단위 + HTTP 계약 테스트 (네트워크·키 없음)
cd ~/ai-agent-chat-demo/app && flutter analyze && flutter test
```
