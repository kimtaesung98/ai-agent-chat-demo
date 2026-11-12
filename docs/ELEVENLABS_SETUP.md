# ElevenLabs Agents 실시간 음성 설정 (F-022)

> 앱의 음성 대화를 ElevenLabs Agents(실시간 음성)로 바꾸는 설정입니다. 구조는 `ARCHITECTURE.md` ADR-025.
> 설정하지 않으면 앱은 지금처럼 기기 음성(음성 인식·읽어 주기)으로 대화합니다.

```
앱 ── POST /api/voice/token ──▶ chatd ── xi-api-key ──▶ ElevenLabs      (앱은 짧게 쓰는 토큰만 받음)
앱 ◀═══ WebRTC 실시간 음성 ═══▶ ElevenLabs
                                 └─ POST /v1/chat/completions (Bearer 비밀값) ──▶ chatd ──▶ Claude
                                    (페르소나·기억으로 서버가 프롬프트를 만듦)
```

**비밀값 세 가지는 채팅·코드·Git에 넣지 말고, chatd를 띄우는 터미널(또는 배포 때 SSM)에만 넣어 주세요.**

| 환경변수 | 어디서 | 설명 |
|---|---|---|
| `ELEVENLABS_API_KEY` | ElevenLabs → Developers → API Keys | 대화 토큰 발급용. 권한은 Agents(ElevenAgents) 읽기면 충분 |
| `ELEVENLABS_AGENT_ID` | 아래 1번에서 만든 에이전트 | `agent_…` 형태 |
| `ELEVENLABS_LLM_SECRET` | 직접 만듦: `openssl rand -hex 24` | ElevenLabs가 우리 서버를 부를 때 보내는 비밀값 (16자 이상) |
| `ANTHROPIC_API_KEY` | (기존) | 없으면 모의 답으로 대화됨 — 연결 확인에 좋음 |

---

## 1. chatd를 공개 HTTPS 주소로 열기

ElevenLabs 서버가 우리 `chatd`를 불러야 하므로 인터넷에서 닿는 HTTPS 주소가 필요합니다. 로컬 알파테스트는 Cloudflare 일회용 터널이 가장 쉽습니다 (계정 불필요).

```bash
# 터미널 1 — 서버
cd server
export ELEVENLABS_LLM_SECRET=$(openssl rand -hex 24); echo "$ELEVENLABS_LLM_SECRET"   # 2번에서 한 번 씀
export ELEVENLABS_API_KEY=...        # ElevenLabs API 키
export ELEVENLABS_AGENT_ID=...       # 2번에서 만든 뒤 넣고 다시 실행
export ANTHROPIC_API_KEY=...         # 없으면 모의 모드
STATIC_DIR=../app/build/web go run ./cmd/chatd
# 시작 로그에 "실시간 음성: ElevenLabs Agents 켜짐"이 보여야 함

# 터미널 2 — 터널 (brew install cloudflared)
cloudflared tunnel --url http://localhost:3000
# → https://<무작위>.trycloudflare.com 주소가 나옴. 터널을 다시 켜면 주소가 바뀌니 2번의 URL도 바꿔야 함
```

배포(F-014) 때는 SSM Parameter Store에 `/chatd/elevenlabs-api-key`, `/chatd/elevenlabs-agent-id`, `/chatd/elevenlabs-llm-secret`(SecureString)을 넣으면 `deploy/run-chatd.sh`가 켭니다. Cloudflare Access 뒤라면 `/v1/chat/completions` 경로는 Access 예외(Bypass)로 두고 Bearer 비밀값으로만 막습니다 (R-A14).

## 2. ElevenLabs에서 에이전트 만들기

ElevenLabs 웹 → **Agents** → **New agent** → Blank(빈 에이전트). 아래만 바꾸고 **Publish**.

| 위치 | 값 |
|---|---|
| Agent → Language | Korean |
| Agent → First message | `안녕하세요, {{persona_name}}예요. 오늘은 어떻게 지내셨어요?` (`persona_name`은 앱이 지금 페르소나 이름을 넣어 줌) |
| Agent → System prompt | `대화 지시는 서버가 정합니다.` — 아무 문장이나 괜찮아요. 우리 서버가 이 프롬프트를 버리고 페르소나·기억으로 다시 만듭니다 |
| Agent → LLM | **Custom LLM** |
| Custom LLM → Server URL | `https://<1번 터널 주소>/v1` (ElevenLabs가 뒤에 `/chat/completions`를 붙입니다. 화면이 전체 경로를 요구하면 `…/v1/chat/completions`) |
| Custom LLM → Model ID | 아무 이름 (예: `claude-via-chatd`) — 실제 모델은 서버의 `ANTHROPIC_MODEL` |
| Custom LLM → API key | **Create new secret** → 값에 1번의 `ELEVENLABS_LLM_SECRET` (Bearer로 보내집니다) |
| Voice | 한국어를 잘 읽는 다국어 목소리 (어르신용은 차분하고 느린 목소리, Speed 0.9 정도) |
| Security → Enable authentication | **켬** — 서버가 발급한 토큰으로만 연결됨 |
| Security → Overrides | 모두 꺼 둠 (쓰지 않음) |
| Advanced → Max conversation duration | 길게 (예: 1800초). 끊겨도 앱이 다시 연결합니다 |
| Privacy (있으면) | 대화 기록·녹음 보존을 끄거나 짧게 — 대화 원문은 남기지 않는 것이 이 프로젝트 원칙 (SPEC §11) |

만든 에이전트의 ID(`agent_…`)를 `ELEVENLABS_AGENT_ID`로 넣고 chatd를 다시 실행합니다.

## 3. 앱 빌드·실행

실시간 음성은 **Android·iOS 앱**에서만 씁니다 (웹은 기기 음성). 앱은 토큰만 chatd에서 받으므로 지금처럼 같은 Wi-Fi 주소를 써도 되고, 터널 주소(HTTPS)를 써도 됩니다.

```bash
cd app
flutter build apk --profile --dart-define=API_BASE_URL=https://<터널 주소>   # 또는 http://<맥 LAN IP>:3000
```

폰에서 앱 → 미소 선택 → 음성 대화. 처음 한 번 마이크 권한을 허용합니다.

## 4. 확인 (F-022 AC8)

- [ ] 시작 로그에 "실시간 음성: ElevenLabs Agents 켜짐"
- [ ] 음성 화면을 열면 "연결하고 있어요" 뒤 첫 인사가 들리고, 말하면 바로 답한다
- [ ] 답하는 중에 말하면 멈추고 듣는다 (끼어들기)
- [ ] 와이파이를 잠깐 끄고 켜면 "다시 연결하고 있어요" 뒤 이어서 대화된다
- [ ] 대화 끝내기 → 다시 음성 대화 → 지난번 이야기를 기억한다 (F-019)
- [ ] chatd를 ElevenLabs 설정 없이 띄우면 같은 화면이 기기 음성으로 동작한다

## 문제 해결

| 증상 | 확인 |
|---|---|
| 계속 "기기 음성으로 대화할게요" | `/api/config`의 `voiceAgent`가 `elevenlabs`인지, chatd 로그에 `voice agent token error`가 있는지 (키·에이전트 ID 확인) |
| 연결은 되는데 답이 없음 | ElevenLabs 대화 기록(Conversations)에서 LLM 오류 확인. chatd 로그에 `/v1/chat/completions` 401이면 비밀값 불일치, 404면 `ELEVENLABS_LLM_SECRET` 미설정, 요청이 아예 없으면 터널 주소 확인 |
| 첫 인사가 `{{persona_name}}` 그대로 | 앱이 아닌 ElevenLabs 화면에서 테스트한 경우 — 테스트 화면의 dynamic variable에 값을 넣어 주세요 |
| 목소리가 영어 억양 | Language를 Korean으로, 다국어 목소리·모델 선택 |
