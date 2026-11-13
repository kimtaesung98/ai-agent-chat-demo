/// 실시간 음성 에이전트: 웹은 OpenAI Realtime(F-024). 그 밖(테스트 VM)은 없음.
library;

export 'realtime_agent_none.dart' if (dart.library.js_interop) 'openai_realtime_agent.dart';
