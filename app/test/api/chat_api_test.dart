import 'dart:async';
import 'dart:convert';

import 'package:ai_agent_chat/api/chat_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

/// 응답을 마음대로 흘려보내는 가짜 HTTP 클라이언트 (실제 서버·네트워크 없음).
class FakeClient extends http.BaseClient {
  FakeClient(this.handler);

  final Future<http.StreamedResponse> Function(http.BaseRequest req) handler;
  http.BaseRequest? last;
  bool closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    last = request;
    return handler(request);
  }

  @override
  void close() => closed = true;
}

http.StreamedResponse sse(Stream<String> body, {int status = 200}) =>
    http.StreamedResponse(body.map(utf8.encode), status, headers: {'content-type': 'text/event-stream'});

const msgs = [Message(Role.user, '안녕'), Message(Role.assistant, '네'), Message(Role.user, '또')];

void main() {
  test('F-001 AC1 · F-002 AC1 대화 내역을 보내고 delta·done을 차례로 낸다', () async {
    final client = FakeClient(
      (_) async => sse(
        Stream.fromIterable([
          'event: delta\ndata: {"text":"안"}\n\n',
          'event: delta\ndata: {"text":"녕"}\n\n',
          'event: done\ndata: {"stopReason":"end_turn"}\n\n',
        ]),
      ),
    );
    final api = HttpChatApi(baseUrl: 'http://srv', clientFactory: () => client);
    final events = await api.stream(msgs).toList();

    expect(events, hasLength(3));
    expect((events[0] as ChatDelta).text, '안');
    expect((events[1] as ChatDelta).text, '녕');
    expect((events[2] as ChatDone).stopReason, 'end_turn');
    final req = client.last! as http.Request;
    expect(req.method, 'POST');
    expect(req.url.toString(), 'http://srv/api/chat');
    expect(req.headers['content-type'], startsWith('application/json'));
    expect(jsonDecode(req.body), {
      'messages': [
        {'role': 'user', 'content': '안녕'},
        {'role': 'assistant', 'content': '네'},
        {'role': 'user', 'content': '또'},
      ],
    });
    expect(client.closed, isTrue);
  });

  test('F-004 AC1 스트림 중 error 이벤트는 그 문장으로 실패한다', () async {
    final api = HttpChatApi(
      clientFactory: () => FakeClient(
        (_) async => sse(Stream.value('event: error\ndata: {"message":"요청이 너무 많아요. 잠시 후 다시 시도해 주세요."}\n\n')),
      ),
    );
    final events = await api.stream(msgs).toList();
    expect((events.single as ChatFailed).message, '요청이 너무 많아요. 잠시 후 다시 시도해 주세요.');
  });

  test('F-001 AC3·AC5 400 오류 JSON은 서버 문장으로 실패한다', () async {
    final api = HttpChatApi(
      clientFactory: () => FakeClient(
        (_) async => http.StreamedResponse(
          Stream.value(utf8.encode('{"error":{"code":"TOO_LONG","message":"메시지는 4,000자까지 보낼 수 있어요."}}')),
          400,
        ),
      ),
    );
    final events = await api.stream(msgs).toList();
    expect((events.single as ChatFailed).message, '메시지는 4,000자까지 보낼 수 있어요.');
  });

  test('F-001 연결 실패와 done 없는 종료는 안내 문장으로 실패한다', () async {
    var api = HttpChatApi(clientFactory: () => FakeClient((_) async => throw http.ClientException('down')));
    expect(((await api.stream(msgs).toList()).single as ChatFailed).message, ClientMessages.connect);

    api = HttpChatApi(
      clientFactory: () => FakeClient((_) async => sse(Stream.value('event: delta\ndata: {"text":"앞"}\n\n'))),
    );
    final events = await api.stream(msgs).toList();
    expect((events.last as ChatFailed).message, ClientMessages.ended);
  });

  test('F-003 AC2 구독을 취소하면 요청을 중단하고 클라이언트를 닫는다', () async {
    final body = StreamController<String>();
    late http.Request sent;
    final client = FakeClient((req) async {
      sent = req as http.Request;
      return sse(body.stream);
    });
    final api = HttpChatApi(clientFactory: () => client);
    final got = <ChatEvent>[];
    final sub = api.stream(msgs).listen(got.add);
    await pumpEventQueue();
    body.add('event: delta\ndata: {"text":"첫"}\n\n');
    await pumpEventQueue();
    await sub.cancel();

    expect(got, hasLength(1));
    expect(client.closed, isTrue);
    expect(sent, isA<http.Abortable>());
    expect((sent as http.Abortable).abortTrigger, isNotNull);
    await body.close();
  });

  test('F-001 AC4 /api/config를 읽는다', () async {
    final api = HttpChatApi(
      clientFactory: () => FakeClient(
        (_) async => http.StreamedResponse(Stream.value(utf8.encode('{"provider":"mock","model":"mock-echo"}')), 200),
      ),
    );
    final cfg = await api.config();
    expect(cfg.isMock, isTrue);
    expect(cfg.model, 'mock-echo');
  });
}
