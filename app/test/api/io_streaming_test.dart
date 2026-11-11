// 모바일(dart:io) HTTP 클라이언트가 SSE를 끝까지 기다리지 않고 조각마다 넘기는지 (F-017 AC3).
// 실제 서버 대신 이 테스트 안의 localhost HttpServer만 쓴다 — 외부 네트워크 없음.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ai_agent_chat/api/chat_api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late ServerSocket server;
  late Completer<void> release; // 두 번째 조각을 보내도 되는 때
  late Completer<void> clientGone; // 클라이언트가 TCP 연결을 닫음

  // HTTP 응답을 소켓에 직접 쓴다 — 연결이 닫히는 순간(소켓 스트림 끝)을 정확히 알기 위해
  setUp(() async {
    release = Completer<void>();
    clientGone = Completer<void>();
    server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((socket) {
      var answered = false;
      void send(String event, Object data) => socket.add(utf8.encode('event: $event\ndata: ${jsonEncode(data)}\n\n'));
      socket.listen(
        (_) async {
          if (answered) return; // 요청 본문 조각은 무시
          answered = true;
          socket.add(
            utf8.encode(
              'HTTP/1.1 200 OK\r\ncontent-type: text/event-stream; charset=utf-8\r\nconnection: close\r\n\r\n',
            ),
          );
          send('delta', {'text': '안녕'});
          await Future.any([release.future, clientGone.future]);
          if (clientGone.isCompleted) return;
          send('delta', {'text': '하세요'});
          send('done', {'stopReason': 'end_turn'});
          await socket.close();
        },
        onDone: () {
          if (!clientGone.isCompleted) clientGone.complete();
        },
        onError: (_) {
          if (!clientGone.isCompleted) clientGone.complete();
        },
      );
    });
  });

  tearDown(() => server.close());

  String base() => 'http://${server.address.host}:${server.port}';

  test('F-017 AC3 모바일 클라이언트는 응답이 끝나기 전에 첫 조각을 받는다', () async {
    final api = HttpChatApi(baseUrl: base());
    final events = <ChatEvent>[];
    final first = Completer<void>();
    final done = Completer<void>();
    api.stream(const [Message(Role.user, '안녕')]).listen((e) {
      events.add(e);
      if (!first.isCompleted) first.complete();
    }, onDone: done.complete);

    await first.future.timeout(const Duration(seconds: 5));
    expect(release.isCompleted, isFalse, reason: '서버가 아직 응답을 끝내지 않았다');
    expect((events.single as ChatDelta).text, '안녕');

    release.complete();
    await done.future.timeout(const Duration(seconds: 5));
    expect(events.whereType<ChatDelta>().map((e) => e.text).join(), '안녕하세요');
    expect(events.last, isA<ChatDone>());
  });

  test('F-017 AC3 · F-003 AC2 모바일 클라이언트에서 구독을 취소하면 연결이 끊긴다', () async {
    final api = HttpChatApi(baseUrl: base());
    final first = Completer<void>();
    final sub = api.stream(const [Message(Role.user, '안녕')]).listen((_) {
      if (!first.isCompleted) first.complete();
    });
    await first.future.timeout(const Duration(seconds: 5));
    await sub.cancel();
    await clientGone.future.timeout(const Duration(seconds: 5));
    release.complete();
  });
}
