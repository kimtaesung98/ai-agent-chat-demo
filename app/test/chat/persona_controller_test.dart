import 'package:ai_agent_chat/chat/chat_controller.dart';
import 'package:ai_agent_chat/chat/persona_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes.dart';

void main() {
  test('F-005 기본 페르소나 4개 중 첫 번째가 선택돼 있다 (Q-002)', () {
    final p = PersonaController();
    expect(p.personas.map((e) => e.name), ['기획 파트너 지은', '영어 회화 코치', '다정한 친구', '노인복지사 미소']);
    expect(p.selected.id, 'planner');
    expect(p.selected.initial, '지');
    expect(p.selected.summary, '기획 파트너 · 차분하게 · 존댓말 · 질문으로 정리');
  });

  test('F-005 AC1 다른 페르소나를 고르면 바뀌고 알린다. 같은 것·없는 것은 무시', () {
    final p = PersonaController();
    var n = 0;
    p.addListener(() => n++);
    expect(p.select('friend'), isTrue);
    expect(p.selected.name, '다정한 친구');
    expect(p.select('friend'), isFalse);
    expect(p.select('nope'), isFalse);
    expect(n, 1);
  });

  test('F-005 AC2 저장하면 있던 것은 바꾸고, 새것은 추가하고 선택한다', () {
    final p = PersonaController();
    p.save(p.selected.copyWith(name: '지은 2', tones: ['짧게']));
    expect(p.personas.first.name, '지은 2');
    expect(p.personas, hasLength(4));

    final fresh = p.blank().copyWith(name: '면접관 민수', role: '면접관');
    expect(fresh.id, isNot(p.blank().id));
    p.save(fresh);
    expect(p.personas, hasLength(5));
    expect(p.selected, fresh);
  });

  test('F-005 AC3 내 프로필은 요청 persona.about에 실린다', () {
    final api = FakeApi();
    final personas = PersonaController();
    final chat = ChatController(api, personas: personas);
    personas.setAbout('32살 기획자예요');
    chat.send('안녕');
    final sent = api.personas.single!;
    expect(sent.persona.id, 'planner');
    expect(sent.toJson()['about'], '32살 기획자예요');
    expect(sent.toJson()['name'], '기획 파트너 지은');
  });

  test('F-005 AC1 페르소나 없이 만든 컨트롤러는 persona 없이 보낸다', () {
    final api = FakeApi();
    ChatController(api).send('안녕');
    expect(api.personas.single, isNull);
  });

  test('F-005 내 프로필은 1,000자까지만 둔다', () {
    final p = PersonaController()..setAbout('가' * 1200);
    expect(p.about.length, Persona.maxAbout);
  });

  test('F-005 노인복지사 페르소나는 존댓말로 천천히 쉽게, 의료·응급·사기 경계를 지시한다 (서버 제한 안)', () {
    final p = PersonaController();
    expect(p.select('elder-care'), isTrue);
    final e = p.selected;
    expect(e.name, '노인복지사 미소');
    expect(e.initial, '미');
    expect(e.summary, '노인복지사 · 존댓말 · 천천히 · 쉽게');
    for (final word in ['어르신', '119', '129', '109', '의사', '비밀번호']) {
      expect(e.base, contains(word));
    }
    expect(e.base.length, lessThanOrEqualTo(Persona.maxBase));
    expect(e.instructions, isEmpty, reason: '탑재 페르소나의 지시는 기본 지시 층에 있고, 내 요구 사항은 비어 있다 (F-019)');
    expect(e.tones.length, lessThanOrEqualTo(Persona.maxTones));
    expect(p.request.toJson()['name'], '노인복지사 미소');
  });

  group('F-019 AC2 기본 지시와 내 요구 사항', () {
    test('탑재 페르소나는 모두 기본 지시가 있고 서버 제한 안이다', () {
      for (final p in defaultPersonas) {
        expect(p.base, isNotEmpty, reason: p.name);
        expect(p.base.length, lessThanOrEqualTo(Persona.maxBase));
        expect(p.instructions, isEmpty);
        expect(isBuiltInPersona(p.id), isTrue);
      }
      expect(isBuiltInPersona('custom-1'), isFalse);
    });

    test('요청에는 기본 지시(base)와 내 요구 사항(instructions)이 따로 실린다', () {
      final p = PersonaController()..select('elder-care');
      p.save(p.selected.copyWith(instructions: ' 아침마다 혈압약을 챙겨 줘 '));
      final json = p.request.toJson();
      expect(json['base'], defaultPersonas[3].base);
      expect(json['instructions'], '아침마다 혈압약을 챙겨 줘');
    });

    test('탑재 페르소나의 기본 지시는 저장해도 바뀌지 않고, 내가 만든 페르소나는 바뀐다', () {
      final p = PersonaController();
      p.save(p.selected.copyWith(base: '바꾼 기본 지시', instructions: '내 요청'));
      expect(p.selected.base, defaultPersonas.first.base);
      expect(p.selected.instructions, '내 요청');

      final mine = p.blank().copyWith(name: '면접관', base: '한 번에 하나씩 질문해');
      p.save(mine);
      expect(p.selected.base, '한 번에 하나씩 질문해');
      p.save(p.selected.copyWith(base: '압박 면접처럼'));
      expect(p.selected.base, '압박 면접처럼');
    });

    test('예전에 저장한 탑재 페르소나: 손대지 않은 지시는 기본 지시로 옮기고, 고친 지시는 내 요구 사항으로 남긴다', () {
      final elder = defaultPersonas[3];
      final restored = PersonaController.restore({
        'personas': [
          {'id': 'planner', 'name': '기획 파트너 지은', 'instructions': '전혀 다른 내 지시'},
          {'id': 'elder-care', 'name': elder.name, 'instructions': elder.base},
          {'id': 'coach', 'name': '영어 회화 코치', 'base': '저장소에서 바뀐 기본 지시'},
          {'id': 'custom-1', 'name': '내 것', 'base': '내 기본', 'instructions': '내 요청'},
        ],
      });
      Persona byId(String id) => restored.personas.firstWhere((p) => p.id == id);
      expect(byId('planner').base, defaultPersonas[0].base);
      expect(byId('planner').instructions, '전혀 다른 내 지시');
      expect(byId('elder-care').base, elder.base);
      expect(byId('elder-care').instructions, isEmpty);
      expect(byId('coach').base, defaultPersonas[1].base, reason: '탑재 페르소나의 기본 지시는 늘 앱의 것');
      expect(byId('custom-1').base, '내 기본');
      expect(byId('custom-1').instructions, '내 요청');
    });
  });
}
