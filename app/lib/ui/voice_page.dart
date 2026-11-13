/// S-003 음성 대화 화면 (SPEC.md F-018). 어르신도 쓰기 쉽게, 버튼 없이 계속 이어지는 대화.
/// 화면 아무 데나 누르면 말을 끊고(끼어들기) 듣는다. 끄는 것은 아래 "대화 끝내기" 하나뿐이다.
/// 상태는 [VoiceSession]·[ChatController]가 갖고, 이 위젯은 그리기와 누르기 연결만 한다.
library;

import 'package:flutter/material.dart';

import '../chat/chat_controller.dart';
import '../voice/voice_controller.dart';
import 'keep_awake.dart';
import 'persona_widgets.dart';
import 'theme.dart';
import 'voice_wave.dart';

/// 음성 대화 화면을 열고, 음성 모드가 꺼져 있으면 바로 듣기 시작한다 (F-018 AC1).
Future<void> openVoicePage(
  BuildContext context, {
  required ChatController chat,
  required VoiceSession voice,
  bool wakeLock = true,
}) {
  if (!voice.active) voice.start();
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => VoicePage(chat: chat, voice: voice, wakeLock: wakeLock),
    ),
  );
}

class VoicePage extends StatefulWidget {
  const VoicePage({super.key, required this.chat, required this.voice, this.wakeLock = true});

  final ChatController chat;
  final VoiceSession voice;

  /// 이 브라우저가 화면 꺼짐 막기를 지원하는지 (F-025 AC4). 아니면 한 번 안내한다.
  final bool wakeLock;

  /// 화면 꺼짐 막기를 지원하지 않을 때 보이는 안내.
  static const noWakeLock = '이 브라우저는 화면 꺼짐을 막지 못해요. 대화하는 동안 화면을 켜 두세요.';

  @override
  State<VoicePage> createState() => _VoicePageState();
}

class _VoicePageState extends State<VoicePage> with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));

  VoiceSession get _voice => widget.voice;
  ChatController get _chat => widget.chat;

  /// 탭·앱이 다시 보이면 화면 꺼짐 막기를 다시 켠다 (브라우저는 가려질 때 스스로 푼다).
  late final _lifecycle = AppLifecycleListener(onShow: () => setKeepAwake(true));

  @override
  void initState() {
    super.initState();
    setKeepAwake(true); // 이 화면에 있는 동안은 화면이 꺼지지 않는다 — 늘 듣기 위해 (F-018 AC8)
    _lifecycle;
    if (!widget.wakeLock) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.maybeOf(context)
            ?.showSnackBar(const SnackBar(content: Text(VoicePage.noWakeLock), duration: Duration(seconds: 6)));
      });
    }
  }

  @override
  void dispose() {
    setKeepAwake(false);
    _lifecycle.dispose();
    _pulse.dispose();
    super.dispose();
  }

  /// 글자로 보기: 음성 대화는 그대로 두고 채팅 화면으로 (F-018 AC5).
  void _toText() => Navigator.of(context).maybePop();

  /// 대화 끝내기: 음성 모드를 끄고 채팅 화면으로 (F-018 AC5, F-012 AC4). 지금 대화를 정리해 다음 대화의 기억으로 남긴다 (F-019 AC3).
  void _end() {
    _voice.stop();
    _chat.endSession();
    Navigator.of(context).maybePop();
  }

  /// 듣는 중·말하는 중에만 원이 숨 쉬듯 커졌다 작아진다. 움직임 줄이기 설정이면 멈춘다.
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
                constraints: const BoxConstraints(maxWidth: 520),
                child: Column(
                  children: [
                    _header(c),
                    Expanded(child: _center(c, view)),
                    _endButton(c),
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
      child: Row(
        children: [
          if (persona != null) ...[PersonaAvatar(persona: persona, size: 40), const SizedBox(width: 12)],
          Expanded(
            child: Text(
              persona?.name ?? '음성 대화',
              key: const Key('voice-persona'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: c.text, fontSize: 18, fontWeight: FontWeight.w700),
            ),
          ),
          TextButton.icon(
            key: const Key('voice-to-text'),
            onPressed: _toText,
            style: TextButton.styleFrom(foregroundColor: c.text, minimumSize: const Size(48, 48)),
            icon: const Icon(Icons.chat_bubble_outline, size: 22),
            label: const Text('글자로 보기', style: TextStyle(fontSize: 16)),
          ),
        ],
      ),
    );
  }

  /// 가운데 전체가 누르는 자리다: 생각·말하는 중에 누르면 말을 끊고 듣는다 (F-018 AC4).
  Widget _center(ChatColors c, _VoiceView view) {
    return Semantics(
      button: view.tapLabel != null,
      label: view.tapLabel,
      child: GestureDetector(
        key: const Key('voice-tap-area'),
        behavior: HitTestBehavior.opaque,
        onTap: _voice.tap,
        child: LayoutBuilder(
          builder: (context, box) {
            // 낮은 화면(가로 모드)에서는 원을 줄인다
            final orb = (box.maxHeight * 0.4).clamp(96.0, 220.0);
            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: box.maxHeight),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ScaleTransition(
                      scale: Tween(
                        begin: 1.0,
                        end: 1.08,
                      ).animate(CurvedAnimation(parent: _pulse, curve: Curves.easeInOut)),
                      child: Container(
                        width: orb,
                        height: orb,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(color: view.orbOuter, shape: BoxShape.circle),
                        child: Container(
                          width: orb * 0.64,
                          height: orb * 0.64,
                          decoration: BoxDecoration(color: view.orbInner, shape: BoxShape.circle),
                          child: Icon(view.orbIconData, size: orb * 0.28, color: view.orbIcon),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    VoiceWave(
                      key: const Key('voice-wave'),
                      level: _voice.level,
                      color: c.user,
                      moving: view.pulse,
                      speaking: _voice.state == VoiceState.speaking,
                      height: (orb * 0.25).clamp(32.0, 56.0),
                    ),
                    const SizedBox(height: 20),
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        view.label,
                        key: const Key('voice-page-label'),
                        textAlign: TextAlign.center,
                        style: TextStyle(color: c.text, fontSize: 28, fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(height: 16),
                    ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 110),
                      child: Text(
                        view.caption,
                        key: const Key('voice-page-caption'),
                        textAlign: TextAlign.center,
                        maxLines: 5,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: view.captionColor, fontSize: 22, height: 1.55),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      view.hint,
                      key: const Key('voice-page-hint'),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: c.muted, fontSize: 17, height: 1.5),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _endButton(ChatColors c) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: SizedBox(
        width: double.infinity,
        height: 64,
        child: FilledButton.icon(
          key: const Key('voice-end'),
          onPressed: _end,
          style: FilledButton.styleFrom(
            backgroundColor: c.errorBg,
            foregroundColor: c.error,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
          ),
          icon: const Icon(Icons.call_end, size: 28),
          label: const Text('대화 끝내기', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        ),
      ),
    );
  }
}

/// 음성 상태 → 화면에 그릴 것 (문구·색). 위젯과 떨어뜨려 한 곳에서 정한다.
class _VoiceView {
  const _VoiceView({
    required this.label,
    required this.caption,
    required this.captionColor,
    required this.hint,
    required this.orbOuter,
    required this.orbInner,
    required this.orbIcon,
    required this.orbIconData,
    required this.pulse,
    this.tapLabel,
  });

  final String label, caption, hint;
  final Color captionColor, orbOuter, orbInner, orbIcon;
  final IconData orbIconData;
  final bool pulse;

  /// 누르면 하는 일 (스크린 리더용). 듣는 중에는 누를 일이 없어 null.
  final String? tapLabel;

  static _VoiceView of(VoiceSession voice, ChatController chat, ChatColors c) {
    final userTint = Color.alphaBlend(c.user.withValues(alpha: 0.12), c.panel);
    final userDeep = Color.alphaBlend(Colors.black.withValues(alpha: 0.25), c.user);
    final notice = voice.notice;
    switch (voice.state) {
      case VoiceState.off:
        return _VoiceView(
          label: notice == null ? '대화가 멈췄어요' : '목소리를 들을 수 없어요',
          caption: notice ?? '',
          captionColor: notice == null ? c.muted : c.error,
          hint: '화면을 누르면 다시 들어요',
          orbOuter: c.agent,
          orbInner: c.panel,
          orbIcon: c.muted,
          orbIconData: Icons.mic_off_outlined,
          pulse: false,
          tapLabel: '다시 듣기',
        );
      case VoiceState.listening:
        final heard = voice.partial;
        return _VoiceView(
          label: '듣고 있어요',
          caption: notice ?? (heard.isEmpty ? '' : '“$heard”'),
          captionColor: notice != null || heard.isEmpty ? c.muted : c.text,
          hint: '편하게 말씀하세요.\n말씀이 끝나면 제가 대답할게요.',
          orbOuter: userTint,
          orbInner: c.panel,
          orbIcon: c.user,
          orbIconData: Icons.graphic_eq,
          pulse: true,
        );
      case VoiceState.thinking:
        final asked = chat.entries.reversed.where((e) => e.isUser).firstOrNull?.text ?? '';
        return _VoiceView(
          label: '생각하고 있어요',
          caption: asked.isEmpty ? '' : '“$asked”',
          captionColor: c.muted,
          hint: '잠시만 기다려 주세요',
          orbOuter: c.agent,
          orbInner: c.panel,
          orbIcon: c.muted,
          orbIconData: Icons.more_horiz,
          pulse: false,
          tapLabel: '말 끊고 다시 듣기',
        );
      case VoiceState.speaking:
        return _VoiceView(
          label: '말하고 있어요',
          caption: voice.sentence,
          captionColor: c.text,
          hint: '말씀하시거나 화면을 누르면\n멈추고 들을게요',
          orbOuter: c.user,
          orbInner: userDeep,
          orbIcon: c.userText,
          orbIconData: Icons.graphic_eq,
          pulse: true,
          tapLabel: '말 끊고 다시 듣기',
        );
    }
  }
}
