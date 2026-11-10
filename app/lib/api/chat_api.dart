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
  Stream<ChatEvent> stream(List<Message> messages, {ChatMode mode = ChatMode.text, PersonaRequest? persona});

  Future<ServerConfig> config();
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
    : _base = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl,
      _newClient = clientFactory ?? createHttpClient;

  final String _base;
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
  Stream<ChatEvent> stream(List<Message> messages, {ChatMode mode = ChatMode.text, PersonaRequest? persona}) {
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
