import 'package:ai_agent_chat/chat/chat_controller.dart';
import 'package:ai_agent_chat/chat/persona_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes.dart';

void main() {
  test('F-005 기본 페르소나 3개 중 첫 번째가 선택돼 있다 (Q-002)', () {
    final p = PersonaController();
    expect(p.personas.map((e) => e.name), ['기획 파트너 지은', '영어 회화 코치', '다정한 친구']);
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
    expect(p.personas, hasLength(3));

    final fresh = p.blank().copyWith(name: '면접관 민수', role: '면접관');
    expect(fresh.id, isNot(p.blank().id));
    p.save(fresh);
    expect(p.personas, hasLength(4));
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
}
