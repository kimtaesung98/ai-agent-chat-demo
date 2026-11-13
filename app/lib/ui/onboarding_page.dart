/// S-005 첫 실행 — 대화 상대 고르기 (SPEC.md F-023). 큰 카드 하나를 누르고, 큰 버튼 하나로 시작한다.
/// "말로 이야기 시작하기"를 고르면 다음부터도 앱을 켜면 바로 음성 대화로 시작한다 (F-021 설정을 켠다).
library;

import 'package:flutter/material.dart';

import '../chat/auth_controller.dart';
import '../chat/persona_controller.dart';
import '../chat/start_settings.dart';
import 'big_button.dart';
import 'persona_widgets.dart';
import 'theme.dart';

/// 어르신 대상 서비스라 처음에는 노인복지사 미소를 추천한다.
const recommendedPersonaId = 'elder-care';

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key, required this.auth, required this.personas, this.start, this.hasVoice = false});

  final AuthController auth;
  final PersonaController personas;

  /// 앱 시작 설정 (F-021). 없으면 시작 방식을 저장하지 않는다.
  final StartSettings? start;

  /// 음성 대화를 쓸 수 있으면 "말로 시작"이 첫 버튼이다.
  final bool hasVoice;

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  late String _picked = widget.personas.personas.any((p) => p.id == recommendedPersonaId)
      ? recommendedPersonaId
      : widget.personas.selected.id;

  void _begin({required bool voice}) {
    widget.personas.select(_picked);
    widget.start?.voiceOnStart = voice;
    widget.auth.completeOnboarding(); // 앱이 채팅 화면으로 바꾸고, 말로 시작이면 음성 화면을 연다
  }

  @override
  Widget build(BuildContext context) {
    final c = ChatColors.of(context);
    final name = widget.auth.account?.name ?? '';
    return Scaffold(
      key: const Key('onboarding-page'),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 32, 24, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name.isEmpty ? '누구와 이야기하실래요?' : '$name님,\n누구와 이야기하실래요?',
                        style: TextStyle(color: c.text, fontSize: 28, fontWeight: FontWeight.w800, height: 1.35),
                      ),
                      const SizedBox(height: 8),
                      Text('나중에 언제든 바꿀 수 있어요', style: TextStyle(color: c.muted, fontSize: 18)),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    key: const Key('onboarding-list'),
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    children: [
                      for (final p in widget.personas.personas)
                        _PersonaCard(
                          persona: p,
                          picked: p.id == _picked,
                          recommended: p.id == recommendedPersonaId,
                          onTap: () => setState(() => _picked = p.id),
                        ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
                  decoration: BoxDecoration(
                    color: c.bg,
                    border: Border(top: BorderSide(color: c.line)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: widget.hasVoice
                        ? [
                            BigButton(
                              key: const Key('onboarding-voice'),
                              label: '말로 이야기 시작하기',
                              icon: Icons.mic,
                              onPressed: () => _begin(voice: true),
                            ),
                            const SizedBox(height: 4),
                            BigButton(
                              key: const Key('onboarding-text'),
                              label: '글자로 할게요',
                              style: BigButtonStyle.plain,
                              onPressed: () => _begin(voice: false),
                            ),
                          ]
                        : [
                            BigButton(
                              key: const Key('onboarding-text'),
                              label: '시작하기',
                              onPressed: () => _begin(voice: false),
                            ),
                          ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PersonaCard extends StatelessWidget {
  const _PersonaCard({required this.persona, required this.picked, required this.recommended, required this.onTap});

  final Persona persona;
  final bool picked;
  final bool recommended;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = ChatColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Semantics(
        selected: picked,
        button: true,
        child: Material(
          color: picked ? c.user.withValues(alpha: 0.08) : c.panel,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: picked ? c.user : c.line, width: picked ? 3 : 1.5),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: Key('onboarding-${persona.id}'),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  PersonaAvatar(persona: persona, size: 60, selected: picked),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              persona.name,
                              style: TextStyle(color: c.text, fontSize: 22, fontWeight: FontWeight.w700),
                            ),
                            if (recommended)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                                decoration: BoxDecoration(color: c.user, borderRadius: BorderRadius.circular(999)),
                                child: Text(
                                  '추천',
                                  style: TextStyle(color: c.userText, fontSize: 14, fontWeight: FontWeight.w700),
                                ),
                              ),
                          ],
                        ),
                        if (persona.summary.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(persona.summary, style: TextStyle(color: c.muted, fontSize: 17)),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(picked ? Icons.check_circle : Icons.circle_outlined, size: 32, color: picked ? c.user : c.line),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
