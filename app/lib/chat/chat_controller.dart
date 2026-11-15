/// 대화 내역과 화면 상태 (ARCHITECTURE.md §4.2, ADR-010).
/// `package:flutter/foundation.dart`까지만 import한다 — 위젯 없이 단위 테스트한다.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../api/account_api.dart';
import '../api/chat_api.dart';
import 'memory_controller.dart';
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

/// 대화 세션 하나 (F-019). 첫 메시지 때의 페르소나로 정리한다 — 페르소나를 바꾸면 새 세션이다.
class _Session {
  _Session(this.id, this.persona);
  final String id;
  final PersonaRequest? persona;

  /// 마지막으로 정리한 메시지 수.
  int summarizedCount = 0;

  /// 서버 대화 id (F-028). 로그인한 서버 모드에서 첫 메시지·음성 시작 때 연다.
  Future<String>? conversation;
}

/// 채팅 화면 컨트롤러. 위젯은 [ListenableBuilder]로 구독만 한다.
class ChatController extends ChangeNotifier {
  ChatController(this._api, {this.personas, this.memory, DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final ChatApi _api;

  /// 선택한 페르소나와 내 프로필 (F-005). 없으면 `persona` 없이 보낸다.
  final PersonaController? personas;

  /// 지난 대화 기억 (F-019). 없으면 요약하지 않고 `memory` 없이 보낸다. 페르소나가 있어야 쓴다.
  final MemoryController? memory;
  final DateTime Function() _clock;

  /// 로그인한 서버 계정 (F-028). 있으면 대화를 서버에 열고(`conversationId`), 끝낼 때 서버가 요약·장기 기억을 만든다.
  /// 없으면 지금처럼 앱이 페르소나·기억을 실어 보내고 요약을 기기에 둔다.
  AccountApi? _server;
  bool get serverBacked => _server != null;

  /// 서버 계정에 붙인다 (로그인 뒤). 지금 대화는 새로 시작한다.
  void attachServer(AccountApi api) {
    if (identical(_server, api)) return;
    _resetLocal();
    _server = api;
    _notify();
  }

  /// 서버 계정에서 뗀다 (로그아웃). 지금 대화를 정리한 뒤 비운다.
  void detachServer() {
    if (_server == null) return;
    reset();
    _server = null;
    _notify();
  }

  /// 지금 대화 세션. 첫 메시지를 보낼 때 정하고 [reset]에서 끝난다.
  _Session? _session;
  var _sessionSeq = 0;

  /// 요약·장기 기억 요청이 진행 중인 수 (테스트·화면용).
  int get summarizing => _summarizing;
  var _summarizing = 0;
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
      _configFailed = false; // 한 번 실패했어도 다시 받으면 지운다 (예: iOS 로컬 네트워크 권한 창이 첫 요청을 막음)
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
    final persona = personas?.request;
    final session = _ensureSession();
    final question = ChatEntry._(Role.user, text, EntryStatus.done);
    final answer = ChatEntry._(Role.assistant, '', EntryStatus.streaming);
    _entries.addAll([question, answer]);

    final mode = voice ? ChatMode.voice : ChatMode.text;
    final events = _server != null && session.persona != null
        ? _serverStream(session, messages, mode)
        : _api.stream(
            messages,
            mode: mode,
            persona: persona,
            memory: switch (session.persona) {
              final p? => memory?.recentFor(p.persona.id, exceptSession: session.id) ?? const [],
              null => const [],
            },
            longTerm: switch (session.persona) {
              final p? => memory?.longTermFor(p.persona.id),
              null => null,
            },
          );
    _sub = events.listen(
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
            question.inHistory = false; // 실패한 질문은 내역에서 뺀다 — 다시 시도는 [retry] (F-004 AC2)
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

  _Session _ensureSession() =>
      _session ??= _Session('session-${_clock().microsecondsSinceEpoch}-${_sessionSeq++}', personas?.request);

  /// 서버 대화를 열고(한 번) 그 id로 보낸다 (F-028). 열지 못하면 실패 사건 하나.
  Stream<ChatEvent> _serverStream(_Session session, List<Message> messages, ChatMode mode) async* {
    final String id;
    try {
      id = await _openConversation(session, channel: 'text');
    } on AccountApiError catch (e) {
      yield ChatFailed(e.message);
      return;
    } catch (_) {
      yield const ChatFailed(ClientMessages.connect);
      return;
    }
    yield* _api.stream(messages, mode: mode, conversationId: id);
  }

  Future<String> _openConversation(_Session session, {required String channel}) {
    final server = _server!;
    final personaId = session.persona!.persona.id;
    final opening = session.conversation ??= server.openConversation(personaId, channel: channel);
    // 실패하면 다음에 다시 연다
    return opening.catchError((Object e) {
      if (identical(session.conversation, opening)) session.conversation = null;
      throw e;
    });
  }

  /// 실시간 음성 대화(F-024)를 시작할 때 서버 대화 id. 서버 모드가 아니면 null. 열지 못하면 던진다.
  Future<String?> voiceConversation() async {
    if (_server == null) return null;
    final session = _ensureSession();
    if (session.persona == null) return null;
    return _openConversation(session, channel: 'voice');
  }

  /// 실시간 음성 대화(F-024)에서 확정된 말 한마디를 대화 내역에 넣는다. 서버에 보내지 않는다 —
  /// 답은 OpenAI Realtime이 만들고, 여기서는 화면·요약(F-019)·다시 연결용으로 남긴다.
  void addVoiceTurn(Role role, String text) {
    if (text.trim().isEmpty) return;
    _ensureSession();
    _entries.add(ChatEntry._(role, text.trim(), EntryStatus.done));
    _notify();
  }

  /// 실시간 음성 대화를 시작할 때 서버(API-007)에 넘길 맥락 (F-024). 서버가 이것으로 지시문을 만든다.
  /// API-001과 같은 `persona`·`memory`·`longTerm`에, 다시 연결해도 맥락이 이어지게 지금까지의 `history`를 싣는다.
  /// 시스템 프롬프트 틀은 서버가 만든다 (ADR-016).
  Map<String, Object?> voiceContext() {
    final session = _ensureSession();
    final p = session.persona;
    final recent = history;
    final cut = recent.length > maxVoiceHistory ? recent.sublist(recent.length - maxVoiceHistory) : recent;
    final lt = p == null ? null : memory?.longTermFor(p.persona.id);
    return {
      if (p != null) 'persona': p.toJson(),
      if (p != null)
        'memory': [
          for (final m in memory?.recentFor(p.persona.id, exceptSession: session.id) ?? const <SessionSummary>[])
            m.toRequestJson(),
        ],
      if (lt != null) 'longTerm': lt.toRequestJson(),
      'history': [for (final m in cut) m.toJson()],
    };
  }

  /// [voiceContext] `history` 최대 메시지 수 (서버 chat.MaxSessionHistory와 같음).
  static const maxVoiceHistory = 40;

  /// 마지막 답이 오류면 다시 시도할 수 있다 (F-004 AC2).
  bool get canRetry => !busy && _entries.length >= 2 && _entries.last.status == EntryStatus.error;

  /// 실패한 질문과 오류 말풍선을 지우고 마지막 사용자 메시지로 다시 요청한다 (F-004 AC2).
  /// 다시 시도는 화면 버튼으로 하므로 글 모드로 보낸다. 할 수 없으면 false.
  bool retry() {
    if (!canRetry) return false;
    final question = _entries[_entries.length - 2];
    _entries.removeRange(_entries.length - 2, _entries.length);
    return send(question.text);
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

  /// 새 대화 (F-002 AC3). 응답 중이면 먼저 멈춘다. 지금 대화 세션을 정리하고(F-019) 다음 세션을 연다.
  void reset() {
    stop();
    endSession();
    _resetLocal();
    _notify();
  }

  void _resetLocal() {
    stop();
    _entries.clear();
    _session = null;
  }

  /// 지금 대화 세션을 요약해 기억에 넣는다 (F-019 AC3). 새 대화·페르소나 바꾸기·음성 "대화 끝내기"·앱이 뒤로 갈 때 부른다.
  /// 끝난 주고받기(질문 + 답)가 하나도 없거나 지난 정리 뒤로 바뀐 것이 없으면 아무것도 하지 않고 false.
  /// 요약은 뒤에서 만들고, 실패해도 대화에는 영향이 없다 (다음 정리 때 다시 시도).
  bool endSession() {
    final session = _session;
    final store = memory;
    final persona = session?.persona;
    if (session == null || store == null || persona == null) return false;
    final messages = [
      for (final e in _entries)
        if (e.inHistory && e.status != EntryStatus.streaming && e.text.trim().isNotEmpty) Message(e.role, e.text),
    ];
    final hasAnswer = messages.any((m) => m.role == Role.assistant);
    if (!hasAnswer || messages.length == session.summarizedCount) return false;
    session.summarizedCount = messages.length;
    if (_server case final server?) return _endOnServer(server, session, store, messages);
    final endedAt = _clock();
    final turns = messages.where((m) => m.role == Role.user).length;
    _summarizing++;
    unawaited(
      _api
          .summarize(messages, persona: persona)
          .then((json) {
            final s = SessionSummary.fromApiJson(
              json,
              id: session.id,
              personaId: persona.persona.id,
              endedAt: endedAt,
              turns: turns,
            );
            if (s != null) {
              store.put(s);
              _consolidate(store, persona);
            }
          })
          .catchError((Object e) {
            session.summarizedCount = 0; // 다음 정리 때 다시 시도
            debugPrint('대화 정리 실패'); // 내용은 로그에 남기지 않는다
          })
          .whenComplete(() {
            _summarizing--;
            _notify();
          }),
    );
    return true;
  }

  /// 서버 대화를 끝낸다 (F-028 AC4): 원문을 한 번 보내면 서버가 요약을 저장하고, 쌓이면 장기 기억도 묶는다.
  /// 받은 요약은 화면용으로 기억에 넣는다. 대화를 아직 열지 않았으면(첫 답 전) 아무것도 하지 않는다.
  bool _endOnServer(AccountApi server, _Session session, MemoryController store, List<Message> messages) {
    final opening = session.conversation;
    if (opening == null) {
      session.summarizedCount = 0;
      return false;
    }
    _summarizing++;
    unawaited(
      opening
          .then((id) => server.endConversation(id, messages))
          .then((ended) {
            if (!identical(server, _server)) return; // 그 사이 로그아웃함 — 남의 기억을 기기에 넣지 않는다
            if (ended.summary case final s?) store.put(s);
          })
          .catchError((Object e) {
            session.summarizedCount = 0; // 다음 정리 때 다시 시도 — 서버에는 원문이 없으니 앱이 다시 보낸다
            debugPrint('대화 끝내기 실패'); // 내용은 로그에 남기지 않는다
          })
          .whenComplete(() {
            _summarizing--;
            _notify();
          }),
    );
    return true;
  }

  /// 오래된 요약이 쌓였으면 장기 기억으로 묶는다 (F-020 AC2). 페르소나마다 한 번에 하나, 실패하면 다음 정리 때 다시.
  void _consolidate(MemoryController store, PersonaRequest persona) {
    final id = persona.persona.id;
    final pending = store.pendingFold(id);
    if (pending.isEmpty || !_consolidating.add(id)) return;
    final previous = store.longTermFor(id);
    final take = pending.length > maxConsolidate ? pending.sublist(pending.length - maxConsolidate) : pending;
    _summarizing++;
    unawaited(
      _api
          .consolidate(take, persona: persona, longTerm: previous)
          .then((json) {
            final l = LongTermMemory.fromApiJson(
              json,
              personaId: id,
              updatedAt: _clock(),
              coversUntil: take.last.endedAt,
            );
            if (l != null) store.setLongTerm(l);
          })
          .catchError((Object e) {
            debugPrint('장기 기억 정리 실패'); // 내용은 로그에 남기지 않는다
          })
          .whenComplete(() {
            _consolidating.remove(id);
            _summarizing--;
            _notify();
          }),
    );
  }

  /// 장기 기억 한 번에 묶는 최대 요약 수 (API-004 sessions 최대 20개).
  static const maxConsolidate = 20;
  final _consolidating = <String>{};

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
