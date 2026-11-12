/// 페르소나 사이드바와 아바타 (SPEC.md F-005, S-001). Material 3 위젯만 쓴다.
library;

import 'package:flutter/material.dart';

import '../chat/persona_controller.dart';
import 'theme.dart';

/// 이 폭부터 사이드바를 고정하고, 좁으면 서랍으로 연다 (F-005 AC7).
const sidebarBreakpoint = 900.0;
const sidebarWidth = 288.0;

/// 페르소나 첫 글자 아바타.
class PersonaAvatar extends StatelessWidget {
  const PersonaAvatar({super.key, required this.persona, this.size = 36, this.selected = true});

  final Persona persona;
  final double size;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final c = ChatColors.of(context);
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: selected ? c.user : c.agent,
      foregroundColor: selected ? c.userText : c.text,
      child: Text(
        persona.initial,
        style: TextStyle(fontSize: size * 0.42, fontWeight: FontWeight.w700),
      ),
    );
  }
}

/// 페르소나 목록 · 페르소나 만들기 · 내 프로필.
class PersonaSidebar extends StatelessWidget {
  const PersonaSidebar({
    super.key,
    required this.personas,
    required this.enabled,
    required this.onSelect,
    required this.onCreate,
    required this.onEditProfile,
    this.onOpenSettings,
  });

  final PersonaController personas;

  /// 응답 중에는 다른 페르소나를 고를 수 없다 (F-005 AC1).
  final bool enabled;
  final ValueChanged<Persona> onSelect;
  final VoidCallback onCreate;
  final VoidCallback onEditProfile;

  /// 설정 화면 (F-023 S-006) — 시작 방식·서버 주소·글자 크기·로그아웃은 거기에 있다. null이면 그리지 않는다.
  final VoidCallback? onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final c = ChatColors.of(context);
    final text = Theme.of(context).textTheme;
    final selected = personas.selected;
    final about = personas.about.trim();
    return Material(
      color: c.panel,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 16, 8),
              child: Text('페르소나', style: text.titleSmall?.copyWith(color: c.muted)),
            ),
            Expanded(
              child: ListView(
                key: const Key('persona-list'),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  for (final p in personas.personas)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: ListTile(
                        key: Key('persona-${p.id}'),
                        enabled: enabled,
                        selected: p.id == selected.id,
                        selectedTileColor: Theme.of(context).colorScheme.secondaryContainer,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                        leading: PersonaAvatar(persona: p, selected: p.id == selected.id),
                        title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: p.summary.isEmpty
                            ? null
                            : Text(p.summary, maxLines: 1, overflow: TextOverflow.ellipsis),
                        onTap: () => onSelect(p),
                      ),
                    ),
                  ListTile(
                    key: const Key('create-persona'),
                    enabled: enabled,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                    leading: const SizedBox(width: 36, child: Icon(Icons.add)),
                    title: const Text('페르소나 만들기'),
                    onTap: onCreate,
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: ListTile(
                key: const Key('profile'),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                leading: CircleAvatar(
                  radius: 18,
                  backgroundColor: c.agent,
                  foregroundColor: c.text,
                  child: const Icon(Icons.person_outline, size: 20),
                ),
                title: const Text('내 프로필'),
                subtitle: Text(about.isEmpty ? '나에 대해 알려 주세요' : about, maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: const Icon(Icons.edit_outlined, size: 20),
                onTap: onEditProfile,
              ),
            ),
            if (onOpenSettings case final onOpenSettings?)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: ListTile(
                  key: const Key('open-settings'),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                  leading: const SizedBox(width: 36, child: Icon(Icons.settings_outlined, size: 22)),
                  title: const Text('설정'),
                  subtitle: const Text('글자 크기 · 시작 방식 · 계정', maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: const Icon(Icons.chevron_right, size: 20),
                  onTap: onOpenSettings,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 내 프로필 편집 대화상자 (F-005 상세 동작 4). 저장하면 새 값, 취소하면 null.
Future<String?> showProfileDialog(BuildContext context, String current) {
  return showDialog<String>(
    context: context,
    builder: (context) => _ProfileDialog(initial: current),
  );
}

class _ProfileDialog extends StatefulWidget {
  const _ProfileDialog({required this.initial});
  final String initial;

  @override
  State<_ProfileDialog> createState() => _ProfileDialogState();
}

class _ProfileDialogState extends State<_ProfileDialog> {
  late final _text = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('내 프로필'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('에이전트가 대화 맥락으로 참고해요. 모든 페르소나에 함께 쓰여요.', style: TextStyle(color: ChatColors.of(context).muted)),
            const SizedBox(height: 16),
            TextField(
              key: const Key('profile-about'),
              controller: _text,
              autofocus: true,
              minLines: 3,
              maxLines: 6,
              maxLength: Persona.maxAbout,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: '나에 대해',
                hintText: '예: 32살 기획자예요. 긴 설명보다 핵심부터 말해 주면 좋아요.',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소')),
        FilledButton(
          key: const Key('save-profile'),
          onPressed: () => Navigator.pop(context, _text.text),
          child: const Text('저장'),
        ),
      ],
    );
  }
}
