/// 플랫폼별 실시간 음성 에이전트 (F-022): Android·iOS는 ElevenLabs, 웹은 없음.
library;

export 'realtime_agent_none.dart' if (dart.library.io) 'elevenlabs_agent.dart';
