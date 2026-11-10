/// 최소 SSE 파서. 빈 줄로 이벤트를 나누고, `data:` 줄이 여럿이면 줄바꿈으로 잇는다.
/// 주석(`:`로 시작)과 알 수 없는 필드는 무시한다.
library;

import 'dart:async';
import 'dart:convert';

/// SSE 이벤트 하나.
class SseEvent {
  const SseEvent(this.event, this.data);
  final String event;
  final String data;
}

/// 바이트 스트림을 SSE 이벤트 스트림으로 바꾼다.
Stream<SseEvent> parseSse(Stream<List<int>> bytes) async* {
  var event = 'message';
  final data = <String>[];
  await for (final line in bytes.transform(utf8.decoder).transform(const LineSplitter())) {
    if (line.isEmpty) {
      if (data.isNotEmpty) yield SseEvent(event, data.join('\n'));
      event = 'message';
      data.clear();
      continue;
    }
    if (line.startsWith(':')) continue;
    final colon = line.indexOf(':');
    final field = colon == -1 ? line : line.substring(0, colon);
    var value = colon == -1 ? '' : line.substring(colon + 1);
    if (value.startsWith(' ')) value = value.substring(1);
    if (field == 'event') {
      event = value;
    } else if (field == 'data') {
      data.add(value);
    }
  }
  if (data.isNotEmpty) yield SseEvent(event, data.join('\n'));
}
