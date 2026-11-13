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

  test('F-005 AC1·AC3 persona가 있으면 빈 필드를 빼고 본문에 싣는다', () async {
    final client = FakeClient((_) async => sse(Stream.value('event: done\ndata: {"stopReason":"end_turn"}\n\n')));
    final api = HttpChatApi(baseUrl: 'http://srv', clientFactory: () => client);
    const persona = Persona(id: 'x', name: ' 지은 ', role: '기획 파트너', tones: ['차분하게'], instructions: ' ');
    await api
        .stream(
          msgs,
          mode: ChatMode.voice,
          persona: const PersonaRequest(persona, about: '기획자'),
        )
        .toList();
    final body = jsonDecode((client.last! as http.Request).body) as Map<String, dynamic>;
    expect(body['mode'], 'voice');
    expect(body['persona'], {
      'name': '지은',
      'role': '기획 파트너',
      'tones': ['차분하게'],
      'about': '기획자',
    });
  });

  test('F-019 AC1·AC4 base와 지난 대화 요약(memory)을 본문에 싣는다', () async {
    final client = FakeClient((_) async => sse(Stream.value('event: done\ndata: {"stopReason":"end_turn"}\n\n')));
    final api = HttpChatApi(baseUrl: 'http://srv', clientFactory: () => client);
    const persona = Persona(id: 'x', name: '미소', base: ' 어르신을 존중해요 ', instructions: '혈압약 챙겨 줘');
    await api
        .stream(
          msgs,
          persona: const PersonaRequest(persona),
          memory: [
            SessionSummary(
              id: 's',
              personaId: 'x',
              endedAt: DateTime(2026, 11, 10, 12),
              summary: '산책 이야기',
              facts: const ['무릎'],
            ),
          ],
        )
        .toList();
    final body = jsonDecode((client.last! as http.Request).body) as Map<String, dynamic>;
    expect(body['persona'], {'name': '미소', 'base': '어르신을 존중해요', 'instructions': '혈압약 챙겨 줘'});
    expect(body['memory'], [
      {
        'date': '2026-11-10',
        'summary': '산책 이야기',
        'facts': ['무릎'],
        'followUps': [],
      },
    ]);

    await api.stream(msgs).toList();
    expect(jsonDecode((client.last! as http.Request).body), isNot(contains('memory')));
  });

  test('F-019 AC3 summarize는 /api/summary로 보내고 요약 JSON을 돌려준다', () async {
    final client = FakeClient(
      (_) async => http.StreamedResponse(
        Stream.value(utf8.encode('{"summary":"산책 이야기","facts":[],"followUps":["병원"]}')),
        200,
        headers: {'content-type': 'application/json'},
      ),
    );
    final api = HttpChatApi(baseUrl: 'http://srv', clientFactory: () => client);
    final got = await api.summarize(
      msgs,
      persona: const PersonaRequest(Persona(id: 'x', name: '미소')),
    );
    expect(got['summary'], '산책 이야기');
    final req = client.last! as http.Request;
    expect(req.url.toString(), 'http://srv/api/summary');
    expect(jsonDecode(req.body), {
      'messages': [
        {'role': 'user', 'content': '안녕'},
        {'role': 'assistant', 'content': '네'},
        {'role': 'user', 'content': '또'},
      ],
      'persona': {'name': '미소'},
    });
    expect(client.closed, isTrue);
  });

  test('F-019 AC3 summarize 실패는 화면용 문장으로 SummaryFailed', () async {
    final error = HttpChatApi(
      baseUrl: 'http://srv',
      clientFactory: () => FakeClient(
        (_) async => http.StreamedResponse(
          Stream.value(utf8.encode('{"error":{"code":"PROVIDER_ERROR","message":"잠시 후 다시"}}')),
          502,
        ),
      ),
    );
    await expectLater(
      error.summarize(msgs),
      throwsA(isA<SummaryFailed>().having((e) => e.message, 'message', '잠시 후 다시')),
    );
    final down = HttpChatApi(
      baseUrl: 'http://srv',
      clientFactory: () => FakeClient((_) => Future.error(Exception('x'))),
    );
    await expectLater(
      down.summarize(msgs),
      throwsA(isA<SummaryFailed>().having((e) => e.message, 'message', ClientMessages.connect)),
    );
  });

  test('F-020 AC1·AC3 longTerm을 대화 본문에 싣고, consolidate는 /api/consolidate로 보낸다', () async {
    final lt = LongTermMemory(
      personaId: 'x',
      summary: '오래된 이야기',
      facts: const ['무릎'],
      updatedAt: DateTime(2026),
      coversUntil: DateTime(2026),
    );
    final chatClient = FakeClient((_) async => sse(Stream.value('event: done\ndata: {"stopReason":"end_turn"}\n\n')));
    await HttpChatApi(baseUrl: 'http://srv', clientFactory: () => chatClient).stream(msgs, longTerm: lt).toList();
    expect((jsonDecode((chatClient.last! as http.Request).body) as Map)['longTerm'], {
      'summary': '오래된 이야기',
      'facts': ['무릎'],
    });

    final client = FakeClient(
      (_) async => http.StreamedResponse(Stream.value(utf8.encode('{"summary":"묶음","facts":[]}')), 200),
    );
    final api = HttpChatApi(baseUrl: 'http://srv', clientFactory: () => client);
    final got = await api.consolidate([
      SessionSummary(id: 's', personaId: 'x', endedAt: DateTime(2026, 11, 1, 12), summary: '산책'),
    ], longTerm: lt);
    expect(got['summary'], '묶음');
    final req = client.last! as http.Request;
    expect(req.url.toString(), 'http://srv/api/consolidate');
    expect(jsonDecode(req.body), {
      'sessions': [
        {'date': '2026-11-01', 'summary': '산책', 'facts': [], 'followUps': []},
      ],
      'longTerm': {
        'summary': '오래된 이야기',
        'facts': ['무릎'],
      },
    });
  });

  http.StreamedResponse json(String body, int status) => http.StreamedResponse(Stream.value(utf8.encode(body)), status);

  test('F-024 AC4 API-002 voiceAgent가 openai일 때만 실시간 음성을 쓸 수 있다', () async {
    for (final (body, want) in [
      ('{"provider":"mock","model":"m","voiceAgent":"openai"}', true),
      ('{"provider":"mock","model":"m","voiceAgent":"elevenlabs"}', false),
      ('{"provider":"mock","model":"m","voiceAgent":"none"}', false),
      ('{"provider":"mock","model":"m"}', false),
    ]) {
      final api = HttpChatApi(baseUrl: 'http://srv', clientFactory: () => FakeClient((_) async => json(body, 200)));
      expect((await api.config()).voiceAgent, want, reason: body);
    }
  });

  test('F-024 AC4 voiceSession은 맥락을 POST /api/voice/session에 보내고 임시 키만 꺼내며, 실패는 VoiceTokenFailed', () async {
    final client = FakeClient((_) async => json('{"clientSecret":"ek_1","expiresAt":1,"model":"gpt-realtime"}', 200));
    final api = HttpChatApi(baseUrl: 'http://srv', clientFactory: () => client);
    final context = {
      'persona': {'name': '미소'},
      'history': <Object?>[],
    };
    expect(await api.voiceSession(context), 'ek_1');
    final req = client.last! as http.Request;
    expect(req.method, 'POST');
    expect(req.url.toString(), 'http://srv/api/voice/session');
    expect(jsonDecode(req.body), context);
    expect(client.closed, isTrue);
    for (final res in [
      () async => json('{"error":{"code":"VOICE_AGENT_OFF","message":"x"}}', 503),
      () async => json('{"clientSecret":""}', 200),
      () async => throw http.ClientException('down'),
    ]) {
      final failing = HttpChatApi(baseUrl: 'http://srv', clientFactory: () => FakeClient((_) => res()));
      await expectLater(failing.voiceSession(const {}), throwsA(isA<VoiceTokenFailed>()));
    }
  });
}
