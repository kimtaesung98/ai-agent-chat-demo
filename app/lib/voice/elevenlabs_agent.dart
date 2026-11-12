/// ElevenLabs Agents(WebRTC) 구현 (F-022, ADR-025). `elevenlabs_agents` 패키지는 이 파일에서만 import한다.
/// Android·iOS 전용 — 웹은 `realtime_agent_none.dart`(실시간 음성 없음 → 기기 음성).
library;

import 'dart:async';

import 'package:elevenlabs_agents/elevenlabs_agents.dart' as el;
import 'package:flutter/foundation.dart';

import 'realtime_agent.dart';

/// 이 플랫폼의 실시간 음성 에이전트.
RealtimeAgent? createRealtimeAgent() => ElevenLabsAgent();

class ElevenLabsAgent implements RealtimeAgent {
  final _events = StreamController<AgentEvent>.broadcast();
  el.ConversationClient? _client;
  var _ending = false;

  @override
  Stream<AgentEvent> get events => _events.stream;

  void _emit(AgentEvent e) {
    if (!_events.isClosed) _events.add(e);
  }

  @override
  Future<void> start({
    required String token,
    required Map<String, Object?> context,
    required Map<String, String> variables,
  }) async {
    await _dispose();
    _ending = false;
    final client = el.ConversationClient(
      callbacks: el.ConversationCallbacks(
        onConnect: ({required conversationId}) => _emit(const AgentConnected()),
        onDisconnect: (details) => _emit(AgentDisconnected(byUser: _ending || details.reason == 'user')),
        onModeChange: ({required mode}) => _emit(AgentMode(speaking: mode == el.ConversationMode.speaking)),
        onTentativeUserTranscript: ({required transcript, required eventId}) => _emit(AgentHeardPartial(transcript)),
        onUserTranscript: ({required transcript, required eventId}) => _emit(AgentHeard(transcript)),
        onMessage: ({required message, required source}) {
          if (source == el.Role.ai) _emit(AgentReply(message));
        },
        onError: (message, [context]) {
          debugPrint('실시간 음성 오류'); // 원문에 대화 내용이 섞일 수 있어 남기지 않는다
          _emit(const AgentFailed());
        },
      ),
    );
    _client = client;
    await client.startSession(
      conversationToken: token,
      customLlmExtraBody: Map<String, dynamic>.from(context),
      dynamicVariables: Map<String, dynamic>.from(variables),
    );
  }

  @override
  Future<void> end() async {
    _ending = true;
    await _client?.endSession();
  }

  @override
  Future<void> setMuted(bool muted) async => _client?.setMicMuted(muted);

  Future<void> _dispose() async {
    final c = _client;
    _client = null;
    if (c == null) return;
    _ending = true;
    try {
      await c.endSession();
    } catch (_) {}
    c.dispose();
  }

  @override
  void dispose() {
    unawaited(_dispose().whenComplete(_events.close));
  }
}
