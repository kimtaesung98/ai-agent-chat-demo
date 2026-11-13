/// S-007 지난 대화 기억 (SPEC.md F-023, F-019·F-020). 페르소나를 고르면 그 페르소나의 장기 기억과 세션 요약이 보인다.
/// 목록 그리기는 편집 화면과 같은 [MemoryList]를 쓴다.
library;

import 'package:flutter/material.dart';

import '../chat/memory_controller.dart';
import '../chat/persona_controller.dart';
import 'persona_editor.dart';
import 'persona_widgets.dart';
import 'theme.dart';

Future<void> openMemoryPage(
  BuildContext context, {
  required PersonaController personas,
  required MemoryController memory,
}) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => MemoryPage(personas: personas, memory: memory),
    ),
  );
}

class MemoryPage extends StatefulWidget {
  const MemoryPage({super.key, required this.personas, required this.memory});

  final PersonaController personas;
  final MemoryController memory;

  @override
  State<MemoryPage> createState() => _MemoryPageState();
}

class _MemoryPageState extends State<MemoryPage> {
  late String _personaId = widget.personas.selected.id;

  @override
  Widget build(BuildContext context) {
    final c = ChatColors.of(context);
    return Scaffold(
      key: const Key('memory-page'),
      appBar: AppBar(
        title: const Text('지난 대화 기억'),
        backgroundColor: c.panel,
        surfaceTintColor: Colors.transparent,
        shape: Border(bottom: BorderSide(color: c.line)),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              Text(
                '대화를 끝낼 때마다 짧게 정리해 이 기기에만 남겨요. 다음 대화에서 이어 가는 데 써요.',
                style: TextStyle(color: c.muted, fontSize: 16, height: 1.5),
              ),
              const SizedBox(height: 16),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final p in widget.personas.personas)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          key: Key('memory-persona-${p.id}'),
                          avatar: PersonaAvatar(persona: p, size: 24, selected: p.id == _personaId),
                          label: Text(p.name),
                          selected: p.id == _personaId,
                          showCheckmark: false,
                          onSelected: (_) => setState(() => _personaId = p.id),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              MemoryList(key: ValueKey(_personaId), memory: widget.memory, personaId: _personaId),
            ],
          ),
        ),
      ),
    );
  }
}
