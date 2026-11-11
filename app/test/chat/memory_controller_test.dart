import 'package:ai_agent_chat/chat/memory_controller.dart';
import 'package:flutter_test/flutter_test.dart';

SessionSummary at(String id, String persona, int day, {String summary = '요약'}) =>
    SessionSummary(id: id, personaId: persona, endedAt: DateTime.utc(2026, 11, day), summary: '$summary $id');

void main() {
  test('F-019 AC4 다음 요청에는 그 페르소나의 최근 5개를 오래된 것부터 싣고, 지금 세션은 뺀다', () {
    final m = MemoryController([for (var d = 1; d <= 7; d++) at('s$d', 'p', d), at('o1', 'other', 8)]);
    expect(m.recentFor('p').map((s) => s.id), ['s3', 's4', 's5', 's6', 's7']);
    expect(m.recentFor('p', exceptSession: 's7').map((s) => s.id), ['s2', 's3', 's4', 's5', 's6']);
    expect(m.recentFor('other').map((s) => s.id), ['o1']);
    expect(m.forPersona('p').first.id, 's7', reason: '화면은 최근 것부터');
  });

  test('F-019 AC3 같은 세션을 다시 정리하면 바꾸고, 페르소나마다 20개까지만 남긴다', () {
    final m = MemoryController();
    var notified = 0;
    m.addListener(() => notified++);
    m.put(at('s1', 'p', 1, summary: '처음'));
    m.put(at('s1', 'p', 2, summary: '다시'));
    expect(m.forPersona('p').single.summary, '다시 s1');
    for (var d = 1; d <= 25; d++) {
      m.put(at('n$d', 'p', d));
    }
    m.put(at('o', 'other', 1));
    expect(m.forPersona('p'), hasLength(MemoryController.keepPerPersona));
    expect(m.forPersona('p').last.id, isNot('n1'), reason: '오래된 것부터 지운다');
    expect(m.forPersona('other'), hasLength(1));
    expect(notified, 28);
  });

  test('F-019 AC6 하나 또는 페르소나 하나의 기억을 모두 지울 수 있다', () {
    final m = MemoryController([at('a', 'p', 1), at('b', 'p', 2), at('c', 'q', 3)]);
    m.remove('a');
    expect(m.forPersona('p').map((s) => s.id), ['b']);
    m.clear('p');
    expect(m.forPersona('p'), isEmpty);
    expect(m.forPersona('q'), hasLength(1));
  });

  test('F-019 AC5 저장 값으로 되살리고, 틀린 항목·중복은 버린다', () {
    final m = MemoryController([at('a', 'p', 1), at('b', 'p', 2)]);
    final snap = m.snapshot();
    final list = [
      ...(snap['sessions']! as List),
      {'id': 'a', 'personaId': 'p', 'endedAt': '2026-11-03T00:00:00Z', 'summary': '중복'},
      'x',
      {},
    ];
    final back = MemoryController.restore({'sessions': list});
    expect(back.forPersona('p').map((s) => s.summary), ['요약 b', '요약 a']);
    expect(MemoryController.restore(null).forPersona('p'), isEmpty);
    expect(MemoryController.restore({'sessions': 'x'}).forPersona('p'), isEmpty);
  });

  test('F-019 AC3 서버 요약은 제한으로 자르고, 요청에는 날짜·요약·사실·이어 갈 것을 싣는다', () {
    final s = SessionSummary.fromApiJson(
      {
        'summary': '가' * 700,
        'facts': ['a', 1, '', 'b', 'c', 'd', 'e', 'f'],
        'followUps': ['x' * 150],
      },
      id: 's',
      personaId: 'p',
      endedAt: DateTime(2026, 11, 11, 15),
    )!;
    expect(s.summary.length, SessionSummary.maxSummary);
    expect(s.facts, ['a', 'b', 'c', 'd', 'e']);
    expect(s.followUps.single.length, SessionSummary.maxItem);
    expect(s.toRequestJson()['date'], '2026-11-11');
    expect(SessionSummary.fromApiJson({'summary': ' '}, id: 's', personaId: 'p', endedAt: DateTime(2026)), isNull);
  });

  group('F-020 장기 기억', () {
    LongTermMemory lt(String persona, int coversDay) => LongTermMemory(
      personaId: persona,
      summary: '장기 $persona',
      facts: const ['f'],
      updatedAt: DateTime.utc(2026, 11, 20),
      coversUntil: DateTime.utc(2026, 11, coversDay),
    );

    test('AC2 최근 5개 밖이고 아직 묶지 않은 요약만 묶을 차례다', () {
      final m = MemoryController([for (var d = 1; d <= 8; d++) at('s$d', 'p', d), at('o', 'q', 1)]);
      expect(m.pendingFold('p').map((s) => s.id), ['s1', 's2', 's3']);
      expect(m.pendingFold('q'), isEmpty, reason: '5개 이하면 묶지 않는다');
      m.setLongTerm(lt('p', 2));
      expect(m.pendingFold('p').map((s) => s.id), ['s3']);
      m.setLongTerm(lt('p', 3));
      expect(m.pendingFold('p'), isEmpty);
    });

    test('AC4 장기 기억은 저장 값으로 되살아나고, 모두 지우기로 함께 지워진다', () {
      final m = MemoryController([at('a', 'p', 1)], [lt('p', 1), lt('q', 1)]);
      final back = MemoryController.restore(m.snapshot());
      expect(back.longTermFor('p')!.summary, '장기 p');
      expect(back.longTermFor('p')!.coversUntil, DateTime.utc(2026, 11, 1));
      expect(
        MemoryController.restore({
          'longTerm': [
            'x',
            {'personaId': 'p'},
          ],
        }).longTermFor('p'),
        isNull,
      );
      back.clear('p');
      expect(back.longTermFor('p'), isNull);
      expect(back.longTermFor('q'), isNotNull);
    });

    test('AC1 서버 장기 기억은 제한으로 자르고 요청에는 요약·사실만 싣는다', () {
      final l = LongTermMemory.fromApiJson(
        {
          'summary': '가' * 1200,
          'facts': [for (var i = 0; i < 12; i++) 'f$i'],
        },
        personaId: 'p',
        updatedAt: DateTime(2026),
        coversUntil: DateTime(2026),
      )!;
      expect(l.summary.length, LongTermMemory.maxSummary);
      expect(l.facts, hasLength(LongTermMemory.maxFacts));
      expect(l.toRequestJson().keys, ['summary', 'facts']);
      expect(
        LongTermMemory.fromApiJson(
          {'summary': ''},
          personaId: 'p',
          updatedAt: DateTime(2026),
          coversUntil: DateTime(2026),
        ),
        isNull,
      );
    });
  });
}
