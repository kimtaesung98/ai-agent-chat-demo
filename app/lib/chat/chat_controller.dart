/// 대화 내역과 화면 상태 (ARCHITECTURE.md §4.2, ADR-010).
/// `package:flutter/foundation.dart`까지만 import한다 — 위젯 없이 단위 테스트한다.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../api/chat_api.dart';
import 'persona_controller.dart';

/// 말풍선 상태.
enum EntryStatus { streaming, done, stopped, error }

/// 화면에 보이는 말풍선 하나.
class ChatEntry {
  ChatEntry._(this.role, this.text, this.status);

  final Role role;
  String text;
  EntryStatus status;

  /// 다음 요청에 대화 내역으로 보낼지. 실패한 질문과 빈 응답은 보내지 않는다.
  bool inHistory = true;

  bool get isUser => role == Role.user;
}

/// 채팅 화면 컨트롤러. 위젯은 [ListenableBuilder]로 구독만 한다.
class ChatController extends ChangeNotifier {
  ChatController(this._api, {this.personas});

  final ChatApi _api;

  /// 선택한 페르소나와 내 프로필 (F-005). 없으면 `persona` 없이 보낸다.
  final PersonaController? personas;
  final List<ChatEntry> _entries = [];
  StreamSubscription<ChatEvent>? _sub;
  ServerConfig? _config;
  bool _configFailed = false;
  bool _disposed = false;

  List<ChatEntry> get entries => List.unmodifiable(_entries);
  bool get busy => _sub != null;
  ServerConfig? get config => _config;
  bool get configFailed => _configFailed;

  /// 다음 요청에 보낼 대화 내역 (F-002 AC1).
  List<Message> get history => [
    for (final e in _entries)
      if (e.inHistory && e.text.trim().isNotEmpty) Message(e.role, e.text),
  ];

  /// 서버 모드를 불러온다 (F-001 AC4).
  Future<void> loadConfig() async {
    try {
      _config = await _api.config();
    } catch (_) {
      _configFailed = true;
    }
    _notify();
  }

  /// 메시지를 보낸다. 빈 메시지이거나 응답 중이면 아무것도 하지 않고 false (F-001 AC3).
  /// [voice]면 서버에 말하기용 답을 요청한다 (F-012, API-001 `mode: "voice"`).
  bool send(String text, {bool voice = false}) {
    if (busy || text.trim().isEmpty) return false;
    final messages = [...history, Message(Role.user, text)];
    final question = ChatEntry._(Role.user, text, EntryStatus.done);
    final answer = ChatEntry._(Role.assistant, '', EntryStatus.streaming);
    _entries.addAll([question, answer]);

    _sub = _api
        .stream(messages, mode: voice ? ChatMode.voice : ChatMode.text, persona: personas?.request)
        .listen(
          (event) {
            switch (event) {
              case ChatDelta(:final text):
                answer.text += text; // F-001 AC1
              case ChatDone():
                answer.status = EntryStatus.done;
                _finish();
              case ChatFailed(:final message):
                answer
                  ..text = message
                  ..status = EntryStatus.error
                  ..inHistory = false;
                question.inHistory = false; // 실패한 질문은 내역에서 뺀다 (재시도는 F-004)
                _finish();
            }
            _notify();
          },
          onDone: () {
            if (answer.status == EntryStatus.streaming) {
              answer
                ..text = ClientMessages.ended
                ..status = EntryStatus.error
                ..inHistory = false;
              question.inHistory = false;
              _finish();
              _notify();
            }
          },
        );
    _notify();
    return true;
  }

  /// 응답을 멈춘다 (F-003 AC1·AC3). 받은 내용은 남기고 "중단됨"으로 표시한다.
  void stop() {
    final sub = _sub;
    if (sub == null) return;
    _sub = null;
    unawaited(sub.cancel()); // 요청 중단 → 서버가 제공자 호출 취소 (F-003 AC2)
    final answer = _entries.last;
    answer.status = EntryStatus.stopped;
    _notify();
  }

  /// 새 대화 (F-002 AC3). 응답 중이면 먼저 멈춘다.
  void reset() {
    stop();
    _entries.clear();
    _notify();
  }

  void _finish() => _sub = null;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _sub?.cancel();
    _sub = null;
    super.dispose();
  }
}
