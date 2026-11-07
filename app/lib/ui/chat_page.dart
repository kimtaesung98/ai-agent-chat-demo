/// S-001 채팅 화면. 상태는 [ChatController]가 갖고, 이 위젯은 그리기와 입력 연결만 한다.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../chat/chat_controller.dart';
import '../voice/voice_controller.dart';
import 'theme.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({super.key, required this.controller, this.voice});

  final ChatController controller;

  /// 음성 대화 (F-012). 없으면 마이크 버튼을 그리지 않는다.
  final VoiceController? voice;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _input = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  bool _wasBusy = false;

  ChatController get _chat => widget.controller;
  VoiceController? get _voice => widget.voice;

  @override
  void initState() {
    super.initState();
    _chat.addListener(_onChange);
  }

  @override
  void dispose() {
    _chat.removeListener(_onChange);
    _input.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onChange() {
    // 응답이 끝나면 입력창에 다시 초점 (F-001 AC2), 새 조각이 오면 맨 아래로
    if (_wasBusy && !_chat.busy) _focus.requestFocus();
    _wasBusy = _chat.busy;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  void _submit() {
    if (_chat.send(_input.text)) _input.clear(); // 빈 메시지는 보내지 않음 (F-001 AC3)
  }

  @override
  Widget build(BuildContext context) {
    final c = ChatColors.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([_chat, ?_voice]),
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          backgroundColor: c.panel,
          surfaceTintColor: Colors.transparent,
          shape: Border(bottom: BorderSide(color: c.line)),
          title: Text(
            'AI Agent Chat',
            style: TextStyle(color: c.text, fontSize: 18, fontWeight: FontWeight.w600),
          ),
          actions: [
            _ModeBadge(chat: _chat),
            const SizedBox(width: 8),
            OutlinedButton(
              key: const Key('new-chat'),
              onPressed: _chat.entries.isEmpty ? null : _chat.reset,
              child: const Text('새 대화'),
            ),
            const SizedBox(width: 12),
          ],
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(
                children: [
                  Expanded(child: _log(c)),
                  if (_voice case final voice?) _VoiceBar(voice: voice),
                  _composer(c),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _log(ChatColors c) {
    final entries = _chat.entries;
    if (entries.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            '무엇이든 물어보세요. 답이 만들어지는 대로 바로 보여 드려요.',
            key: const Key('empty'),
            textAlign: TextAlign.center,
            style: TextStyle(color: c.muted),
          ),
        ),
      );
    }
    return Semantics(
      label: '대화',
      container: true,
      child: ListView.builder(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
        itemCount: entries.length,
        itemBuilder: (context, i) => _Bubble(entry: entries[i]),
      ),
    );
  }

  Widget _composer(ChatColors c) {
    final busy = _chat.busy;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: CallbackShortcuts(
              // Enter 전송 · Shift+Enter 줄바꿈 (F-001 상세 동작 1)
              bindings: {const SingleActivator(LogicalKeyboardKey.enter): _submit},
              child: TextField(
                key: const Key('input'),
                controller: _input,
                focusNode: _focus,
                autofocus: true,
                enabled: !busy,
                minLines: 1,
                maxLines: 6,
                maxLength: 4000,
                keyboardType: TextInputType.multiline,
                decoration: InputDecoration(
                  hintText: '메시지를 입력하세요 (Enter 전송 · Shift+Enter 줄바꿈)',
                  counterText: '',
                  filled: true,
                  fillColor: c.panel,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: c.line),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: c.line),
                  ),
                ),
              ),
            ),
          ),
          if (_voice case final voice?) ...[const SizedBox(width: 8), _MicButton(voice: voice)],
          const SizedBox(width: 8),
          SizedBox(
            height: 48,
            child: busy
                ? FilledButton.tonal(key: const Key('stop'), onPressed: _chat.stop, child: const Text('중단'))
                : FilledButton(
                    key: const Key('send'),
                    style: FilledButton.styleFrom(backgroundColor: c.user, foregroundColor: c.userText),
                    onPressed: _submit,
                    child: const Text('전송'),
                  ),
          ),
        ],
      ),
    );
  }
}

/// 마이크 버튼: 켜기 · 끄기 · 읽는 중 끼어들기 (F-012 AC5).
class _MicButton extends StatelessWidget {
  const _MicButton({required this.voice});
  final VoiceController voice;

  @override
  Widget build(BuildContext context) {
    final c = ChatColors.of(context);
    final (icon, tip) = switch (voice.state) {
      VoiceState.off => (Icons.mic_none, '음성 대화 시작'),
      VoiceState.listening => (Icons.mic, '음성 대화 끄기'),
      VoiceState.thinking || VoiceState.speaking => (Icons.front_hand_outlined, '끼어들기 — 읽기를 멈추고 듣기'),
    };
    return SizedBox(
      height: 48,
      width: 48,
      child: IconButton.filled(
        key: const Key('mic'),
        tooltip: tip,
        isSelected: voice.active,
        style: IconButton.styleFrom(
          backgroundColor: voice.active ? c.user : c.panel,
          foregroundColor: voice.active ? c.userText : c.text,
          side: BorderSide(color: voice.active ? c.user : c.line),
        ),
        onPressed: voice.toggle,
        icon: Icon(icon),
      ),
    );
  }
}

/// 음성 상태와 인식 중인 문장, 안내 (F-012 상세 동작 1·2·7).
class _VoiceBar extends StatelessWidget {
  const _VoiceBar({required this.voice});
  final VoiceController voice;

  @override
  Widget build(BuildContext context) {
    final c = ChatColors.of(context);
    if (voice.notice case final notice?) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
        child: Text(
          notice,
          key: const Key('voice-notice'),
          style: TextStyle(color: c.error, fontSize: 13),
        ),
      );
    }
    final label = switch (voice.state) {
      VoiceState.off => null,
      VoiceState.listening => voice.partial.isEmpty ? '듣는 중… 말씀하세요' : voice.partial,
      VoiceState.thinking => '생각 중…',
      VoiceState.speaking => '말하는 중 — 말하거나 손 버튼을 누르면 끼어들어요',
    };
    if (label == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Semantics(
        liveRegion: true,
        child: Row(
          children: [
            Icon(voice.state == VoiceState.speaking ? Icons.volume_up : Icons.graphic_eq, size: 16, color: c.user),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                label,
                key: const Key('voice-status'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: voice.partial.isEmpty ? c.muted : c.text, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModeBadge extends StatelessWidget {
  const _ModeBadge({required this.chat});
  final ChatController chat;

  @override
  Widget build(BuildContext context) {
    final c = ChatColors.of(context);
    final cfg = chat.config;
    final label = chat.configFailed
        ? '서버 연결 안 됨'
        : cfg == null
        ? '연결 중…'
        : cfg.isMock
        ? '모의 모드'
        : 'Claude · ${cfg.model}';
    final color = cfg != null && !cfg.isMock ? c.user : c.muted;
    return Tooltip(
      message: '현재 AI 제공자',
      child: Container(
        key: const Key('mode'),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: cfg != null && !cfg.isMock ? c.user : c.line),
        ),
        child: Text(label, style: TextStyle(color: color, fontSize: 13)),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.entry});
  final ChatEntry entry;

  @override
  Widget build(BuildContext context) {
    final c = ChatColors.of(context);
    final user = entry.isUser;
    final (bg, fg) = switch (entry.status) {
      _ when user => (c.user, c.userText),
      EntryStatus.error => (c.errorBg, c.error),
      _ => (c.agent, c.text),
    };
    final streaming = entry.status == EntryStatus.streaming;
    final bubble = Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      constraints: const BoxConstraints(maxWidth: 600),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(16),
          topRight: const Radius.circular(16),
          bottomLeft: Radius.circular(user ? 16 : 4),
          bottomRight: Radius.circular(user ? 4 : 16),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          SelectableText(streaming ? '${entry.text}▍' : entry.text, style: TextStyle(color: fg, height: 1.5)),
          if (entry.status == EntryStatus.stopped)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '중단됨',
                key: const Key('stopped'),
                style: TextStyle(color: c.muted, fontSize: 12),
              ),
            ),
        ],
      ),
    );
    return Align(
      alignment: user ? Alignment.centerRight : Alignment.centerLeft,
      // 스트리밍 중인 응답은 스크린 리더에 바로 알린다 (F-011 AC4, ARCHITECTURE §7)
      child: Semantics(liveRegion: streaming, child: bubble),
    );
  }
}
