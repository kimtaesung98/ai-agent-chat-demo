/// 실시간 음성 대화 (SPEC.md F-022, ARCHITECTURE.md ADR-025).
/// 서버가 ElevenLabs Agents를 켜 두었고 이 기기에 실시간 에이전트가 있으면 그것으로 대화하고,
/// 아니면(웹·서버 설정 없음·토큰 실패·연결이 계속 안 됨) 기기 음성([VoiceController], F-012)으로 대화한다.
/// 어느 쪽이든 화면은 같다 — 토글·버튼 없이 늘 듣는다 (F-018). 위젯 없이 가짜 에이전트로 단위 테스트한다.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../api/models.dart';
import '../chat/chat_controller.dart';
import 'realtime_agent.dart';
import 'voice_controller.dart';

/// 화면에 보여 줄 실시간 음성 안내.
abstract final class AgentMessages {
  static const connecting = '연결하고 있어요. 잠깐만요.';
  static const reconnecting = '잠깐 연결이 끊겼어요. 다시 연결하고 있어요.';
  static const fellBack = '실시간 음성에 연결하지 못해 기기 음성으로 대화할게요.';
}

class AgentVoiceController extends ChangeNotifier implements VoiceSession {
  AgentVoiceController(
    this._chat,
    this._fetchToken,
    this._fallback, {
    this.agent,
    this.retryDelay = const Duration(seconds: 1),
    this.maxConnectFailures = 3,
  }) {
    _fallback.addListener(_onFallback);
    _sub = agent?.events.listen(_onEvent);
  }

  final ChatController _chat;

  /// 서버에서 대화 토큰을 받는다 (API-005, `ChatApi.voiceToken`). 실패하면 [VoiceTokenFailed].
  final Future<String> Function() _fetchToken;
  final VoiceController _fallback;

  /// 이 기기의 실시간 음성 에이전트. 없으면(웹) 늘 기기 음성.
  final RealtimeAgent? agent;
  StreamSubscription<AgentEvent>? _sub;

  /// 끊겼을 때 다시 연결하기까지 기다리는 시간. 연달아 끊기면 1 · 2 · 4 · 8 · 16배 (F-022 AC7).
  final Duration retryDelay;

  /// 한 번도 연결되지 못하고 이만큼 연달아 실패하면 기기 음성으로 바꾼다 (F-022 AC6).
  final int maxConnectFailures;

  var _useFallback = false;
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

  /// 지금 실시간 음성(ElevenLabs)으로 대화 중인지. 기기 음성이면 false.
  bool get realtime => !_useFallback && _state != VoiceState.off;

  @override
  VoiceState get state => _useFallback ? _fallback.state : _state;
  @override
  bool get active => state != VoiceState.off;
  @override
  String get partial => _useFallback ? _fallback.partial : _partial;
  @override
  String get sentence => _useFallback ? _fallback.sentence : _sentence;
  @override
  String? get notice => _useFallback ? (_fallback.notice ?? _notice) : _notice;
  @override
  bool get supported => agent != null || _fallback.supported;

  bool get _canRealtime => agent != null && (_chat.config?.voiceAgent ?? false);

  @override
  void toggle() {
    if (_useFallback) return _fallback.toggle();
    if (_state == VoiceState.off) {
      unawaited(start());
    } else {
      stop();
    }
  }

  /// 화면 누르기: 꺼져 있으면 켠다. 켜져 있으면 아무것도 하지 않는다 — 끼어들기는 말로 하면 에이전트가 알아서 멈춘다.
  @override
  void tap() {
    if (_useFallback) return _fallback.tap();
    if (_state == VoiceState.off) unawaited(start());
  }

  @override
  Future<void> start() async {
    if (active) return;
    _notice = null;
    if (!_canRealtime) {
      _useFallback = true;
      return _fallback.start();
    }
    _useFallback = false;
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
    try {
      final token = await _fetchToken();
      if (gen != _gen || _disposed) return;
      await agent!.start(
        token: token,
        context: _chat.voiceContext(),
        variables: {'persona_name': _chat.personas?.selected.name ?? ''},
      );
    } on VoiceTokenFailed {
      if (gen == _gen && !_disposed) _toFallback(); // 서버가 토큰을 못 줌 → 바로 기기 음성
    } catch (_) {
      if (gen == _gen && !_disposed) _connectFailed();
    }
  }

  void _connectFailed() {
    _connectFailures++;
    if (_connectFailures >= maxConnectFailures) return _toFallback();
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

  /// 기기 음성으로 바꿔 계속 대화한다 (F-022 AC6).
  void _toFallback() {
    _gen++;
    unawaited(agent?.end());
    _state = VoiceState.off;
    _partial = '';
    _sentence = '';
    _useFallback = true;
    _notice = AgentMessages.fellBack;
    _notify();
    unawaited(_fallback.start());
  }

  void _onEvent(AgentEvent e) {
    if (_disposed || _useFallback || _state == VoiceState.off) return;
    switch (e) {
      case AgentConnected():
        _connected = true;
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
      case AgentFailed():
        break; // 끊기면 AgentDisconnected가 따로 온다
      case AgentDisconnected(:final byUser):
        if (byUser) return;
        // 늘 듣는 것이 목표 — 에이전트·네트워크가 끊어도 다시 연결한다 (F-022 AC7)
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
    if (_useFallback) {
      _fallback.stop();
      _useFallback = false;
      _notice = null;
      _notify();
      return;
    }
    if (_state == VoiceState.off) return;
    _gen++;
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
    if (_useFallback) return _fallback.pause();
    if (_state == VoiceState.off || _suspended) return;
    _suspended = true;
    unawaited(agent?.setMuted(true));
  }

  /// 앱이 돌아옴: 마이크를 다시 켜고, 그사이 끊겼으면 다시 연결한다.
  @override
  void resume() {
    if (_useFallback) return _fallback.resume();
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

  void _onFallback() {
    if (_useFallback) _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _gen++;
    _fallback.removeListener(_onFallback);
    unawaited(_sub?.cancel());
    agent?.dispose();
    super.dispose();
  }
}
