/// S-003 음성 전용 화면 (SPEC.md F-018). MVP HTML 디자인의 "음성 대화" 화면을 Flutter로 옮겼다.
/// 상태는 [VoiceController]·[ChatController]가 갖고, 이 위젯은 그리기와 버튼 연결만 한다.
library;

import 'package:flutter/material.dart';

import '../chat/chat_controller.dart';
import '../voice/voice_controller.dart';
import 'persona_widgets.dart';
import 'theme.dart';

/// 음성 전용 화면을 열고, 음성 모드가 꺼져 있으면 바로 듣기 시작한다 (F-018 AC1).
Future<void> openVoicePage(BuildContext context, {required ChatController chat, required VoiceController voice}) {
  if (!voice.active) voice.start();
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => VoicePage(chat: chat, voice: voice),
    ),
  );
}

class VoicePage extends StatefulWidget {
  const VoicePage({super.key, required this.chat, required this.voice});

  final ChatController chat;
  final VoiceController voice;

  @override
  State<VoicePage> createState() => _VoicePageState();
}

class _VoicePageState extends State<VoicePage> with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));

  VoiceController get _voice => widget.voice;
  ChatController get _chat => widget.chat;

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  /// 글로 보기 · 뒤로: 음성 대화는 그대로 두고 채팅 화면으로 (F-018 AC5).
  void _toText() => Navigator.of(context).maybePop();

  /// 끝내기: 음성 모드를 끄고 채팅 화면으로 (F-018 AC5, F-012 AC4).
  void _end() {
    _voice.stop();
    Navigator.of(context).maybePop();
  }

  /// 듣는 중·읽는 중에만 원이 숨 쉬듯 커졌다 작아진다. 움직임 줄이기 설정이면 멈춘다.
  void _syncPulse(bool on) {
    if (on && !_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    } else if (!on && _pulse.isAnimating) {
      _pulse
        ..stop()
        ..value = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = ChatColors.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([_voice, _chat, ?_chat.personas]),
      builder: (context, _) {
        final view = _VoiceView.of(_voice, _chat, c);
        _syncPulse(view.pulse && !MediaQuery.disableAnimationsOf(context));
        return Scaffold(
          key: const Key('voice-page'),
          backgroundColor: c.bg,
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Column(
                  children: [
                    _header(c),
                    Expanded(child: _center(c, view)),
                    _controls(c, view),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _header(ChatColors c) {
    final persona = _chat.personas?.selected;
    return SizedBox(
      height: 64,
      child: Row(
        children: [
          const SizedBox(width: 4),
          IconButton(
            key: const Key('voice-back'),
            tooltip: '채팅으로 돌아가기',
            onPressed: _toText,
            icon: const Icon(Icons.chevron_left, size: 28),
          ),
          if (persona != null) ...[PersonaAvatar(persona: persona, size: 32), const SizedBox(width: 10)],
          Expanded(
            child: Text(
              persona?.name ?? '음성 대화',
              key: const Key('voice-persona'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: c.text, fontSize: 15, fontWeight: FontWeight.w700),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: c.user.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(999)),
            child: Text(
              '음성',
              style: TextStyle(color: c.user, fontSize: 12, fontWeight: FontWeight.w500),
            ),
          ),
          const SizedBox(width: 12),
        ],
      ),
    );
  }

  Widget _center(ChatColors c, _VoiceView view) {
    return LayoutBuilder(
      builder: (context, box) {
        // 낮은 화면(가로 모드)에서는 원을 줄인다
        final orb = (box.maxHeight * 0.42).clamp(96.0, 200.0);
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: box.maxHeight),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ScaleTransition(
                  scale: Tween(begin: 1.0, end: 1.08).animate(CurvedAnimation(parent: _pulse, curve: Curves.easeInOut)),
                  child: Container(
                    width: orb,
                    height: orb,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: view.orbOuter, shape: BoxShape.circle),
                    child: Container(
                      width: orb * 0.64,
                      height: orb * 0.64,
                      decoration: BoxDecoration(color: view.orbInner, shape: BoxShape.circle),
                      child: Icon(Icons.graphic_eq, size: orb * 0.28, color: view.orbIcon),
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    view.label,
                    key: const Key('voice-page-label'),
                    style: TextStyle(color: c.text, fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(height: 20),
                ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 84),
                  child: Text(
                    view.caption,
                    key: const Key('voice-page-caption'),
                    textAlign: TextAlign.center,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: view.captionColor, fontSize: 16, height: 1.65),
                  ),
                ),
                const SizedBox(height: 8),
                ExcludeSemantics(child: _steps(c, view.step)),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 듣기 · 생각 · 읽기 단계 표시 (지금 단계만 진하게).
  Widget _steps(ChatColors c, int? current) {
    const names = ['듣기', '생각', '읽기'];
    return Wrap(
      spacing: 6,
      children: [
        for (var i = 0; i < names.length; i++)
          Container(
            key: Key('voice-step-$i'),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: i == current ? c.text : c.agent, borderRadius: BorderRadius.circular(999)),
            child: Text(names[i], style: TextStyle(fontSize: 12, color: i == current ? c.bg : c.muted)),
          ),
      ],
    );
  }

  Widget _controls(ChatColors c, _VoiceView view) {
    final round = IconButton.styleFrom(minimumSize: const Size(56, 56), fixedSize: const Size(56, 56));
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 36),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_voice.state == VoiceState.speaking)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Text('말을 시작하면 읽기를 멈추고 들어요', style: TextStyle(color: c.muted, fontSize: 12)),
            ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                key: const Key('voice-to-text'),
                tooltip: '글로 보기',
                onPressed: _toText,
                style: round.copyWith(
                  backgroundColor: WidgetStatePropertyAll(c.panel),
                  foregroundColor: WidgetStatePropertyAll(c.text),
                  side: WidgetStatePropertyAll(BorderSide(color: c.line)),
                ),
                icon: const Icon(Icons.chat_bubble_outline, size: 22),
              ),
              const SizedBox(width: 28),
              IconButton(
                key: const Key('voice-main'),
                tooltip: view.mainTooltip,
                onPressed: _voice.toggle,
                style: IconButton.styleFrom(
                  minimumSize: const Size(76, 76),
                  fixedSize: const Size(76, 76),
                  backgroundColor: c.user,
                  foregroundColor: c.userText,
                ),
                icon: Icon(view.mainIcon, size: 28),
              ),
              const SizedBox(width: 28),
              IconButton(
                key: const Key('voice-end'),
                tooltip: '음성 대화 끝내기',
                onPressed: _end,
                style: round.copyWith(
                  backgroundColor: WidgetStatePropertyAll(c.errorBg),
                  foregroundColor: WidgetStatePropertyAll(c.error),
                ),
                icon: const Icon(Icons.close, size: 22),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            view.action,
            key: const Key('voice-page-action'),
            style: TextStyle(color: c.muted, fontSize: 13, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}

/// 음성 상태 → 화면에 그릴 것 (문구·색·버튼). 위젯과 떨어뜨려 한 곳에서 정한다.
class _VoiceView {
  const _VoiceView({
    required this.label,
    required this.caption,
    required this.captionColor,
    required this.action,
    required this.mainIcon,
    required this.mainTooltip,
    required this.orbOuter,
    required this.orbInner,
    required this.orbIcon,
    required this.pulse,
    this.step,
  });

  final String label, caption, action, mainTooltip;
  final Color captionColor, orbOuter, orbInner, orbIcon;
  final IconData mainIcon;
  final bool pulse;
  final int? step;

  static _VoiceView of(VoiceController voice, ChatController chat, ChatColors c) {
    final userTint = Color.alphaBlend(c.user.withValues(alpha: 0.12), c.panel);
    final userDeep = Color.alphaBlend(Colors.black.withValues(alpha: 0.25), c.user);
    switch (voice.state) {
      case VoiceState.off:
        final notice = voice.notice;
        return _VoiceView(
          label: notice == null ? '잠시 멈췄어요' : '음성을 쓸 수 없어요',
          caption: notice ?? '가운데 버튼을 누르면 다시 들어요',
          captionColor: notice == null ? c.muted : c.error,
          action: notice == null ? '눌러서 말하기' : '다시 시도',
          mainIcon: Icons.mic_none,
          mainTooltip: '듣기 시작',
          orbOuter: c.agent,
          orbInner: c.panel,
          orbIcon: c.muted,
          pulse: false,
        );
      case VoiceState.listening:
        final heard = voice.partial;
        return _VoiceView(
          label: '듣고 있어요',
          caption: heard.isEmpty ? '말씀하세요. 말이 끝나면 자동으로 보내요' : '“$heard”',
          captionColor: heard.isEmpty ? c.muted : c.text,
          action: '말 끝나면 자동으로 보내요',
          mainIcon: Icons.mic,
          mainTooltip: '잠시 멈추기',
          orbOuter: userTint,
          orbInner: c.panel,
          orbIcon: c.user,
          pulse: true,
          step: 0,
        );
      case VoiceState.thinking:
        final asked = chat.entries.reversed.where((e) => e.isUser).firstOrNull?.text ?? '';
        return _VoiceView(
          label: '생각하고 있어요',
          caption: asked.isEmpty ? '' : '보낸 말: $asked',
          captionColor: c.muted,
          action: '답을 준비하고 있어요',
          mainIcon: Icons.front_hand_outlined,
          mainTooltip: '끼어들기 — 멈추고 다시 듣기',
          orbOuter: c.agent,
          orbInner: c.panel,
          orbIcon: c.muted,
          pulse: false,
          step: 1,
        );
      case VoiceState.speaking:
        return _VoiceView(
          label: '말하고 있어요',
          caption: voice.sentence,
          captionColor: c.text,
          action: '끼어들기',
          mainIcon: Icons.front_hand_outlined,
          mainTooltip: '끼어들기 — 읽기를 멈추고 듣기',
          orbOuter: c.user,
          orbInner: userDeep,
          orbIcon: c.userText,
          pulse: true,
          step: 2,
        );
    }
  }
}
