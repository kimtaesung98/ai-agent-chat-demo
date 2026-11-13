import 'dart:async';

import 'package:ai_agent_chat/voice/openai_realtime.dart';
import 'package:ai_agent_chat/voice/realtime_agent.dart';
import 'package:flutter_test/flutter_test.dart';

/// `web/realtime.js` 대신 테스트가 사건을 흘리는 가짜 다리.
class FakeBridge implements RealtimeBridge {
  final starts = <({String secret, bool greet})>[];
  void Function(String, String)? onEvent;
  var stops = 0;
  final muted = <bool>[];

  @override
  Future<void> start(String secret, bool greet, void Function(String type, String text) onEvent) async {
    starts.add((secret: secret, greet: greet));
    this.onEvent = onEvent;
  }

  @override
  void stop() => stops++;

  @override
  void setMuted(bool m) => muted.add(m);
}

void main() {
  late FakeBridge bridge;
  late OpenAiRealtimeAgent agent;
  late List<AgentEvent> events;
  late StreamSubscription<AgentEvent> sub;

  setUp(() {
    bridge = FakeBridge();
    agent = OpenAiRealtimeAgent(bridge);
    events = [];
    sub = agent.events.listen(events.add);
  });
  tearDown(() async {
    await sub.cancel();
    agent.dispose();
  });

  test('F-024 AC4 임시 키로만 연결하고, 처음 연결이면 먼저 인사하며 다시 연결이면 이어서 한다', () async {
    await agent.start(token: 'ek_1', context: {'history': []});
    await agent.start(
      token: 'ek_2',
      context: {
        'history': [
          {'role': 'user', 'content': '안녕'},
        ],
      },
    );
    expect(bridge.starts.map((s) => (s.secret, s.greet)), [('ek_1', true), ('ek_2', false)]);
  });

  test('F-024 AC5 전사·상태 사건을 AgentEvent로 바꾸고, 소리 크기를 파형 값으로 준다', () async {
    await agent.start(token: 'ek', context: const {});
    final on = bridge.onEvent!;
    on('connected', '');
    on('user_speaking', '');
    on('heard_partial', '오늘');
    on('heard', '오늘 덥네');
    on('speaking', '');
    on('reply', '물 많이 드세요');
    on('listening', '');
    on('level', '0.420');
    await pumpEventQueue();
    expect(events.map((e) => e.runtimeType.toString()), [
      'AgentConnected',
      'AgentHeardPartial',
      'AgentHeardPartial',
      'AgentHeard',
      'AgentMode',
      'AgentReply',
      'AgentMode',
    ]);
    expect((events[3] as AgentHeard).text, '오늘 덥네');
    expect((events[5] as AgentReply).text, '물 많이 드세요');
    expect((events[4] as AgentMode).speaking, isTrue);
    expect(agent.level.value, closeTo(0.42, 1e-9));
  });

  test('F-024 AC6 끊김·마이크 거부·오류를 알리고, 앱이 끊으면 늦게 온 사건은 버린다', () async {
    await agent.start(token: 'ek', context: const {});
    final on = bridge.onEvent!;
    on('mic_denied', '');
    on('error', '');
    on('disconnected', '');
    await agent.end();
    on('heard', '늦은 말');
    await pumpEventQueue();
    expect((events[0] as AgentFailed).micDenied, isTrue);
    expect((events[1] as AgentFailed).micDenied, isFalse);
    expect((events[2] as AgentDisconnected).byUser, isFalse);
    expect((events[3] as AgentDisconnected).byUser, isTrue);
    expect(events, hasLength(4), reason: '끊은 뒤 사건은 버린다');
    expect(bridge.stops, 1);
    await agent.setMuted(true);
    expect(bridge.muted, [true]);
  });
}
