/// 실시간 음성 대화 (SPEC.md F-024, ARCHITECTURE.md ADR-026).
/// 서버가 실시간 음성(API-002 `voiceAgent` == `openai`)을 켜 두었고 이 브라우저가 WebRTC·마이크를 쓸 수 있으면
/// OpenAI Realtime으로 대화한다. 안 되면(서버 설정 없음·임시 키 실패·연결이 계속 안 됨) 한 번 알리고 꺼진다 —
/// 대화는 글 채팅으로 계속한다. 토글·버튼 없이 늘 듣는다 (F-018). 위젯 없이 가짜 에이전트로 단위 테스트한다.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../api/models.dart';
import '../chat/chat_controller.dart';
import 'realtime_agent.dart';
import 'voice_session.dart';

export 'voice_session.dart';

/// 화면에 보여 줄 실시간 음성 안내.
abstract final class AgentMessages {
  static const connecting = '연결하고 있어요. 잠깐만요.';
  static const reconnecting = '잠깐 연결이 끊겼어요. 다시 연결하고 있어요.';
  static const failed = '음성 대화에 연결하지 못했어요. 글로 이야기하거나 잠시 뒤 다시 눌러 주세요.';
  static const serverOff = '지금은 음성 대화를 할 수 없어요. 글로 이야기해 주세요.';
  static const noConfig = '서버에 연결하지 못해 음성 대화를 시작할 수 없어요. 네트워크를 확인해 주세요.';
  static const unsupported = '이 브라우저에서는 음성 대화를 할 수 없어요. Chrome이나 Safari 최신 버전에서 열어 주세요.';
  static const micDenied = '마이크를 쓸 수 없어요. 브라우저 설정에서 이 사이트의 마이크를 허용해 주세요.';
}

class AgentVoiceController extends ChangeNotifier implements VoiceSession {
  AgentVoiceController(
    this._chat,
    this._fetchToken, {
    this.agent,
    this.retryDelay = const Duration(seconds: 1),
    this.maxConnectFailures = 3,
    this.connectTimeout = const Duration(seconds: 15),
  }) {
    _sub = agent?.events.listen(_onEvent);
  }

  final ChatController _chat;

  /// 서버에서 API-007 임시 키를 받는다 (인자는 페르소나·기억·내역). 실패하면 [VoiceTokenFailed].
  final Future<String> Function(Map<String, Object?> context) _fetchToken;

  /// 이 브라우저의 실시간 음성 에이전트. 없으면(WebRTC·마이크 없음, 테스트 VM) 음성 대화를 켜지 않는다.
  final RealtimeAgent? agent;
  StreamSubscription<AgentEvent>? _sub;

  /// 끊겼을 때 다시 연결하기까지 기다리는 시간. 연달아 끊기면 1 · 2 · 4 · 8 · 16배 (F-024 AC6).
  final Duration retryDelay;

  /// 한 번도 연결되지 못하고 이만큼 연달아 실패하면 알리고 끈다 (F-024 상세 7).
  final int maxConnectFailures;

  /// 이만큼 기다려도 연결되지 않으면 실패로 본다 — 연결이 실패도 끊김도 알리지 않고 멈출 수 있다.
  final Duration connectTimeout;

  VoiceState _state = VoiceState.off;
  String _partial = '';
  String _sentence = '';
  String? _notice;
  var _connected = false;
  var _connectFailures = 0;
  var _retries = 0;
  var _gen = 0; // 연결 세대 — 끄기·다시 연결 때 늘려 이전 연결의 사건을 무시한다
  var _disposed = false;
  var _suspended = false;
  Timer? _timeout; // 연결 시간 초과 — 연결되거나 끄면 취소한다

  @override
  VoiceState get state => _state;
  @override
  bool get active => _state != VoiceState.off;
  @override
  String get partial => _partial;
  @override
  String get sentence => _sentence;
  @override
  String? get notice => _notice;

  /// 에이전트가 주는 마이크 소리 크기(주지 못하면 0 — 파형은 상태에 따라 저절로 움직인다).
  @override
  ValueListenable<double> get level => agent?.level ?? silentLevel;
  @override
  bool get supported => agent != null;

  @override
  void toggle() {
    if (_state == VoiceState.off) {
      unawaited(start());
    } else {
      stop();
    }
  }

  /// 화면 누르기: 꺼져 있으면 켠다. 켜져 있으면 아무것도 하지 않는다 — 끼어들기는 말로 하면 에이전트가 알아서 멈춘다.
  @override
  void tap() {
    if (_state == VoiceState.off) unawaited(start());
  }

  @override
  Future<void> start() async {
    if (active) return;
    _notice = null;
    if (agent == null) return _off(AgentMessages.unsupported);
    // 앱을 켜자마자 음성 대화를 시작하면 서버 설정(voiceAgent)이 아직 안 왔을 수 있다 — 기다렸다가 고른다
    if (_chat.config == null) {
      await _chat.loadConfig();
      if (_disposed || active) return;
    }
    final config = _chat.config;
    if (config == null) {
      debugPrint('실시간 음성 꺼짐: 서버 설정(/api/config)을 받지 못함');
      return _off(AgentMessages.noConfig);
    }
    if (!config.voiceAgent) {
      debugPrint('실시간 음성 꺼짐: 서버가 voiceAgent=none — chatd의 OpenAI 키 설정 확인');
      return _off(AgentMessages.serverOff);
    }
    _connectFailures = 0;
    _retries = 0;
    _state = VoiceState.thinking;
    _notice = AgentMessages.connecting;
    _notify();
    await _connect();
  }

  Future<void> _connect() async {
    final gen = ++_gen;
    _connected = false;
    _timeout?.cancel();
    _timeout = Timer(connectTimeout, () {
      if (gen != _gen || _disposed || _connected || _state == VoiceState.off) return;
      debugPrint('실시간 음성: 연결 시간 초과');
      _gen++; // 늦게 오는 이 연결의 사건은 무시한다
      unawaited(agent?.end());
      _connectFailed();
    });
    try {
      final context = _chat.voiceContext();
      final token = await _fetchToken(context);
      if (gen != _gen || _disposed) return;
      await agent!.start(token: token, context: context);
    } on VoiceTokenFailed {
      debugPrint('실시간 음성: 서버가 임시 키를 주지 못함');
      if (gen == _gen && !_disposed) _giveUp(); // 서버가 키를 못 줌 → 다시 해도 소용없다
    } catch (e) {
      debugPrint('실시간 음성: 연결 실패 (${e.runtimeType})');
      if (gen == _gen && !_disposed) _connectFailed();
    }
  }

  void _connectFailed() {
    _connectFailures++;
    if (_connectFailures >= maxConnectFailures) return _giveUp();
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    _retries++;
    _state = VoiceState.thinking;
    _partial = '';
    _sentence = '';
    _notice = AgentMessages.reconnecting;
    _notify();
    final gen = ++_gen;
    final delay = retryDelay * (1 << (_retries - 1).clamp(0, 4));
    unawaited(
      Future<void>.delayed(delay, () {
        if (gen != _gen || _disposed || _state == VoiceState.off) return;
        if (_suspended) return; // 돌아오면 resume이 다시 연결한다
        unawaited(_connect());
      }),
    );
  }

  /// 연결을 포기하고 한 번 알린다 — 대화는 글 채팅으로 계속한다 (F-024 AC6).
  void _giveUp() {
    _gen++;
    unawaited(agent?.end());
    _off(AgentMessages.failed);
  }

  void _off(String notice) {
    _timeout?.cancel();
    _state = VoiceState.off;
    _partial = '';
    _sentence = '';
    _suspended = false;
    _notice = notice;
    _notify();
  }

  void _onEvent(AgentEvent e) {
    if (_disposed || _state == VoiceState.off) return;
    switch (e) {
      case AgentConnected():
        _connected = true;
        _timeout?.cancel();
        _connectFailures = 0;
        _retries = 0;
        _notice = null;
        _state = VoiceState.listening;
        if (_suspended) unawaited(agent?.setMuted(true));
      case AgentMode(:final speaking):
        _state = speaking ? VoiceState.speaking : VoiceState.listening;
        if (!speaking) _sentence = '';
      case AgentHeardPartial(:final text):
        _partial = text;
        if (_state == VoiceState.speaking) _sentence = ''; // 끼어들었다 — 에이전트가 멈춘다
      case AgentHeard(:final text):
        _partial = '';
        _chat.addVoiceTurn(Role.user, text);
        if (_state != VoiceState.speaking) _state = VoiceState.thinking;
      case AgentReply(:final text):
        _sentence = text;
        _chat.addVoiceTurn(Role.assistant, text);
      case AgentFailed(:final micDenied):
        if (micDenied) {
          // 권한이 없으면 다시 연결해도 소용없다 — 멈추고 알린다 (F-025 AC4)
          stop();
          _notice = AgentMessages.micDenied;
        }
      // 그 밖의 오류는 끊기면 AgentDisconnected가 따로 온다
      case AgentDisconnected(:final byUser):
        if (byUser) return;
        // 늘 듣는 것이 목표 — 에이전트·네트워크가 끊어도 다시 연결한다 (F-024 AC6)
        if (_connected) {
          _scheduleReconnect();
        } else {
          _connectFailed();
        }
    }
    _notify();
  }

  @override
  void stop() {
    if (_state == VoiceState.off) {
      if (_notice != null) {
        _notice = null;
        _notify();
      }
      return;
    }
    _gen++;
    _timeout?.cancel();
    unawaited(agent?.end());
    _state = VoiceState.off;
    _partial = '';
    _sentence = '';
    _notice = null;
    _suspended = false;
    _notify();
  }

  /// 앱이 뒤로 감: 마이크만 끈다. 연결과 대화는 그대로.
  @override
  void pause() {
    if (_state == VoiceState.off || _suspended) return;
    _suspended = true;
    unawaited(agent?.setMuted(true));
  }

  /// 앱이 돌아옴: 마이크를 다시 켜고, 그사이 끊겼으면 다시 연결한다.
  @override
  void resume() {
    final was = _suspended;
    _suspended = false;
    if (_state == VoiceState.off || !was) return;
    if (_connected) {
      unawaited(agent?.setMuted(false));
    } else {
      _retries = 0;
      unawaited(_connect());
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _gen++;
    _timeout?.cancel();
    unawaited(_sub?.cancel());
    agent?.dispose();
    super.dispose();
  }
}
