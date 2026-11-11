import 'dart:convert';

import 'package:ai_agent_chat/chat/persona_controller.dart';
import 'package:ai_agent_chat/storage/app_storage.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> settle() => Future<void>.delayed(Duration.zero);

void main() {
  test('Q-005 F-005 저장한 페르소나·선택·내 프로필이 앱을 다시 열어도 남는다', () async {
    final store = MemoryStore();
    final first = loadPersonas(store);
    final mine = first.blank().copyWith(name: '면접관 민수', role: '면접관', tones: ['짧게']);
    first.save(mine);
    first.setAbout('3년 차 백엔드 개발자');
    await settle();

    final again = loadPersonas(store); // 다시 실행
    expect(again.personas.map((p) => p.name), [...defaultPersonas.map((p) => p.name), '면접관 민수']);
    expect(again.selected, mine);
    expect(again.about, '3년 차 백엔드 개발자');
  });

  test('Q-005 저장된 값이 없거나 깨졌으면 기본 페르소나로 시작한다', () {
    expect(loadPersonas(MemoryStore()).personas, defaultPersonas);
    for (final broken in ['{', '[]', '{"personas": "x"}', '{"personas": [{"id": 1}]}']) {
      final c = loadPersonas(MemoryStore({StoreKeys.personas: broken}));
      expect(c.personas, defaultPersonas, reason: broken);
      expect(c.selected, defaultPersonas.first);
    }
  });

  test('Q-005 저장소의 값은 서버 제한으로 자르고, 없는 선택은 첫 페르소나로', () {
    final saved = jsonEncode({
      'personas': [
        {'id': 'a', 'name': '가' * 100, 'tones': List.filled(10, '짧게')},
        {'id': 'a', 'name': '중복'},
      ],
      'selected': 'zzz',
      'about': 'x' * 2000,
    });
    final c = loadPersonas(MemoryStore({StoreKeys.personas: saved}));
    expect(c.personas, hasLength(1));
    expect(c.selected.name.length, Persona.maxName);
    expect(c.selected.tones, hasLength(Persona.maxTones));
    expect(c.about.length, Persona.maxAbout);
  });

  test('F-017 AC7 앱에서 넣은 서버 주소는 다시 열어도 남고, 비우면 기본 주소로 돌아간다', () async {
    final store = MemoryStore();
    final s = loadServer(store, fallback: 'http://10.0.2.2:3000');
    expect(s.address, 'http://10.0.2.2:3000');
    expect(s.update('http://192.168.0.10:3000/'), isNull);
    await settle();
    expect(loadServer(store, fallback: 'http://10.0.2.2:3000').address, 'http://192.168.0.10:3000');

    s.update('');
    await settle();
    expect(store.read(StoreKeys.server), isNull);
    expect(loadServer(store, fallback: 'http://10.0.2.2:3000').address, 'http://10.0.2.2:3000');
  });

  test('Q-005 대화 내용은 저장하지 않는다 (F-007 전)', () {
    expect(StoreKeys.all, {StoreKeys.personas, StoreKeys.server});
  });
}
