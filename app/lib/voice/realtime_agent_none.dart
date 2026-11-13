/// 실시간 음성 에이전트가 없는 곳(테스트 VM)용. 음성 대화는 안내만 하고 켜지지 않는다.
library;

import 'realtime_agent.dart';

RealtimeAgent? createRealtimeAgent() => null;
