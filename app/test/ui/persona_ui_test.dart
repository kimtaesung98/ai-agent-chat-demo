import 'package:ai_agent_chat/api/chat_api.dart';
import 'package:ai_agent_chat/chat/chat_controller.dart';
import 'package:ai_agent_chat/chat/memory_controller.dart';
import 'package:ai_agent_chat/chat/persona_controller.dart';
import 'package:ai_agent_chat/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes.dart';

void main() {
  late FakeApi api;
  late ChatController chat;
  late PersonaController personas;
  late MemoryController memory;

  Future<void> open(WidgetTester tester, {Size size = const Size(1280, 800)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    api = FakeApi();
    personas = PersonaController();
    memory = MemoryController();
    chat = ChatController(api, personas: personas, memory: memory);
    await chat.loadConfig();
    await tester.pumpWidget(ChatApp(controller: chat));
    await tester.pump();
  }

  Finder title() => find.byKey(const Key('persona-title'));
  Finder inTitle(String s) => find.descendant(of: title(), matching: find.text(s));

  Future<void> send(WidgetTester tester, String text) async {
    await tester.enterText(find.byKey(const Key('input')), text);
    await tester.tap(find.byKey(const Key('send')));
    await tester.pump();
  }

  testWidgets('F-005 AC7 넓은 화면은 사이드바를 고정하고 상단에 페르소나를 보여 준다', (tester) async {
    await open(tester);
    expect(find.byKey(const Key('persona-sidebar')), findsOneWidget);
    expect(find.byKey(const Key('persona-planner')), findsOneWidget);
    expect(find.byKey(const Key('persona-friend')), findsOneWidget);
    expect(inTitle('기획 파트너 지은'), findsOneWidget);
    expect(find.byTooltip('Open navigation menu'), findsNothing);
  });

  testWidgets('F-005 AC7 좁은 화면은 메뉴 버튼으로 서랍을 연다', (tester) async {
    await open(tester, size: const Size(600, 900));
    expect(find.byKey(const Key('persona-sidebar')), findsNothing);
    expect(find.byKey(const Key('persona-friend')), findsNothing);
    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('persona-friend')));
    await tester.pumpAndSettle();
    expect(inTitle('다정한 친구'), findsOneWidget);
    expect(find.byKey(const Key('persona-friend')), findsNothing, reason: '고르면 서랍이 닫힌다');
  });

  testWidgets('F-005 AC1 다른 페르소나를 고르면 새 대화로 시작하고 다음 요청에 실린다', (tester) async {
    await open(tester);
    await send(tester, '안녕');
    api.current.add(const ChatDone('end_turn'));
    await tester.pump();
    expect(chat.entries, hasLength(2));

    await tester.tap(find.byKey(const Key('persona-friend')));
    await tester.pump();
    expect(inTitle('다정한 친구'), findsOneWidget);
    expect(chat.entries, isEmpty);
    expect(find.byKey(const Key('empty')), findsOneWidget);

    await send(tester, '뭐해');
    expect(api.personas.last!.persona.id, 'friend');
  });

  testWidgets('F-005 AC1 응답 중에는 다른 페르소나를 고를 수 없다', (tester) async {
    await open(tester);
    await send(tester, '안녕');
    await tester.tap(find.byKey(const Key('persona-friend')), warnIfMissed: false);
    await tester.pump();
    expect(personas.selected.id, 'planner');
    expect(chat.entries, hasLength(2));
    expect(tester.widget<ListTile>(find.byKey(const Key('persona-friend'))).enabled, isFalse);
  });

  testWidgets('F-005 AC2 편집해서 저장하면 상단·목록·다음 요청에 반영된다', (tester) async {
    await open(tester);
    await tester.tap(find.byKey(const Key('edit-persona')));
    await tester.pumpAndSettle();
    expect(find.text('페르소나 편집'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('persona-name')), '기획 코치 지은');
    await tester.tap(find.byKey(const Key('role-면접관')));
    await tester.tap(find.byKey(const Key('tone-존댓말'))); // 끄기
    await tester.tap(find.byKey(const Key('tone-유머 있게'))); // 켜기
    await tester.enterText(find.byKey(const Key('persona-instructions')), '한 줄로 답해 줘');
    await tester.pump();
    await tester.tap(find.byKey(const Key('save-persona')));
    await tester.pumpAndSettle();

    expect(inTitle('기획 코치 지은'), findsOneWidget);
    expect(personas.selected.role, '면접관');
    expect(personas.selected.tones, ['차분하게', '질문으로 정리', '유머 있게']);
    await send(tester, '시작');
    expect(api.personas.last!.toJson()['instructions'], '한 줄로 답해 줘');
  });

  testWidgets('F-005 AC2 취소하면 바뀌지 않고, 이름이 비면 저장할 수 없다', (tester) async {
    await open(tester);
    final before = personas.selected;
    await tester.tap(find.byKey(const Key('edit-persona')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('persona-name')), '  ');
    await tester.pump();
    expect(tester.widget<FilledButton>(find.byKey(const Key('save-persona'))).onPressed, isNull);
    await tester.tap(find.byKey(const Key('cancel-persona')));
    await tester.pumpAndSettle();
    expect(personas.selected, before);
    expect(inTitle('기획 파트너 지은'), findsOneWidget);
  });

  testWidgets('F-005 AC2 말투는 최대 6개까지 고를 수 있다', (tester) async {
    await open(tester);
    await tester.tap(find.byKey(const Key('edit-persona')));
    await tester.pumpAndSettle();
    for (final t in ['친근하게', '반말', '짧게']) {
      await tester.tap(find.byKey(Key('tone-$t')));
      await tester.pump();
    }
    expect(tester.widget<FilterChip>(find.byKey(const Key('tone-자세하게'))).onSelected, isNull);
    expect(tester.widget<FilterChip>(find.byKey(const Key('tone-짧게'))).onSelected, isNotNull, reason: '고른 것은 끌 수 있다');
  });

  testWidgets('F-005 AC2 새로 만든 페르소나는 목록에 추가되고 선택되며 새 대화로 시작한다', (tester) async {
    await open(tester);
    await send(tester, '안녕');
    api.current.add(const ChatDone('end_turn'));
    await tester.pump();

    await tester.tap(find.byKey(const Key('create-persona')));
    await tester.pumpAndSettle();
    expect(find.text('페르소나 만들기'), findsWidgets);
    expect(tester.widget<FilledButton>(find.byKey(const Key('save-persona'))).onPressed, isNull);
    await tester.enterText(find.byKey(const Key('persona-name')), '면접관 민수');
    await tester.pump();
    await tester.tap(find.byKey(const Key('save-persona')));
    await tester.pumpAndSettle();

    expect(personas.personas, hasLength(defaultPersonas.length + 1));
    expect(inTitle('면접관 민수'), findsOneWidget);
    expect(chat.entries, isEmpty);
    expect(find.byKey(Key('persona-${personas.selected.id}')), findsOneWidget);
  });

  testWidgets('F-005 AC3 내 프로필을 저장하면 다음 요청 about에 실린다', (tester) async {
    await open(tester);
    await tester.tap(find.byKey(const Key('profile')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('profile-about')), '32살 기획자예요');
    await tester.tap(find.byKey(const Key('save-profile')));
    await tester.pumpAndSettle();
    expect(find.text('32살 기획자예요'), findsOneWidget, reason: '사이드바에 요약이 보인다');
    await send(tester, '안녕');
    expect(api.personas.last!.about, '32살 기획자예요');
  });

  testWidgets('F-019 AC2 탑재 페르소나는 기본 지시를 읽기만 하고, 내 요구 사항만 덧붙인다', (tester) async {
    await open(tester);
    await tester.tap(find.byKey(const Key('edit-persona')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('persona-base-fixed')), findsOneWidget);
    expect(find.byKey(const Key('persona-base')), findsNothing);
    expect(find.text(defaultPersonas.first.base), findsOneWidget);

    await tester.enterText(find.byKey(const Key('persona-instructions')), '목록 없이 말로만');
    await tester.tap(find.byKey(const Key('save-persona')));
    await tester.pumpAndSettle();
    await send(tester, '시작');
    final json = api.personas.last!.toJson();
    expect(json['base'], defaultPersonas.first.base);
    expect(json['instructions'], '목록 없이 말로만');
  });

  testWidgets('F-019 AC2 내가 만든 페르소나는 기본 지시도 직접 쓴다', (tester) async {
    await open(tester);
    await tester.tap(find.byKey(const Key('create-persona')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('persona-base-fixed')), findsNothing);
    expect(find.byKey(const Key('memory-empty')), findsNothing, reason: '새 페르소나는 기억 칸이 없다');
    await tester.enterText(find.byKey(const Key('persona-name')), '면접관 민수');
    await tester.enterText(find.byKey(const Key('persona-base')), '한 번에 하나씩 질문해');
    await tester.enterText(find.byKey(const Key('persona-instructions')), '백엔드 위주로');
    await tester.pump();
    await tester.tap(find.byKey(const Key('save-persona')));
    await tester.pumpAndSettle();
    await send(tester, '시작');
    final json = api.personas.last!.toJson();
    expect(json['base'], '한 번에 하나씩 질문해');
    expect(json['instructions'], '백엔드 위주로');
  });

  testWidgets('F-019 AC6 편집 화면에서 이 페르소나의 지난 대화 기억을 보고 지울 수 있다', (tester) async {
    await open(tester);
    memory.put(
      SessionSummary(
        id: 'a',
        personaId: 'planner',
        endedAt: DateTime(2026, 11, 9, 12),
        summary: '출시 일정을 정리했어요',
        followUps: const ['QA 일정'],
      ),
    );
    memory.put(
      SessionSummary(id: 'b', personaId: 'planner', endedAt: DateTime(2026, 11, 10, 12), summary: '회고 방식을 이야기했어요'),
    );
    memory.put(SessionSummary(id: 'c', personaId: 'coach', endedAt: DateTime(2026, 11, 10, 12), summary: '영어 이야기'));
    await tester.tap(find.byKey(const Key('edit-persona')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('memory-clear')),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('출시 일정을 정리했어요'), findsOneWidget);
    expect(find.text('다음에 이어 갈 것: QA 일정'), findsOneWidget);
    expect(find.text('2026-11-10'), findsOneWidget);
    expect(find.text('영어 이야기'), findsNothing);

    await tester.ensureVisible(find.byKey(const Key('memory-delete-a')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('memory-delete-a')));
    await tester.pump();
    expect(find.text('출시 일정을 정리했어요'), findsNothing);
    await tester.ensureVisible(find.byKey(const Key('memory-clear')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('memory-clear')));
    await tester.pump();
    expect(find.byKey(const Key('memory-empty')), findsOneWidget);
    expect(memory.forPersona('coach'), hasLength(1));
  });

  testWidgets('F-019 AC3 새 대화 버튼을 누르면 지난 대화를 정리해 기억에 넣는다', (tester) async {
    await open(tester);
    await send(tester, '안녕');
    api.current
      ..add(const ChatDelta('반가워요'))
      ..add(const ChatDone('end_turn'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('new-chat')));
    await tester.pumpAndSettle();
    expect(api.summaryRequests, hasLength(1));
    expect(memory.forPersona('planner'), hasLength(1));
  });
}
