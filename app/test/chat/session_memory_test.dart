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
}
