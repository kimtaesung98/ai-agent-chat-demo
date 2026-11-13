# OpenAI Realtime 음성 대화 설정·폰 확인 (F-024)

> 구조: ARCHITECTURE.md ADR-026 · 기능: SPEC.md F-024 · API: SPEC.md API-007

브라우저가 OpenAI GPT Realtime과 **WebRTC로 직접** 대화합니다. 서버(`chatd`)는 페르소나·기억·대화 내역으로 지시문을 만들어
**임시 키**에 담아 줄 뿐이라, OpenAI API 키와 프롬프트 틀은 서버에만 있습니다.

```
브라우저 ── POST /api/voice/session (페르소나·기억·내역) ──▶ chatd ── OPENAI_API_KEY + 지시문 ──▶ OpenAI
브라우저 ◀══════════════ WebRTC 음성 (임시 키, 10분 안에 연결) ══════════════▶ OpenAI Realtime
```

## 1. 서버 켜기

```bash
cd app && flutter build web --no-web-resources-cdn && cd ..
cd server
OPENAI_API_KEY=sk-... STATIC_DIR=../app/build/web go run ./cmd/chatd
# 글 채팅도 Claude로: ANTHROPIC_API_KEY=sk-ant-... 를 함께 (Q-008 — 지금은 글 채팅·요약은 Claude)
```

시작 로그에 `실시간 음성: OpenAI Realtime 켜짐`이 보이고, `GET /api/config`의 `voiceAgent`가 `"openai"`면 됩니다.
키는 터미널·SSM에만 두고 코드·채팅·로그에 붙이지 마세요.

| 환경변수 | 기본값 | 설명 |
|---|---|---|
| `OPENAI_API_KEY` | (없음) | 없으면 실시간 음성이 꺼지고 웹은 기기 음성으로 대화 |
| `OPENAI_REALTIME_MODEL` | `gpt-realtime` | 실시간 모델 |
| `OPENAI_REALTIME_VOICE` | `marin` | 목소리 (`cedar`도 추천) |
| `OPENAI_TRANSCRIBE_MODEL` | `gpt-4o-transcribe` | 자막용 입력 전사 모델 |

## 2. 컴퓨터에서 먼저 확인

Chrome으로 `http://localhost:3000` → 로그인 → 음성 화면. `localhost`는 HTTPS가 아니어도 마이크를 쓸 수 있습니다.

## 3. 폰에서 확인 (HTTPS 필요)

폰 브라우저는 **HTTPS 주소에서만** 마이크를 줍니다. 같은 Wi-Fi의 `http://192.168.x.x:3000`으로는 안 됩니다.
가장 쉬운 방법은 임시 터널입니다 (주소는 실행할 때마다 바뀜, 끄면 닫힘):

```bash
cloudflared tunnel --url http://localhost:3000     # 출력된 https://….trycloudflare.com 을 폰에서 열기
```

> 터널 주소를 아는 사람은 누구나 우리 OpenAI 키로 음성 대화를 할 수 있습니다. 확인이 끝나면 바로 끄세요.

확인할 것 (F-024 AC7):

- [ ] iPhone Safari에서 음성 화면 → 마이크 허락 → 페르소나가 먼저 인사하고, 말하면 답한다
- [ ] 답하는 중에 말하면 바로 멈추고 듣는다 (끼어들기)
- [ ] 스피커로 나온 자기 답을 다시 듣고 혼자 대화하지 않는다
- [ ] 자막에 내 말·답이 나오고, 대화 끝내기 뒤 채팅 내역에 남는다
- [ ] 대화를 끝내고 새로 시작하면 지난 대화를 기억한다 (요약 기억)
- [ ] 소리가 수화기 쪽으로 작게 나오지 않는다 (R-A15)
- [ ] 같은 것을 Android Chrome에서

## 4. 홈 화면에 앱처럼 설치 (F-025)

- **iPhone**: Safari로 터널 주소를 열면 채팅 화면 위에 안내가 나와요. 아래쪽 공유 버튼 → "홈 화면에 추가" → "AI 말벗" 아이콘으로 열기
- **Android**: Chrome에서 안내의 "추가하기"를 누르면 설치 창이 떠요
- 홈 화면 앱으로 열면 주소창 없이 열리고, 안내는 더 보이지 않아요. 터널 주소가 바뀌면 다시 추가해야 해요 (공개 배포 F-014 때 고정 주소)
- 확인할 것: 홈 화면 앱에서도 마이크 허락 → 음성 대화가 되는지, 앱을 다시 열 때 마이크를 또 묻는지

## 5. 잘 안 될 때

| 증상 | 확인 |
|---|---|
| "기기 음성으로 대화할게요"가 뜬다 | `OPENAI_API_KEY`, 시작 로그, `/api/config`의 `voiceAgent` |
| "마이크를 쓸 수 없어요" | 주소가 HTTPS인지, 브라우저·iOS 설정에서 이 사이트 마이크 허용 |
| 연결 중에서 멈춘다 | 서버 로그의 `realtime session error`(키·모델 이름), 브라우저 콘솔의 `realtime 4xx` |
| 소리가 안 난다 (iPhone) | 무음 스위치, 화면을 한 번 눌러 시작했는지 (자동 재생 제한) |
