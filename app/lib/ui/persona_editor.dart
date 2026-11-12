/// S-002 페르소나 편집 화면 (SPEC.md F-005 상세 동작 3, F-019). 저장하면 새 [Persona], 취소하면 null을 돌려준다.
/// 추가 지시는 두 층이다: 기본 지시(탑재 페르소나는 고정) + 내 요구 사항. 아래에 이 페르소나의 지난 대화 기억을 보여 준다.
library;

import 'package:flutter/material.dart';

import '../chat/memory_controller.dart';
import '../chat/persona_controller.dart';
import 'persona_widgets.dart';
import 'theme.dart';

Future<Persona?> openPersonaEditor(
  BuildContext context,
  Persona persona, {
  required bool isNew,
  MemoryController? memory,
}) {
  return Navigator.of(context).push<Persona>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => PersonaEditorPage(initial: persona, isNew: isNew, memory: memory),
    ),
  );
}

class PersonaEditorPage extends StatefulWidget {
  const PersonaEditorPage({super.key, required this.initial, this.isNew = false, this.memory});

  final Persona initial;
  final bool isNew;

  /// 지난 대화 기억 (F-019 AC6). 없으면 기억 칸을 그리지 않는다.
  final MemoryController? memory;

  @override
  State<PersonaEditorPage> createState() => _PersonaEditorPageState();
}

class _PersonaEditorPageState extends State<PersonaEditorPage> {
  late final _name = TextEditingController(text: widget.initial.name);
  late final _role = TextEditingController(text: widget.initial.role);
  late final _base = TextEditingController(text: widget.initial.base);
  late final _instructions = TextEditingController(text: widget.initial.instructions);

  /// 탑재 페르소나는 기본 지시를 바꿀 수 없다 (F-019 AC2).
  late final _builtIn = isBuiltInPersona(widget.initial.id);
  late final List<String> _tones = [...widget.initial.tones];

  @override
  void initState() {
    super.initState();
    for (final c in [_name, _role]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _role.dispose();
    _base.dispose();
    _instructions.dispose();
    super.dispose();
  }

  bool get _canSave => _name.text.trim().isNotEmpty; // 이름이 비면 저장할 수 없다 (F-005 AC2)

  Persona get _draft => widget.initial.copyWith(
    name: _name.text.trim(),
    role: _role.text.trim(),
    tones: List.unmodifiable(_tones),
    base: _builtIn ? widget.initial.base : _base.text.trim(),
    instructions: _instructions.text.trim(),
  );

  void _toggleTone(String tone, bool on) {
    setState(() => on ? _tones.add(tone) : _tones.remove(tone));
  }

  @override
  Widget build(BuildContext context) {
    final c = ChatColors.of(context);
    final text = Theme.of(context).textTheme;
    final tones = [...toneSuggestions, ..._tones.where((t) => !toneSuggestions.contains(t))];
    final full = _tones.length >= Persona.maxTones;

    Widget section(String title, {String? help, required Widget child}) => Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(title, style: text.titleSmall),
              const Spacer(),
              if (help != null) Text(help, style: text.bodySmall?.copyWith(color: c.muted)),
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );

    return Scaffold(
      appBar: AppBar(
        backgroundColor: c.panel,
        surfaceTintColor: Colors.transparent,
        shape: Border(bottom: BorderSide(color: c.line)),
        leading: IconButton(
          key: const Key('cancel-persona'),
          tooltip: '취소',
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(widget.isNew ? '페르소나 만들기' : '페르소나 편집'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: FilledButton(
              key: const Key('save-persona'),
              onPressed: _canSave ? () => Navigator.pop(context, _draft) : null,
              child: const Text('저장'),
            ),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 40),
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 4, right: 16),
                    child: PersonaAvatar(persona: _draft, size: 56),
                  ),
                  Expanded(
                    child: TextField(
                      key: const Key('persona-name'),
                      controller: _name,
                      autofocus: widget.isNew,
                      maxLength: Persona.maxName,
                      decoration: const InputDecoration(
                        labelText: '이름',
                        hintText: '예: 기획 파트너 지은',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              section(
                '역할',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final r in roleSuggestions)
                          ChoiceChip(
                            key: Key('role-$r'),
                            label: Text(r),
                            selected: _role.text.trim() == r,
                            onSelected: (on) => _role.text = on ? r : '',
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: const Key('persona-role'),
                      controller: _role,
                      maxLength: Persona.maxRole,
                      decoration: const InputDecoration(
                        labelText: '직접 입력',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ],
                ),
              ),
              section(
                '말투',
                help: '여러 개 고를 수 있어요 (최대 ${Persona.maxTones}개)',
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final t in tones)
                      FilterChip(
                        key: Key('tone-$t'),
                        label: Text(t),
                        selected: _tones.contains(t),
                        onSelected: !_tones.contains(t) && full ? null : (on) => _toggleTone(t, on),
                      ),
                  ],
                ),
              ),
              section(
                '추가 지시',
                help: '에이전트가 항상 지키는 규칙',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('기본 지시', style: text.labelLarge),
                    const SizedBox(height: 6),
                    if (_builtIn)
                      _FixedBase(text: widget.initial.base)
                    else
                      TextField(
                        key: const Key('persona-base'),
                        controller: _base,
                        minLines: 2,
                        maxLines: 6,
                        maxLength: Persona.maxBase,
                        decoration: const InputDecoration(
                          hintText: '이 페르소나가 누구이고 어떻게 대화하는지. 예: 면접관처럼 한 번에 하나씩 묻고 답을 평가해 줘.',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    const SizedBox(height: 16),
                    Text('내 요구 사항', style: text.labelLarge),
                    const SizedBox(height: 6),
                    TextField(
                      key: const Key('persona-instructions'),
                      controller: _instructions,
                      minLines: 3,
                      maxLines: 8,
                      maxLength: Persona.maxInstructions,
                      decoration: const InputDecoration(
                        hintText: '기본 지시에 덧붙일 내 요청. 예: 아침마다 혈압약 드셨는지 물어봐 줘.',
                        helperText: '기본 지시와 다르면 내 요구 사항을 먼저 따라요 (안전 지시는 지켜요).',
                        helperMaxLines: 2,
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.memory case final memory? when !widget.isNew)
                section(
                  '지난 대화 기억',
                  help: '대화를 끝낼 때마다 정리돼요',
                  child: MemoryList(memory: memory, personaId: widget.initial.id),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 탑재 페르소나의 기본 지시 — 읽기만 (F-019 AC2).
class _FixedBase extends StatelessWidget {
  const _FixedBase({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = ChatColors.of(context);
    final theme = Theme.of(context).textTheme;
    return Container(
      key: const Key('persona-base-fixed'),
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.panel,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.lock_outline, size: 16, color: c.muted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '탑재 페르소나의 기본 지시예요. 바꿀 수 없고, 아래 내 요구 사항으로 덧붙일 수 있어요.',
                  style: theme.bodySmall?.copyWith(color: c.muted),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(text.isEmpty ? '(없음)' : text, style: theme.bodyMedium),
        ],
      ),
    );
  }
}

/// 이 페르소나와 나눈 지난 대화 요약 목록. 하나씩 또는 모두 지울 수 있다 (F-019 AC6).
class MemoryList extends StatelessWidget {
  const MemoryList({super.key, required this.memory, required this.personaId});
  final MemoryController memory;
  final String personaId;

  @override
  Widget build(BuildContext context) {
    final c = ChatColors.of(context);
    final theme = Theme.of(context).textTheme;
    return ListenableBuilder(
      listenable: memory,
      builder: (context, _) {
        final list = memory.forPersona(personaId);
        final longTerm = memory.longTermFor(personaId);
        if (list.isEmpty && longTerm == null) {
          return Text(
            '아직 없어요. 대화를 끝내면(새 대화, 다른 페르소나, 대화 끝내기) 요약이 쌓이고, 다음 대화에서 최근 ${MemoryController.sendPerRequest}개를 참고해요. 그보다 오래된 요약은 장기 기억 하나로 묶어요.',
            key: const Key('memory-empty'),
            style: theme.bodySmall?.copyWith(color: c.muted),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (longTerm != null)
              Card(
                key: const Key('memory-long-term'),
                margin: const EdgeInsets.only(bottom: 12),
                elevation: 0,
                color: c.panel,
                shape: RoundedRectangleBorder(
                  side: BorderSide(color: c.line),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.auto_stories_outlined, size: 18, color: c.muted),
                          const SizedBox(width: 6),
                          Text('장기 기억', style: theme.labelLarge),
                          const Spacer(),
                          Text(
                            '${dayString(longTerm.coversUntil)}까지 묶음',
                            style: theme.labelMedium?.copyWith(color: c.muted),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(longTerm.summary, style: theme.bodyMedium),
                      if (longTerm.facts.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text('알고 있는 것: ${longTerm.facts.join(' · ')}', style: theme.bodySmall),
                      ],
                    ],
                  ),
                ),
              ),
            for (final s in list)
              Card(
                key: Key('memory-${s.id}'),
                margin: const EdgeInsets.only(bottom: 8),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  side: BorderSide(color: c.line),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 4, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(s.date, style: theme.labelMedium?.copyWith(color: c.muted)),
                          const Spacer(),
                          IconButton(
                            key: Key('memory-delete-${s.id}'),
                            tooltip: '이 기억 지우기',
                            icon: const Icon(Icons.delete_outline, size: 20),
                            onPressed: () => memory.remove(s.id),
                          ),
                        ],
                      ),
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(s.summary, style: theme.bodyMedium),
                            if (s.facts.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text('알게 된 점: ${s.facts.join(' · ')}', style: theme.bodySmall),
                            ],
                            if (s.followUps.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text('다음에 이어 갈 것: ${s.followUps.join(' · ')}', style: theme.bodySmall),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            TextButton.icon(
              key: const Key('memory-clear'),
              onPressed: () => memory.clear(personaId),
              icon: const Icon(Icons.delete_sweep_outlined),
              label: const Text('이 페르소나의 기억 모두 지우기'),
            ),
          ],
        );
      },
    );
  }
}
