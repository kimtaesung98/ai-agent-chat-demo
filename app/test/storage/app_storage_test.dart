import 'dart:convert';

import 'package:ai_agent_chat/chat/memory_controller.dart';
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
    expect(c.personas.map((p) => p.id), [
      'a',
      ...defaultPersonas.map((p) => p.id),
    ], reason: '중복은 버리고, 빠진 기본 페르소나는 뒤에 붙인다');
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

  test('Q-005 F-019 대화 내용 자체는 저장하지 않고 끝난 대화의 요약만 남긴다 (F-007 전)', () {
    expect(StoreKeys.all, {
      StoreKeys.personas,
      StoreKeys.server,
      StoreKeys.memory,
      StoreKeys.voiceOnStart,
      StoreKeys.auth,
      StoreKeys.textSize,
    });
  });

  test('F-021 AC3 켜면 바로 음성 대화 설정이 앱을 다시 열어도 남는다', () async {
    final store = MemoryStore();
    expect(loadStart(store).voiceOnStart, isFalse);
    loadStart(store).voiceOnStart = true;
    await settle();
    expect(loadStart(store).voiceOnStart, isTrue);
    loadStart(store).voiceOnStart = false;
    await settle();
    expect(store.read(StoreKeys.voiceOnStart), isNull);
  });

  test('F-019 AC5 대화 요약이 앱을 다시 열어도 남고, 깨진 값이면 빈 기억으로 시작한다', () async {
    final store = MemoryStore();
    final first = loadMemory(store);
    first.put(
      SessionSummary(
        id: 's1',
        personaId: 'elder-care',
        endedAt: DateTime.utc(2026, 11, 10, 9),
        summary: '산책 이야기를 했어요',
        facts: const ['무릎이 아프심'],
        turns: 3,
      ),
    );
    await settle();
    final again = loadMemory(store);
    final s = again.forPersona('elder-care').single;
    expect(s.summary, '산책 이야기를 했어요');
    expect(s.facts, ['무릎이 아프심']);
    expect(s.turns, 3);
    expect(s.endedAt, DateTime.utc(2026, 11, 10, 9));

    expect(loadMemory(MemoryStore({StoreKeys.memory: '{깨짐'})).forPersona('elder-care'), isEmpty);
    expect(
      loadMemory(
        MemoryStore({
          StoreKeys.memory: '{"sessions":[{"id":1},{"id":"a","personaId":"p","endedAt":"x","summary":"s"}]}',
        }),
      ).forPersona('p'),
      isEmpty,
    );
  });

  test('F-005 Q-005 예전에 저장한 기기에도 새로 생긴 기본 페르소나(노인복지사)가 뒤에 붙고, 선택·내 것은 그대로다', () {
    final saved = jsonEncode({
      'v': 1,
      'personas': [
        for (final p in defaultPersonas.where((p) => p.id != 'elder-care')) p.toStoreJson(),
        {'id': 'custom-1', 'name': '면접관 민수'},
      ],
      'selected': 'custom-1',
      'about': '3년 차 개발자',
    });
    final c = loadPersonas(MemoryStore({StoreKeys.personas: saved}));
    expect(c.personas.map((p) => p.id), ['planner', 'coach', 'friend', 'custom-1', 'elder-care']);
    expect(c.selected.id, 'custom-1');
    expect(c.about, '3년 차 개발자');
  });
}
