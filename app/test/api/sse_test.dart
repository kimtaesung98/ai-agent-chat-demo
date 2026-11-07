import 'dart:convert';

import 'package:ai_agent_chat/api/sse.dart';
import 'package:flutter_test/flutter_test.dart';

Stream<List<int>> chunks(List<String> parts) => Stream.fromIterable(parts.map(utf8.encode));

void main() {
  test('F-001 AC1 조각난 바이트에서도 이벤트를 순서대로 읽는다', () async {
    final events = await parseSse(
      chunks([
        'event: delta\nda',
        'ta: {"text":"안"}\n\nevent: delta\ndata: {"text":"녕"}\n',
        '\n: 주석\nevent: done\ndata: {"stopReason":"end_turn"}\n\n',
      ]),
    ).toList();
    expect(events.map((e) => '${e.event}:${e.data}'), [
      'delta:{"text":"안"}',
      'delta:{"text":"녕"}',
      'done:{"stopReason":"end_turn"}',
    ]);
  });

  test('F-001 data 줄이 여러 개면 줄바꿈으로 잇고, CRLF도 처리한다', () async {
    final events = await parseSse(chunks(['data: a\r\ndata: b\r\n\r\n'])).toList();
    expect(events.single.event, 'message');
    expect(events.single.data, 'a\nb');
  });

  test('F-001 마지막 빈 줄 없이 끝나도 남은 이벤트를 낸다', () async {
    final events = await parseSse(chunks(['event: done\ndata: {}'])).toList();
    expect(events.single.event, 'done');
  });

  test('F-001 한글 바이트가 중간에 잘려도 깨지지 않는다', () async {
    final bytes = utf8.encode('event: delta\ndata: {"text":"한글"}\n\n');
    final events = await parseSse(Stream.fromIterable([bytes.sublist(0, 25), bytes.sublist(25)])).toList();
    expect(events.single.data, '{"text":"한글"}');
  });
}
