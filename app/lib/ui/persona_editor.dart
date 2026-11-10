/// S-002 페르소나 편집 화면 (SPEC.md F-005 상세 동작 3). 저장하면 새 [Persona], 취소하면 null을 돌려준다.
library;

import 'package:flutter/material.dart';

import '../chat/persona_controller.dart';
import 'persona_widgets.dart';
import 'theme.dart';

Future<Persona?> openPersonaEditor(BuildContext context, Persona persona, {required bool isNew}) {
  return Navigator.of(context).push<Persona>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => PersonaEditorPage(initial: persona, isNew: isNew),
    ),
  );
}

class PersonaEditorPage extends StatefulWidget {
  const PersonaEditorPage({super.key, required this.initial, this.isNew = false});

  final Persona initial;
  final bool isNew;

  @override
  State<PersonaEditorPage> createState() => _PersonaEditorPageState();
}

class _PersonaEditorPageState extends State<PersonaEditorPage> {
  late final _name = TextEditingController(text: widget.initial.name);
  late final _role = TextEditingController(text: widget.initial.role);
  late final _instructions = TextEditingController(text: widget.initial.instructions);
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
    _instructions.dispose();
    super.dispose();
  }

  bool get _canSave => _name.text.trim().isNotEmpty; // 이름이 비면 저장할 수 없다 (F-005 AC2)

  Persona get _draft => widget.initial.copyWith(
    name: _name.text.trim(),
    role: _role.text.trim(),
    tones: List.unmodifiable(_tones),
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
                child: TextField(
                  key: const Key('persona-instructions'),
                  controller: _instructions,
                  minLines: 3,
                  maxLines: 8,
                  maxLength: Persona.maxInstructions,
                  decoration: const InputDecoration(
                    hintText: '예: 답을 바로 주기보다 질문 한두 개로 내 생각을 먼저 끌어내 줘.',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
