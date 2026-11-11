import 'dart:async';

import 'package:ai_agent_chat/api/chat_api.dart';
import 'package:ai_agent_chat/chat/chat_controller.dart';
import 'package:ai_agent_chat/chat/memory_controller.dart';
import 'package:ai_agent_chat/chat/persona_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes.dart';

void main() {
  late FakeApi api;
  late PersonaController personas;
  late MemoryController memory;
  late ChatController chat;
  var now = DateTime.utc(2026, 11, 11, 9);
  setUp(() {
    api = FakeApi();
    personas = PersonaController();
    memory = MemoryController();
    now = DateTime.utc(2026, 11, 11, 9);
    chat = ChatController(api, personas: personas, memory: memory, clock: () => now);
  });
  tearDown(() => chat.dispose());

  Future<void> flush() => pumpEventQueue();

  Future<void> turn(String q, String a) async {
    expect(chat.send(q), isTrue);
    api.current
      ..add(ChatDelta(a))
      ..add(const ChatDone('end_turn'));
    await flush();
  }

  test('F-019 AC3 새 대화를 시작하면 끝난 대화를 그 페르소나 이름으로 요약해 기억에 넣는다', () async {
    await turn('산책 다녀왔어요', '잘하셨어요');
    await turn('무릎이 아파요', '쉬세요');
    chat.reset();
    expect(chat.entries, isEmpty);
    expect(api.summaryRequests.single.map((m) => m.content), ['산책 다녀왔어요', '잘하셨어요', '무릎이 아파요', '쉬세요']);
    expect(api.summaryPersonas.single!.persona.id, 'planner');
    await flush();
    final s = memory.forPersona('planner').single;
    expect(s.summary, '요약 1: 산책 다녀왔어요');
    expect(s.facts, ['사실']);
    expect(s.turns, 2);
    expect(s.endedAt, now);
    expect(chat.summarizing, 0);
  });

  test('F-019 AC3 주고받은 답이 없거나 정리 뒤 바뀐 것이 없으면 요약하지 않는다', () async {
    chat.reset();
    expect(chat.send('질문만'), isTrue);
    api.current.add(const ChatFailed('오류'));
    await flush();
    expect(chat.endSession(), isFalse, reason: '실패한 질문은 내역이 아니다');
    chat.reset();
    expect(api.summaryRequests, isEmpty);

    await turn('안녕', '네');
    expect(chat.endSession(), isTrue);
    expect(chat.endSession(), isFalse, reason: '그사이 바뀐 것이 없다');
    await flush();
    chat.reset();
    expect(api.summaryRequests, hasLength(1));
  });

  test('F-019 AC3 대화를 끝냈다가 이어 가면 같은 세션 요약을 새것으로 바꾼다', () async {
    await turn('첫 질문', '답');
    chat.endSession(); // 예: 음성 "대화 끝내기"
    await flush();
    await turn('이어서', '답2');
    chat.endSession();
    await flush();
    final list = memory.forPersona('planner');
    expect(list, hasLength(1));
    expect(list.single.summary, '요약 2: 첫 질문');
    expect(list.single.turns, 2);
  });

  test('F-019 AC3 다른 페르소나로 바꾸면 이전 페르소나의 기억으로 정리한다', () async {
    await turn('계획 세우자', '좋아요');
    personas.select('elder-care'); // 화면은 고른 뒤 새 대화로 시작한다
    chat.reset();
    await flush();
    expect(memory.forPersona('planner'), hasLength(1));
    expect(memory.forPersona('elder-care'), isEmpty);
  });

  test('F-019 AC3 요약에 실패하면 기억에 넣지 않고, 다음 정리 때 다시 시도한다', () async {
    final failed = Completer<Map<String, Object?>>();
    api.summaryReplies.add(failed);
    await turn('안녕', '네');
    chat.endSession();
    failed.completeError(const SummaryFailed('잠시 후 다시'));
    await flush();
    expect(memory.forPersona('planner'), isEmpty);
    expect(chat.entries, hasLength(2), reason: '대화에는 영향이 없다');
    expect(chat.endSession(), isTrue);
    await flush();
    expect(memory.forPersona('planner'), hasLength(1));
  });

  test('F-019 AC4 다음 대화 요청에 그 페르소나의 지난 요약을 싣고, 다른 페르소나 것은 싣지 않는다', () async {
    memory.put(SessionSummary(id: 'old', personaId: 'planner', endedAt: DateTime.utc(2026, 11, 10), summary: '지난번 기획'));
    memory.put(SessionSummary(id: 'x', personaId: 'elder-care', endedAt: DateTime.utc(2026, 11, 10), summary: '어르신'));
    await turn('다시 왔어요', '반가워요');
    expect(api.memories.last.map((s) => s.id), ['old']);

    chat.endSession();
    await flush();
    await turn('계속', '네');
    expect(api.memories.last.map((s) => s.id), ['old'], reason: '지금 세션의 요약은 내역이 따로 가니 싣지 않는다');

    chat.reset();
    await flush();
    await turn('새 대화', '네');
    expect(api.memories.last.length, 2, reason: '방금 끝난 세션이 다음 대화의 기억이 된다');
  });

  test('F-019 기억이 없는 컨트롤러는 요약하지 않고 memory 없이 보낸다', () async {
    final plain = ChatController(api, personas: personas);
    addTearDown(plain.dispose);
    plain.send('안녕');
    api.current
      ..add(const ChatDelta('네'))
      ..add(const ChatDone('end_turn'));
    await flush();
    expect(plain.endSession(), isFalse);
    expect(api.memories.last, isEmpty);
  });

  group('F-020 장기 기억', () {
    void seed(int n) {
      for (var d = 1; d <= n; d++) {
        memory.put(
          SessionSummary(id: 'old$d', personaId: 'planner', endedAt: DateTime.utc(2026, 11, d), summary: '옛 $d'),
        );
      }
    }

    test('AC2 요약이 쌓여 최근 5개 밖으로 밀린 것이 생기면 장기 기억으로 묶는다', () async {
      seed(5);
      await turn('오늘 이야기', '네');
      chat.reset();
      await flush();
      expect(api.consolidateRequests.single.map((s) => s.id), ['old1'], reason: '여섯째가 들어오면 가장 오래된 하나가 밀린다');
      expect(api.consolidatePrevious.single, isNull);
      final l = memory.longTermFor('planner')!;
      expect(l.summary, '장기 1: 1개');
      expect(l.coversUntil, DateTime.utc(2026, 11, 1));
      expect(memory.pendingFold('planner'), isEmpty);

      await turn('또 이야기', '네');
      chat.reset();
      await flush();
      expect(api.consolidateRequests.last.map((s) => s.id), ['old2']);
      expect(api.consolidatePrevious.last!.summary, '장기 1: 1개', reason: '이전 장기 기억을 이어 받는다');
      expect(memory.longTermFor('planner')!.summary, '장기 2: 1개');
    });

    test('AC2 5개 이하면 묶지 않고, 실패하면 장기 기억을 바꾸지 않은 채 다음에 다시 묶는다', () async {
      seed(3);
      await turn('a', 'b');
      chat.reset();
      await flush();
      expect(api.consolidateRequests, isEmpty);

      seed(6); // old1~old6 (+ 방금 세션) → 2개가 밀림
      final failed = Completer<Map<String, Object?>>();
      api.consolidateReplies.add(failed);
      await turn('c', 'd');
      chat.reset();
      await flush();
      failed.completeError(const SummaryFailed('x'));
      await flush();
      expect(memory.longTermFor('planner'), isNull);
      await turn('e', 'f');
      chat.reset();
      await flush();
      expect(memory.longTermFor('planner'), isNotNull);
      expect(api.consolidateRequests.first.map((s) => s.id), ['old1', 'old2', 'old3']);
      expect(api.consolidateRequests.last.map((s) => s.id), ['old1', 'old2', 'old3', 'old4'], reason: '실패한 것도 다시 묶는다');
    });

    test('AC3 다음 대화 요청에 그 페르소나의 장기 기억을 싣는다', () async {
      memory.setLongTerm(
        LongTermMemory(
          personaId: 'planner',
          summary: '오래 함께 기획했어요',
          updatedAt: DateTime.utc(2026, 11, 10),
          coversUntil: DateTime.utc(2026, 11, 1),
        ),
      );
      await turn('안녕', '네');
      expect(api.longTerms.last!.summary, '오래 함께 기획했어요');
      personas.select('coach');
      chat.reset();
      await flush();
      await turn('hi', 'hello');
      expect(api.longTerms.last, isNull, reason: '다른 페르소나의 장기 기억은 싣지 않는다');
    });
  });
}
