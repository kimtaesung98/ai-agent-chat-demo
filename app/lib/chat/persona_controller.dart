/// 페르소나 목록·선택·내 프로필 (SPEC.md F-005, ARCHITECTURE.md ADR-016).
/// `package:flutter/foundation.dart`까지만 import한다 — 위젯 없이 단위 테스트한다.
/// 기기 저장은 [snapshot]·[PersonaController.restore]로 바깥(`storage/`)이 한다 — 이 파일은 저장소를 모른다 (SPEC.md Q-005).
library;

import 'package:flutter/foundation.dart';

import '../api/chat_api.dart';

export '../api/models.dart' show Persona;

/// 처음 보이는 기본 페르소나 (SPEC.md Q-002).
const defaultPersonas = [
  Persona(
    id: 'planner',
    name: '기획 파트너 지은',
    role: '기획 파트너',
    tones: ['차분하게', '존댓말', '질문으로 정리'],
    instructions: '답을 바로 주기보다 질문 한두 개로 내 생각을 먼저 끌어내 줘. 목록은 세 개 이하로.',
  ),
  Persona(
    id: 'coach',
    name: '영어 회화 코치',
    role: '영어 회화 코치',
    tones: ['짧게', '친근하게'],
    instructions: '영어로 짧게 대화하고, 내가 어색한 표현을 쓰면 한국어로 한 줄만 고쳐 줘.',
  ),
  Persona(id: 'friend', name: '다정한 친구', role: '친구', tones: ['편하게', '반말', '공감 먼저']),
];

/// 역할 추천 (편집 화면 칩).
const roleSuggestions = ['기획 파트너', '영어 회화 코치', '친구', '상담사', '면접관', '선생님'];

/// 말투 추천 (편집 화면 칩).
const toneSuggestions = ['차분하게', '친근하게', '존댓말', '반말', '짧게', '자세하게', '질문으로 정리', '공감 먼저', '유머 있게', '편하게'];

class PersonaController extends ChangeNotifier {
  PersonaController({List<Persona> initial = defaultPersonas})
    : assert(initial.isNotEmpty),
      _personas = [...initial],
      _selectedId = initial.first.id;

  /// 저장해 둔 값으로 시작한다. 없거나 모양이 틀리면 [fallback] (Q-005).
  factory PersonaController.restore(Object? saved, {List<Persona> fallback = defaultPersonas}) {
    final c = PersonaController(initial: fallback);
    if (saved is! Map) return c;
    final list = saved['personas'];
    final personas = <Persona>[];
    final seen = <String>{};
    if (list is List) {
      for (final item in list) {
        final p = Persona.fromStoreJson(item);
        if (p != null && seen.add(p.id)) personas.add(p);
      }
    }
    if (personas.isEmpty) return c;
    final restored = PersonaController(initial: personas);
    final selected = saved['selected'];
    if (selected is String) restored.select(selected);
    final about = saved['about'];
    if (about is String) restored.setAbout(about);
    return restored;
  }

  /// 저장할 값 — [PersonaController.restore]가 읽는다.
  Map<String, Object> snapshot() => {
    'v': 1,
    'personas': [for (final p in _personas) p.toStoreJson()],
    'selected': _selectedId,
    'about': _about,
  };

  final List<Persona> _personas;
  String _selectedId;
  String _about = '';
  var _seq = 0;

  List<Persona> get personas => List.unmodifiable(_personas);
  Persona get selected => _personas.firstWhere((p) => p.id == _selectedId);

  /// 내 프로필 (나에 대해).
  String get about => _about;

  /// 다음 요청에 실을 값 (API-001 `persona`).
  PersonaRequest get request => PersonaRequest(selected, about: _about);

  /// 페르소나를 고른다. 이미 선택돼 있거나 없는 id면 false.
  bool select(String id) {
    if (id == _selectedId || !_personas.any((p) => p.id == id)) return false;
    _selectedId = id;
    notifyListeners();
    return true;
  }

  /// 새 페르소나를 만들 때 쓸 빈 값.
  Persona blank() => Persona(id: 'custom-${DateTime.now().microsecondsSinceEpoch}-${_seq++}', name: '');

  /// 저장한다. 목록에 있으면 바꾸고, 없으면 추가하고 선택한다.
  void save(Persona persona) {
    final i = _personas.indexWhere((p) => p.id == persona.id);
    if (i >= 0) {
      _personas[i] = persona;
    } else {
      _personas.add(persona);
      _selectedId = persona.id;
    }
    notifyListeners();
  }

  void setAbout(String value) {
    final v = value.length > Persona.maxAbout ? value.substring(0, Persona.maxAbout) : value;
    if (v == _about) return;
    _about = v;
    notifyListeners();
  }
}
