import 'dart:async';

import 'package:ai_agent_chat/api/chat_api.dart';

/// 요청마다 StreamController를 하나 열어 두는 가짜 API. 테스트가 이벤트를 직접 흘린다.
class FakeApi implements ChatApi {
  final requests = <List<Message>>[];
  final streams = <StreamController<ChatEvent>>[];
  var cancels = 0;

  StreamController<ChatEvent> get current => streams.last;

  @override
  Stream<ChatEvent> stream(List<Message> messages) {
    requests.add(messages);
    final c = StreamController<ChatEvent>(onCancel: () => cancels++);
    streams.add(c);
    return c.stream;
  }

  @override
  Future<ServerConfig> config() async => const ServerConfig(provider: 'mock', model: 'mock-echo');
}
