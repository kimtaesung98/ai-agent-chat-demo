/// 플랫폼별 실시간 음성 에이전트: 웹은 OpenAI Realtime(F-024), Android·iOS는 ElevenLabs(F-022 — 정리 단계에서 지움).
library;

export 'realtime_agent_none.dart'
    if (dart.library.io) 'elevenlabs_agent.dart'
    if (dart.library.js_interop) 'openai_realtime_agent.dart';
