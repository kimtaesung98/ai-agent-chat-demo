/// `/api/chat` · `/api/config` 호출 (ARCHITECTURE.md §4.2). `chat`·`ui`를 import하지 않는다.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'client_factory.dart';
import 'models.dart';
import 'sse.dart';

export 'models.dart';

/// 서버 통신 인터페이스. 컨트롤러는 이것만 알고, 테스트는 가짜를 쓴다.
abstract interface class ChatApi {
  /// 대화를 보내고 응답 사건을 차례로 내보낸다. 마지막은 [ChatDone] 또는 [ChatFailed].
  /// 구독을 취소하면 요청이 중단된다 (F-003). [mode]가 voice면 말하기용 답을 요청한다 (F-012).
  /// [persona]가 있으면 그 페르소나와 내 프로필로 답하게 한다 (F-005).
  /// [memory]는 지난 대화 요약, 오래된 것부터 (F-019, API-001 `memory`).
  Stream<ChatEvent> stream(
    List<Message> messages, {
    ChatMode mode = ChatMode.text,
    PersonaRequest? persona,
    List<SessionSummary> memory = const [],
    LongTermMemory? longTerm,
  });

  /// 오래된 요약 [sessions](오래된 것부터)를 이전 [longTerm]과 묶어 장기 기억을 만든다 (F-020, API-004).
  /// 실패하면 [SummaryFailed]. 돌려주는 값의 `summary`·`facts`만 쓴다.
  Future<Map<String, Object?>> consolidate(
    List<SessionSummary> sessions, {
    PersonaRequest? persona,
    LongTermMemory? longTerm,
  });

  /// 끝난 대화 세션을 요약한다 (F-019, API-003). 실패하면 [SummaryFailed]를 던진다.
  /// 돌려주는 값의 `summary`·`facts`·`followUps`만 쓴다 — 나머지는 부르는 쪽이 채운다.
  Future<Map<String, Object?>> summarize(List<Message> messages, {PersonaRequest? persona});

  Future<ServerConfig> config();
}

/// 요약 실패. [message]는 화면에 보여도 되는 문장이다.
class SummaryFailed implements Exception {
  const SummaryFailed(this.message);
  final String message;

  @override
  String toString() => 'SummaryFailed($message)';
}

/// 화면에 보여 줄 연결 오류 문장.
abstract final class ClientMessages {
  static const connect = '서버에 연결할 수 없어요. 네트워크를 확인해 주세요.';
  static const request = '요청을 처리하지 못했어요.';
  static const dropped = '응답을 받는 중에 연결이 끊겼어요.';
  static const ended = '응답이 중간에 끝났어요.';
}

/// HTTP로 서버를 부르는 [ChatApi].
class HttpChatApi implements ChatApi {
  /// [baseUrl]이 비어 있으면 같은 출처(웹)로 부른다. 모바일은 `--dart-define=API_BASE_URL=...`.
  HttpChatApi({String baseUrl = '', http.Client Function()? clientFactory})
    : _base = _trim(baseUrl),
      _newClient = clientFactory ?? createHttpClient;

  String _base;

  /// 서버 주소. 앱 설정에서 바꾸면 다음 요청부터 쓴다 (F-017).
  String get baseUrl => _base;
  set baseUrl(String value) => _base = _trim(value);

  static String _trim(String v) => v.endsWith('/') ? v.substring(0, v.length - 1) : v;

  final http.Client Function() _newClient;

  Uri _uri(String path) => _base.isEmpty ? Uri.base.resolve(path) : Uri.parse('$_base$path');

  @override
  Future<ServerConfig> config() async {
    final client = _newClient();
    try {
      final res = await client.get(_uri('/api/config'));
      final json = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      return ServerConfig(provider: json['provider'] as String, model: json['model'] as String);
    } finally {
      client.close();
    }
  }

  @override
  Future<Map<String, Object?>> summarize(List<Message> messages, {PersonaRequest? persona}) => _postJson(
    '/api/summary',
    {'messages': messages.map((m) => m.toJson()).toList(), if (persona != null) 'persona': persona.toJson()},
  );

  @override
  Future<Map<String, Object?>> consolidate(
    List<SessionSummary> sessions, {
    PersonaRequest? persona,
    LongTermMemory? longTerm,
  }) => _postJson('/api/consolidate', {
    'sessions': sessions.map((s) => s.toRequestJson()).toList(),
    if (persona != null) 'persona': persona.toJson(),
    if (longTerm != null) 'longTerm': longTerm.toRequestJson(),
  });

  /// JSON을 보내고 JSON 객체를 받는다. 실패는 화면용 문장의 [SummaryFailed].
  Future<Map<String, Object?>> _postJson(String path, Map<String, Object> payload) async {
    final client = _newClient();
    try {
      final http.Response res;
      try {
        res = await client.post(_uri(path), headers: {'content-type': 'application/json'}, body: jsonEncode(payload));
      } catch (_) {
        throw const SummaryFailed(ClientMessages.connect);
      }
      final Object? body;
      try {
        body = jsonDecode(utf8.decode(res.bodyBytes));
      } catch (_) {
        throw const SummaryFailed(ClientMessages.request);
      }
      if (res.statusCode != 200 || body is! Map<String, Object?>) {
        final error = body is Map ? body['error'] : null;
        final message = error is Map ? error['message'] : null;
        throw SummaryFailed(message is String ? message : ClientMessages.request);
      }
      return body;
    } finally {
      client.close();
    }
  }

  @override
  Stream<ChatEvent> stream(
    List<Message> messages, {
    ChatMode mode = ChatMode.text,
    PersonaRequest? persona,
    List<SessionSummary> memory = const [],
    LongTermMemory? longTerm,
  }) {
    final client = _newClient();
    final abort = Completer<void>();
    late final StreamController<ChatEvent> out;
    var cancelled = false;

    Future<void> run() async {
      try {
        final req = http.AbortableRequest('POST', _uri('/api/chat'), abortTrigger: abort.future)
          ..headers['content-type'] = 'application/json'
          ..body = jsonEncode({
            'messages': messages.map((m) => m.toJson()).toList(),
            if (mode == ChatMode.voice) 'mode': 'voice', // 기본(text)은 보내지 않는다 — 기존 요청과 같음
            if (persona != null) 'persona': persona.toJson(), // F-005
            if (memory.isNotEmpty) 'memory': memory.map((m) => m.toRequestJson()).toList(), // F-019
            if (longTerm != null) 'longTerm': longTerm.toRequestJson(), // F-020
          });

        final http.StreamedResponse res;
        try {
          res = await client.send(req);
        } catch (_) {
          if (!cancelled) out.add(const ChatFailed(ClientMessages.connect));
          return;
        }

        if (res.statusCode != 200) {
          out.add(ChatFailed(await _errorMessage(res)));
          return;
        }

        var finished = false;
        try {
          await for (final ev in parseSse(res.stream)) {
            if (cancelled) return;
            final data = jsonDecode(ev.data) as Map<String, dynamic>;
            switch (ev.event) {
              case 'delta':
                out.add(ChatDelta(data['text'] as String));
              case 'done':
                finished = true;
                out.add(ChatDone(data['stopReason'] as String? ?? ''));
                return;
              case 'error':
                finished = true;
                out.add(ChatFailed(data['message'] as String? ?? ClientMessages.request));
                return;
            }
          }
        } catch (_) {
          if (!cancelled) {
            finished = true;
            out.add(const ChatFailed(ClientMessages.dropped));
          }
        }
        if (!finished && !cancelled) out.add(const ChatFailed(ClientMessages.ended));
      } finally {
        client.close();
        if (!out.isClosed) await out.close();
      }
    }

    out = StreamController<ChatEvent>(
      onListen: run,
      onCancel: () {
        cancelled = true;
        if (!abort.isCompleted) abort.complete(); // 요청 중단 → 서버가 제공자 호출을 취소
        client.close();
      },
    );
    return out.stream;
  }

  static Future<String> _errorMessage(http.StreamedResponse res) async {
    try {
      final body = jsonDecode(await res.stream.bytesToString()) as Map<String, dynamic>;
      return (body['error'] as Map<String, dynamic>)['message'] as String;
    } catch (_) {
      return ClientMessages.request;
    }
  }
}
